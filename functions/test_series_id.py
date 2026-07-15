"""Local (no-AI) test: recurring series get a stable sid, rows are tagged by
series MEMBERSHIP (merchant + per-charge amount), and a one-off same-merchant
purchase at a different amount is NOT swept into a subscription."""
import datetime as dt
import os
import sys

sys.path.insert(0, os.path.dirname(__file__))
from dashboard import build_dashboard  # noqa: E402


def tx(amount, date, ref):
    return {
        "entry_reference": ref, "booking_date": date,
        "credit_debit_indicator": "DBIT",
        "transaction_amount": {"amount": f"{amount:.2f}", "currency": "EUR"},
        "creditor": {"name": "APPLE.COM/BILL"},
        "remittance_information": ["APPLE.COM/BILL"],
        "bank_transaction_code": {"code": "CCRD", "sub_code": "OTHR"},
    }


txns = []
# recurring €22.99 monthly (the "ChatGPT" stream)
for i, d in enumerate(["2026-05-15", "2026-06-15", "2026-07-14"]):
    txns.append(tx(22.99, d, f"a{i}"))
# recurring €8.99 monthly (a different Apple sub)
for i, d in enumerate(["2026-05-10", "2026-06-10", "2026-07-10"]):
    txns.append(tx(8.99, d, f"b{i}"))
# one-off €137.99 Apple purchase (must NOT get a subscription sid)
txns.append(tx(137.99, "2026-06-25", "c0"))

dash = build_dashboard(
    txns, [{"name": "SEB", "balance": 100, "sub": "", "icon": "bank", "currency": "EUR"}],
    today=dt.date(2026, 7, 15), ai_key=None)

items = dash["subs"]["items"]
print("recurring items (name | cost | cadence | sid):")
for it in items:
    print(f"  {it['name'][:18]:18} {it['cost']:>7} {str(it.get('cadence')):10} sid={it.get('sid')}")

sids = {it.get("sid") for it in items}
assert all(it.get("sid") for it in items), "every recurring item must have a sid"
assert len(sids) == len([it for it in items]), "distinct-amount streams must have distinct sids"

# rows: check membership tagging
rows = dash["all"]
by_amt = {}
for r in rows:
    by_amt.setdefault(round(abs(r["a"]), 2), []).append(r.get("sid"))
print("\nrow sid tagging by amount:")
for amt in sorted(by_amt):
    print(f"  €{amt:>7}: sids={set(by_amt[amt])}")

# 22.99 rows share ONE sid; 8.99 rows share ANOTHER; 137.99 one-off has NO sid
sid_2299 = set(by_amt[22.99])
sid_899 = set(by_amt[8.99])
sid_137 = set(by_amt[137.99])
assert len(sid_2299) == 1 and None not in sid_2299, f"22.99 rows must share one sid: {sid_2299}"
assert len(sid_899) == 1 and None not in sid_899, f"8.99 rows must share one sid: {sid_899}"
assert sid_2299 != sid_899, "the two subs must have different sids"
assert sid_137 == {None}, f"one-off 137.99 must NOT be tagged with a series sid: {sid_137}"
print("\nAll series-id assertions passed ✓  "
      "(subs separated by amount, one-off untouched)")
