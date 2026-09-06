"""One malformed row must cost that row — never the whole dashboard.

`build_dashboard` used to parse dates with `map(int, s.split("-"))` and amounts
with a bare `float()`. Either raised on a row a bank formatted differently, the
exception escaped to the caller, and `main.py` turned the ENTIRE dashboard into
null — every payment gone because of one. These tests pin that shut.
"""
import os
import sys

sys.path.insert(0, os.path.dirname(__file__))

from dashboard import _amt, _ymd, build_dashboard


def _tx(date, amount="10.00", currency="EUR", name="Maxima"):
    return {
        "booking_date": date,
        "transaction_amount": {"amount": amount, "currency": currency},
        "credit_debit_indicator": "DBIT",
        "status": "BOOK",
        "entry_reference": f"ref-{date}-{amount}",
        "creditor": {"name": name},
    }


ACCOUNTS = [{"name": "Sąskaita", "amount": 100.0, "currency": "EUR",
             "bank": "SEB", "iban": "LT121000011101001000"}]


def test_ymd_accepts_the_shapes_banks_actually_send():
    assert _ymd("2026-07-20") == (2026, 7, 20)
    assert _ymd("2026-07-20T10:30:00") == (2026, 7, 20)
    assert _ymd("2026-07-20T10:30:00+03:00") == (2026, 7, 20)


def test_ymd_refuses_junk_instead_of_raising():
    for bad in (None, "", "not-a-date", "2026-13-45", 12345, {}):
        assert _ymd(bad) is None, bad


def test_amt_survives_a_non_numeric_amount():
    assert _amt({"transaction_amount": {"amount": "abc"}}) == 0.0
    assert _amt({"transaction_amount": {"amount": None}}) == 0.0
    assert _amt({}) == 0.0


def test_one_bad_date_does_not_empty_the_dashboard():
    txns = [_tx("2026-07-20"), _tx("wildly-wrong"), _tx("2026-07-19")]
    dash = build_dashboard(txns, ACCOUNTS)
    assert dash is not None, "a single bad row nulled the whole dashboard"
    dates = {r["d"] for r in dash["all"]}
    assert dates == {"2026-07-20", "2026-07-19"}, dates


def test_a_date_with_a_time_component_is_kept_not_dropped():
    # The realistic case: not junk, just a shape the old parser choked on.
    dash = build_dashboard([_tx("2026-07-20T10:30:00")], ACCOUNTS)
    assert len(dash["all"]) == 1, dash["all"]


def test_bad_amount_keeps_the_row_and_the_rest_of_the_totals():
    dash = build_dashboard([_tx("2026-07-20", amount="oops"),
                            _tx("2026-07-19", amount="25.00")], ACCOUNTS)
    assert dash is not None
    assert len(dash["all"]) == 2, dash["all"]


def main_():
    for name, fn in sorted(globals().items()):
        if name.startswith("test_") and callable(fn):
            fn()
            print(f"  ✓ {name}")
    print("\nMalformed rows stay contained ✓")


if __name__ == "__main__":
    main_()
