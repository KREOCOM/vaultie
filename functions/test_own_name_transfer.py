"""A personal name — first name + surname — must NEVER be a recurring bill or
subscription, whatever the amount or memo (the user's hard rule). A real business
(legal form, or a known merchant) must still be a bill. Regression for the
"Osvaldas Sulajevas €350 in Sąskaitos" class of bug.
"""
import datetime as dt

from recurring import detect_recurring


def _txn(month, name, amount, iban=None):
    t = {
        "credit_debit_indicator": "DBIT",
        "transaction_amount": {"amount": str(amount), "currency": "EUR"},
        "creditor": {"name": name},
        "remittance_information": [name],
        "booking_date": f"2026-{month:02d}-05",
    }
    if iban:
        t["creditor"]["account"] = {"iban": iban}
    return t


def _txn_remit_only(month, name, amount):
    """A bank that fills ONLY the remittance, with no structured creditor.name —
    so canonical's party_kind_hint (built from creditor.name) is empty."""
    return {
        "credit_debit_indicator": "DBIT",
        "transaction_amount": {"amount": str(amount), "currency": "EUR"},
        "remittance_information": [name],
        "booking_date": f"2026-{month:02d}-05",
    }


def _typ(det, name):
    for c in det["candidates"]:
        if c.get("name") == name:
            return c.get("type")
    return None


def _run():
    today = dt.date(2026, 6, 1)

    # 1) LT person, €350 (reads as housing) — must be a transfer, NOT a bill,
    #    even without any own-name hint. This is the carve-out removal.
    person = detect_recurring([_txn(m, "Osvaldas Sulajevas", 350) for m in (3, 4, 5)],
                              own_ibans=set(), today=today)
    assert _typ(person, "Osvaldas Sulajevas") != "bill", \
        f"LT person leaked as: {_typ(person, 'Osvaldas Sulajevas')}"

    # 2) A different real person paying rent-sized amounts — still a transfer.
    p2 = detect_recurring([_txn(m, "Lina Gliozeriene", 220) for m in (3, 4, 5)],
                          own_ibans=set(), today=today)
    assert _typ(p2, "Lina Gliozeriene") not in ("bill", "subscription"), \
        f"person p2 leaked as: {_typ(p2, 'Lina Gliozeriene')}"

    # 3) Own self-transfer matched purely by holder NAME (no counterparty IBAN,
    #    name not LT-shaped) — skipped as own transfer, not a bill.
    own = detect_recurring([_txn(m, "Erik Johansson", 300) for m in (3, 4, 5)],
                           own_ibans=set(), own_names=["Erik Johansson"], today=today)
    assert _typ(own, "Erik Johansson") not in ("bill", "subscription"), \
        f"own-name self-transfer leaked as: {_typ(own, 'Erik Johansson')}"

    # 4) A FOREIGN first-name + surname over €200 (reads as housing) — must be a
    #    transfer, not a bill. This is the gap the LT-only fix left open.
    for name in ("John Smith", "GIOVANNI ROSSI"):
        r = detect_recurring([_txn(m, name, 300) for m in (3, 4, 5)],
                             own_ibans=set(), today=today)
        assert _typ(r, name) not in ("bill", "subscription"), \
            f"foreign person {name!r} leaked as: {_typ(r, name)}"
        # ...and never surfaced in the recurring items at all.

    # 5) A real BUSINESS that merely looks person-shaped (a company word, no legal
    #    form) must STAY a bill — never stripped by the person rule.
    for biz in ("Teva Baltics", "Artus Grupe", "Verslo Vartai"):
        r = detect_recurring([_txn(m, biz, 300) for m in (3, 4, 5)],
                             own_ibans=set(), today=today)
        assert _typ(r, biz) in ("bill", "subscription"), \
            f"business {biz!r} wrongly stripped to: {_typ(r, biz)}"

    # 6) A foreign person whose name the bank put ONLY in the remittance (no
    #    structured creditor.name) — must STILL be a transfer, not a housing bill.
    for name in ("John Smith", "Giovanni Rossi"):
        r = detect_recurring([_txn_remit_only(m, name, 300) for m in (3, 4, 5)],
                             own_ibans=set(), today=today)
        assert _typ(r, name) not in ("bill", "subscription"), \
            f"remittance-only person {name!r} leaked as: {_typ(r, name)}"

    print("test_own_name_transfer: PASS")


if __name__ == "__main__":
    _run()
