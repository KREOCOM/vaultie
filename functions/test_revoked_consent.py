"""A bank that refused us must stop being shown — not re-served from cache.

`known_cache` exists so a bank that goes quiet (rate limit, outage) doesn't make
its payments vanish from the dashboard. That is right for a quiet bank and wrong
for a revoked one: when a consent expires, or the user withdraws bank access in
their own bank, continuing to display their transactions defeats the entire
point of withdrawing it. The two were indistinguishable — every failure was just
`error`, so a revoked bank kept being refilled from the phone's cache forever.
"""
import os
import sys

sys.path.insert(0, os.path.dirname(__file__))

from known_cache import merge_known

TXN = {"booking_date": "2026-07-15", "status": "BOOK", "_bank": "SEB",
       "entry_reference": "r1",
       "transaction_amount": {"amount": "10.00", "currency": "EUR"}}
ACCT = {"name": "SEB sąskaita", "bank": "SEB", "iban": "LT12", "amount": 50.0}
KNOWN = {"txns": [TXN], "accounts": [ACCT]}


def _merge(diag):
    return merge_known([], [], set(), diag, KNOWN, 12)


def test_quiet_bank_is_still_filled_in_from_cache():
    # The behaviour known_cache was built for — must not regress.
    txns, accts, _ibans, stale = _merge(
        [{"bank": "SEB", "error": "boom", "rateLimited": True, "revoked": False}])
    assert len(txns) == 1, txns
    assert len(accts) == 1, accts
    assert stale == ["SEB"], stale


def test_revoked_bank_is_not_served_from_cache():
    txns, accts, _ibans, _stale = _merge(
        [{"bank": "SEB", "error": "403", "rateLimited": False, "revoked": True}])
    assert txns == [], "revoked bank's transactions were re-served"
    assert accts == [], "revoked bank's account was re-served"


def test_revoked_bank_is_not_reported_as_merely_stale():
    _txns, _accts, _ibans, stale = _merge(
        [{"bank": "SEB", "error": "401", "rateLimited": False, "revoked": True}])
    assert stale == [], stale


def test_a_bank_that_answered_is_not_duplicated_from_cache():
    txns, accts, _ibans, _stale = _merge([{"bank": "SEB"}])
    assert txns == [] and accts == []


def test_one_bank_revoked_does_not_hide_another_quiet_bank():
    known = {"txns": [TXN, {**TXN, "_bank": "Revolut", "entry_reference": "r2"}],
             "accounts": [ACCT, {**ACCT, "bank": "Revolut"}]}
    txns, accts, _ibans, stale = merge_known(
        [], [], set(),
        [{"bank": "SEB", "error": "403", "revoked": True},
         {"bank": "Revolut", "error": "429", "rateLimited": True, "revoked": False}],
        known, 12)
    assert [t["_bank"] for t in txns] == ["Revolut"], txns
    assert [a["bank"] for a in accts] == ["Revolut"], accts
    assert stale == ["Revolut"], stale


def main_():
    for name, fn in sorted(globals().items()):
        if name.startswith("test_") and callable(fn):
            fn()
            print(f"  ✓ {name}")
    print("\nRevoked consent stops the data ✓")


if __name__ == "__main__":
    main_()
