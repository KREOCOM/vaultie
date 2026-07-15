"""A bank's payments must NEVER disappear because the bank went quiet.

This is the regression test for the failure the user hit: SEB rate-limited a
refresh, and the rebuilt dashboard showed SEB's balance with none of its
payments — rent and the MOGO loan gone from the feed and from the monthly
commitment. The scan-level fix (test_scan_ratelimit) stops a quiet bank from
being mistaken for an empty one; THIS is the guarantee that a quiet bank still
shows its data at all.

Run:  python3 functions/test_known_cache.py
"""
import datetime as dt

from known_cache import merge_known

TODAY = dt.date(2026, 7, 16)


def _txn(bank, ref, date, amount, status="BOOK"):
    return {"_bank": bank, "entry_reference": ref, "booking_date": date,
            "status": status,
            "transaction_amount": {"amount": str(amount), "currency": "EUR"}}


def _acct(bank, iban, amount):
    return {"name": f"{bank} sąskaita", "bank": bank, "iban": iban,
            "amount": amount, "currency": "EUR"}


# The user's real shape: Revolut answers, SEB doesn't.
FRESH_TXNS = [_txn("Revolut", "r1", "2026-07-14", -25.00)]
FRESH_ACCTS = [_acct("Revolut", "LT111", 6909.77)]
DIAG_SEB_DOWN = [
    {"account": "Osvaldas", "bank": "Revolut", "count": 298},
    {"account": "ŠULAJEVAS OSVALDAS", "bank": "SEB",
     "error": "[HTTP 429] rate limited", "rateLimited": True},
]
KNOWN = {
    "txns": [_txn("SEB", "s1", "2026-07-01", -1197.00),   # rent
             _txn("SEB", "s2", "2026-07-05", -399.00),    # MOGO
             _txn("Revolut", "rOld", "2026-06-01", -10.0)],
    "accounts": [_acct("SEB", "LT999", 448.80),
                 _acct("Revolut", "LT111", 1.0)],  # stale balance
}


def _merge(fresh_txns=None, fresh_accts=None, diag=None, known=None, months=6):
    return merge_known(
        list(FRESH_TXNS if fresh_txns is None else fresh_txns),
        list(FRESH_ACCTS if fresh_accts is None else fresh_accts),
        {"LT111"},
        DIAG_SEB_DOWN if diag is None else diag,
        KNOWN if known is None else known,
        months, today=TODAY)


def test_quiet_bank_keeps_its_payments():
    """THE guarantee: SEB rate-limited → rent and MOGO are still there."""
    txns, _, _, _ = _merge()
    refs = {t["entry_reference"] for t in txns}
    assert "s1" in refs, "RENT DISAPPEARED — the whole point of this module"
    assert "s2" in refs, "MOGO DISAPPEARED — the whole point of this module"


def test_quiet_bank_keeps_its_balance():
    """SEB's 448,80 € must not vanish off the balances screen either."""
    _, accts, _, stale = _merge()
    banks = {a["bank"] for a in accts}
    assert "SEB" in banks, f"SEB's balance vanished: {accts}"
    assert stale == ["SEB"], f"SEB should be flagged as stale, got {stale}"


def test_answering_bank_is_authoritative():
    """Revolut answered → its FRESH data wins; the stale copy is not merged in."""
    txns, accts, _, _ = _merge()
    revolut = [t for t in txns if t["_bank"] == "Revolut"]
    assert {t["entry_reference"] for t in revolut} == {"r1"}, \
        f"stale Revolut data leaked back in: {revolut}"
    balances = [a["amount"] for a in accts if a["bank"] == "Revolut"]
    assert balances == [6909.77], f"stale Revolut balance won: {balances}"


def test_quiet_banks_ibans_stay_own():
    """Lose a quiet bank's IBAN and its transfers to the other bank stop being
    own-account moves — they'd book as real spending."""
    _, _, ibans, _ = _merge()
    assert "LT999" in ibans, f"SEB's own IBAN was dropped: {ibans}"


def test_pending_is_never_reused():
    """Pending entries still move at the bank; a cancelled one must not live on
    in the cache forever."""
    known = {"txns": [_txn("SEB", "p1", "2026-07-02", -50.0, status="PDNG")],
             "accounts": [_acct("SEB", "LT999", 448.80)]}
    txns, _, _, _ = _merge(known=known)
    assert not [t for t in txns if t["entry_reference"] == "p1"], \
        "a pending entry was resurrected from cache"


def test_cache_cannot_widen_the_window():
    """Reused history is clipped to the window asked for, so the cache can't
    quietly grow the dashboard's date range over time."""
    known = {"txns": [_txn("SEB", "ancient", "2024-01-01", -5.0)],
             "accounts": [_acct("SEB", "LT999", 448.80)]}
    txns, _, _, _ = _merge(known=known, months=6)
    assert not [t for t in txns if t["entry_reference"] == "ancient"], \
        "a 2-year-old cached transaction leaked into a 6-month window"


def test_all_banks_healthy_changes_nothing():
    """The everyday path: everyone answered → the cache is inert."""
    diag = [{"account": "Osvaldas", "bank": "Revolut"},
            {"account": "ŠULAJEVAS OSVALDAS", "bank": "SEB"}]
    fresh = [_txn("Revolut", "r1", "2026-07-14", -25.0),
             _txn("SEB", "s9", "2026-07-15", -1197.0)]
    accts = [_acct("Revolut", "LT111", 6909.77), _acct("SEB", "LT999", 448.80)]
    txns, out_accts, _, stale = _merge(fresh_txns=fresh, fresh_accts=accts,
                                       diag=diag)
    assert {t["entry_reference"] for t in txns} == {"r1", "s9"}, txns
    assert len(out_accts) == 2, out_accts
    assert stale == [], f"nothing should be stale: {stale}"


def test_no_cache_is_not_a_crash():
    """First ever scan: no cache exists."""
    txns, accts, _, stale = _merge(known={})
    assert txns == FRESH_TXNS and accts == FRESH_ACCTS and stale == []


if __name__ == "__main__":
    for name, fn in sorted(globals().items()):
        if name.startswith("test_") and callable(fn):
            fn()
            print(f"  ok  {name}")
    print("test_known_cache: all green")
