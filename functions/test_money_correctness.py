"""Two ways the dashboard used to report money that wasn't true.

1. A refund only counted as a refund when the bank used one of three transaction
   codes. Plenty of merchants don't, so a returned purchase was booked as
   INCOME — and since `net = income − expenses`, the figure was wrong by twice
   the refund, with the savings rate inflated at both ends. The mirror error:
   an incoming credit we couldn't attribute to any merchant ("Kita") — freelance,
   interest, a one-off payment — was booked as a refund, deflating both income
   and expenses. A recognised-category credit is a refund; an unattributed one
   is income.

2. An unrecognised currency was converted at a rate of 1.0, so ¥50 000 was added
   to the totals as €50 000, silently and with nothing in the logs.
"""
import os
import sys

sys.path.insert(0, os.path.dirname(__file__))

import fx
from dashboard import _flow


# ── refunds ────────────────────────────────────────────────────────────────

def _row(sec, cat, amount):
    return {"sec": sec, "cat": cat, "a": amount}


def test_money_back_from_a_shop_is_a_refund_not_income():
    # The case that was wrong: a return the bank didn't tag with a refund code.
    assert _flow(_row("Apsipirkimas", "Drabužiai", 200.0)) == "refund"


def test_an_explicitly_coded_refund_is_still_a_refund():
    assert _flow(_row("Pajamos", "Grąžinimas", 45.0)) == "refund"


def test_unattributed_incoming_credit_is_income_not_a_refund():
    # A credit we couldn't tie to a spending merchant ("Kita") — freelance, a
    # one-off payment, interest. It used to be booked as a refund (subtracted
    # from expenses, added 0 to income), deflating both sides and inflating the
    # savings rate. It's money IN.
    assert _flow(_row("Kita", "Kita", 300.0)) == "income"
    # An outgoing "Kita" is still ordinary spending.
    assert _flow(_row("Kita", "Kita", -18.0)) == "expense"


def test_salary_is_still_income():
    assert _flow(_row("Pajamos", "Atlyginimas", 2000.0)) == "income"


def test_transfers_are_still_transfers():
    assert _flow(_row("Pervedimai", "Savas pervedimas", 400.0)) == "transfer"
    assert _flow(_row("Pervedimai", "Asmeninis pervedimas", -60.0)) == "transfer"


def test_ordinary_spending_is_still_an_expense():
    assert _flow(_row("Maistas, gėrimai", "Maisto prekės", -12.40)) == "expense"


# ── currency ───────────────────────────────────────────────────────────────

def test_known_currency_converts():
    assert fx.to_eur(100, "NOK") == 100 * 0.086
    assert fx.to_eur(100, "EUR") == 100.0


def test_currency_code_is_case_insensitive():
    assert fx.to_eur(100, "nok") == fx.to_eur(100, "NOK")


def test_missing_currency_is_treated_as_euro():
    assert fx.to_eur(100, None) == 100.0


def test_unknown_currency_no_longer_passes_through_at_face_value():
    # The bug: 50 000 of anything became 50 000 EUR.
    assert fx.to_eur(50000, "XYZ") == 0.0


def test_yen_is_converted_rather_than_counted_as_euros():
    # Was 50 000. Anything in the right order of magnitude beats that.
    eur = fx.to_eur(50000, "JPY")
    assert 200 < eur < 500, eur


def main_():
    for name, fn in sorted(globals().items()):
        if name.startswith("test_") and callable(fn):
            fn()
            print(f"  ✓ {name}")
    print("\nMoney is reported honestly ✓")


if __name__ == "__main__":
    main_()
