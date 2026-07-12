"""Evidence-preserving multi-candidate entity resolution (P1-P3, P5-P7).

Replaces the flat "clean string -> first-match lookup" identity step. The raw
descriptor is immutable evidence; normalization/fingerprints are used only for
retrieval and clustering. Flow:

  raw descriptor
   -> DescriptorEvidence            (P1: raw, tokens+positions, fingerprint, signals)
   -> token role hypotheses         (P2: BRAND/LEGAL_FORM/LOCATION/PROCESSOR/...)
   -> candidate generation          (P3: leading brand span, brand-only, full,
                                          remittance domain, processor unwrap)
   -> KB lookup                      (kb.py: curated entities + flat DB fallback)
   -> contextual ranking            (P5: evidence + explanation_coverage)
   -> abstention                    (P6: min score + min margin -> UNKNOWN /
                                          NEEDS_EXTERNAL_ENRICHMENT)
   -> post-resolution enrichment    (P7: type/category/location/icon)

Reuses entity.py building blocks (classify_type, parse_remittance, normalize,
build_corpus, processor_probability, accessors). Does NOT reuse entity.resolve_
entity (the old priority cascade this module supersedes).
"""

import re

import global_index
import kb
from entity import (
    _BANK_PRIORS, _COUNTRY, _LEGAL, _PROCESSOR_PRIORS, _amount, _creditor,
    _debtor, _fold, _looks_like_person, _remittance, build_corpus,
    classify_type, normalize, parse_remittance, processor_probability,
)

# ── resolution status (P6) ──
RESOLVED = "RESOLVED"
UNKNOWN = "UNKNOWN"
NEEDS_EXTERNAL = "NEEDS_EXTERNAL_ENRICHMENT"

# ── abstention thresholds (tunable) ──
MIN_ACCEPT = 0.55      # top candidate must clear this
MIN_MARGIN = 0.12      # top must beat second by this — else too ambiguous

# ── small lexicons used by role hypotheses ──
_BRANCH_LEX = {"fil", "filialas", "filialai", "branch", "br"}
_GENERIC_LEX = {
    "solutions", "solution", "group", "grupe", "groupe", "services", "service",
    "trading", "holding", "company", "co", "systems", "digital", "global",
    "international", "int", "pro", "standard", "premium", "plus", "basic",
    "membership", "subscription", "prekyba",
    # TLD fragments + billing/payment descriptor noise (non-identity).
    "com", "net", "io", "org", "www", "bill", "billing", "payment", "pay",
    "purchase", "pos",
}
_STRUCTURAL = {
    "LEGAL_FORM", "COUNTRY", "STORE_ID", "TERMINAL_ID", "BRANCH", "PROCESSOR",
    "BANK", "LOCATION", "GENERIC",
}

# Legal-form abbreviations + country names — qualifier tokens that are dropped
# from a canonical name for the completeness check (not identity-critical).
# Descriptive words (international, group, corporation…) are deliberately NOT here.
_GEO_LEGAL = {
    "uab", "ab", "asa", "as", "oy", "oyj", "ou", "sia", "sa", "gmbh", "ltd",
    "llc", "inc", "plc", "bv", "ag", "nv", "aps", "kb", "ky", "spa", "srl",
    "latvia", "latvija", "lithuania", "lietuva", "estonia", "eesti", "norway",
    "norge", "sweden", "sverige", "finland", "suomi", "denmark", "danmark",
    "poland", "polska", "germany", "deutschland", "portugal", "spain", "france",
    "italy", "italia", "ireland",
}


# ── descriptor source (mirrors recurring.counterparty_name priority) ──
def _counterparty(t):
    for getter in (_creditor, _debtor):
        v = getter(t)
        if v:
            return v
    return _remittance(t) or ""


def _clean_surface(name):
    """Role-aware processor-prefix strip ("PAYPAL*APPMYWEB" -> "APPMYWEB").
    Not destructive of evidence — the raw descriptor is kept separately."""
    if "*" in name:
        after = name.split("*", 1)[1].strip()
        if len(after) >= 2:
            return after
    return name.strip()


def _otokens(s):
    """Original-case tokens (keep diacritics + digits, drop punctuation)."""
    return re.findall(r"[^\W_]+", s or "", re.UNICODE)


# ── P1: DescriptorEvidence ──
def build_evidence(t):
    raw = _counterparty(t)
    surface = _clean_surface(raw)
    otoks = _otokens(surface)
    ftoks = [_fold(x) for x in otoks]
    pr = parse_remittance(t)
    norm = normalize(surface)
    ttype, ttype_ev = classify_type(t)
    return {
        "raw_descriptor": raw,                       # IMMUTABLE evidence
        "surface": surface,                          # role-aware identity surface
        "normalized_descriptor": norm["normalized_identity"],
        "otokens": otoks,
        "ftokens": ftoks,
        "matching_fingerprint": norm["matching_fingerprint"],
        "remittance_signals": pr,
        "domain_merchant": pr.get("domain_merchant"),
        "web_merchant": pr.get("web_merchant"),
        "card_merchant": pr.get("card_merchant"),
        "country_hint": pr.get("country_hint"),
        "city_hint": pr.get("city_hint"),
        "transaction_type": ttype,
        "type_evidence": ttype_ev,
        "amount": _amount(t),
        "is_person": _looks_like_person(surface),
    }


# ── P2: token role hypotheses ──
def role_hypotheses(ev):
    ftoks = ev["ftokens"]
    roles = []
    for i, tok in enumerate(ftoks):
        r = {}
        if tok in _LEGAL:
            r["LEGAL_FORM"] = 0.99
        if tok in _COUNTRY:
            r["COUNTRY"] = 0.9
        if tok.isdigit():
            r["STORE_ID" if len(tok) >= 3 else "TERMINAL_ID"] = 0.9
        if kb.is_processor_token(tok) or tok in _PROCESSOR_PRIORS:
            r["PROCESSOR"] = 0.9
        if tok in _BANK_PRIORS:
            r["BANK"] = 0.9
        if kb.is_brand_token(tok):
            r["BRAND"] = 0.95
            r["MERCHANT"] = 0.8
        if tok in _BRANCH_LEX:
            r["BRANCH"] = 0.7
        if tok in _GENERIC_LEX:
            r["GENERIC"] = 0.6
        if not r:
            r["MERCHANT"] = 0.5
            r["UNKNOWN"] = 0.4
        roles.append(r)

    # Positional LOCATION: a bare merchant/unknown token that FOLLOWS a strong
    # brand token is far likelier a place than a second identity (GRAMYRA after
    # YX, BALLANGEN after ST1). Adds a role — never deletes the token.
    for i in range(1, len(ftoks)):
        top_prev = max(roles[i - 1], key=roles[i - 1].get)
        cur = roles[i]
        cur_top = max(cur, key=cur.get)
        if top_prev in ("BRAND",) and cur_top in ("MERCHANT", "UNKNOWN"):
            cur["LOCATION"] = max(cur.get("LOCATION", 0), 0.6)

    # PERSON: whole descriptor looks like a natural person (P2P), not a merchant.
    if ev["is_person"]:
        for r in roles:
            if max(r, key=r.get) in ("MERCHANT", "UNKNOWN"):
                r["PERSON"] = 0.7
    return roles


def _top_roles(roles):
    return [max(r, key=r.get) for r in roles]


# ── P3: candidate generation ──
def _is_unwrap(surface, ev):
    """True when a remittance-extracted merchant is genuinely HIDDEN behind the
    creditor (a processor unwrap) rather than just restating the creditor itself
    (e.g. creditor 'SOMECLOUD.IO' with remittance 'SOMECLOUD.IO')."""
    sfold = set(_fold(x) for x in _otokens(surface))
    return bool(sfold) and not sfold.issubset(set(ev["ftokens"]))


def generate_candidates(ev, roles):
    ftoks, otoks = ev["ftokens"], ev["otokens"]
    tops = _top_roles(roles)
    surfaces = []  # (surface_original_case, provenance)

    def add(s, prov):
        s = (s or "").strip()
        if s and all(s.lower() != x[0].lower() for x in surfaces):
            surfaces.append((s, prov))

    # 1. Full role-aware surface (backward-compatible DB substring path).
    add(ev["surface"], "full")
    # 2. Leading brand/merchant span (stop at first structural/legal/location).
    span = []
    for i, tok in enumerate(otoks):
        if tops[i] in ("BRAND", "MERCHANT") and tops[i] not in _STRUCTURAL:
            span.append(tok)
        else:
            break
    if span:
        add(" ".join(span), "leading_span")
        add(span[0], "brand_only")
    # 3. First token alone (brand-only), even if step 2 stopped early.
    if otoks:
        add(otoks[0], "first_token")
    # 4. Processor-unwrap evidence: a domain/web merchant hidden behind the
    #    creditor (only when it is not simply the creditor restated).
    if ev["domain_merchant"] and _is_unwrap(ev["domain_merchant"], ev):
        add(ev["domain_merchant"], "remittance_domain")
    if ev["web_merchant"] and _is_unwrap(ev["web_merchant"], ev):
        add(ev["web_merchant"], "remittance_domain")
    # 5. Card-line merchant extraction (clean surface for messy card remittance).
    add(ev["card_merchant"], "remittance_card")
    # 6. Split-brand discovery: joined adjacent-token windows over the brand core
    #    (identity tokens, minus structural noise and person tokens). Reached via
    #    the KB's normalized-exact index, so a tokenizer-split brand
    #    ("UNO","X" / "7","ELEVEN") becomes findable. Generic — no brand named.
    core = [otoks[i] for i in range(len(otoks))
            if tops[i] not in _STRUCTURAL and tops[i] != "PERSON"]
    for w in (2, 3):
        for i in range(len(core) - w + 1):
            add("".join(core[i:i + w]), "join")
    # 7. Noise-strip: the whole brand core with structural/store/legal tokens
    #    removed (e.g. "REMA 1000 BYPORTEN" -> "REMA BYPORTEN").
    if core and len(core) < len(otoks):
        add(" ".join(core), "noise_strip")
    return surfaces


# ── P5: scoring with explanation coverage ──
_IDENTITY_STRENGTH = {
    "exact": 1.0, "related": 0.95, "brand": 0.95, "domain": 0.85, "db": 0.8,
    "fused": 0.8,
}


def _identity_ftokens(entity, surface, ev, prov):
    """The descriptor tokens that constitute the resolved IDENTITY — the brand /
    alias tokens, NOT every token in the candidate surface. This is what keeps
    GRAMYRA/0836/UAB/Fil as residual evidence instead of being swallowed by a
    full-descriptor substring match."""
    keys = set()
    if entity:
        for a in entity.get("aliases", []) + entity.get("related_aliases", []):
            keys.update(_fold(x) for x in _otokens(a))
        keys.update(_fold(x) for x in _otokens(entity.get("canonical_name", "")))
    else:
        # Domain/other surface with no KB entity: its own tokens are the identity.
        keys.update(_fold(x) for x in _otokens(surface))
    return [ft for ft in ev["ftokens"] if ft in keys]


def _coverage(matched, ev, roles):
    sig = ev["ftokens"]
    if not sig:
        return 1.0, []
    tops = _top_roles(roles)
    explained = set(matched)
    residual = []
    for i, ft in enumerate(sig):
        if ft in explained:
            continue
        if tops[i] in _STRUCTURAL:
            explained.add(ft)          # structurally explained (legal/loc/store…)
        else:
            residual.append(i)
    coverage = len(explained) / len(sig)
    return coverage, residual


def _score_candidate(surface, prov, entity, kind, ev, roles):
    identity = _IDENTITY_STRENGTH.get(kind, 0.4)
    # Domain-evidence surfaces get domain strength even without a KB entity.
    if entity is None:
        identity = 0.85 if prov == "remittance_domain" else 0.25
    # Corpus/prior processor evidence strengthens a genuine unwrap.
    if prov == "remittance_domain" and ev.get("processor_probability", 0.0) >= 0.7:
        identity = max(identity, 0.9)

    is_processor = bool(entity and entity.get("is_processor"))
    matched = _identity_ftokens(entity, surface, ev, prov)
    # A processor surface acting as the merchant identity is heavily penalised.
    if is_processor:
        identity = 0.12

    coverage, _residual_idx = _coverage(matched, ev, roles)

    # Bonuses.
    bonus = 0.0
    tops = _top_roles(roles)
    if entity and ev["country_hint"] and ev["country_hint"] in \
            [c.upper() for c in entity.get("country_coverage", [])]:
        bonus += 0.05
    if surface and ev["otokens"] and \
            surface.lower().startswith(ev["otokens"][0].lower()):
        bonus += 0.05  # leading position

    evidence_match = min(identity + bonus, 1.0)

    # Penalty: a dominant BRAND token in the descriptor not covered here.
    penalty = 0.0
    brand_idx = [i for i, tp in enumerate(tops) if tp == "BRAND"]
    if brand_idx and not any(ev["ftokens"][i] in matched for i in brand_idx):
        penalty += 0.25

    score = 0.55 * evidence_match + 0.45 * coverage - penalty
    score = max(0.0, min(score, 1.0))
    matched_set = set(matched)
    # Residual = every descriptor token that is NOT the identity — kept as
    # evidence (UAB, Fil, Ballangen, 0836…), never deleted (P1).
    residual = [o for o in ev["otokens"] if _fold(o) not in matched_set]
    return {
        "surface": surface,
        "provenance": prov,
        "entity": entity,
        "match_kind": kind if entity else ("domain" if prov == "remittance_domain" else "none"),
        "score": round(score, 3),
        "evidence_match": round(evidence_match, 3),
        "explanation_coverage": round(coverage, 3),
        "matched_tokens": [o for o in ev["otokens"] if _fold(o) in set(matched)],
        "residual_tokens": residual,
        "is_processor": is_processor,
    }


def _rank(ev, roles, surfaces, use_global=False):
    scored = []
    for surface, prov in surfaces:
        hits = kb.lookup(surface)
        # Fused-brand discovery: a single glued token whose prefix is a known
        # brand (e.g. "circleklillehammer"). Only when nothing else matched.
        if not hits and " " not in surface.strip():
            hits = kb.probe_prefix(surface)
        # Fallback layer: the big offline global merchant index, consulted ONLY on
        # the abstention re-rank (use_global). Its hits are ordinary candidates —
        # they go through the same scoring/completeness/abstention below. The main
        # KB is authoritative; the index excludes any identity it already owns.
        if use_global:
            hits = hits + global_index.lookup(surface)
        if hits:
            for entity, kind in hits:
                scored.append(_score_candidate(surface, prov, entity, kind, ev, roles))
        elif prov == "remittance_domain":
            # Bare domain = strong merchant identity even without a KB entity.
            scored.append(_score_candidate(surface, prov, None, "domain", ev, roles))
    # Artifact is authoritative at the descriptor level: if ANY compiled-KB
    # candidate exists, drop flat-DB-fallback siblings (a legacy-DB variant of a
    # brand the artifact already knows would otherwise trip margin-abstention on
    # a different surface of the same descriptor). Mirrors kb.lookup's per-surface
    # rule across the whole candidate set. Not a scoring/threshold change.
    if any(c["match_kind"] != "db" for c in scored):
        scored = [c for c in scored if c["match_kind"] != "db"]
    # Collapse duplicate entities, keep the best-scoring surface per entity.
    best = {}
    for c in scored:
        eid = c["entity"]["entity_id"] if c["entity"] else "surface:" + c["surface"].lower()
        if eid not in best or c["score"] > best[eid]["score"]:
            best[eid] = c
    ranked = sorted(best.values(), key=lambda c: -c["score"])
    return ranked


# ── P7: post-resolution enrichment ──
def enrich(entity, ev, roles):
    if entity is None:
        return {
            "merchant_type": None, "category": "other", "recurring_type": "subscription",
            "location": ev.get("city_hint"), "country": ev.get("country_hint"),
            "brand": None, "icon_key": None, "logo_domain": None,
        }
    cats = entity.get("categories") or []
    tops = _top_roles(roles)
    locs = [ev["otokens"][i] for i, tp in enumerate(tops) if tp == "LOCATION"]
    country = ev.get("country_hint")
    if not country:
        cc = entity.get("country_coverage") or []
        country = cc[0] if len(cc) == 1 else None
    return {
        "merchant_type": entity.get("merchant_type"),
        "category": cats[0] if cats else "other",
        "recurring_type": entity.get("recurring_type") or "subscription",
        "location": (locs[0] if locs else ev.get("city_hint")),
        "country": country,
        "brand": entity.get("canonical_name") if entity.get("is_brand") else None,
        "icon_key": entity.get("icon_key"),
        "logo_domain": entity.get("logo_domain") or (
            entity.get("known_domains") or [None])[0],
    }


# ── P6 safety boundary: canonical-identity completeness ──
def _identity_complete(top, ev):
    """Bias to UNKNOWN unless the matched entity's FULL canonical identity is
    present in the descriptor. Every holdout false-merge matched only a FRAGMENT
    of a multi-token entity ("AVIA TRUCK" -> AVIA *International*; "COMARKET" ->
    Coma) — a token of the entity's name was missing from the descriptor. Legit
    "brand + location" (Coop Hasvik, Circle K Miskas, Esso Mosjoen) carry the
    entity's whole canonical name, so they pass. Generic — no merchant literals.

    Exemptions carry independent evidence and so keep their own identity:
      * remittance_domain — merchant proven by a payment domain, not creditor
        tokens (e.g. OPAY unwrap -> gymplius.lt).
      * related-alias — an intentional asset/service->entity link (Stena
        Scandica -> Stena Line).
    """
    ent = top.get("entity")
    if ent is None or top.get("provenance") == "remittance_domain" \
            or top.get("match_kind") == "related":
        return True
    name = ent.get("canonical_name", "")
    canon = [t for t in (_fold(x) for x in _otokens(name)) if len(t) >= 2]
    if not canon:
        return True
    # Drop legal-form abbreviations and country names from the required core —
    # they are qualifiers, not identity ("Lidl Eesti" -> core "lidl"). Descriptive
    # business words (International, Group, …) are KEPT so fragment matches (AVIA
    # TRUCK -> AVIA International) still abstain.
    core = [t for t in canon if t not in _GEO_LEGAL] or canon
    present = set(ev["ftokens"])
    if all(t in present for t in core):
        return True                      # (a) every core canonical token present
    # (b) the fully-normalized canonical (apostrophe/punctuation collapsed) is a
    #     descriptor token — "McDonald's" -> "mcdonalds", "Uno-X" -> "unox". A
    #     longer glued token is NOT equality, so fragments still abstain.
    return kb._norm(name) in present


# ── main entry ──
def resolve(t, corpus):
    """Full Resolution for one transaction (used by tests + recurring adapter)."""
    ev = build_evidence(t)
    # Corpus-aware processor probability (prior + "N distinct merchants behind
    # one creditor"). Falls back to a single-txn corpus so the resolver works
    # standalone in tests. Only strengthens a genuine remittance unwrap.
    if corpus is None:
        corpus = build_corpus([t])
    pp, pev = processor_probability(
        _creditor(t), ev["domain_merchant"] or ev["web_merchant"], corpus)
    ev["processor_probability"] = pp
    ev["processor_evidence"] = pev
    roles = role_hypotheses(ev)

    # Processor-unwrap evidence folded into candidate generation: if the creditor
    # is a probable processor and the remittance exposes a real merchant, that
    # merchant is already emitted as a remittance_domain/web candidate above; the
    # processor's own surface is separately penalised in scoring.
    surfaces = generate_candidates(ev, roles)
    result = _finalize(ev, roles, _rank(ev, roles, surfaces))

    # Fallback: only when the authoritative main KB abstained, re-rank WITH the big
    # offline global merchant index added to the candidate pool and re-apply the
    # exact same accept/completeness/abstention. If it now resolves, take it;
    # otherwise keep the original abstention. The index is never consulted for a
    # transaction the main KB already resolved, so recognized merchants and the
    # SQLite is only touched on the unknown tail.
    if result["status"] != RESOLVED and global_index.available():
        alt = _finalize(ev, roles, _rank(ev, roles, surfaces, use_global=True))
        if alt["status"] == RESOLVED and _fallback_evidence_ok(alt, ev):
            return alt
    return result


def _fallback_evidence_ok(alt, ev):
    """Long-tail safety for the big global index: a fallback merchant may stand as a
    RESOLVED match on its own only when it carries real evidence. If NO descriptor
    token was matched (identity came only from a normalized sub-span), trust it only
    when the entity IS the whole descriptor — not a short fragment of a longer name
    that still has other content tokens ("Areas Portugal Sa" -> "Aréas": "areas" is
    one of three tokens, none matched -> reject; "Intermarche" -> "Intermarché": the
    descriptor is exactly the entity -> keep). Generic — no merchant is named, no
    threshold/completeness change; only overture/global-index candidates are gated."""
    if alt["matched_tokens"]:
        return True
    top = alt["candidates"][0] if alt["candidates"] else None
    ent = (top or {}).get("entity") or {}
    if not str(ent.get("_source", "")).startswith("overture"):
        return True                      # main-KB candidate — unaffected
    return kb._norm(ent.get("canonical_name", "")) == kb._norm("".join(ev["otokens"]))


def _finalize(ev, roles, ranked):
    """Turn a ranked candidate list into a resolution (accept + completeness, or
    abstain). Pure function of (ev, roles, ranked) so resolve() can call it once on
    the main-KB ranking and again on the global-index-augmented ranking."""
    top = ranked[0] if ranked else None
    second = ranked[1] if len(ranked) > 1 else None
    top_score = top["score"] if top else 0.0
    second_score = second["score"] if second else 0.0
    margin = round(top_score - second_score, 3)

    result = {
        "status": UNKNOWN,
        "entity": None,
        "canonical_name": None,
        "entity_type": None,
        "top_score": top_score,
        "second_score": second_score,
        "margin": margin,
        "explanation_coverage": top["explanation_coverage"] if top else 0.0,
        "matched_tokens": top["matched_tokens"] if top else [],
        "residual_tokens": top["residual_tokens"] if top else ev["otokens"],
        "enrichment": None,
        "raw_descriptor": ev["raw_descriptor"],
        "surface": ev["surface"],
        "fingerprint": ev["matching_fingerprint"],
        "candidates": ranked[:5],
    }

    if top and top_score >= MIN_ACCEPT and margin >= MIN_MARGIN and \
            _identity_complete(top, ev):
        ent = top["entity"]
        canonical = ent["canonical_name"] if ent else top["surface"]
        result.update(
            status=RESOLVED,
            entity=ent,
            canonical_name=canonical,
            entity_type=(ent["entity_type"] if ent else "MERCHANT"),
            enrichment=enrich(ent, ev, roles),
        )
        return result

    # Abstain. Distinguish "there is a merchant-ish signal we couldn't pin down"
    # (-> NEEDS_EXTERNAL) from "nothing merchant-like" (-> UNKNOWN).
    has_signal = bool(
        ev["domain_merchant"] or ev["web_merchant"] or
        any(c["is_processor"] for c in ranked) or
        (top and top_score > 0.35)
    )
    result["status"] = NEEDS_EXTERNAL if has_signal else UNKNOWN
    return result


# ── recurring integration adapter (P8) ──
def resolve_hit(t, corpus, classify_unknown=None):
    """Return (surface, hit_tuple_or_None, resolution) for recurring.detect_
    recurring. ``hit`` keeps the legacy 4-tuple shape
    (canonical, recurring_type, category, logo) so all downstream grouping /
    routing is untouched (P8). When we abstain, the local deterministic
    ``classify_unknown`` hook is consulted before giving up."""
    res = resolve(t, corpus)
    surface = res["surface"]
    if res["status"] == RESOLVED and res["entity"] is not None:
        enr = res["enrichment"]
        hit = (res["canonical_name"], enr["recurring_type"], enr["category"],
               enr["logo_domain"])
        return surface, hit, res
    if res["status"] == RESOLVED:  # domain-only resolve (no KB entity)
        enr = res["enrichment"]
        hit = (res["canonical_name"], enr["recurring_type"], enr["category"], None)
        return surface, hit, res
    # Abstained: local deterministic hook (kept for parity with the old path;
    # same (name, amount) contract the previous classify_unknown used).
    if classify_unknown is not None:
        hook = classify_unknown(surface, _amount(t))
        if hook is not None:
            return surface, hook, res
    return surface, None, res
