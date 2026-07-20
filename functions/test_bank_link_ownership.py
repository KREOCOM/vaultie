"""The backend must never fetch a bank account the caller did not connect.

Before this guard existed, ``refresh_dashboard`` took the account uids straight
from the phone and fetched them with the server's Enable Banking key. Any
signed-in user who learned someone else's account uid — from a device backup, a
shared phone, a rooted device — could pull that person's full transaction
history. These tests pin the guard shut. No network, no Firestore, no secrets.
"""
import os
import sys

sys.path.insert(0, os.path.dirname(__file__))

import main


def _acc(uid, bank="SEB"):
    return {"uid": uid, "name": "Sąskaita", "currency": "EUR",
            "iban": None, "bank": bank}


def test_only_owned_accounts_survive():
    owned = {"a1", "a2"}
    requested = [_acc("a1"), _acc("evil"), _acc("a2")]
    kept = main._authorised_metas(requested, owned)
    assert [m["uid"] for m in kept] == ["a1", "a2"], kept


def test_someone_elses_account_is_dropped():
    kept = main._authorised_metas([_acc("victim-account")], {"my-account"})
    assert kept == [], kept


def test_owning_nothing_keeps_nothing():
    # An empty ownership set must not be read as "no restriction".
    kept = main._authorised_metas([_acc("a1"), _acc("a2")], set())
    assert kept == [], kept


def test_account_without_uid_is_dropped():
    # Nothing to check it against, so it cannot be attributed to anyone.
    kept = main._authorised_metas([{"uid": None, "bank": "SEB"}], {"a1"})
    assert kept == [], kept


def test_ownership_is_not_substring_matched():
    # "a1" must not grant "a12" — set membership, never prefix logic.
    kept = main._authorised_metas([_acc("a12")], {"a1"})
    assert kept == [], kept


def main_():
    for name, fn in sorted(globals().items()):
        if name.startswith("test_") and callable(fn):
            fn()
            print(f"  ✓ {name}")
    print("\nBank-link ownership guard holds ✓")


if __name__ == "__main__":
    main_()
