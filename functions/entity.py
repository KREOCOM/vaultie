"""Stage 2 — Merchant / Entity Resolution v1 (deterministic, evidence-based).

Goal: from raw Enable Banking transaction signals, reliably determine WHICH real
financial entity each transaction is with — independent of categorization and
recurring detection. Distinguishes MERCHANT / COUNTERPARTY / PROCESSOR / BANK /
UNKNOWN, and unwraps processors (e.g. creditor="UAB OPAY SOLUTIONS" but the real
merchant is gymplius.lt in the remittance).

Every resolution is fully explainable: it carries its evidence, source and
confidence. No AI, no categorization, no recurring logic here.

Pipeline:
  classify_type -> extract_signals -> parse_remittance -> normalize
  -> detect_processor (corpus-aware) -> resolve_entity -> cluster
"""

import re
from collections import defaultdict

# ── transaction types ──
PURCHASE = "PURCHASE"
TRANSFER_OUT = "TRANSFER_OUT"
TRANSFER_IN = "TRANSFER_IN"
BANK_FEE = "BANK_FEE"
REFUND = "REFUND"
CASH = "CASH"
UNKNOWN_TYPE = "UNKNOWN"

# ── entity types ──
MERCHANT = "MERCHANT"
COUNTERPARTY = "COUNTERPARTY"
PROCESSOR = "PROCESSOR"
BANK = "BANK"
UNKNOWN_ENTITY = "UNKNOWN"

# Strong-prior payment processors / platforms (NOT the only signal).
_PROCESSOR_PRIORS = {
    "opay", "paypal", "stripe", "sumup", "adyen", "klarna", "montonio",
    "neopay", "kevin", "dermateka", "mokejimai", "maksekeskus",
}
# Known banks (fees / bank-issued lines).
_BANK_PRIORS = {"seb", "swedbank", "luminor", "citadele", "medicinos bankas"}

_FOLD = str.maketrans("ąčęėįšųūž", "aceeisuuz")
_LEGAL = {"uab", "ab", "mb", "vsi", "vsi", "ii", "ij", "ou", "oy", "gmbh",
          "ltd", "inc", "llc", "as", "sia", "sa", "bv", "plc"}
_COUNTRY = {"lt", "ltu", "lv", "lva", "ee", "est", "no", "nor", "de", "deu",
            "pl", "pol", "se", "swe", "fi", "fin", "gb", "gbr"}


def _fold(s):
    return (s or "").lower().translate(_FOLD)


def _tokens(s):
    return [t for t in re.split(r"[^a-z0-9]+", _fold(s)) if t]


# ── raw accessors ──
def _code(t):
    b = t.get("bank_transaction_code")
    if isinstance(b, dict):
        return b.get("code"), b.get("sub_code")
    return None, None


def _creditor(t):
    c = t.get("creditor")
    return c.get("name") if isinstance(c, dict) and c.get("name") else None


def _debtor(t):
    d = t.get("debtor")
    return d.get("name") if isinstance(d, dict) and d.get("name") else None


def _remittance(t):
    r = t.get("remittance_information")
    if isinstance(r, list):
        return " | ".join(str(x) for x in r if x)
    return (r or "").strip()


def _amount(t):
    a = t.get("transaction_amount") or {}
    try:
        return abs(float(a.get("amount"))) if isinstance(a, dict) else abs(float(a))
    except (TypeError, ValueError):
        return None


def _date(t):
    return t.get("booking_date") or t.get("value_date") or t.get("transaction_date")


# ── 1. TYPE CLASSIFIER ──
def classify_type(t):
    code, sub = _code(t)
    if code == "CCRD":
        if sub == "FEES":
            return BANK_FEE, f"bank_txn_code={code}/{sub}"
        return PURCHASE, f"bank_txn_code={code}/{sub}"
    if code == "ICDT":
        return TRANSFER_OUT, f"bank_txn_code={code}/{sub}"
    if code == "RCDT":
        return TRANSFER_IN, f"bank_txn_code={code}/{sub}"
    if code == "MDOP" or sub == "FEES":
        return BANK_FEE, f"bank_txn_code={code}/{sub}"
    # No code — infer from remittance shape (SEB Apple/pending card lines).
    rmt = _remittance(t).lower()
    if "kortel" in rmt or re.search(r"\.(com|lt|net|io|app|eu|co)\b", rmt):
        return PURCHASE, "no_code:card/merchant-like remittance"
    return UNKNOWN_TYPE, "no_code"


# ── 2/3. REMITTANCE PARSER (deterministic, tuned to observed SEB format) ──
# Card line: "... kortelė...124261 MERCHANT/CITY/COUNTRY #123 | CLR..."
_CARD_RE = re.compile(
    r"kortel[eėe][.\s]*\d*\s+(?P<m>.+?)\s*/\s*(?P<city>[^/#|]+?)\s*/\s*(?P<cc>[A-Za-z]{2,3})\b"
)
# Processor website line: "Mokėjimas tinklalapyje gymplius.lt, ..."
_WEB_RE = re.compile(r"tinklalapyje\s+(?P<m>[\w.\-]+)", re.I)
# Card suffix mask: "...124261"
_SUFFIX_RE = re.compile(r"kortel[eėe][.\s]*(\d{3,})")
# A leading domain (Apple: "APPLE.COM/BILL")
_DOMAIN_RE = re.compile(r"^([\w\-]+\.(?:com|lt|net|io|app|eu|co|org))\b", re.I)


def parse_remittance(t):
    """Return best merchant candidate(s) + hints from the remittance string."""
    rmt = _remittance(t)
    out = {
        "remittance_raw": rmt,
        "card_merchant": None,
        "web_merchant": None,
        "domain_merchant": None,
        "city_hint": None,
        "country_hint": None,
        "card_suffix": None,
        "is_mobile_selfpay": False,
    }
    if not rmt:
        return out
    m = _CARD_RE.search(rmt)
    if m:
        out["card_merchant"] = m.group("m").strip(" .-")
        out["city_hint"] = m.group("city").strip()
        out["country_hint"] = m.group("cc").upper()
    w = _WEB_RE.search(rmt)
    if w:
        out["web_merchant"] = w.group("m").strip(" .,")
    d = _DOMAIN_RE.search(rmt.strip())
    if d:
        out["domain_merchant"] = d.group(1)
    s = _SUFFIX_RE.search(rmt)
    if s:
        out["card_suffix"] = s.group(1)
    if "mobiliaja programele" in _fold(rmt) or "mobiliąja programėle" in rmt:
        out["is_mobile_selfpay"] = True
    return out


# ── 4. NORMALIZATION ──
def normalize(name):
    """display_name (tidy), normalized_identity (folded), matching_fingerprint
    (aggressively stripped for clustering only)."""
    raw = (name or "").strip()
    display = raw.strip(' "').replace("  ", " ")
    normalized = " ".join(_tokens(raw))
    # fingerprint: drop legal forms, country codes, store/terminal codes (tokens
    # with digits), www; keep the meaningful head tokens.
    fp = []
    for tok in _tokens(raw):
        if tok in _LEGAL or tok in _COUNTRY or tok == "www":
            continue
        if any(ch.isdigit() for ch in tok):
            continue
        fp.append(tok)
    fingerprint = "".join(fp[:3])  # head tokens, no spaces
    return {
        "display_name": display or raw,
        "normalized_identity": normalized,
        "matching_fingerprint": fingerprint or normalized.replace(" ", ""),
    }


def identity_key(name):
    """Conservative cross-merchant identity for CACHE clustering (not matching).

    Strips only NOISE — legal forms, country codes, www, and store/terminal
    codes (tokens containing a digit) — and keeps EVERY remaining brand token
    (no head-truncation). So a business's descriptor variants that differ only by
    processor prefix / store number / legal suffix collapse to one key
    ("SumUp *Trattoria Enzo", "TRATTORIA ENZO 02" -> "trattoriaenzo"), while two
    DISTINCT businesses that merely share a descriptive prefix stay separate
    ("Escuela Infantil Privada Alce" != "...Alicia"). Unlike matching_fingerprint
    this is deliberately NON-aggressive: it must never merge different merchants.
    Reuses the same tokenizer + LEGAL/COUNTRY sets as normalize(); no parallel
    normaliser. Returns "" when nothing identifying remains (caller falls back)."""
    toks = [t for t in _tokens(name)
            if t not in _LEGAL and t not in _COUNTRY and t != "www"
            and not any(ch.isdigit() for ch in t)]
    return "".join(toks)


# ── 5. PROCESSOR DETECTOR (corpus-aware, hybrid) ──
def build_corpus(txns):
    """Per-creditor stats used to detect processors: how many distinct remittance
    merchants hide behind the same creditor name."""
    cred_merchants = defaultdict(set)  # creditor_fp -> {remittance merchant fp}
    cred_count = defaultdict(int)
    for t in txns:
        cred = _creditor(t)
        if not cred:
            continue
        cfp = normalize(cred)["matching_fingerprint"]
        cred_count[cfp] += 1
        pr = parse_remittance(t)
        rem = pr["web_merchant"] or pr["domain_merchant"]
        if rem:
            cred_merchants[cfp].add(normalize(rem)["matching_fingerprint"])
    return {"cred_merchants": cred_merchants, "cred_count": cred_count}


def processor_probability(creditor, remittance_merchant, corpus):
    """0–1 that `creditor` is a processor rather than the real merchant."""
    if not creditor:
        return 0.0, []
    cfp = normalize(creditor)["matching_fingerprint"]
    ev = []
    p = 0.0
    if cfp in _PROCESSOR_PRIORS:
        p = max(p, 0.85)
        ev.append(f"creditor '{cfp}' in processor prior list")
    distinct = corpus["cred_merchants"].get(cfp, set())
    if len(distinct) >= 2:
        p = max(p, 0.9)
        ev.append(f"{len(distinct)} distinct remittance merchants behind creditor")
    if remittance_merchant:
        rfp = normalize(remittance_merchant)["matching_fingerprint"]
        if rfp and rfp != cfp:
            p = max(p, 0.7)
            ev.append(f"remittance merchant '{rfp}' != creditor '{cfp}'")
    return p, ev


# ── 6. ENTITY RESOLVER ──
def _looks_like_person(name):
    toks = [x for x in re.split(r"\s+", (name or "").strip()) if x]
    if len(toks) < 2 or len(toks) > 4:
        return False
    # mostly alphabetic capitalized words, no legal form / no digits
    if any(t.lower() in _LEGAL for t in toks):
        return False
    if any(any(ch.isdigit() for ch in t) for t in toks):
        return False
    return all(re.match(r"^[A-ZŠŽĖČĄĮŲŪa-zšžėčąįųū.\-]+$", t) for t in toks)


def resolve_entity(t, corpus):
    ttype, ttype_ev = classify_type(t)
    creditor = _creditor(t)
    debtor = _debtor(t)
    pr = parse_remittance(t)
    evidence = {
        "transaction_type": ttype,
        "type_evidence": ttype_ev,
        "creditor_name_raw": creditor,
        "debtor_name_raw": debtor,
        "remittance_raw": pr["remittance_raw"][:160],
        "card_merchant": pr["card_merchant"],
        "web_merchant": pr["web_merchant"],
        "domain_merchant": pr["domain_merchant"],
        "city_hint": pr["city_hint"],
        "country_hint": pr["country_hint"],
    }

    # Bank fee → BANK.
    if ttype == BANK_FEE:
        who = creditor or "Bank"
        norm = normalize(who)
        return _mk(who, norm, BANK, 0.9, "BANK_FEE", ttype, evidence)

    # Transfers: figure out the counterparty, unless a processor hides a merchant.
    if ttype in (TRANSFER_OUT, TRANSFER_IN):
        # Processor hiding a real merchant inside a transfer (OPAY -> gymplius.lt)?
        pp, pev = processor_probability(creditor, pr["web_merchant"] or pr["domain_merchant"], corpus)
        real = pr["web_merchant"] or pr["domain_merchant"]
        if pp >= 0.7 and real:
            norm = normalize(real)
            e = dict(evidence, processor=creditor, processor_probability=round(pp, 2),
                     processor_evidence=pev)
            return _mk(real, norm, MERCHANT, min(0.6 + pp * 0.35, 0.97),
                       "PROCESSOR_UNWRAP", ttype, e)
        # Otherwise it's a real transfer to a counterparty (person / institution).
        who = creditor or debtor
        if who:
            norm = normalize(who)
            etype = COUNTERPARTY
            conf = 0.9
            src = "COUNTERPARTY_NAME"
            if _fold(who) in _BANK_PRIORS:
                etype, src = BANK, "KNOWN_ENTITY_PRIOR"
            return _mk(who, norm, etype, conf, src, ttype, evidence)
        return _mk("Transfer", normalize("Transfer"), UNKNOWN_ENTITY, 0.3,
                   "UNRESOLVED", ttype, evidence)

    # PURCHASE / UNKNOWN → merchant resolution.
    # Processor unwrap first.
    pp, pev = processor_probability(creditor, pr["web_merchant"] or pr["domain_merchant"], corpus)
    real = pr["web_merchant"] or pr["domain_merchant"]
    if pp >= 0.75 and real:
        norm = normalize(real)
        e = dict(evidence, processor=creditor, processor_probability=round(pp, 2),
                 processor_evidence=pev)
        return _mk(real, norm, MERCHANT, min(0.6 + pp * 0.35, 0.97),
                   "PROCESSOR_UNWRAP", ttype, e)

    # Prefer creditor.name (78% coverage, clean for card txns).
    if creditor:
        # Strip a card-processor '*' prefix ("DERMATEKA*GROZIO PRIEM" -> real part).
        name = creditor.split("*", 1)[1].strip() if "*" in creditor else creditor
        norm = normalize(name)
        conf = 0.9 if ttype == PURCHASE else 0.75
        return _mk(name, norm, MERCHANT, conf, "CREDITOR_NAME", ttype, evidence)

    # No creditor → remittance-parsed merchant (Apple: APPLE.COM/BILL).
    cand = pr["card_merchant"] or pr["domain_merchant"] or pr["web_merchant"]
    if cand:
        norm = normalize(cand)
        return _mk(cand, norm, MERCHANT, 0.7, "REMITTANCE_PARSE", ttype, evidence)

    return _mk("Unknown", normalize("Unknown"), UNKNOWN_ENTITY, 0.2,
               "UNRESOLVED", ttype, evidence)


def _mk(canonical, norm, etype, conf, source, ttype, evidence):
    return {
        "entity_id": norm["matching_fingerprint"] or "unknown",
        "canonical_name": norm["display_name"],
        "display_name": norm["display_name"],
        "normalized_identity": norm["normalized_identity"],
        "entity_type": etype,
        "identity_confidence": round(float(conf), 2),
        "identity_source": source,
        "transaction_type": ttype,
        "identity_evidence": evidence,
    }


# ── 7. CLUSTERING ──
def cluster(resolved, txns):
    groups = defaultdict(list)
    for r, t in zip(resolved, txns):
        groups[(r["entity_id"], r["entity_type"])].append((r, t))
    clusters = []
    for (eid, etype), items in groups.items():
        amounts = [_amount(t) for _, t in items if _amount(t) is not None]
        dates = sorted(d for _, t in items if (d := _date(t)))
        confs = [r["identity_confidence"] for r, _ in items]
        srcs = defaultdict(int)
        types = defaultdict(int)
        for r, _ in items:
            srcs[r["identity_source"]] += 1
            types[r["transaction_type"]] += 1
        clusters.append({
            "entity_id": eid,
            "canonical_name": items[0][0]["canonical_name"],
            "entity_type": etype,
            "transaction_count": len(items),
            "total_amount": round(sum(amounts), 2),
            "first_seen": dates[0] if dates else None,
            "last_seen": dates[-1] if dates else None,
            "amounts": amounts,
            "identity_confidence": round(sum(confs) / len(confs), 2),
            "main_source": max(srcs, key=srcs.get),
            "transaction_types": dict(types),
            "raw_names": sorted({(r["identity_evidence"].get("creditor_name_raw")
                                  or r["identity_evidence"].get("remittance_raw", ""))[:40]
                                 for r, _ in items}),
        })
    clusters.sort(key=lambda c: -c["total_amount"])
    return clusters


def run(txns):
    dbit = [t for t in txns if t.get("credit_debit_indicator") == "DBIT"]
    corpus = build_corpus(dbit)
    resolved = [resolve_entity(t, corpus) for t in dbit]
    clusters = cluster(resolved, dbit)
    return {"resolved": resolved, "clusters": clusters, "dbit": dbit}
