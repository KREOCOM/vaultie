"""A recurring stream's sid must SURVIVE the two things that routinely change it
for a real user, because every verdict the user records is stored against it.

  1. More history arriving. Connecting a bank runs a fast 3-month scan and then a
     deeper 12-month one. `cost` is an AVERAGE, so the deeper scan moved it, moved
     the sid, and the user was asked the same review questions a second time.
  2. A price change. The engine treats 9.99 -> 10.99 as ONE subscription at the
     new price (test_price_change), but the sid used to move with the price, so a
     stream the user had excluded came back the month it got more expensive.

What must still DIFFER: two subscriptions at genuinely different prices from the
same merchant, or the user could never manage them separately.

Run:  ./venv/bin/python test_series_id_stable.py
"""
import datetime as dt
import os
import sys

sys.path.insert(0, os.path.dirname(__file__))
from dashboard import build_dashboard  # noqa: E402

TODAY = dt.date(2026, 7, 20)
ACCOUNTS = [{"name": "SEB", "balance": 500, "sub": "", "icon": "bank",
             "currency": "EUR"}]

fails = []


def check(ok, msg):
    if not ok:
        fails.append(msg)


def tx(amount, date, ref, merchant):
    return {
        "entry_reference": ref, "booking_date": date,
        "credit_debit_indicator": "DBIT",
        "transaction_amount": {"amount": f"{amount:.2f}", "currency": "EUR"},
        "creditor": {"name": merchant},
        "remittance_information": [merchant],
        "bank_transaction_code": {"code": "CCRD", "sub_code": "OTHR"},
    }


def sids(txns):
    """[(merchant name, sid)] for one scan.

    A LIST, not a dict: two streams from one merchant share a display name, and
    keying by name silently collapsed them — which looked exactly like the bug
    this file is here to catch.
    """
    dash = build_dashboard(txns, ACCOUNTS, today=TODAY, ai_key=None)
    return [(it["name"], it.get("sid")) for it in dash["subs"]["items"]]


def sid_for(table, needle):
    hits = [sid for name, sid in table if needle.lower() in name.lower()]
    return hits[0] if len(hits) == 1 else None


# ── 1. deeper history must not move the sid ─────────────────────────────────
SHALLOW = [tx(12.99, d, f"n{i}", "NETFLIX.COM")
           for i, d in enumerate(["2026-05-08", "2026-06-08", "2026-07-08"])]
# the deeper scan reaches further back — same stream, more of it
DEEPER = [tx(12.99, d, f"n{i}", "NETFLIX.COM")
          for i, d in enumerate(["2026-01-08", "2026-02-08", "2026-03-08",
                                 "2026-04-08", "2026-05-08", "2026-06-08",
                                 "2026-07-08"])]

shallow_sid = sid_for(sids(SHALLOW), "netflix")
deeper_sid = sid_for(sids(DEEPER), "netflix")
check(shallow_sid is not None, "Netflix missing from the shallow scan")
check(deeper_sid is not None, "Netflix missing from the deeper scan")
check(shallow_sid == deeper_sid,
      f"sid moved when history deepened: {shallow_sid} -> {deeper_sid}")

# ── 2. a price rise must not move the sid ───────────────────────────────────
# Same subscription, cheaper for three months and dearer for three.
RAISED = ([tx(12.99, d, f"o{i}", "NETFLIX.COM")
           for i, d in enumerate(["2026-02-08", "2026-03-08", "2026-04-08"])] +
          [tx(14.99, d, f"p{i}", "NETFLIX.COM")
           for i, d in enumerate(["2026-05-08", "2026-06-08", "2026-07-08"])])
raised_sid = sid_for(sids(RAISED), "netflix")
check(raised_sid is not None, "Netflix missing after the price rise")
check(raised_sid == deeper_sid,
      f"sid moved when the price rose: {deeper_sid} -> {raised_sid}")

# ── 3. genuinely different prices must STILL be different streams ───────────
TWO = ([tx(2.99, d, f"q{i}", "APPLE.COM/BILL")
        for i, d in enumerate(["2026-05-10", "2026-06-10", "2026-07-10"])] +
       [tx(19.95, d, f"r{i}", "APPLE.COM/BILL")
        for i, d in enumerate(["2026-05-20", "2026-06-20", "2026-07-20"])])
apple_sids = {sid for name, sid in sids(TWO)
              if "apple" in name.lower() and sid}
check(len(apple_sids) == 2,
      f"iCloud 2.99 and Apple One 19.95 must stay separate, got {apple_sids}")

print("sid(shallow)      =", shallow_sid)
print("sid(deeper)       =", deeper_sid)
print("sid(after raise)  =", raised_sid)
print("apple sids        =", sorted(apple_sids))

if fails:
    print("\nFAILURES:")
    for f in fails:
        print("  ✗", f)
    sys.exit(1)
print("\nAll series-id stability assertions passed ✓")
