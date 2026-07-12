"""Generic country-aware merchant-enrichment builder (generalizes build_lt_
enrichment.py). ONE builder for every country — no per-country copies:

    python3 tools/kb_build/build_enrichment.py --country LT
    python3 tools/kb_build/build_enrichment.py --country LV --out DIR --cache DIR

Same architecture as the LT artifact: Overture POI -> build-time brand-collapse ->
known-brand store-format collapse -> bounded country-scoped artifact. Nothing about
the resolver, recurring pipeline, categories, or collapse rules is country-specific;
only the Overture query scope (country + bbox) and the emitted country_coverage tag
are parametrized. Offline only; runtime never touches the network.

Emits country-scoped artifacts (enrichment.<CC>.v1.json). Country-scoped (vs one
merged file) so a user's linked banks decide which countries load, each rebuilds
independently, and memory stays bounded to the countries actually in use.
"""

import argparse
import json
import os
import re
import time
from collections import Counter, defaultdict

_HERE = os.path.dirname(os.path.abspath(__file__))
import sys
sys.path.insert(0, _HERE)
import normalize as N

_ROOT = os.path.dirname(os.path.dirname(_HERE))
_KB_DIR = os.path.join(_ROOT, "functions", "kb")
_MAIN_ARTIFACT = os.path.join(_KB_DIR, "merchant_kb.v2.json")

# Overture query scope per country (bbox prefilter; addresses.country is the exact
# filter applied at pull time). The ONLY country-specific data in the builder.
COUNTRY_BBOX = {
    "LT": (20.9, 53.8, 26.9, 56.5),
    "LV": (20.8, 55.6, 28.3, 58.1),
    "EE": (21.7, 57.5, 28.2, 59.8),
    "NO": (4.0, 57.9, 31.6, 71.5),
}
RELEASE = "2026-06-17.0"
CATEGORIES = [
    "restaurant", "fast_food_restaurant", "supermarket", "grocery_store",
    "convenience_store", "pharmacy", "bakery", "car_wash", "gas_station",
    "gym", "fitness_center", "health_club",
]

_CATEGORY_MAP = {
    "restaurant": ("RESTAURANT", "frequent", "FOOD"),
    "fast_food_restaurant": ("RESTAURANT", "frequent", "FOOD"),
    "supermarket": ("SUPERMARKET", "frequent", "GROCERIES"),
    "grocery_store": ("SUPERMARKET", "frequent", "GROCERIES"),
    "convenience_store": ("SUPERMARKET", "frequent", "GROCERIES"),
    "pharmacy": ("PHARMACY", "frequent", "PHARMACY"),
    "bakery": ("RETAIL", "frequent", "SHOPPING"),
    "car_wash": ("RETAIL", "frequent", "SHOPPING"),
    "gas_station": ("GAS_STATION", "frequent", "FUEL"),
    "gym": ("RETAIL", None, "SHOPPING"),
    "fitness_center": ("RETAIL", None, "SHOPPING"),
    "health_club": ("RETAIL", None, "SHOPPING"),
}
_GENERIC = {
    "vaistine", "aptieka", "kavine", "restoranas", "baras", "parduotuve",
    "market", "supermarket", "bakery", "kepykla", "cafe", "restaurant",
    "pharmacy", "autoservisas", "plovykla", "degaline", "sportoklubas",
    "sportas", "klubas", "centras", "maistas", "grocery", "shop", "store",
}
_FORMAT_WORDS = {
    "express", "extra", "city", "market", "supermarket", "hypermarket", "mini",
    "local", "center", "centre", "super", "plus", "food", "shop", "store",
    "maxi", "mega", "xl",
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


def _safe_qualifier(tok):
    return (tok in _FORMAT_WORDS
            or re.fullmatch(r"[a-z]", tok) is not None
            or (re.fullmatch(r"(.)\1*", tok) is not None and len(tok) <= 4)
            or re.fullmatch(r"[ivxlcdm]{1,4}", tok) is not None
            or re.fullmatch(r"\d{1,4}", tok) is not None)


def _is_brand_format_variant(name, brand_cores):
    tk = [t for t in re.split(r"[^a-z0-9]+", N.fold(name).lower()) if t]
    for k in range(len(tk) - 1, 0, -1):
        core = N.norm("".join(tk[:k]))
        if len(core) >= 4 and core in brand_cores:
            residue = tk[k:]
            if residue and all(_safe_qualifier(t) for t in residue):
                return True
    return False


def _majority_category(recs):
    c = Counter(r["cat"] for r in recs if r["cat"] in _CATEGORY_MAP)
    if not c:
        return None
    top = c.most_common()
    if len(top) > 1 and top[0][1] == top[1][1]:
        if len({_CATEGORY_MAP[k][0] for k, n in top if n == top[0][1]}) > 1:
            return None
    return top[0][0]


def _entity(eid, name, n, cat, country, source, extra):
    mtype, rtype, icon = _CATEGORY_MAP[cat]
    e = {
        "entity_id": eid, "canonical_name": name, "entity_type": "MERCHANT",
        "aliases": [name], "related_aliases": [], "alias_norms": [n],
        "country_coverage": [country], "categories": [cat],
        "merchant_type": mtype, "icon_key": icon, "known_domains": [],
        "is_processor": False, "is_brand": True, "brand_relationships": [],
        "popularity_prior": 0.45, "recurring_type": rtype, "_source": source,
    }
    e.update(extra)
    return e


def _fetch(country, cache_dir, refresh):
    path = os.path.join(cache_dir, f"overture_{country}.json")
    if not refresh and os.path.exists(path):
        with open(path, encoding="utf-8") as f:
            return json.load(f)
    import duckdb
    con = duckdb.connect()
    con.execute("INSTALL httpfs; LOAD httpfs; SET s3_region='us-west-2';")
    src = (f"s3://overturemaps-us-west-2/release/{RELEASE}"
           "/theme=places/type=place/*.parquet")
    inlist = ",".join(f"'{c}'" for c in CATEGORIES)
    x0, y0, x1, y1 = COUNTRY_BBOX[country]
    rows = con.execute(f"""
        SELECT names.primary, categories.primary, brand.names.primary,
               brand.wikidata, websites[1],
               round((bbox.xmin+bbox.xmax)/2,4), round((bbox.ymin+bbox.ymax)/2,4)
        FROM read_parquet('{src}')
        WHERE bbox.xmin BETWEEN {x0} AND {x1} AND bbox.ymin BETWEEN {y0} AND {y1}
          AND names.primary IS NOT NULL AND categories.primary IN ({inlist})
          AND addresses[1].country = '{country}'
    """).fetchall()
    recs = [{"name": r[0], "cat": r[1], "brand": r[2], "brand_wd": r[3],
             "website": r[4], "lon": r[5], "lat": r[6]} for r in rows]
    os.makedirs(cache_dir, exist_ok=True)
    with open(path, "w", encoding="utf-8") as f:
        json.dump(recs, f, ensure_ascii=False, separators=(",", ":"))
    return recs


def _is_branded(r):
    return bool(r.get("brand_wd") or (r.get("brand") and len(N.norm(r["brand"])) >= 3))


def build(country, cache_dir, out_dir, refresh=False):
    t0 = time.time()
    raw = _fetch(country, cache_dir, refresh)
    taken = _existing_norms()
    brand_cores = {n for n in taken if len(n) >= 4}

    stats = {"country": country, "raw": len(raw), "collisions": 0,
             "format_collapsed": 0}
    branded = defaultdict(list)
    unbranded = defaultdict(list)
    for r in raw:
        if r.get("cat") not in _CATEGORY_MAP:
            continue
        if _is_branded(r):
            key = ("wd", r["brand_wd"]) if r.get("brand_wd") else ("nm", N.norm(r["brand"]))
            branded[key].append(r)
        else:
            n = N.norm(r.get("name") or "")
            if len(n) < 5 or n in _GENERIC:
                continue
            if n in taken:
                stats["collisions"] += 1
                continue
            unbranded[n].append(r)

    stats["branded_pois"] = sum(len(v) for v in branded.values())
    stats["unbranded_pois"] = sum(len(v) for v in unbranded.values())
    stats["brand_families"] = len(branded)
    stats["multi_branch_families"] = sum(1 for v in branded.values() if len(v) >= 2)

    entities = []
    for key, recs in branded.items():
        bn = Counter(r["brand"] for r in recs if r.get("brand")).most_common(1)
        bn = bn[0][0].strip() if bn else recs[0]["name"].strip()
        n = N.norm(bn)
        if len(n) < 3 or n in _GENERIC or n in taken:
            if n in taken:
                stats["collisions"] += 1
            continue
        cat = _majority_category(recs)
        if not cat:
            continue
        wd = key[1] if key[0] == "wd" else next(
            (r["brand_wd"] for r in recs if r.get("brand_wd")), None)
        web = next((r["website"] for r in recs if r.get("website")), None)
        dom = web.split("//")[-1].split("/")[0].replace("www.", "") if web else None
        entities.append(_entity(
            f"ovb:{country.lower()}:{n}", bn, n, cat, country,
            "overture-brand" + ("+wikidata" if wd else ""),
            {"brand_wikidata": wd, "website": web,
             "known_domains": [dom] if dom else [], "poi_count": len(recs)}))

    for n, recs in unbranded.items():
        cat = _majority_category(recs)
        if not cat:
            continue
        name = Counter(r["name"].strip() for r in recs).most_common(1)[0][0]
        if _is_brand_format_variant(name, brand_cores):
            stats["format_collapsed"] += 1
            continue
        web = next((r["website"] for r in recs if r.get("website")), None)
        dom = web.split("//")[-1].split("/")[0].replace("www.", "") if web else None
        entities.append(_entity(
            f"ovu:{country.lower()}:{n}", name, n, cat, country, "overture-local",
            {"website": web, "known_domains": [dom] if dom else [],
             "poi_count": len(recs)}))

    entities.sort(key=lambda e: e["entity_id"])
    stats["entities"] = len(entities)
    stats["branded_entities"] = sum(1 for e in entities if e["_source"].startswith("overture-brand"))
    stats["unbranded_entities"] = len(entities) - stats["branded_entities"]

    os.makedirs(out_dir, exist_ok=True)
    out = os.path.join(out_dir, f"enrichment.{country}.v1.json")
    artifact = {
        "schema_version": 1, "kb_version": f"2026.07-enrichment-{country}",
        "sources": [f"overture:CC-BY-4.0:release={RELEASE}:{len(raw)}records"],
        "country_scope": [country], "category_scope": CATEGORIES,
        "entity_count": len(entities), "entities": entities,
    }
    with open(out, "w", encoding="utf-8") as f:
        json.dump(artifact, f, ensure_ascii=False, indent=1)
        f.write("\n")
    stats["size_bytes"] = os.path.getsize(out)
    stats["build_time_s"] = round(time.time() - t0, 1)
    stats["out"] = out
    return stats


if __name__ == "__main__":
    ap = argparse.ArgumentParser()
    ap.add_argument("--country", required=True, choices=list(COUNTRY_BBOX))
    ap.add_argument("--cache", default=os.path.join(_HERE, "cache"))
    ap.add_argument("--out", default=_KB_DIR)
    ap.add_argument("--refresh", action="store_true")
    a = ap.parse_args()
    s = build(a.country, a.cache, a.out, a.refresh)
    print(json.dumps(s, indent=1))
