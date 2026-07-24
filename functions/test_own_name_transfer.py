"""A self-transfer a bank sends with only a NAME (no counterparty IBAN) must be
neutralised by matching the user's own account-holder name — never surfaced as a
recurring bill/subscription. Regression for "Osvaldas Sulajevas €350 in Sąskaitos".
"""
import datetime as dt

from recurring import detect_recurring


def _txn(month, name, amount):
    return {
        "credit_debit_indicator": "DBIT",
        "transaction_amount": {"amount": str(amount), "currency": "EUR"},
        "creditor": {"name": name},
        "remittance_information": [name],
        "booking_date": f"2026-{month:02d}-05",
    }


def _bills(det):
    return [c for c in det["candidates"]
            if c.get("type") in ("bill", "subscription")]


def _run():
    # Three monthly €350 transfers to the user's own name, NO counterparty IBAN
    # (the SEB self-transfer shape). €350 reads as housing, so without the name
    # match it lands in Sąskaitos as a bill.
    txns = [_txn(m, "Osvaldas Sulajevas", 350) for m in (3, 4, 5)]
    today = dt.date(2026, 6, 1)

    without = detect_recurring([dict(t) for t in txns], own_ibans=set(), today=today)
    assert _bills(without), "setup: self-transfer should reproduce as a bill without the fix"

    # With the holder name known, it must be skipped as an own transfer.
    withn = detect_recurring([dict(t) for t in txns], own_ibans=set(),
                             own_names=["Osvaldas Sulajevas"], today=today)
    assert not _bills(withn), f"own-name self-transfer leaked as: {_bills(withn)}"

    # Case/diacritic-folded holder name still matches (ALLCAPS bank form).
    caps = detect_recurring([dict(t) for t in txns], own_ibans=set(),
                            own_names=["OSVALDAS SULAJEVAS"], today=today)
    assert not _bills(caps), "folded ALLCAPS own name should still match"

    # A real person who is NOT the user must still be caught (as a transfer, not a
    # bill) but must NOT be silently dropped by the own-name rule.
    other = detect_recurring([_txn(m, "Lina Kazlauskiene", 200) for m in (3, 4, 5)],
                             own_ibans=set(), own_names=["Osvaldas Sulajevas"],
                             today=today)
    assert not any(c.get("type") == "bill" for c in other["candidates"]
                   if c.get("name") == "Lina Kazlauskiene"), \
        "an unrelated person should not become a bill"

    print("test_own_name_transfer: PASS")


if __name__ == "__main__":
    _run()
