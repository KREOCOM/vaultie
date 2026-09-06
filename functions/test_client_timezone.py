"""The week and the month must follow the user's calendar, not the server's.

Cloud Run runs in UTC; the user does not. At 01:30 on a Monday in Lithuania it
is still Sunday 22:30 UTC, so the server anchored "this week" to the PREVIOUS
Monday and the entire week view shifted seven days. In the first hours of a
month, "this month" was still the last one. Nobody would catch this by hand —
it only misbehaves for a few hours a day — so it is pinned here.
"""
import datetime as dt
import os
import sys

sys.path.insert(0, os.path.dirname(__file__))

import main
from dashboard import build_dashboard

ACCOUNTS = [{"name": "Sąskaita", "amount": 100.0, "currency": "EUR",
             "bank": "SEB", "iban": "LT121000011101001000"}]


def _tx(date, amount="10.00"):
    return {
        "booking_date": date,
        "transaction_amount": {"amount": amount, "currency": "EUR"},
        "credit_debit_indicator": "DBIT",
        "status": "BOOK",
        "entry_reference": f"ref-{date}-{amount}",
        "creditor": {"name": "Maxima"},
    }


# ── parsing what the phone sends ───────────────────────────────────────────

def test_client_date_is_read():
    assert main._client_today({"today": "2026-07-20"}) == dt.date(2026, 7, 20)


def test_a_full_timestamp_is_accepted():
    assert main._client_today({"today": "2026-07-20T01:30:00"}) == dt.date(2026, 7, 20)


def test_missing_date_falls_back_to_the_server():
    assert main._client_today({}) is None
    assert main._client_today({"today": ""}) is None


def test_junk_is_refused_rather_than_crashing():
    for bad in ("not-a-date", "2026-13-45", 12345, None, {}):
        assert main._client_today({"today": bad}) is None, bad


# ── the behaviour that was actually wrong ──────────────────────────────────

def test_the_week_follows_the_users_monday_not_the_servers():
    # Monday 2026-07-20 local. In UTC it is still Sunday the 19th, and the old
    # code would have anchored the week to Monday the 13th.
    monday = dt.date(2026, 7, 20)
    dash = build_dashboard([_tx("2026-07-20", "25.00")], ACCOUNTS, today=monday)
    days = dash["week"]["days"]
    assert len(days) == 7, days
    # Monday is the first bar and it holds the transaction.
    assert days[0]["total"] == 25.0, days[0]
    assert dash["week"]["total"] == 25.0, dash["week"]


def test_the_same_data_lands_in_the_previous_week_when_anchored_a_day_earlier():
    # Demonstrates the failure directly: anchored to Sunday the 19th, the
    # server's week runs 13th-19th and Monday's spending is not in it.
    sunday = dt.date(2026, 7, 19)
    dash = build_dashboard([_tx("2026-07-20", "25.00")], ACCOUNTS, today=sunday)
    assert dash["week"]["total"] == 0.0, dash["week"]


def test_a_purchase_on_the_first_of_the_month_belongs_to_that_month():
    first = dt.date(2026, 8, 1)
    dash = build_dashboard([_tx("2026-08-01", "40.00")], ACCOUNTS, today=first)
    assert any(r["d"] == "2026-08-01" for r in dash["all"]), dash["all"]
    assert "2026-08" in dash["totals"]["months"], list(dash["totals"]["months"])


def main_():
    for name, fn in sorted(globals().items()):
        if name.startswith("test_") and callable(fn):
            fn()
            print(f"  ✓ {name}")
    print("\nThe calendar is the user's ✓")


if __name__ == "__main__":
    main_()
