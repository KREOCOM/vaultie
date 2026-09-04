"""Unit test for _txn_epoch — Revolut's entry_reference carries the txn time.

Revolut's entry_reference is a time-ordered id whose first 8 hex chars are the
Unix timestamp (verified against real data: they decode to the booking date + a
real HH:MM). SEB uses a plain numeric ref with no time → None. A guard window
(2020-2035) means a non-timestamp id is never misread as a time.

Run:  python3 functions/test_txn_time.py
"""
import datetime as dt
import os
import sys

sys.path.insert(0, os.path.dirname(__file__))

import dashboard  # noqa: E402


def main() -> int:
    fails = []

    def check(cond, msg):
        if not cond:
            fails.append(msg)

    # Real Revolut refs seen in this user's data + their booking date.
    revolut = [
        ("6a5e3f88-48ab-acbc-8c76-8397be3cad91", "2026-07-20"),
        ("6a5e426b-c9b9-a691-af2c-ad110ec4f3b7", "2026-07-20"),
        ("6a5f3594-fb19-a9f8-a1f4-d300ccccb353", "2026-07-21"),
    ]
    for ref, booking in revolut:
        ts = dashboard._txn_epoch({"entry_reference": ref})
        check(ts is not None, f"Revolut ref {ref[:8]} gave no epoch")
        if ts:
            d = dt.datetime.fromtimestamp(ts, dt.timezone.utc)
            check(str(d.date()) == booking,
                  f"{ref[:8]} decoded to {d.date()}, expected {booking}")

    # SEB: long numeric ref, no time → None (no dash at position 8).
    check(dashboard._txn_epoch({"entry_reference": "17825405093283035746"}) is None,
          "SEB numeric ref wrongly parsed as time")

    # A UUID whose first segment is NOT a plausible timestamp → None.
    check(dashboard._txn_epoch({"entry_reference": "ffffffff-0000-0000-0000-000000000000"}) is None,
          "out-of-range hex head wrongly accepted")
    check(dashboard._txn_epoch({"entry_reference": "00000001-0000-0000-0000-000000000000"}) is None,
          "tiny hex head wrongly accepted")

    # Missing / malformed refs → None (never crash, never guess).
    for bad in (None, "", "short", 12345, "abcdefgh-no-hex"):
        check(dashboard._txn_epoch({"entry_reference": bad}) is None,
              f"bad ref {bad!r} not None")

    if fails:
        print("FAILURES:")
        for f in fails:
            print("  ✗", f)
        return 1
    print("All _txn_epoch assertions passed ✓")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
