"""Offline merchant-KB builder.

Compiles curated seed + open-data (Wikidata, CC0) into the versioned, deploy-
bundled runtime artifact functions/kb/merchant_kb.v{1,2}.json. OFFLINE only —
never invoked during a bank sync. Lives outside functions/ so it is not part of
the Cloud Functions deploy artifact.

  v1  = curated only (byte-safe; --v1)
  v2  = curated (override) + Wikidata brands (default)

Determinism: entities sorted by entity_id; provenance is source shas / snapshot
record counts, no wall-clock. Runtime consumes only the compiled artifact.

Usage:
  python3 tools/kb_build/build_kb.py            # v2 from cached snapshot
  python3 tools/kb_build/build_kb.py --refresh  # re-fetch Wikidata, rebuild v2
  python3 tools/kb_build/build_kb.py --v1       # rebuild byte-safe v1
"""

import hashlib
import json
import os
import sys
from collections import defaultdict

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import normalize as N
from sources import osm, wikidata

_ROOT = os.path.dirname(os.path.dirname(os.path.dirname(os.path.abspath(__file__))))
_CURATED = os.path.join(_ROOT, "functions", "kb_entities.json")
_OUT_DIR = os.path.join(_ROOT, "functions", "kb")

SCHEMA_VERSION = 2
_MERCHANT_TYPE = {"fuel": "GAS_STATION", "food": "RESTAURANT",
                  "groceries": "SUPERMARKET", "pharmacy": "PHARMACY",
                  "retail": "RETAIL"}
_ICON = {"fuel": "FUEL", "food": "FOOD", "groceries": "GROCERIES",
         "pharmacy": "PHARMACY", "retail": "SHOPPING"}


def _sha(path):
    with open(path, "rb") as f:
        return hashlib.sha256(f.read()).hexdigest()


def _curated():
    with open(_CURATED, encoding="utf-8") as f:
        ents = json.load(f).get("entities", [])
    # Ensure curated entities carry alias_norms for the runtime index.
    for e in ents:
        e.setdefault("alias_norms",
                     sorted({N.norm(a) for a in e.get("aliases", []) if N.norm(a)}))
        e["_source"] = "curated"
    return ents


def _wikidata_entities(records, curated_norms):
    by_id = {}
    for r in records:
        disp, norms = N.sanitize_aliases([r["label"]] + r.get("alts", []))
        # Never let open data shadow a curated alias (curated wins).
        keep = [(d, n) for d, n in zip(disp, norms) if n not in curated_norms]
        if not keep:
            continue
        disp = [d for d, _ in keep]
        norms = sorted({n for _, n in keep})
        eid = N.slug(r["label"])
        if not eid or eid in curated_norms:
            continue
        cat = r["category"]
        e = by_id.get(eid)
        if e is None:
            e = {
                "entity_id": eid,
                "canonical_name": r["label"],
                "entity_type": "BRAND",
                "aliases": [], "related_aliases": [], "alias_norms": [],
                "country_coverage": [], "categories": [cat],
                "merchant_type": _MERCHANT_TYPE.get(cat, "RETAIL"),
                "icon_key": _ICON.get(cat, "SHOPPING"),
                "known_domains": [], "is_processor": False, "is_brand": True,
                "brand_relationships": [],
                "popularity_prior": 0.6 if r["scope"] == "global" else 0.5,
                "recurring_type": "frequent",
                "_source": "wikidata",
            }
            by_id[eid] = e
        e["aliases"] = sorted(set(e["aliases"]) | set(disp))
        e["alias_norms"] = sorted(set(e["alias_norms"]) | set(norms))
        e["country_coverage"] = sorted(set(e["country_coverage"]) | set(r["countries"]))
        if cat not in e["categories"]:
            e["categories"].append(cat)
    return _merge_shared_alias(list(by_id.values()))


def _merge_shared_alias(entities):
    """Collapse entities that share any alias_norm into one (union-find). Cross-
    country same-brand records (Coop Norge / Coop Sverige, Esso / Esso Express)
    otherwise return as sibling candidates and mutually trip margin-abstention.
    Generic — no brand is named; connectivity is purely shared sanitized alias."""
    parent = {}

    def find(x):
        parent.setdefault(x, x)
        root = x
        while parent[root] != root:
            root = parent[root]
        while parent[x] != root:
            parent[x], x = root, parent[x]
        return root

    def union(a, b):
        parent[find(a)] = find(b)

    owner = {}
    for e in entities:
        find(e["entity_id"])
        for n in e["alias_norms"]:
            if n in owner:
                union(e["entity_id"], owner[n])
            else:
                owner[n] = e["entity_id"]

    comp = defaultdict(list)
    for e in entities:
        comp[find(e["entity_id"])].append(e)

    merged = []
    for group in comp.values():
        if len(group) == 1:
            merged.append(group[0])
            continue
        base = min(group, key=lambda e: (len(e["canonical_name"]), e["entity_id"]))
        m = dict(base)
        m["aliases"] = sorted({a for e in group for a in e["aliases"]})
        m["alias_norms"] = sorted({n for e in group for n in e["alias_norms"]})
        m["country_coverage"] = sorted({c for e in group for c in e["country_coverage"]})
        cats = []
        for e in group:
            for c in e["categories"]:
                if c not in cats:
                    cats.append(c)
        m["categories"] = cats
        m["popularity_prior"] = max(e["popularity_prior"] for e in group)
        merged.append(m)
    return merged


def build_v2(refresh=False):
    curated = _curated()
    curated_norms = {n for e in curated for n in e.get("alias_norms", [])}
    curated_ids = {e["entity_id"] for e in curated}

    records = wikidata.fetch(refresh=refresh)
    records += osm.fetch(refresh=refresh)  # [] unless ODbL review enabled
    wd = [e for e in _wikidata_entities(records, curated_norms | curated_ids)]

    entities = sorted(curated + wd, key=lambda e: e["entity_id"])
    countries = sorted({c for e in entities for c in e.get("country_coverage", [])})
    artifact = {
        "schema_version": SCHEMA_VERSION,
        "kb_version": "2026.07.2-wikidata",
        "sources": [
            f"curated:kb_entities.json@sha256:{_sha(_CURATED)[:16]}",
            f"wikidata:CC0:{len(records)}records",
            "osm:ODbL:disabled",
        ],
        "countries": countries,
        "entity_count": len(entities),
        "curated_count": len(curated),
        "wikidata_count": len(wd),
        "entities": entities,
    }
    out = os.path.join(_OUT_DIR, "merchant_kb.v2.json")
    os.makedirs(_OUT_DIR, exist_ok=True)
    with open(out, "w", encoding="utf-8") as f:
        json.dump(artifact, f, ensure_ascii=False, indent=1, sort_keys=False)
        f.write("\n")
    print(f"built {out}")
    print(f"  entities={len(entities)} (curated={len(curated)} wikidata={len(wd)}) "
          f"countries={len(countries)} raw_records={len(records)}")


def build_v1():
    curated = _curated()
    for e in curated:
        e.pop("_source", None)
    artifact = {
        "schema_version": SCHEMA_VERSION, "kb_version": "2026.07.1-curated",
        "sources": [f"curated:kb_entities.json@sha256:{_sha(_CURATED)[:16]}"],
        "countries": sorted({c for e in curated for c in e.get("country_coverage", [])}),
        "entity_count": len(curated), "entities": curated,
    }
    out = os.path.join(_OUT_DIR, "merchant_kb.v1.json")
    with open(out, "w", encoding="utf-8") as f:
        json.dump(artifact, f, ensure_ascii=False, indent=2)
        f.write("\n")
    print(f"built {out} entities={len(curated)}")


if __name__ == "__main__":
    if "--v1" in sys.argv:
        build_v1()
    else:
        build_v2(refresh="--refresh" in sys.argv)
