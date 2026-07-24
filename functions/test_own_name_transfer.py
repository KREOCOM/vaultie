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

    print("test_own_name_transfer: PASS")


if __name__ == "__main__":
    _run()
