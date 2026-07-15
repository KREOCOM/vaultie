"""Collect real merchant names + independent OSM category tags across EU cities
via the Overpass API. Writes a JSON list of {name, osm, country} — the raw,
independent test population (NOT from our merchant_index.sqlite).
"""
import json
import sys
import time
import urllib.parse
import urllib.request

OUT = sys.argv[1] if len(sys.argv) > 1 else "/tmp/osm_merchants.json"

# (country, city, bbox S,W,N,E)
CITIES = [
    ("DE", "Berlin", "52.45,13.30,52.56,13.47"),
    ("FR", "Paris", "48.82,2.27,48.90,2.41"),
    ("NO", "Oslo", "59.88,10.66,59.96,10.83"),
    ("PL", "Warszawa", "52.19,20.94,52.29,21.09"),
    ("SE", "Stockholm", "59.29,18.02,59.37,18.13"),
    ("FI", "Helsinki", "60.14,24.89,60.21,25.02"),
    ("IT", "Roma", "41.86,12.44,41.93,12.54"),
    ("ES", "Madrid", "40.39,-3.73,40.46,-3.65"),
    ("NL", "Amsterdam", "52.34,4.85,52.40,4.95"),
    ("LT", "Vilnius", "54.65,25.22,54.72,25.34"),
    ("EE", "Tallinn", "59.41,24.71,59.46,24.82"),
    ("LV", "Riga", "56.92,24.06,56.98,24.17"),
    ("DK", "Kobenhavn", "55.65,12.53,55.71,12.62"),
    ("CZ", "Praha", "50.05,14.39,50.11,14.48"),
    ("AT", "Wien", "48.18,16.34,48.24,16.41"),
    ("PT", "Lisboa", "38.69,-9.17,38.75,-9.11"),
]

AMENITIES = ("restaurant|cafe|fast_food|bar|pub|pharmacy|fuel|bank|cinema|"
             "dentist|clinic|doctors|hospital|theatre|nightclub|school|"
             "university|college|kindergarten|ice_cream|food_court")

ENDPOINTS = ["https://overpass-api.de/api/interpreter",
             "https://overpass.kumi.systems/api/interpreter"]


def query(bbox):
    q = (f"[out:json][timeout:60];("
         f'node["shop"]["name"]({bbox});'
         f'node["amenity"~"^({AMENITIES})$"]["name"]({bbox});'
         f");out tags 1400;")
    data = urllib.parse.urlencode({"data": q}).encode()
    last = None
    for ep in ENDPOINTS:
        for attempt in range(2):
            try:
                req = urllib.request.Request(ep, data=data,
                                             headers={"User-Agent": "vaultie-coverage-test"})
                with urllib.request.urlopen(req, timeout=90) as r:
                    return json.loads(r.read().decode())
            except Exception as e:  # noqa: BLE001
                last = e
                time.sleep(4 * (attempt + 1))
    print("  query failed:", last)
    return {"elements": []}


def main():
    out = []
    for cc, city, bbox in CITIES:
        d = query(bbox)
        els = d.get("elements", [])
        n = 0
        for e in els:
            t = e.get("tags", {})
            name = (t.get("name") or "").strip()
            osm = t.get("shop") or t.get("amenity")
            if not name or not osm:
                continue
            out.append({"name": name, "osm": osm, "country": cc})
            n += 1
        print(f"  {cc} {city}: {n} named POIs (total {len(out)})")
        time.sleep(3)
    with open(OUT, "w") as f:
        json.dump(out, f, ensure_ascii=False)
    print(f"\nWrote {len(out)} raw POIs to {OUT}")


if __name__ == "__main__":
    main()
