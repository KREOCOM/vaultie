"""Offline builder for the LT merchant-enrichment artifact (strategy B).

Compiles Overture Places (LT, narrow merchant categories; primary source) into an
ADDITIVE KB candidate artifact: functions/kb/lt_enrichment.v1.json. Wikidata is
used only complementarily — the Overture brand tag already carries a Wikidata QID,
preserved as provenance (no separate Wikidata crawl for this POC).

BRAND-COLLAPSE (strategy B): Overture is POI/branch-level. Several POIs that share
one reliable brand identity (Overture brand name or brand Wikidata QID) are
collapsed into a SINGLE merchant-identity entity at build time — canonical = brand
name, branch/location names never become separate sibling identity candidates.
category/website/country/provenance are aggregated conservatively. Unbranded local
POIs are kept at POI level (dedup by normalized name); there is NO unbranded
name-family collapse (strategy C is deliberately not implemented — it over-merges).

The runtime (kb.py) consumes this artifact ONLY through indexed exact / normalized
/ prefix lookup — never the broad substring pass — and any identity the
curated/Wikidata KB already owns is dropped (main KB wins), so existing resolutions
are unchanged (McDonald's, Rimi resolve via the main KB exactly as before).

  python3 tools/kb_build/build_lt_enrichment.py            # from cached snapshot
  python3 tools/kb_build/build_lt_enrichment.py --refresh  # re-query Overture S3

NOT part of the Cloud Functions deploy tooling; runs offline only.
"""

import json
import os
import sys
from collections import Counter, defaultdict

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import normalize as N
from sources import overture

_ROOT = os.path.dirname(os.path.dirname(os.path.dirname(os.path.abspath(__file__))))
_KB_DIR = os.path.join(_ROOT, "functions", "kb")
_MAIN_ARTIFACT = os.path.join(_KB_DIR, "merchant_kb.v2.json")
_OUT = os.path.join(_KB_DIR, "lt_enrichment.v1.json")

# PHASE 4 — conservative map of Overture taxonomy into EXISTING Vaultie semantics.
# (merchant_type, recurring_type, icon_key). recurring_type "frequent" = physical
# spending (many small visits), NOT a subscription/bill. gym stays recurring-CAPABLE
# (recurring_type=None) so a real membership is still free to classify as recurring.
_CATEGORY_MAP = {
    "restaurant":            ("RESTAURANT",  "frequent", "FOOD"),
    "fast_food_restaurant":  ("RESTAURANT",  "frequent", "FOOD"),
    "supermarket":           ("SUPERMARKET", "frequent", "GROCERIES"),
    "grocery_store":         ("SUPERMARKET", "frequent", "GROCERIES"),
    "convenience_store":     ("SUPERMARKET", "frequent", "GROCERIES"),
    "pharmacy":              ("PHARMACY",    "frequent", "PHARMACY"),
    "bakery":                ("RETAIL",      "frequent", "SHOPPING"),
    "car_wash":              ("RETAIL",      "frequent", "SHOPPING"),
    "gas_station":           ("GAS_STATION", "frequent", "FUEL"),
    "gym":                   ("RETAIL",      None,       "SHOPPING"),
    "fitness_center":        ("RETAIL",      None,       "SHOPPING"),
    "health_club":           ("RETAIL",      None,       "SHOPPING"),
}

# Single-token POI "names" that are really generic category words — never a merchant
# identity. Dropped so they cannot norm-match a generic descriptor surface.
_GENERIC = {
    "vaistine", "aptieka", "kavine", "restoranas", "baras", "parduotuve",
    "market", "supermarket", "bakery", "kepykla", "cafe", "restaurant",
    "pharmacy", "autoservisas", "plovykla", "degaline", "sportoklubas",
    "sportas", "klubas", "centras", "maistas", "grocery", "shop", "store",
}


def _existing_norms():
    try:
        with open(_MAIN_ARTIFACT, encoding="utf-8") as f:
            ents = json.load(f).get("entities", [])
    except Exception:
        return set()
    out = set()
    for e in ents:
        out |= set(e.get("alias_norms") or [])
        out |= {N.norm(a) for a in e.get("aliases", [])}
    return {n for n in out if n}


def _is_branded(r):
    """A POI has a reliable brand identity iff it carries a brand Wikidata QID or a
    non-trivial brand name."""
    return bool(r.get("brand_wd") or (r.get("brand") and len(N.norm(r["brand"])) >= 3))


def _majority_category(recs):
    """Most common Overture category among grouped POIs; abstain (None) on a hard
    tie between DIFFERENT merchant_types (ambiguous identity -> false-merge safety)."""
    c = Counter(r["cat"] for r in recs if r["cat"] in _CATEGORY_MAP)
    if not c:
        return None
    top = c.most_common()
    if len(top) > 1 and top[0][1] == top[1][1]:
        tied = {_CATEGORY_MAP[k][0] for k, n in top if n == top[0][1]}
        if len(tied) > 1:
            return None
    return top[0][0]


def _entity(eid, name, alias_norms, aliases, cat, source, extra):
    mtype, rtype, icon = _CATEGORY_MAP[cat]
    e = {
        "entity_id": eid,
        "canonical_name": name,
        "entity_type": "MERCHANT",
        "aliases": aliases,
        "related_aliases": [],
        "alias_norms": sorted(alias_norms),
        "country_coverage": ["LT"],
        "categories": [cat],
        "merchant_type": mtype,
        "icon_key": icon,
        "known_domains": [],
        "is_processor": False,
        "is_brand": True,
        "brand_relationships": [],
        "popularity_prior": 0.45,     # below curated (0.6) — curated wins ties
        "recurring_type": rtype,
        "_source": source,
    }
    e.update(extra)
    return e


def build(refresh=False):
    raw = overture.fetch(refresh=refresh)
    taken = _existing_norms()          # curated/Wikidata identities always win

    branded = defaultdict(list)        # brand key -> POIs (one merchant each)
    unbranded_by_name = defaultdict(list)  # norm(name) -> POIs (POI-level)
    for r in raw:
        if r.get("cat") not in _CATEGORY_MAP:
            continue
        if _is_branded(r):
            key = ("wd", r["brand_wd"]) if r.get("brand_wd") else ("nm", N.norm(r["brand"]))
            branded[key].append(r)
        else:
            n = N.norm(r.get("name") or "")
            if len(n) < 5 or n in _GENERIC or n in taken:
                continue
            unbranded_by_name[n].append(r)

    entities = []

    # BRAND-COLLAPSE: one identity per brand; branch names are NOT emitted.
    for key, recs in branded.items():
        bname = Counter(r["brand"] for r in recs if r.get("brand")).most_common(1)
        bname = bname[0][0].strip() if bname else recs[0]["name"].strip()
        n = N.norm(bname)
        if len(n) < 3 or n in _GENERIC or n in taken:
            continue
        cat = _majority_category(recs)
        if not cat:
            continue
        website = next((r["website"] for r in recs if r.get("website")), None)
        brand_wd = key[1] if key[0] == "wd" else \
            next((r["brand_wd"] for r in recs if r.get("brand_wd")), None)
        domain = website.split("//")[-1].split("/")[0].replace("www.", "") \
            if website else None
        e = _entity(
            "ovb:" + n, bname, {n}, [bname], cat,
            "overture-brand" + ("+wikidata" if brand_wd else ""),
            {"brand_wikidata": brand_wd, "website": website,
             "known_domains": [domain] if domain else [], "poi_count": len(recs)},
        )
        entities.append(e)

    # UNBRANDED local POIs — POI level, dedup by normalized name (NO family collapse).
    for n, recs in unbranded_by_name.items():
        cat = _majority_category(recs)
        if not cat:
            continue
        name = Counter(r["name"].strip() for r in recs).most_common(1)[0][0]
        website = next((r["website"] for r in recs if r.get("website")), None)
        coords = next(((r["lon"], r["lat"]) for r in recs
                       if r.get("lon") is not None), None)
        domain = website.split("//")[-1].split("/")[0].replace("www.", "") \
            if website else None
        e = _entity(
            "ovu:" + n, name, {n}, [name], cat, "overture-local",
            {"website": website, "known_domains": [domain] if domain else [],
             "coordinates": list(coords) if coords else None,
             "poi_count": len(recs)},
        )
        entities.append(e)

    entities.sort(key=lambda e: e["entity_id"])
    branded_n = sum(1 for e in entities if e["entity_id"].startswith("ovb:"))
    cat_hist = Counter(e["categories"][0] for e in entities)
    artifact = {
        "schema_version": 1,
        "kb_version": "2026.07-lt-enrichment-brandcollapse",
        "sources": [
            f"overture:CC-BY-4.0:release={overture.RELEASE}:{len(raw)}records",
            "wikidata:CC0:brand-qid-provenance-only",
        ],
        "strategy": "brand-collapse (B): branded POIs -> one identity per brand; "
                    "unbranded POIs at POI level; no unbranded family collapse",
        "country_scope": ["LT"],
        "category_scope": overture.CATEGORIES,
        "entity_count": len(entities),
        "branded_entities": branded_n,
        "unbranded_entities": len(entities) - branded_n,
        "category_histogram": dict(cat_hist.most_common()),
        "entities": entities,
    }
    with open(_OUT, "w", encoding="utf-8") as f:
        json.dump(artifact, f, ensure_ascii=False, indent=1, sort_keys=False)
        f.write("\n")
    print(f"built {_OUT}")
    print(f"  raw_pois={len(raw)} -> entities={len(entities)} "
          f"(branded={branded_n} unbranded={len(entities) - branded_n})")
    print(f"  categories={dict(cat_hist.most_common())}")


if __name__ == "__main__":
    build(refresh="--refresh" in sys.argv)
