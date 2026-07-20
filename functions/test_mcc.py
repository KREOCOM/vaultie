"""MCC categorisation — the universal signal that covers the long tail.

MCC (the card network's merchant category code) categorises any shop in Europe
by what KIND of merchant it is, without a name lookup. These tests pin the code
mapping and the cascade: when the bank sends an MCC, it decides the category;
when it doesn't, the name resolver still carries it (no regression). This is the
fix for "how can it not know Amazon" — with an MCC it doesn't need to know Amazon
at all.
"""
import os
import sys

sys.path.insert(0, os.path.dirname(__file__))

import mcc
from dashboard import build_dashboard

ACCOUNTS = [{"name": "Sąskaita", "amount": 100.0, "currency": "EUR",
             "bank": "SEB", "iban": "LT121000011101001000"}]


def _tx(name, code_mcc=None):
    t = {
        "booking_date": "2026-07-15",
        "transaction_amount": {"amount": "12.34", "currency": "EUR"},
        "credit_debit_indicator": "DBIT",
        "status": "BOOK",
        "entry_reference": f"r-{name}",
        "creditor": {"name": name},
        "bank_transaction_code": {"code": "CCRD"},
    }
    if code_mcc:
        t["merchant_category_code"] = code_mcc
    return t


def _cat(name, code_mcc=None):
    dash = build_dashboard([_tx(name, code_mcc)], ACCOUNTS)
    return dash["all"][0]["cat"] if dash["all"] else None


# ── the code table ─────────────────────────────────────────────────────────

def test_common_codes_map_to_the_right_family():
    assert mcc.category_for_mcc("5411") == "groceries"
    assert mcc.category_for_mcc("5541") == "fuel"
    assert mcc.category_for_mcc("5812") == "restaurant"
    assert mcc.category_for_mcc("4121") == "taxi"
    assert mcc.category_for_mcc("5912") == "pharmacy"
    assert mcc.category_for_mcc("5651") == "clothing"
    assert mcc.category_for_mcc("5712") == "hardware"   # furniture (IKEA)
    assert mcc.category_for_mcc("4900") == "utilities"


def test_padding_and_int_forms_are_accepted():
    assert mcc.category_for_mcc(5411) == "groceries"
    assert mcc.category_for_mcc(" 5411 ") == "groceries"


def test_unknown_or_junk_defers_to_the_resolver():
    assert mcc.category_for_mcc(None) is None
    assert mcc.category_for_mcc("") is None
    assert mcc.category_for_mcc("abcd") is None
    assert mcc.category_for_mcc("0000") is None


# ── the cascade through the real classifier ────────────────────────────────

def test_mcc_fixes_a_shop_the_name_resolver_gets_wrong():
    # IKEA fuzzy-matched the "IKI" grocery chain → groceries. With its furniture
    # MCC it lands in home goods regardless of the name.
    assert _cat("IKEA VILNIUS") in ("Maisto prekės", "Kita")  # without MCC: wrong/unknown
    assert _cat("IKEA VILNIUS", "5712") == "Namų prekės"


def test_mcc_categorises_a_merchant_the_app_has_never_heard_of():
    # An invented merchant name the KB can't know — MCC alone must categorise it.
    assert _cat("QWX ZURI STORE 4471") == "Kita"                 # no MCC → unknown
    assert _cat("QWX ZURI STORE 4471", "5411") == "Maisto prekės"  # grocery MCC


def test_no_mcc_still_works_via_the_name_resolver():
    # The everyday LT merchants must not regress when the bank sends no MCC.
    assert _cat("MAXIMA LT X587") == "Maisto prekės"
    assert _cat("CIRCLE K MISKAS") == "Kuras"


def main_():
    for name, fn in sorted(globals().items()):
        if name.startswith("test_") and callable(fn):
            fn()
            print(f"  ✓ {name}")
    print("\nMCC carries the long tail ✓")


if __name__ == "__main__":
    main_()
