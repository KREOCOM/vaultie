"""Unit tests for recurring detection — no network, runs anywhere.

Covers both detection paths: whitelist merchants (recurring on sight, even a
single charge) and the pattern algorithm (>=2 similar amounts at a regular
cadence, incl. rent). One-off spend, groceries and single unknown payments must
NOT be flagged.

Run:  python3 functions/test_recurring.py
"""

import os
import sys

sys.path.insert(0, os.path.dirname(__file__))

from recurring import detect_recurring  # noqa: E402


def _txn(date, amount, name, indicator="DBIT"):
    return {
        "booking_date": date,
        "value_date": date,
        "credit_debit_indicator": indicator,
        "status": "BOOK",
        "transaction_amount": {"amount": f"{amount:.2f}", "currency": "EUR"},
        "creditor": {"name": name} if indicator == "DBIT" else None,
        "debtor": {"name": name} if indicator == "CRDT" else None,
        "remittance_information": [name],
    }


DEMO_TRANSACTIONS = [
    # Whitelist merchants (recurring on sight).
    _txn("2026-04-05", 9.99, "Spotify AB"),
    _txn("2026-05-05", 9.99, "Spotify AB"),
    _txn("2026-06-05", 9.99, "Spotify AB"),
    _txn("2026-04-12", 12.99, "Netflix International"),
    _txn("2026-05-12", 12.99, "Netflix International"),
    _txn("2026-06-12", 12.99, "Netflix International"),
    # Whitelist, seen only ONCE — must still be detected.
    _txn("2026-06-19", 19.99, "Adobe Systems Software"),
    # Reference-number variants of one whitelist merchant collapse into one.
    _txn("2026-04-08", 11.99, "PVM SF 2026/04 UAB Telia 8842"),
    _txn("2026-05-08", 11.99, "PVM SF 2026/05 UAB Telia 9137"),
    _txn("2026-06-08", 11.99, "PVM SF 2026/06 UAB Telia 9455"),
    # Rent: large regular payment to a person — algorithm path → housing.
    _txn("2026-04-01", 650.00, "UAB Namu Valda"),
    _txn("2026-05-01", 650.00, "UAB Namu Valda"),
    _txn("2026-06-01", 650.00, "UAB Namu Valda"),
    # Unknown merchant, regular monthly → detected by the algorithm.
    _txn("2026-05-15", 29.90, "Sporto klubas XYZ"),
    _txn("2026-06-15", 29.90, "Sporto klubas XYZ"),
    # Incoming salary — CRDT, must be ignored.
    _txn("2026-05-01", 2100.00, "Employer UAB", indicator="CRDT"),
    _txn("2026-06-01", 2100.00, "Employer UAB", indicator="CRDT"),
    # Groceries (variable + blacklisted) — must NOT be flagged.
    _txn("2026-06-03", 43.17, "Maxima LT"),
    _txn("2026-06-09", 21.80, "Maxima LT"),
    _txn("2026-06-20", 8.40, "Maxima LT"),
    # Single unknown payment — no pattern, must NOT be flagged.
    _txn("2026-06-22", 45.00, "Kuro Pavilnys UAB"),
]


def main() -> int:
    cands = detect_recurring(DEMO_TRANSACTIONS)
    by_name = {c["name"]: c for c in cands}
    failures = []

    def check(cond, msg):
        if not cond:
            failures.append(msg)

    # Whitelist detections.
    check("Spotify" in by_name, "Spotify not detected")
    check("Netflix" in by_name, "Netflix not detected")
    check("Adobe" in by_name, "Adobe (single whitelist charge) not detected")

    # Reference-number variants merged into one, named cleanly.
    check("Telia" in by_name, "Telia variants not merged/detected")
    if "Telia" in by_name:
        check(by_name["Telia"]["occurrences"] == 3,
              f"Telia occurrences {by_name['Telia']['occurrences']} != 3")
        check(by_name["Telia"]["category"] == "connectivity",
              "Telia category != connectivity")

    # Rent via the algorithm → housing, flagged for review.
    check("UAB Namu Valda" in by_name, "Rent not detected")
    if "UAB Namu Valda" in by_name:
        check(by_name["UAB Namu Valda"]["category"] == "housing",
              "Rent category != housing")
        check(by_name["UAB Namu Valda"]["needsReview"] is True,
              "Rent should need review")

    # Unknown regular monthly → detected, flagged for review.
    check("Sporto klubas XYZ" in by_name, "Unknown monthly not detected")
    if "Sporto klubas XYZ" in by_name:
        check(by_name["Sporto klubas XYZ"]["needsReview"] is True,
              "Algorithm hit should need review")

    # Must NOT be flagged.
    check("Employer UAB" not in by_name, "Incoming salary wrongly flagged")
    check("Maxima LT" not in by_name, "Groceries wrongly flagged")
    check("Kuro Pavilnys UAB" not in by_name,
          "Single unknown payment wrongly flagged")

    # Whitelist candidates are trusted (no review flag) with app-key categories.
    if "Spotify" in by_name:
        s = by_name["Spotify"]
        check(s["cost"] == 9.99, f"Spotify cost {s['cost']} != 9.99")
        check(s["category"] == "entertainment",
              f"Spotify category {s['category']} != entertainment")
        check(s["logoDomain"] == "spotify.com", "Spotify logo domain wrong")
        check(s["needsReview"] is False, "Whitelist hit should not need review")
        check(s["occurrences"] == 3, f"Spotify occurrences {s['occurrences']} != 3")
        check(s["nextBillingDate"] == "2026-07-05",
              f"Spotify next date {s['nextBillingDate']} != 2026-07-05")

    print(f"Detected {len(cands)} recurring candidate(s):")
    for c in cands:
        flag = " (review)" if c["needsReview"] else ""
        print(f"  • {c['name']:<20} {c['cost']:>7.2f} {c['currency']} "
              f"{c['billingCycle']:<9} {c['category']:<13} ×{c['occurrences']}{flag}")

    if failures:
        print("\nFAILURES:")
        for f in failures:
            print(f"  ✗ {f}")
        return 1
    print("\nAll assertions passed ✓")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
