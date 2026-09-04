"""An uncoded refund (no bank-recognised CARD_REFUND/CARD_CREDIT/RRTN code —
_flow() only catches it via the amount-sign heuristic) used to vanish from the
week/day total instead of netting it down.

Root cause: _week() summed `total` from each section's amount AFTER flooring
every section to max(amount, 0) — a same-day refund bigger than that day's
purchase in the SAME section zeroed the section (correctly, for the BAR, which
can't go negative) but also zeroed it out of the TOTAL, instead of the true net
showing through. A 25 EUR purchase + a 120 EUR same-day, same-section, uncoded
refund has a true net of -95 EUR; the old code summed max(25-120, 0) = 0 for
that day, silently disagreeing with the client's own independent
_computeWeek/_sumExpenses (dashboard_preview.dart), which never floors and was
always right.

Calls dashboard._week() directly with a controlled resolve_cat stub, so this
doesn't depend on the merchant resolver/KB being available (test_
outgoing_transfer_is_spending.py's own "merchant_db load failed — using empty
DB" warning shows that dependency is flaky in this environment).

Run:  ./venv/bin/python test_week_uncoded_refund.py
"""
import datetime as dt
import os
import sys

sys.path.insert(0, os.path.dirname(__file__))
import dashboard  # noqa: E402

failures = []


def check(label, cond, detail=""):
    if not cond:
        failures.append(f"{label}{(' — ' + detail) if detail else ''}")


def resolve_cat_groceries(_t):
    # ("canonical", "category key into CAT_MAP", "logo_domain") — "groceries"
    # → sec="Maistas, gėrimai", the same section for BOTH rows below, which is
    # the scenario that actually loses money: an uncoded refund landing in
    # the SAME section as the purchase it's undoing.
    return ("Test Merchant XYZ", "groceries", None)


def tx(direction, amount, day):
    return {
        "booking_date": day,
        "credit_debit_indicator": direction,
        "transaction_amount": {"amount": f"{amount:.2f}", "currency": "EUR"},
        # CCRD = a generic card code — reaches the merchant-resolver branch
        # in _classify, not any of the special-cased ones (fee/refund/topup/
        # transfer/exchange codes) that would short-circuit resolve_cat.
        "bank_transaction_code": {"code": "CCRD"},
        "creditor": {"name": "Test Merchant XYZ"},
        "debtor": {"name": "Test Merchant XYZ"},
    }


TODAY = dt.date(2026, 8, 17)  # a Monday — first day of _week's own window
DAY = TODAY.isoformat()

txns = [
    tx("DBIT", 25.00, DAY),   # the purchase
    tx("CRDT", 120.00, DAY),  # the uncoded refund — same merchant, same day
]

week = dashboard._week(txns, salary_refs=set(), resolve_cat=resolve_cat_groceries,
                       today=TODAY, own_ibans=None)
mon = week["days"][0]

check("Monday's true net is -95 (25 spent, 120 refunded back)",
      mon["total"] == -95.0, f"total={mon['total']}")
check("the week's own total matches the single day (nothing else in the window)",
      week["total"] == -95.0, f"week total={week['total']}")
check("the section's DISPLAY amount is still floored at 0 (a bar can't go negative)",
      mon["cats"] and mon["cats"][0]["amount"] == 0.0,
      f"cats={mon['cats']}")

# ── a day with ONLY a purchase, no refund, is unaffected ────────────────────
week2 = dashboard._week([tx("DBIT", 25.00, DAY)], salary_refs=set(),
                        resolve_cat=resolve_cat_groceries, today=TODAY, own_ibans=None)
check("a plain purchase day still totals normally",
      week2["days"][0]["total"] == 25.0, f"total={week2['days'][0]['total']}")

if failures:
    print("FAILURES:")
    for f in failures:
        print("  ✗", f)
    sys.exit(1)
print("All week-total netting assertions hold ✓")
