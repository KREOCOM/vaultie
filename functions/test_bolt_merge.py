"""Bolt (and similar unique-ref merchants) canonicalize so same-day charges merge.

Bolt's bank descriptor bakes a unique ride id into the name
("Bolt.euo2607161334", "Bolt.eu/r/2605221012", "Bolt.eu/o/...", "Bolt.eud..."),
so every charge got a different merge key and same-day rides never collapsed into
"Bolt N×". _BRAND_CANON maps the matched keyword to a canonical brand ("Bolt"),
giving all of them one merge key while keeping the Taksi category.

Run:  python3 functions/test_bolt_merge.py
"""
import os
import sys

sys.path.insert(0, os.path.dirname(__file__))

import kb  # noqa: E402
import dashboard  # noqa: E402

# No network / KB needed — a NAME_OVERRIDES match returns before the resolver.
kb._entities = []
kb._alias_index = kb._related_index = kb._norm_index = kb._prefix_index = {}
kb._loaded_source = "test-empty"


def _tx(name):
    return {
        "creditor": {"name": name},
        "credit_debit_indicator": "DBIT",
        "transaction_amount": {"amount": "5.50", "currency": "EUR"},
        "bank_transaction_code": {"code": "CARD_PAYMENT"},
        "remittance_information": [name],
    }


def _classify(name):
    return dashboard._classify(_tx(name), lambda t: (None, "other"), set(), set())


def main() -> int:
    fails = []

    def check(cond, msg):
        if not cond:
            fails.append(msg)

    bolt_surfaces = [
        "Bolt.euo2607161334",
        "Bolt.eud2606260908",
        "Bolt.eu/r/2605221012",
        "Bolt.eu/o/2607071211",
        "Bolt.eu/d/2605290928",
    ]
    canons = set()
    for nm in bolt_surfaces:
        canon, cat = _classify(nm)[0], _classify(nm)[1]
        canons.add(canon)
        check(canon == "Bolt", f"{nm!r} -> canonical {canon!r}, expected 'Bolt'")
        check(cat == "Taksi", f"{nm!r} -> category {cat!r}, expected 'Taksi'")
    # The whole point: every surface collapses to ONE merge key.
    check(len(canons) == 1, f"Bolt surfaces did not collapse: {canons}")

    # Uber gets the same treatment.
    check(_classify("Uber *trip 998877")[0] == "Uber", "Uber not canonicalized")

    # A generic 'taksi' keyword (no brand alias) keeps its real name — we only
    # canonicalize the specific unique-ref brands, never every taxi.
    check(_classify("Vilniaus Taksi UAB")[0] == "Vilniaus Taksi UAB",
          "generic taxi wrongly renamed")

    if fails:
        print("FAILURES:")
        for f in fails:
            print("  ✗", f)
        return 1
    print("All Bolt-merge assertions passed ✓")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
