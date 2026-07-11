"""Wikidata (CC0) merchant-brand acquisition — OFFLINE build-time only.

Wikidata's data is released under CC0 1.0 (public domain), so derived brand
records may be bundled into the runtime artifact with no attribution or share-
alike obligation. (Contrast OSM/ODbL — see sources/osm.py.)

This runs during `tools/kb_build/build_kb.py`, NEVER at runtime. It fetches
consumer-facing brand/chain entities for the target markets, caches the raw
result to data/wikidata_brands.snapshot.json for reproducible offline rebuilds,
and returns normalized records. Runtime never imports this module.

Two acquisition shapes:
  * GLOBAL, by type — categories dominated by multinationals that appear on
    statements everywhere (fuel, fast food). Country coverage from P17, widened
    to the full target set because P17 is HQ, not operating country.
  * PER-COUNTRY (P17 == target) — domestic retail / supermarket / brand.

No merchant is special-cased; everything is a category-scoped bulk pull.
"""

import json
import os
import time
import urllib.parse
import urllib.request

_ENDPOINT = "https://query.wikidata.org/sparql"
_UA = "VaultieKB-build/0.2 (offline merchant KB; contact osva50042@gmail.com)"
_SNAPSHOT = os.path.join(os.path.dirname(__file__), "..", "data",
                         "wikidata_brands.snapshot.json")

# ISO code -> Wikidata country QID (target markets).
TARGET_COUNTRIES = {
    "LT": "Q37", "LV": "Q211", "EE": "Q191", "NO": "Q20",
    "SE": "Q34", "DK": "Q35", "FI": "Q33",
}

# Wikidata class QIDs -> our coarse category. Types are consumer-facing chains
# that plausibly appear as bank-statement counterparties.
_GLOBAL_TYPES = {           # multinationals: query worldwide
    "Q64027599": "fuel",            # gas station chain
    "Q18509232": "food",            # fast food restaurant chain
}
_COUNTRY_TYPES = {          # domestic: query per target country
    "Q507619": "retail",            # chain store / retail chain
    "Q18043413": "groceries",       # supermarket chain
    "Q431289": "retail",            # brand
}
_LANGS = "en,lt,lv,et,nb,sv,da,fi,de"
_ALT_LANGS = '"en","lt","lv","et","nb","sv","da","fi","de"'


def _run(query, timeout=55):
    url = _ENDPOINT + "?" + urllib.parse.urlencode(
        {"query": query, "format": "json"})
    req = urllib.request.Request(url, headers={"User-Agent": _UA,
                                               "Accept": "application/sparql-results+json"})
    with urllib.request.urlopen(req, timeout=timeout) as r:
        return json.load(r)["results"]["bindings"]


def _global_query(type_qid):
    return f"""
SELECT ?item ?itemLabel (GROUP_CONCAT(DISTINCT ?alt;separator="|") AS ?alts)
       (GROUP_CONCAT(DISTINCT ?cc;separator="|") AS ?ccs) WHERE {{
  ?item wdt:P31 wd:{type_qid} .
  OPTIONAL {{ ?item wdt:P17 ?c . ?c wdt:P297 ?cc }}
  OPTIONAL {{ ?item skos:altLabel ?alt FILTER(LANG(?alt) IN ({_ALT_LANGS})) }}
  SERVICE wikibase:label {{ bd:serviceParam wikibase:language "{_LANGS}". }}
}} GROUP BY ?item ?itemLabel LIMIT 2000"""


def _country_query(country_qid):
    types = " ".join(f"wd:{q}" for q in _COUNTRY_TYPES)
    return f"""
SELECT ?item ?itemLabel (GROUP_CONCAT(DISTINCT ?alt;separator="|") AS ?alts)
       (GROUP_CONCAT(DISTINCT ?tl;separator="|") AS ?types) WHERE {{
  ?item wdt:P17 wd:{country_qid} ; wdt:P31 ?t .
  VALUES ?t {{ {types} }}
  ?t rdfs:label ?tl FILTER(LANG(?tl)="en")
  OPTIONAL {{ ?item skos:altLabel ?alt FILTER(LANG(?alt) IN ({_ALT_LANGS})) }}
  SERVICE wikibase:label {{ bd:serviceParam wikibase:language "{_LANGS}". }}
}} GROUP BY ?item ?itemLabel LIMIT 1500"""


def _cat_from_types(type_str):
    low = (type_str or "").lower()
    if "gas station" in low or "petrol" in low:
        return "fuel"
    if "fast food" in low or "restaurant" in low:
        return "food"
    if "supermarket" in low or "grocery" in low:
        return "groceries"
    if "pharmacy" in low or "drugstore" in low:
        return "pharmacy"
    return "retail"


def fetch(refresh=False):
    """Return raw brand records. Uses the cached snapshot unless refresh=True."""
    if not refresh and os.path.exists(_SNAPSHOT):
        with open(_SNAPSHOT, encoding="utf-8") as f:
            return json.load(f)["records"]

    records = []
    # Global (international) categories.
    for qid, cat in _GLOBAL_TYPES.items():
        for b in _run(_global_query(qid)):
            label = b["itemLabel"]["value"]
            if label.startswith("Q") and label[1:].isdigit():
                continue  # unlabeled entity
            ccs = [c for c in b.get("ccs", {}).get("value", "").split("|") if c]
            records.append({
                "label": label,
                "alts": [a for a in b.get("alts", {}).get("value", "").split("|") if a],
                "category": cat,
                "countries": sorted(set(ccs) & set(TARGET_COUNTRIES)) or list(TARGET_COUNTRIES),
                "scope": "global",
            })
        time.sleep(0.3)
    # Per-country (domestic) categories.
    for cc, qid in TARGET_COUNTRIES.items():
        for b in _run(_country_query(qid)):
            label = b["itemLabel"]["value"]
            if label.startswith("Q") and label[1:].isdigit():
                continue
            records.append({
                "label": label,
                "alts": [a for a in b.get("alts", {}).get("value", "").split("|") if a],
                "category": _cat_from_types(b.get("types", {}).get("value", "")),
                "countries": [cc],
                "scope": "domestic",
            })
        time.sleep(0.3)

    os.makedirs(os.path.dirname(_SNAPSHOT), exist_ok=True)
    with open(_SNAPSHOT, "w", encoding="utf-8") as f:
        json.dump({"source": "wikidata", "license": "CC0-1.0",
                   "record_count": len(records), "records": records},
                  f, ensure_ascii=False, indent=1)
    return records
