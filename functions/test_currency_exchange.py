"""Currency-exchange detection: a same-owner conversion (NOK→EUR etc.) is neither
income nor spending, whether the bank stamps an EXCHANGE code OR only a
description ("Exchanged to EUR"). Generic across banks and currency pairs — no
per-bank, per-currency rule. Run: python3 functions/test_currency_exchange.py"""
import datetime as dt
import os
import sys

sys.path.insert(0, os.path.dirname(__file__))
from dashboard import _is_exchange, _flow, build_dashboard  # noqa: E402


def main() -> int:
    fails = []

    # ── detection: description-only exchanges (Revolut-style, no EXCHANGE code) ──
    yes = [
        {"remittance_information": ["Exchanged to EUR"]},
        {"remittance_information": ["NOK → EUR"]},
        {"remittance_information": ["USD -> EUR conversion"]},
        {"note": "Valiutos keitimas"},
        {"bank_transaction_code": {"code": "EXCHANGE"}},
    ]
    no = [
        {"remittance_information": ["PIRKINYS ... MAXIMA KLAIPEDA 000LT"]},
        {"remittance_information": ["Nok 114,87 Scaletech Software"]},  # DNB card buy
        {"remittance_information": ["Atlyginimas"], "bank_transaction_code": {"code": "RCDT"}},
        {"creditor": {"name": "NERGARD SOROYA AS"}},
    ]
    for t in yes:
        if not _is_exchange(t):
            fails.append(f"MISSED exchange: {t}")
    for t in no:
        if _is_exchange(t):
            fails.append(f"WRONGLY flagged as exchange: {t}")

    # ── end-to-end: a NOK→EUR conversion must NOT count as income or spending ──
    def tx(amt, rmt, date, ref):
        return {"entry_reference": ref, "booking_date": date,
                "credit_debit_indicator": "DBIT" if amt < 0 else "CRDT",
                "transaction_amount": {"amount": f"{abs(amt):.2f}", "currency": "EUR"},
                "remittance_information": [rmt]}

    txns = [
        tx(4090.65, "Exchanged to EUR", "2026-06-05", "x1"),   # conversion IN
        tx(-30.00, "PIRKINYS ... MAXIMA 000LT", "2026-06-10", "m1"),  # real spend
    ]
    dash = build_dashboard(
        txns, [{"name": "Revolut", "balance": 100, "sub": "", "icon": "R", "currency": "EUR"}],
        today=dt.date(2026, 6, 20), ai_key=None)
    ex = [r for r in dash["all"] if "keitim" in str(r.get("cat", "")).lower()]
    if not ex:
        fails.append("conversion not classified as 'Valiutos keitimas'")
    elif not all(_flow(r) == "transfer" for r in ex):
        # transfer flow = excluded from BOTH income and spending totals
        fails.append(f"exchange not neutral: _flow={[_flow(r) for r in ex]}")

    if fails:
        print(f"FAILURES ({len(fails)}):")
        for f in fails:
            print("  x", f)
        return 1
    print(f"All currency-exchange assertions passed OK "
          f"({len(yes)} detected, {len(no)} correctly ignored, e2e neutral)")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
