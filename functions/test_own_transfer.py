"""M5 own-account transfer regression test.

A transfer whose counterparty IBAN is one of the user's OWN connected accounts
(e.g. SEB -> Revolut) must classify as "Savas pervedimas" (own-account transfer)
so it is excluded from both spending/income AND "Gauta". A transfer from another
person (mama) must stay "Asmeninis pervedimas". Without own_ibans, behaviour is
unchanged.

Run:  python3 functions/test_own_transfer.py
"""
import os
import sys

sys.path.insert(0, os.path.dirname(__file__))

from dashboard import build_dashboard  # noqa: E402

SEB = "LT111111111111111111"
REV = "LT222222222222222222"
MAMA = "LT999999999999999999"


def _tx(date, direction, amount, *, own_iban, cp_iban, cp_name, code="ICDT"):
    """Build one Enable Banking-shaped transaction."""
    acct = "debtor_account" if direction == "CRDT" else "creditor_account"
    own_acct = "creditor_account" if direction == "CRDT" else "debtor_account"
    party = "debtor" if direction == "CRDT" else "creditor"
    return {
        "booking_date": date,
        "credit_debit_indicator": direction,
        "transaction_amount": {"amount": f"{amount:.2f}", "currency": "EUR"},
        "bank_transaction_code": {"code": code},
        acct: {"iban": cp_iban},
        own_acct: {"iban": own_iban},
        party: {"name": cp_name},
        "entry_reference": f"{date}-{direction}-{amount}-{cp_iban}",
    }


def _row_for(dash, cat):
    return [r for r in dash["all"] if r["cat"] == cat]


def main():
    txns = [
        # SEB -> Revolut own transfer (outgoing leg, seen on the SEB account)
        _tx("2026-06-10", "DBIT", 500.0, own_iban=SEB, cp_iban=REV, cp_name="Vardas Pavarde"),
        # Revolut side (incoming leg, seen on the Revolut account)
        _tx("2026-06-10", "CRDT", 500.0, own_iban=REV, cp_iban=SEB, cp_name="Vardas Pavarde"),
        # mama -> me: a real P2P transfer from another person (NOT own)
        _tx("2026-06-12", "CRDT", 700.0, own_iban=SEB, cp_iban=MAMA, cp_name="Milda Dirsiene"),
    ]
    accounts = [
        {"name": "SEB", "amount": 1000.0, "iban": SEB, "currency": "EUR", "icon": "bank"},
        {"name": "Revolut EUR", "amount": 500.0, "iban": REV, "currency": "EUR", "icon": "R"},
    ]
    own_ibans = {SEB, REV}

    # --- WITH multi-bank context ---
    dash = build_dashboard(txns, accounts, own_ibans=own_ibans)
    own_rows = _row_for(dash, "Savas pervedimas")
    mama_rows = _row_for(dash, "Asmeninis pervedimas")
    assert len(own_rows) == 2, f"expected 2 own-transfer legs, got {len(own_rows)}"
    assert len(mama_rows) == 1, f"expected mama to stay Asmeninis pervedimas, got {len(mama_rows)}"
    # Own transfers must not touch income/expenses (they are transfers).
    t = dash["totals"]["all"]
    assert t["income"] == 0.0, f"own transfers leaked into income: {t['income']}"
    assert t["expenses"] == 0.0, f"own transfers leaked into expenses: {t['expenses']}"

    # --- WITHOUT context (single bank): no own detection, legacy behaviour ---
    dash0 = build_dashboard(txns, accounts)  # own_ibans=None
    assert not _row_for(dash0, "Savas pervedimas"), "own detection fired without own_ibans"

    print("own-transfer legs (with own_ibans):   ", len(own_rows), "-> Savas pervedimas")
    print("person transfer stays Asmeninis:       ", len(mama_rows))
    print("income/expenses untouched by transfers: income=%.2f expenses=%.2f" % (t["income"], t["expenses"]))
    print("without own_ibans: 0 own-transfers detected (legacy) ✓")
    print("\nAll M5 own-account transfer assertions passed ✓")


if __name__ == "__main__":
    main()
