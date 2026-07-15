"""LOCAL taxonomy-alignment audit (no AI). Are the categories the resolver +
AI can emit all mappable by CAT_MAP? Anything emittable but NOT a CAT_MAP key
silently becomes 'Kita' — a hidden section leak."""
import json
import sys

sys.path.insert(0, ".")
import resolver
import global_index
from dashboard import CAT_MAP, OTHER
from ai_enrichment import _CATEGORIES

CATSET = set(CAT_MAP.keys())


def tx(n):
    return {"booking_date": "2026-05-01", "credit_debit_indicator": "DBIT",
            "transaction_amount": {"amount": "12", "currency": "EUR"},
            "creditor": {"name": n}, "remittance_information": [n],
            "bank_transaction_code": {"code": "CCRD", "sub_code": "OTHR"}}


def main():
    print("=== AI vocabulary vs CAT_MAP ===")
    ai_missing = [c for c in _CATEGORIES if c not in CATSET and c != "other"]
    print(f"AI categories: {len(_CATEGORIES)}   not in CAT_MAP: {ai_missing or 'NONE ✓'}")

    print("\n=== Resolver/global-index emitted categories vs CAT_MAP ===")
    raw = json.load(open(sys.argv[1]))
    seen, names = set(), []
    for r in raw:
        k = r["name"].lower()
        if k not in seen:
            seen.add(k)
            names.append(r["name"])
    from collections import Counter
    resolved_cats = Counter()
    unmapped = Counter()
    n_hit = 0
    for nm in names:
        try:
            _, hit, _ = resolver.resolve_hit(tx(nm), None)
        except Exception:
            continue
        if hit:
            n_hit += 1
            cat = (hit[2] or "other").lower()
            resolved_cats[cat] += 1
            if cat not in CATSET and cat != "other":
                unmapped[cat] += 1
    print(f"resolved hits: {n_hit:,}   distinct categories emitted: {len(resolved_cats)}")
    print(f"categories emitted but NOT in CAT_MAP (→ silently 'Kita'): {len(unmapped)}")
    for c, n in unmapped.most_common(40):
        print(f"    {c:32} {n:>5} merchants  → Kita")
    leaked = sum(unmapped.values())
    print(f"\n  total resolved merchants silently dropped to Kita: {leaked:,} "
          f"({100*leaked/max(1,n_hit):.1f}% of resolved)")


if __name__ == "__main__":
    main()
