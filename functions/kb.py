"""P4 — Merchant / entity Knowledge Base.

Evolves the flat merchant-alias lookup (merchant_db.py) into an entity model
WITHOUT losing any existing alias: curated rich entities (kb_entities.json) are
layered on top, and the flat Firestore DB is consulted as a fallback and wrapped
as a simple MERCHANT entity. So every merchant the old path recognized is still
recognized, and the new brands/processors/related-aliases get first-class
entity semantics (brand priors, country coverage, related aliases, is_processor).

Lookup is surface-oriented: given a candidate surface (a token span the resolver
generated) it returns matching entities + the KIND of match (exact / related /
brand / db), which the ranker turns into an identity strength. It does not itself
pick a winner — that is the ranker's job (P5).
"""

import json
import os
import re
import unicodedata

import merchant_db

# Diacritic folding + alnum normalization — MUST match tools/kb_build/normalize
# so that alias_norms compiled offline line up with runtime-normalized surfaces.
_SPECIAL = {"ø": "o", "œ": "oe", "æ": "ae", "ß": "ss", "đ": "d", "ł": "l",
            "þ": "th", "ð": "d"}


def _norm(s):
    s = (s or "").lower()
    for k, v in _SPECIAL.items():
        s = s.replace(k, v)
    s = unicodedata.normalize("NFKD", s)
    s = "".join(c for c in s if not unicodedata.combining(c))
    return re.sub(r"[^a-z0-9]+", "", s)

# Runtime reads the compiled, versioned artifact (built offline from the curated
# seed by tools/kb_build). It falls back to the raw curated seed if the artifact
# is absent, so behaviour degrades gracefully and dev checkouts still work. Both
# expose the same ``entities`` list, so lookup is byte-identical either way.
_KB_DIR = os.path.join(os.path.dirname(__file__), "kb")
_CURATED_PATH = os.path.join(os.path.dirname(__file__), "kb_entities.json")
# Newest compiled artifact wins; fall back to older artifact, then raw curated.
_ARTIFACTS = (
    (os.path.join(_KB_DIR, "merchant_kb.v2.json"), "artifact-v2"),
    (os.path.join(_KB_DIR, "merchant_kb.v1.json"), "artifact-v1"),
    (_CURATED_PATH, "curated"),
)
# Additive open-data enrichment (Overture LT, CC-BY; brand-collapsed offline).
# Consulted ONLY via the indexed exact/normalized/prefix paths below — NEVER by the
# broad substring scan (step 3) or the is_brand/is_processor iterations — so a noisy
# POI name can never substring-match into an unrelated descriptor. The curated/
# Wikidata KB always wins on collision, so existing resolutions are unchanged.
_ENRICH_ARTIFACT = os.path.join(_KB_DIR, "lt_enrichment.v1.json")

_entities = None          # list[dict] | None  (loaded entities)
_enrich_entities = None   # list[dict]         (open-data enrichment, index-only)
_alias_index = None       # alias(str) -> list[entity]
_related_index = None     # related_alias(str) -> list[entity]
_norm_index = None        # alias_norm -> list[entity]   (joined/fused-exact)
_prefix_index = None      # first3 -> list[(alias_norm, entity)]  (fused prefix)
_word_re = {}             # alias -> compiled word-boundary regex
_loaded_source = None     # provenance for diagnostics ("artifact" | "curated" | "none")


def _load():
    global _entities, _alias_index, _related_index, _norm_index, _prefix_index
    global _loaded_source, _enrich_entities
    if _entities is not None:
        return
    _entities, _loaded_source = None, None
    for path, src in _ARTIFACTS:
        try:
            with open(path, encoding="utf-8") as f:
                _entities = json.load(f).get("entities", [])
                _loaded_source = src
                break
        except Exception:  # noqa: BLE001 — try the next source
            continue
    if _entities is None:  # neither present -> DB-only
        _entities, _loaded_source = [], "none"
    _alias_index = {}
    _related_index = {}
    _norm_index = {}
    _prefix_index = {}
    for e in _entities:
        for a in e.get("aliases", []):
            _alias_index.setdefault(a.lower(), []).append(e)
        for a in e.get("related_aliases", []):
            _related_index.setdefault(a.lower(), []).append(e)
        # Normalized indices (compiled offline as alias_norms; fall back to
        # normalizing the aliases if an older artifact lacks them).
        norms = e.get("alias_norms") or [_norm(a) for a in e.get("aliases", [])]
        for n in norms:
            if not n:
                continue
            _norm_index.setdefault(n, []).append(e)
            if len(n) >= 4:
                _prefix_index.setdefault(n[:3], []).append((n, e))

    # Additive open-data enrichment: index-only, and never over an identity the
    # curated/Wikidata KB already owns (main KB stays authoritative -> no new
    # sibling candidate, so existing resolutions are byte-for-byte unchanged).
    _enrich_entities = []
    try:
        with open(_ENRICH_ARTIFACT, encoding="utf-8") as f:
            enrich = json.load(f).get("entities", [])
    except Exception:  # noqa: BLE001 — enrichment is optional
        enrich = []
    for e in enrich:
        norms = e.get("alias_norms") or [_norm(a) for a in e.get("aliases", [])]
        survive = {n for n in norms if n and n not in _norm_index}
        if not survive:
            continue
        _enrich_entities.append(e)
        # Index only aliases whose normalized form survived the collision filter —
        # otherwise a branch/brand alias the main KB already owns would re-enter the
        # exact-alias path and spawn a sibling candidate that trips margin-abstention.
        for a in e.get("aliases", []):
            if _norm(a) in survive:
                _alias_index.setdefault(a.lower(), []).append(e)
        for n in survive:
            _norm_index.setdefault(n, []).append(e)
            if len(n) >= 4:
                _prefix_index.setdefault(n[:3], []).append((n, e))


def reset_cache():
    """Drop caches (curated + the underlying merchant_db)."""
    global _entities, _alias_index, _related_index, _norm_index, _prefix_index
    global _word_re, _loaded_source, _enrich_entities
    _entities = _alias_index = _related_index = _loaded_source = None
    _norm_index = _prefix_index = _enrich_entities = None
    _word_re = {}
    merchant_db.reset_cache()


def _alias_hit(surface_low, alias):
    """Token-boundary match for EVERY alias. A brand must appear as a whole token
    (or hyphen/dot-delimited run), never inside a longer word — otherwise a broad
    KB mis-fires ('auran' inside 'restaurants', 'gofuel' inside 'agrigofuel').
    Genuinely glued brands are handled separately by probe_prefix, not here."""
    pat = _word_re.get(alias)
    if pat is None:
        pat = re.compile(
            r"(^|[^a-z0-9ąčęėįšųūž])" + re.escape(alias) +
            r"([^a-z0-9ąčęėįšųūž]|$)"
        )
        _word_re[alias] = pat
    return pat.search(surface_low) is not None


def _db_entity(surface):
    """Wrap a flat merchant_db hit as a simple entity dict (source='db')."""
    hit = merchant_db.match(surface)
    if hit is None:
        return None
    display, mtype, category, logo = hit
    return {
        "entity_id": display.lower(),
        "canonical_name": display,
        "entity_type": "MERCHANT",
        "aliases": [],
        "related_aliases": [],
        "country_coverage": [],
        "categories": [category] if category else [],
        "merchant_type": None,
        "icon_key": None,
        "known_domains": [],
        "is_processor": False,
        "is_brand": False,
        "brand_relationships": [],
        "popularity_prior": 0.4,
        "recurring_type": mtype,          # subscription | bill | frequent | possible
        "logo_domain": logo,
        "_source": "db",
    }


def lookup(surface):
    """Return a list of (entity, match_kind) for a candidate surface.

    match_kind ∈ {"exact","related","brand","db"} — strongest first. A surface
    may match several entities; the ranker scores them. Empty list = KB miss.
    """
    _load()
    if not surface:
        return []
    low = surface.lower().strip()
    out = []
    seen = set()

    # 1. Exact curated alias.
    for e in _alias_index.get(low, []):
        if e["entity_id"] not in seen:
            out.append((e, "exact")); seen.add(e["entity_id"])
    # 2. Related alias (e.g. "stena scandica" -> Stena Line).
    for e in _related_index.get(low, []):
        if e["entity_id"] not in seen:
            out.append((e, "related")); seen.add(e["entity_id"])
    # 2b. Normalized-exact: the surface, folded to alnum, equals an alias_norm —
    #     lets the resolver's split-brand joins ("uno x" -> "unox") reach a brand
    #     the tokenizer had fragmented.
    for e in _norm_index.get(_norm(surface), []):
        if e["entity_id"] not in seen:
            out.append((e, "exact")); seen.add(e["entity_id"])
    # 3. Curated brand alias appearing INSIDE the surface (word/substring).
    for e in _entities:
        if e["entity_id"] in seen:
            continue
        for a in e.get("aliases", []) + e.get("related_aliases", []):
            if _alias_hit(low, a.lower()):
                kind = "brand" if e.get("is_brand") else "exact"
                out.append((e, kind)); seen.add(e["entity_id"])
                break
    # 4. Flat DB fallback — ONLY when the compiled artifact produced no hit, so
    #    the artifact is authoritative and a brand present in BOTH does not return
    #    as two sibling candidates (which would trip margin-abstention). merchant_db
    #    stays a genuine overlay for brands the artifact does not cover.
    if not out:
        dbe = _db_entity(surface)
        if dbe is not None:
            out.append((dbe, "db"))
    return out


def probe_prefix(surface):
    """Fused-brand discovery: a single glued token whose leading chars are a
    known alias_norm (e.g. 'circlekbergen' -> Circle K). Longest unambiguous
    prefix only; abstains on ties to preserve the zero-false-merge invariant."""
    _load()
    t = _norm(surface)
    if len(t) < 6:
        return []
    cands = [(n, e) for n, e in _prefix_index.get(t[:3], [])
             if len(n) >= 4 and t.startswith(n)]
    if not cands:
        return []
    cands.sort(key=lambda x: -len(x[0]))
    best = len(cands[0][0])
    top = [(n, e) for n, e in cands if len(n) == best]
    if len({e["entity_id"] for _, e in top}) != 1:
        return []  # ambiguous prefix -> abstain
    return [(top[0][1], "fused")]


def is_processor_token(token):
    _load()
    low = (token or "").lower()
    for e in _entities:
        if e.get("is_processor") and low in [a.lower() for a in e.get("aliases", [])]:
            return True
    return False


def is_brand_token(token):
    _load()
    low = (token or "").lower()
    for e in _entities:
        if e.get("is_brand") and low in [a.lower() for a in e.get("aliases", [])]:
            return True
    return False
