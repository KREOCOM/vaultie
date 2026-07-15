"""Recurring LIFECYCLE + projection regression test (Plaid/Tink-style).

Asserts the monthly-commitment projection (dashboard._subs):
  * ENDED streams (a finished tax plan / paid-off loan) drop out of the total.
  * ACTIVE streams are counted, monthly-normalized (a quarterly bill /3).
  * near-duplicate streams of one payee (loan booked 399 & 398) collapse to one.
  * own-account transfers (own_ibans) are never recurring.

Run:  python3 functions/test_recurring_lifecycle.py
"""
import datetime as dt
import os
import sys

sys.path.insert(0, os.path.dirname(__file__))

import kb            # noqa: E402
import merchant_db   # noqa: E402
import dashboard     # noqa: E402

kb._entities = []
kb._alias_index = kb._related_index = kb._norm_index = kb._prefix_index = {}
kb._loaded_source = "test"

merchant_db._cache = [
    {"_key": "netflix", "displayName": "Netflix", "type": "subscription",
     "category": "entertainment", "logoDomain": None, "aliases": ["netflix"], "status": "active"},
    {"_key": "vmi", "displayName": "VMI", "type": "bill",
     "category": "tax", "logoDomain": None, "aliases": ["vmi"], "status": "active"},
    {"_key": "mogo", "displayName": "MOGO", "type": "bill",
     "category": "finance", "logoDomain": None, "aliases": ["mogo"], "status": "active"},
    {"_key": "quartco", "displayName": "QuartCo", "type": "bill",
     "category": "utilities", "logoDomain": None, "aliases": ["quartco"], "status": "active"},
    {"_key": "gymplius", "displayName": "GymPlius", "type": "subscription",
     "category": "health", "logoDomain": None, "aliases": ["gymplius"], "status": "active"},
]

TODAY = dt.date(2026, 7, 15)


def tx(date, amt, name, iban=None):
    t = {
        "booking_date": date, "credit_debit_indicator": "DBIT",
        "transaction_amount": {"amount": f"{amt:.2f}", "currency": "EUR"},
        "creditor": {"name": name}, "remittance_information": [name],
        "bank_transaction_code": {"code": "CCRD", "sub_code": "OTHR"},
        "entry_reference": f"{date}-{name}-{amt}",
    }
    if iban:
        t["creditor_account"] = {"iban": iban}
    return t


def main() -> int:
    OWN = "LT000000000000000OWN"
    txns = [
        # ACTIVE monthly subscription (last charge 10 days ago)
        tx("2026-05-05", 12.99, "netflix"), tx("2026-06-05", 12.99, "netflix"),
        tx("2026-07-05", 12.99, "netflix"),
        # ENDED monthly plan — last payment ~6 months ago (finished VMI plan)
        tx("2025-08-20", 200.0, "vmi"), tx("2025-09-20", 200.0, "vmi"),
        tx("2025-10-20", 200.0, "vmi"), tx("2025-11-20", 200.0, "vmi"),
        tx("2025-12-20", 200.0, "vmi"), tx("2026-01-20", 200.0, "vmi"),
        # QUARTERLY bill (300 every 3 months) → must count as 100/mo, active
        tx("2026-01-10", 300.0, "quartco"), tx("2026-04-10", 300.0, "quartco"),
        tx("2026-07-10", 300.0, "quartco"),
        # MOGO loan booked as 399 & 398 (alternating) → ONE ~399 obligation
        tx("2026-02-10", 398.0, "mogo"), tx("2026-03-10", 399.0, "mogo"),
        tx("2026-04-10", 398.0, "mogo"), tx("2026-05-10", 399.0, "mogo"),
        tx("2026-06-10", 398.0, "mogo"), tx("2026-07-10", 399.0, "mogo"),
        # OWN-account monthly transfer (SEB→Revolut) → never recurring
        tx("2026-05-01", 500.0, "My Savings", OWN),
        tx("2026-06-01", 500.0, "My Savings", OWN),
        tx("2026-07-01", 500.0, "My Savings", OWN),
        # CATCH-UP: gym is 35.90/mo, sometimes paid late as 71.80 (2 months).
        # Must collapse to ONE ~35.90/mo obligation, and the recent 71.80 keeps
        # it ACTIVE (not "late" from the older 35.90 charges).
        tx("2025-11-05", 35.90, "gymplius"), tx("2025-12-05", 35.90, "gymplius"),
        tx("2026-01-05", 35.90, "gymplius"), tx("2026-02-05", 35.90, "gymplius"),
        tx("2026-05-10", 71.80, "gymplius"), tx("2026-07-08", 71.80, "gymplius"),
        # PERSON-to-person transfer (spouse) → appears as a candidate the user can
        # toggle off (Bilance model); NOT auto-dropped (that also dropped rent).
        tx("2026-05-03", 400.0, "Zivile Pavarde"), tx("2026-06-03", 400.0, "Zivile Pavarde"),
        tx("2026-07-03", 400.0, "Zivile Pavarde"),
        # RENT to a business whose 2-word name fuzzy-matches a frequent brand
        # ("Artus Grupe" → "Artus" supermarket). Must NOT be dropped as frequent
        # spending — a €1197 regular payment is a bill.
        tx("2026-05-05", 1197.0, "Artus Grupe"), tx("2026-06-05", 1197.0, "Artus Grupe"),
        tx("2026-07-05", 1197.0, "Artus Grupe"),
    ]

    subs = dashboard._subs(txns, own_ibans={OWN}, today=TODAY)
    items = {it["name"]: it for it in subs["items"]}
    fails = []

    def check(cond, msg):
        if not cond:
            fails.append(msg)

    # VMI present but ENDED, excluded from the total
    check("VMI" in items, "VMI missing from items")
    check(items.get("VMI", {}).get("status") == "ended",
          f"VMI should be ended, got {items.get('VMI', {}).get('status')}")
    check(not items.get("VMI", {}).get("active"), "VMI should not be active")

    # Netflix active + monthly
    check(items.get("Netflix", {}).get("active") is True, "Netflix not active")

    # Quarterly normalized to monthly (300/3 = 100)
    check("QuartCo" in items, "QuartCo missing")
    check(abs(items.get("QuartCo", {}).get("monthly", 0) - 100.0) < 1.0,
          f"QuartCo not monthly-normalized to ~100, got {items.get('QuartCo', {}).get('monthly')}")
    check(items.get("QuartCo", {}).get("active") is True, "QuartCo not active")

    # MOGO collapsed to ONE item, ~399, active
    mogo = [it for it in subs["items"] if it["name"] == "MOGO"]
    check(len(mogo) == 1, f"MOGO not collapsed (got {len(mogo)})")
    check(mogo and 397 <= mogo[0]["monthly"] <= 400, f"MOGO monthly off: {mogo and mogo[0]['monthly']}")
    check(mogo and mogo[0]["active"] is True, "MOGO not active")

    # Own-account transfer never a recurring item
    check("My Savings" not in items, "own-account transfer wrongly recurring")

    # People are NOT auto-dropped (that dropped rent too) — they appear as
    # candidates the user curates.
    check("Zivile Pavarde" in items, "person candidate wrongly dropped")

    # RENT that fuzzy-matches a frequent brand must SURVIVE (the regression fix).
    rent = [it for it in subs["items"] if it["name"] == "Artus Grupe"]
    check(len(rent) == 1 and rent[0]["monthly"] > 1000,
          f"rent 'Artus Grupe' wrongly dropped/mis-sized: {[(r['name'], r['monthly']) for r in rent]}")
    check(rent and rent[0]["active"] is True, "rent should be active")

    # CATCH-UP: gym collapses to ONE ~35.90/mo, active (recent 71.80 catch-up)
    gym = [it for it in subs["items"] if it["name"] == "GymPlius"]
    check(len(gym) == 1, f"GymPlius not collapsed (got {len(gym)})")
    check(gym and 34 <= gym[0]["monthly"] <= 38,
          f"GymPlius monthly should be ~35.90 (unit, not 71.80): {gym and gym[0]['monthly']}")
    check(gym and gym[0]["active"] is True, "GymPlius should be active (recent catch-up)")

    # TOTAL = Netflix 12.99 + QuartCo 100 + MOGO ~399 + GymPlius ~35.90
    #         + Zivile 400 + rent 1197 (both counted by default; user curates)
    expected = 12.99 + 100.0 + 399.0 + 35.90 + 400.0 + 1197.0
    check(abs(subs["total"] - expected) < 4.0,
          f"total off: got {subs['total']}, expected ~{expected}")

    print("items (status / monthly):")
    for it in subs["items"]:
        print(f"  • {it['name']:<12} {it['status']:<7} {it['monthly']:>7.2f} €/mo "
              f"({it['cycle']}, ×{it['occ']}, active={it['active']})")
    print(f"\nACTIVE monthly total: {subs['total']} €  (VMI ended + own transfer excluded)")

    if fails:
        print("\nFAILURES:")
        for f in fails:
            print(f"  ✗ {f}")
        return 1
    print("All recurring-lifecycle assertions passed ✓")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
