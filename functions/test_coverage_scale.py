"""Scale / coverage test for merchant categorisation.

Samples random merchants from the 97k-entity global index (30 EU countries),
treats each canonical name as a bank descriptor, runs it through the SAME
resolver production uses, and measures:

  * coverage      — % that RESOLVE (vs abstain to UNKNOWN → would go to AI)
  * right entity  — of resolved, % that matched the SAME merchant (not a fuzzy
                    over-match onto a different brand, the "Artus Grupe" bug)
  * category-exact— of right-entity hits, % whose category equals ground truth
  * bucket-match  — same, but after mapping through our CAT_MAP (coarser LT
                    buckets), which is what the user actually sees

Also runs a NOISY pass (uppercase / UAB prefix / city suffix / store number /
truncation) to simulate real bank descriptors and show the coverage drop.

Run:  python3 functions/test_coverage_scale.py [sample_size]
"""
import json
import os
import sqlite3
import sys

sys.path.insert(0, os.path.dirname(__file__))

import kb            # noqa: E402
import merchant_db   # noqa: E402
import resolver      # noqa: E402
import global_index  # noqa: E402
from dashboard import CAT_MAP, OTHER  # noqa: E402

# Empty the Wikidata KB so every lookup exercises the offline global index path
# (the 30-country long tail we care about at scale).
kb._entities = []
kb._alias_index = kb._related_index = kb._norm_index = kb._prefix_index = {}
kb._loaded_source = "test"
merchant_db._cache = []

DB = os.path.join(os.path.dirname(__file__), "kb", "merchant_index.sqlite")
N = int(sys.argv[1]) if len(sys.argv) > 1 else 5000
CITIES = ["Vilnius", "Kaunas", "Berlin", "Riga", "Tallinn", "Warszawa", "Oslo", "Helsinki"]


def bucket(cat):
    """Map a granular category to our coarse LT display bucket (the section)."""
    return CAT_MAP.get((cat or "other").lower(), OTHER)[3]  # section name


def tx(name):
    return {
        "booking_date": "2026-05-01", "credit_debit_indicator": "DBIT",
        "transaction_amount": {"amount": "12.00", "currency": "EUR"},
        "creditor": {"name": name}, "remittance_information": [name],
        "bank_transaction_code": {"code": "CCRD", "sub_code": "OTHR"},
    }


def noisy(name, i):
    """Mangle a clean name into a realistic messy bank descriptor."""
    variants = [
        name.upper(),
        "UAB " + name,
        f"{name} {CITIES[i % len(CITIES)]}",
        f"{name} {587 + (i % 400)}",
        name[:18],
        f"PAYPAL*{name.replace(' ', '')[:16]}",
    ]
    return variants[i % len(variants)]


def run(sample, mangle=None):
    stats = {"total": 0, "resolved": 0, "right_entity": 0, "cat_exact": 0,
             "bucket_match": 0, "unknown": 0, "needs_external": 0}
    wrong_entity, wrong_bucket = [], []
    for i, (canon, gt_cat) in enumerate(sample):
        desc = mangle(canon, i) if mangle else canon
        stats["total"] += 1
        try:
            _, hit, res = resolver.resolve_hit(tx(desc), None)
        except Exception:
            continue
        status = res.get("status")
        if hit is None:
            if status == "NEEDS_EXTERNAL_ENRICHMENT":
                stats["needs_external"] += 1
            else:
                stats["unknown"] += 1
            continue
        stats["resolved"] += 1
        got_name, _typ, got_cat, _logo = hit
        same_entity = got_name.lower().strip() == canon.lower().strip()
        if same_entity:
            stats["right_entity"] += 1
            if (got_cat or "").lower() == (gt_cat or "").lower():
                stats["cat_exact"] += 1
            if bucket(got_cat) == bucket(gt_cat):
                stats["bucket_match"] += 1
            else:
                if len(wrong_bucket) < 25:
                    wrong_bucket.append((desc, gt_cat, got_cat, bucket(gt_cat), bucket(got_cat)))
        else:
            if len(wrong_entity) < 25:
                wrong_entity.append((desc, canon, got_name, got_cat))
    return stats, wrong_entity, wrong_bucket


def pct(a, b):
    return f"{100.0 * a / b:.1f}%" if b else "n/a"


def report(title, stats, wrong_entity, wrong_bucket):
    t, r = stats["total"], stats["resolved"]
    re_ = stats["right_entity"]
    print(f"\n===== {title} (n={t}) =====")
    print(f"  Coverage (resolved):        {r:>6}  {pct(r, t)}")
    print(f"  → UNKNOWN (→AI/other):      {stats['unknown']:>6}  {pct(stats['unknown'], t)}")
    print(f"  → NEEDS_EXTERNAL (→AI):     {stats['needs_external']:>6}  {pct(stats['needs_external'], t)}")
    print(f"  Right entity (of resolved): {re_:>6}  {pct(re_, r)}   (100−this = over-match like 'Artus Grupe')")
    print(f"  Category exact (of right):  {stats['cat_exact']:>6}  {pct(stats['cat_exact'], re_)}")
    print(f"  Bucket match  (of right):   {stats['bucket_match']:>6}  {pct(stats['bucket_match'], re_)}   <- what the user sees")
    if wrong_entity:
        print("  -- over-matched onto a DIFFERENT merchant (sample) --")
        for desc, canon, got, cat in wrong_entity[:12]:
            print(f"     {desc[:28]:28} -> {got[:22]:22} ({cat})   [truth: {canon[:22]}]")
    if wrong_bucket:
        print("  -- right merchant, WRONG bucket (sample) --")
        for desc, gt, got, gb, bb in wrong_bucket[:10]:
            print(f"     {desc[:24]:24} truth={gt}->{gb}  got={got}->{bb}")


def main():
    db = sqlite3.connect(DB)
    rows = db.execute("SELECT entity FROM merchants ORDER BY RANDOM() LIMIT ?", (N,)).fetchall()
    sample = []
    countries = {}
    for (ent,) in rows:
        e = json.loads(ent)
        name = e.get("canonical_name")
        cats = e.get("categories") or []
        if not name or not cats:
            continue
        sample.append((name, cats[0]))
        eid = e.get("entity_id", "?:?:?").split(":")
        cc = eid[1] if len(eid) > 1 else "?"
        countries[cc] = countries.get(cc, 0) + 1
    print(f"Sampled {len(sample)} merchants across {len(countries)} countries: "
          + ", ".join(f"{c}={n}" for c, n in sorted(countries.items(), key=lambda x: -x[1])[:12]))

    report("CLEAN names (best case)", *run(sample))
    report("NOISY names (real bank descriptors)", *run(sample, mangle=noisy))
    print("\nNote: UNKNOWN/NEEDS_EXTERNAL rows are where AI enrichment takes over "
          "in production; this test runs WITHOUT AI to isolate the offline index.")


if __name__ == "__main__":
    main()
