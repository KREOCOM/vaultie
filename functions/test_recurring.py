"""Unit tests for recurring detection — no network/Firestore, runs anywhere.

New model: EVERY outgoing merchant is returned (even seen once), tagged
autoDetected when the merchant DB knows it. Income and frequent-spending
merchants are never candidates. Variants collapse (processor prefixes stripped,
known merchants grouped by canonical name).

Run:  python3 functions/test_recurring.py
"""

import os
import sys

sys.path.insert(0, os.path.dirname(__file__))

import merchant_db  # noqa: E402
from recurring import detect_recurring  # noqa: E402

merchant_db._cache = [
    {"_key": "spotify", "displayName": "Spotify", "type": "subscription",
     "category": "entertainment", "logoDomain": "spotify.com",
     "aliases": ["spotify"], "status": "active"},
    {"_key": "dribbble", "displayName": "Dribbble", "type": "subscription",
     "category": "entertainment", "logoDomain": "dribbble.com",
     "aliases": ["dribbble"], "status": "active"},
    {"_key": "telia", "displayName": "Telia", "type": "bill",
     "category": "connectivity", "logoDomain": None,
     "aliases": ["telia"], "status": "active"},
    {"_key": "maxima", "displayName": "Maxima", "type": "frequent",
     "category": "other", "logoDomain": None,
     "aliases": ["maxima"], "status": "active"},
    {"_key": "applecombill", "displayName": "Apple", "type": "possible",
     "category": "entertainment", "logoDomain": "apple.com",
     "aliases": ["apple.com", "apple"], "status": "active"},
]


def _txn(date, amount, name, indicator="DBIT"):
    return {
        "booking_date": date,
        "credit_debit_indicator": indicator,
        "transaction_amount": {"amount": f"{amount:.2f}", "currency": "EUR"},
        "creditor": {"name": name} if indicator == "DBIT" else None,
        "debtor": {"name": name} if indicator == "CRDT" else None,
        "remittance_information": [name],
    }


DEMO = [
    _txn("2026-05-05", 9.99, "Spotify AB"),
    _txn("2026-06-05", 9.99, "Spotify AB"),
    # Dribbble variants — must collapse into ONE auto-detected candidate.
    _txn("2026-05-28", 14.62, "DRIBBBLE PRO STANDARD"),
    _txn("2026-06-29", 9.04, "DRIBBBLE*"),
    # apple.com variants (possible) → one auto candidate, needs review.
    _txn("2026-05-20", 22.99, "APPLE.COM/BILL"),
    _txn("2026-06-25", 117.46, "APPLE.COM/US"),
    _txn("2026-06-08", 11.99, "UAB Telia 8842"),
    # Unknown, single occurrence — now returned (manual, unchecked).
    _txn("2026-06-22", 45.00, "Kuro Pavilnys UAB"),
    # Card-processor prefix — real merchant is APPMYWEB (unknown).
    _txn("2026-06-11", 61.88, "PAYPAL*APPMYWEB"),
    # Rent (unknown, large) — a manual candidate.
    _txn("2026-05-03", 1203.00, "MB Artusgrupė"),
    _txn("2026-05-31", 1043.00, "MB Artusgrupe"),
    # Frequent + income — never candidates.
    _txn("2026-06-03", 43.17, "Maxima LT"),
    _txn("2026-06-09", 21.80, "Maxima LT"),
    _txn("2026-06-01", 2100.00, "Employer UAB", indicator="CRDT"),
]


def main() -> int:
    result = detect_recurring(DEMO)
    cands = result["candidates"]
    by_name = {c["name"]: c for c in cands}
    freq_names = {f["name"] for f in result["frequent"]}
    failures = []

    def check(cond, msg):
        if not cond:
            failures.append(msg)

    # Auto-detected known merchants.
    check(by_name.get("Spotify", {}).get("autoDetected") is True, "Spotify not auto")
    check(by_name.get("Spotify", {}).get("needsReview") is False, "Spotify needsReview")
    check(by_name.get("Telia", {}).get("type") == "bill", "Telia not bill")

    # Dribbble variants collapse into one.
    dribbble = [c for c in cands if c["name"] == "Dribbble"]
    check(len(dribbble) == 1, f"Dribbble not collapsed (got {len(dribbble)})")
    check(dribbble and dribbble[0]["autoDetected"] is True, "Dribbble not auto")
    check(dribbble and dribbble[0]["occurrences"] == 2, "Dribbble occ != 2")

    # apple.com variants collapse; possible → auto + review.
    apple = [c for c in cands if c["name"] == "Apple"]
    check(len(apple) == 1, f"Apple not collapsed (got {len(apple)})")
    check(apple and apple[0]["autoDetected"] is True, "Apple not auto")
    check(apple and apple[0]["needsReview"] is True, "Apple (possible) not review")

    # Unknown merchants are returned as MANUAL candidates (autoDetected False).
    for nm in ("Kuro Pavilnys UAB", "MB Artusgrupė"):
        check(nm in by_name, f"{nm} not returned")
        check(by_name.get(nm, {}).get("autoDetected") is False, f"{nm} should be manual")

    # Card-processor prefix stripped → APPMYWEB, not PayPal.
    check(any("appmyweb" in c["name"].lower() for c in cands),
          "PAYPAL*APPMYWEB not resolved to APPMYWEB")
    check(all("paypal" not in c["name"].lower() for c in cands),
          "processor prefix leaked into a candidate")

    # Never candidates: frequent + income.
    check("Maxima" in freq_names, "Maxima not frequent")
    check("Maxima" not in by_name, "Maxima wrongly a candidate")
    check("Employer UAB" not in by_name, "Income wrongly a candidate")

    # Every candidate carries the autoDetected flag.
    check(all("autoDetected" in c for c in cands), "candidate missing autoDetected")

    auto = sum(1 for c in cands if c["autoDetected"])
    print(f"{len(cands)} candidates ({auto} auto, {len(cands) - auto} manual), "
          f"{len(result['frequent'])} frequent:")
    for c in cands:
        tag = "AUTO" if c["autoDetected"] else "manual"
        print(f"  • [{tag:6}] {c['name']:<20} {c['type']:<12} {c['cost']:>7.2f} "
              f"{c['category']:<13} ×{c['occurrences']}")

    if failures:
        print("\nFAILURES:")
        for f in failures:
            print(f"  ✗ {f}")
        return 1
    print("\nAll assertions passed ✓")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
