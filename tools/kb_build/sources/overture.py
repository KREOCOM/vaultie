"""Overture Maps Places source — LT physical-merchant POIs (build-time only).

Open data: Overture Places, licensed CC-BY 4.0 (attribution: "© Overture Maps
Foundation"). Queried OFFLINE at build time via DuckDB over the public S3 parquet
release; the runtime never touches S3. A minified snapshot is cached under
tools/kb_build/cache/ so rebuilds are reproducible without re-hitting the network.

Scope is deliberately narrow (PROOF-OF-CONCEPT): COUNTRY = LT only, and only the
merchant categories relevant to Vaultie's real physical-spending false-recurring
problem. Unrelated POI classes are never imported.
"""

import json
import os

_CACHE = os.path.join(os.path.dirname(os.path.dirname(os.path.abspath(__file__))),
                      "cache", "overture_lt_places.json")

RELEASE = "2026-06-17.0"
# LT bounding box (min/max lon/lat). Border spill is filtered downstream by the
# category+name identity match, not by exact admin polygon (POC tolerance).
BBOX = (20.9, 53.8, 26.9, 56.5)

# The only Overture categories we pull — each maps to an existing Vaultie
# merchant_type in build_lt_enrichment.py. Nothing else is imported.
CATEGORIES = [
    "restaurant", "fast_food_restaurant", "supermarket", "grocery_store",
    "convenience_store", "pharmacy", "bakery", "car_wash", "gas_station",
    "gym", "fitness_center", "health_club",
]


def _query_s3():
    """Live DuckDB query over the Overture S3 release. Only used with --refresh;
    normal builds read the cached snapshot. Imported lazily so the builder has no
    hard duckdb dependency when the cache exists."""
    import duckdb
    con = duckdb.connect()
    con.execute("INSTALL httpfs; LOAD httpfs; SET s3_region='us-west-2';")
    path = (f"s3://overturemaps-us-west-2/release/{RELEASE}"
            "/theme=places/type=place/*.parquet")
    inlist = ",".join(f"'{c}'" for c in CATEGORIES)
    x0, y0, x1, y1 = BBOX
    rows = con.execute(f"""
        SELECT names.primary AS name, categories.primary AS cat,
               brand.names.primary AS brand, brand.wikidata AS brand_wd,
               websites[1] AS website,
               round((bbox.xmin+bbox.xmax)/2,4) AS lon,
               round((bbox.ymin+bbox.ymax)/2,4) AS lat
        FROM read_parquet('{path}')
        WHERE bbox.xmin BETWEEN {x0} AND {x1}
          AND bbox.ymin BETWEEN {y0} AND {y1}
          AND names.primary IS NOT NULL
          AND categories.primary IN ({inlist})
    """).fetchall()
    return [{"name": r[0], "cat": r[1], "brand": r[2], "brand_wd": r[3],
             "website": r[4], "lon": r[5], "lat": r[6]} for r in rows]


def fetch(refresh=False):
    """Return the raw LT POI records (from cache, or S3 when refresh=True)."""
    if refresh or not os.path.exists(_CACHE):
        records = _query_s3()
        os.makedirs(os.path.dirname(_CACHE), exist_ok=True)
        with open(_CACHE, "w", encoding="utf-8") as f:
            json.dump(records, f, ensure_ascii=False, separators=(",", ":"))
        return records
    with open(_CACHE, encoding="utf-8") as f:
        return json.load(f)
