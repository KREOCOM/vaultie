"""Unit tests for recurring detection — no network, runs anywhere.

Uses the same schema-accurate sample transactions as the ``banksync.py`` PoC:
outgoing subscriptions/rent/gym should be detected; the incoming salary (CRDT)
and one-off variable spend should NOT be.

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
    _txn("2026-04-05", 9.99, "Spotify AB"),
    _txn("2026-05-05", 9.99, "Spotify AB"),
    _txn("2026-06-05", 9.99, "Spotify AB"),
    _txn("2026-04-12", 12.99, "Netflix International"),
    _txn("2026-05-12", 12.99, "Netflix International"),
    _txn("2026-06-12", 12.99, "Netflix International"),
    _txn("2026-04-01", 650.00, "UAB Namu Valda"),
    _txn("2026-05-01", 650.00, "UAB Namu Valda"),
    _txn("2026-06-01", 650.00, "UAB Namu Valda"),
    _txn("2026-05-15", 29.90, "Lemon Gym"),
    _txn("2026-06-15", 29.90, "Lemon Gym"),
    # Incoming salary — CRDT, must be ignored.
    _txn("2026-05-01", 2100.00, "Employer UAB", indicator="CRDT"),
    _txn("2026-06-01", 2100.00, "Employer UAB", indicator="CRDT"),
    # One-off / variable spend — must NOT be flagged as recurring.
    _txn("2026-06-03", 43.17, "Maxima LT"),
    _txn("2026-06-09", 21.80, "Maxima LT"),
    _txn("2026-06-20", 8.40, "Maxima LT"),
    _txn("2026-06-22", 199.00, "Apple Store"),
    # Same merchant, but the name carries a different reference each month —
    # must still collapse into ONE recurring candidate (the normalisation fix).
    _txn("2026-04-08", 11.99, "PVM SF 2026/04 UAB Telia 8842"),
    _txn("2026-05-08", 11.99, "PVM SF 2026/05 UAB Telia 9137"),
    _txn("2026-06-08", 11.99, "PVM SF 2026/06 UAB Telia 9455"),
]


def main() -> int:
    cands = detect_recurring(DEMO_TRANSACTIONS)
    by_name = {c["name"]: c for c in cands}
    failures = []

    def check(cond, msg):
        if not cond:
            failures.append(msg)

    # Expected recurring detections.
    check("Spotify" in by_name, "Spotify not detected")
    check("Netflix" in by_name, "Netflix not detected")
    check("UAB Namu Valda" in by_name, "Rent (UAB Namu Valda) not detected")
    check("Gym" in by_name or "Lemon Gym" in by_name, "Gym not detected")

    # Reference-number variants of the same merchant collapse into one.
    telia = [c for c in cands if "telia" in c["name"].lower()]
    check(len(telia) == 1, f"Telia variants not merged (got {len(telia)})")
    if telia:
        check(telia[0]["occurrences"] == 3,
              f"Telia occurrences {telia[0]['occurrences']} != 3")

    # Must NOT be flagged.
    check("Employer UAB" not in by_name, "Incoming salary wrongly flagged")
    check("Maxima LT" not in by_name, "Variable grocery spend wrongly flagged")
    check("Apple Store" not in by_name and "Apple" not in by_name,
          "One-off Apple purchase wrongly flagged")

    # Field-level sanity on Spotify.
    if "Spotify" in by_name:
        s = by_name["Spotify"]
        check(s["cost"] == 9.99, f"Spotify cost {s['cost']} != 9.99")
        check(s["billingCycle"] == "monthly", f"Spotify cycle {s['billingCycle']} != monthly")
        check(s["category"] == "Music", f"Spotify category {s['category']} != Music")
        check(s["logoDomain"] == "spotify.com", "Spotify logo domain wrong")
        check(s["occurrences"] == 3, f"Spotify occurrences {s['occurrences']} != 3")
        check(s["nextBillingDate"] == "2026-07-05",
              f"Spotify next date {s['nextBillingDate']} != 2026-07-05")

    print(f"Detected {len(cands)} recurring candidate(s):")
    for c in cands:
        print(f"  • {c['name']:<18} {c['cost']:>7.2f} {c['currency']} "
              f"{c['billingCycle']:<9} ×{c['occurrences']}  next={c['nextBillingDate']}")

    if failures:
        print("\nFAILURES:")
        for f in failures:
            print(f"  ✗ {f}")
        return 1
    print("\nAll assertions passed ✓")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
