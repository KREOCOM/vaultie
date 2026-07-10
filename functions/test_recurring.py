"""Unit tests for recurring detection — no network/Firestore, runs anywhere.

The merchant DB is mocked by seeding merchant_db._cache directly, so we exercise
both paths: known merchants (recurring on sight, incl. type + frequent) and the
pattern algorithm (>=2 similar amounts at a recognised cadence, incl. rent).

Run:  python3 functions/test_recurring.py
"""

import os
import sys

sys.path.insert(0, os.path.dirname(__file__))

import merchant_db  # noqa: E402
from recurring import detect_recurring  # noqa: E402

# Mock merchant DB (bypasses Firestore).
merchant_db._cache = [
    {"_key": "netflix", "displayName": "Netflix", "type": "subscription",
     "category": "entertainment", "logoDomain": "netflix.com",
     "aliases": ["netflix"], "matchMode": "substring", "status": "active"},
    {"_key": "spotify", "displayName": "Spotify", "type": "subscription",
     "category": "entertainment", "logoDomain": "spotify.com",
     "aliases": ["spotify"], "matchMode": "substring", "status": "active"},
    {"_key": "adobe", "displayName": "Adobe", "type": "subscription",
     "category": "entertainment", "logoDomain": "adobe.com",
     "aliases": ["adobe"], "matchMode": "substring", "status": "active"},
    {"_key": "telia", "displayName": "Telia", "type": "bill",
     "category": "connectivity", "logoDomain": None,
     "aliases": ["telia"], "matchMode": "substring", "status": "active"},
    {"_key": "maxima", "displayName": "Maxima", "type": "frequent",
     "category": "other", "logoDomain": None,
     "aliases": ["maxima"], "matchMode": "substring", "status": "active"},
    {"_key": "applecombill", "displayName": "Apple", "type": "possible",
     "category": "entertainment", "logoDomain": "apple.com",
     "aliases": ["apple.com"], "matchMode": "substring", "status": "active"},
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
    _txn("2026-04-05", 9.99, "Spotify AB"),
    _txn("2026-05-05", 9.99, "Spotify AB"),
    _txn("2026-06-05", 9.99, "Spotify AB"),
    _txn("2026-04-12", 12.99, "Netflix International"),
    _txn("2026-05-12", 12.99, "Netflix International"),
    _txn("2026-06-12", 12.99, "Netflix International"),
    # Known subscription seen ONCE — still detected.
    _txn("2026-06-19", 19.99, "Adobe Systems Software"),
    # Known bill, reference-number variants collapse into one.
    _txn("2026-04-08", 11.99, "PVM SF 2026/04 UAB Telia 8842"),
    _txn("2026-05-08", 11.99, "PVM SF 2026/05 UAB Telia 9137"),
    _txn("2026-06-08", 11.99, "PVM SF 2026/06 UAB Telia 9455"),
    # Possible (apple.com) — subscription needing review.
    _txn("2026-05-20", 2.99, "APPLE.COM/BILL"),
    # Rent: large regular payment → bill / housing.
    _txn("2026-04-01", 650.00, "UAB Namu Valda"),
    _txn("2026-05-01", 650.00, "UAB Namu Valda"),
    _txn("2026-06-01", 650.00, "UAB Namu Valda"),
    # Unknown monthly → algorithm subscription.
    _txn("2026-05-15", 29.90, "Sporto klubas XYZ"),
    _txn("2026-06-15", 29.90, "Sporto klubas XYZ"),
    # Frequent (blacklist) — variable groceries, never recurring.
    _txn("2026-06-03", 43.17, "Maxima LT"),
    _txn("2026-06-09", 21.80, "Maxima LT"),
    _txn("2026-06-20", 8.40, "Maxima LT"),
    # Rent to an MB with inconsistent diacritics + varying amount — must merge
    # into ONE housing bill (diacritic fold + large-payment path).
    _txn("2026-05-03", 1203.00, "MB Artusgrupė"),
    _txn("2026-05-31", 1043.00, "MB Artusgrupe"),
    # Salary (CRDT) + single unknown — must NOT be flagged.
    _txn("2026-05-01", 2100.00, "Employer UAB", indicator="CRDT"),
    _txn("2026-06-22", 45.00, "Kuro Pavilnys UAB"),
]


def main() -> int:
    result = detect_recurring(DEMO)
    cands = result["candidates"]
    frequent = result["frequent"]
    by_name = {c["name"]: c for c in cands}
    freq_names = {f["name"] for f in frequent}
    failures = []

    def check(cond, msg):
        if not cond:
            failures.append(msg)

    # Known merchants.
    check(by_name.get("Spotify", {}).get("type") == "subscription",
          "Spotify not a subscription")
    check(by_name.get("Spotify", {}).get("needsReview") is False,
          "Known merchant should not need review")
    check("Adobe" in by_name, "Adobe (single known charge) not detected")
    check(by_name.get("Telia", {}).get("type") == "bill", "Telia not a bill")
    check(by_name.get("Telia", {}).get("occurrences") == 3,
          "Telia variants not merged")

    # Possible → subscription + review.
    check(by_name.get("Apple", {}).get("type") == "subscription",
          "Apple (possible) not a subscription")
    check(by_name.get("Apple", {}).get("needsReview") is True,
          "Possible merchant should need review")

    # Rent via algorithm → bill / housing / review.
    check(by_name.get("UAB Namu Valda", {}).get("type") == "bill",
          "Rent not a bill")
    check(by_name.get("UAB Namu Valda", {}).get("category") == "housing",
          "Rent category != housing")
    check(by_name.get("UAB Namu Valda", {}).get("needsReview") is True,
          "Rent should need review")

    # Unknown monthly → subscription + review.
    check(by_name.get("Sporto klubas XYZ", {}).get("needsReview") is True,
          "Algorithm hit should need review")

    # Frequent — never a candidate, surfaced separately.
    check("Maxima" in freq_names, "Maxima not surfaced as frequent")
    check("Maxima" not in by_name, "Maxima wrongly imported as recurring")

    # MB rent — diacritic variants merge into one housing bill.
    artus = [c for c in cands if "artusgrup" in c["name"].lower()]
    check(len(artus) == 1, f"MB Artusgrupe not merged/detected (got {len(artus)})")
    if artus:
        check(artus[0]["type"] == "bill", "MB rent not a bill")
        check(artus[0]["category"] == "housing", "MB rent not housing")
        check(artus[0]["occurrences"] == 2, "MB rent occurrences != 2")

    # Must NOT be flagged at all.
    check("Employer UAB" not in by_name, "Salary wrongly flagged")
    check("Kuro Pavilnys UAB" not in by_name, "Single unknown wrongly flagged")

    print(f"Detected {len(cands)} candidate(s), {len(frequent)} frequent:")
    for c in cands:
        flag = " (review)" if c["needsReview"] else ""
        print(f"  • {c['name']:<20} {c['type']:<12} {c['cost']:>7.2f} "
              f"{c['category']:<13} ×{c['occurrences']}{flag}")
    for f in frequent:
        print(f"  ~ {f['name']:<20} frequent     ×{f['occurrences']}")

    if failures:
        print("\nFAILURES:")
        for f in failures:
            print(f"  ✗ {f}")
        return 1
    print("\nAll assertions passed ✓")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
