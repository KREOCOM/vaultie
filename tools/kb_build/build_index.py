"""Production builder for the GLOBAL offline merchant search index (SQLite).

Compiles Overture Places for every Vaultie target country into ONE indexed SQLite
file that the resolver falls back to when the in-memory main KB abstains
(UNKNOWN / NEEDS_EXTERNAL). Queried from disk — never loaded whole into RAM.

Same proven build-time safety as the LT enrichment:
  * brand-collapse            — POIs sharing a brand identity -> one merchant entity
  * store-format collapse     — "Maxima X", "Rimi Express" -> parent brand (dropped)
  * main-KB collision drop     — never shadow a curated/Wikidata identity (main wins)
  * normalized-identity dedup — one row per normalized alias, first country wins
  * provenance preserved      — _source + country_coverage kept on every entity

  python3 tools/kb_build/build_index.py                 # from cached harvest
  python3 tools/kb_build/build_index.py --refresh       # re-query Overture S3
  python3 tools/kb_build/build_index.py --out PATH --cache DIR

Offline only; no runtime network. Target countries = the app bank-connect picker
(lib/screens/bank_connect_screen.dart) — 30 ISO codes.
"""

import argparse
import json
import os
import re
import sqlite3
import time
from collections import Counter, defaultdict

_HERE = os.path.dirname(os.path.abspath(__file__))
import sys
sys.path.insert(0, _HERE)
import normalize as N

_ROOT = os.path.dirname(os.path.dirname(_HERE))
_KB_DIR = os.path.join(_ROOT, "functions", "kb")
_MAIN_ARTIFACT = os.path.join(_KB_DIR, "merchant_kb.v2.json")

# Vaultie target countries — exactly the app's bank-connect country picker.
TARGET_COUNTRIES = [
    "LT", "LV", "EE", "FI", "SE", "NO", "DK", "IS", "DE", "PL",
    "GB", "IE", "NL", "BE", "LU", "FR", "ES", "PT", "IT", "AT",
    "CZ", "SK", "SI", "HU", "HR", "RO", "BG", "GR", "CY", "MT",
]
RELEASE = "2026-06-17.0"

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
    with open(_MAIN_ARTIFACT, encoding="utf-8") as f:
        ents = json.load(f).get("entities", [])
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
        if len(core) >= 4 and core in brand_cores and tk[k:] \
                and all(_safe_qualifier(t) for t in tk[k:]):
            return True
    return False


def _is_branded(r):
    return bool(r.get("brand_wd") or (r.get("brand") and len(N.norm(r["brand"])) >= 3))


def _majority_category(recs):
    c = Counter(r["cat"] for r in recs if r["cat"] in _CATEGORY_MAP)
    if not c:
        return None
    top = c.most_common()
    if len(top) > 1 and top[0][1] == top[1][1] \
            and len({_CATEGORY_MAP[k][0] for k, n in top if n == top[0][1]}) > 1:
        return None
    return top[0][0]


def _entity(eid, name, n, cat, country, source, extra):
    mt, rt, ic = _CATEGORY_MAP[cat]
    e = {"entity_id": eid, "canonical_name": name, "entity_type": "MERCHANT",
         "aliases": [name], "related_aliases": [], "alias_norms": [n],
         "country_coverage": [country], "categories": [cat], "merchant_type": mt,
         "icon_key": ic, "known_domains": [], "is_processor": False, "is_brand": True,
         "brand_relationships": [], "recurring_type": rt, "_source": source}
    e.update(extra)
    return e


def _fetch(country, cache_dir):
    path = os.path.join(cache_dir, f"overture_{country}.json")
    with open(path, encoding="utf-8") as f:
        return json.load(f)


def _country_entities(country, raw, taken, brand_cores, stats):
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
            if len(n) < 5 or n in _GENERIC or n in taken:
                continue
            unbranded[n].append(r)
    ents = []
    for key, recs in branded.items():
        bn = Counter(r["brand"] for r in recs if r.get("brand")).most_common(1)
        bn = bn[0][0].strip() if bn else recs[0]["name"].strip()
        n = N.norm(bn)
        if len(n) < 3 or n in _GENERIC or n in taken:
            continue
        cat = _majority_category(recs)
        if not cat:
            continue
        wd = key[1] if key[0] == "wd" else next((r["brand_wd"] for r in recs if r.get("brand_wd")), None)
        web = next((r["website"] for r in recs if r.get("website")), None)
        dom = web.split("//")[-1].split("/")[0].replace("www.", "") if web else None
        ents.append(_entity(f"ovb:{country.lower()}:{n}", bn, n, cat, country,
                            "overture-brand" + ("+wikidata" if wd else ""),
                            {"brand_wikidata": wd, "known_domains": [dom] if dom else []}))
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
        ents.append(_entity(f"ovu:{country.lower()}:{n}", name, n, cat, country,
                            "overture-local", {"known_domains": [dom] if dom else []}))
    return ents


_SLIM = ("entity_id", "canonical_name", "entity_type", "aliases", "related_aliases",
         "categories", "merchant_type", "icon_key", "known_domains", "is_processor",
         "is_brand", "recurring_type", "country_coverage", "_source")


def build(cache_dir, out_path, countries):
    t0 = time.time()
    taken = _existing_norms()
    brand_cores = {n for n in taken if len(n) >= 4}
    stats = {"raw": 0, "format_collapsed": 0, "per_country": {}}
    seen = set()
    rows = []
    kb_drop = dup_drop = 0
    for cc in countries:
        raw = _fetch(cc, cache_dir)
        stats["raw"] += len(raw)
        ents = _country_entities(cc, raw, taken, brand_cores, stats)
        kept = 0
        for e in ents:
            n = e["alias_norms"][0]
            if n in taken:
                kb_drop += 1
                continue
            if n in seen:
                dup_drop += 1
                continue
            seen.add(n)
            slim = {k: e.get(k) for k in _SLIM}
            slim["alias_norms"] = [n]
            rows.append((n, n[:3], json.dumps(slim, ensure_ascii=False)))
            kept += 1
        stats["per_country"][cc] = {"raw": len(raw), "entities": kept}

    if os.path.exists(out_path):
        os.remove(out_path)
    os.makedirs(os.path.dirname(out_path), exist_ok=True)
    con = sqlite3.connect(out_path)
    con.execute("CREATE TABLE merchants (norm TEXT PRIMARY KEY, n3 TEXT, entity TEXT)")
    con.executemany("INSERT INTO merchants VALUES (?,?,?)", rows)
    con.execute("CREATE INDEX i_n3 ON merchants(n3)")
    con.commit()
    con.close()
    stats.update(entities=len(rows), alias_rows=len(rows), kb_collisions=kb_drop,
                 cross_country_dups=dup_drop, db_bytes=os.path.getsize(out_path),
                 build_s=round(time.time() - t0, 1), out=out_path)
    return stats


if __name__ == "__main__":
    ap = argparse.ArgumentParser()
    ap.add_argument("--cache", default=os.path.join(_HERE, "cache", "prod"))
    ap.add_argument("--out", default=os.path.join(_KB_DIR, "merchant_index.sqlite"))
    ap.add_argument("--countries", default=",".join(TARGET_COUNTRIES))
    a = ap.parse_args()
    s = build(a.cache, a.out, a.countries.split(","))
    print(json.dumps({k: v for k, v in s.items() if k != "per_country"}, indent=1))
    print("per-country:", json.dumps(s["per_country"]))
