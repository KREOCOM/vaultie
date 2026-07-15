"""Scan-completeness regression test: a bank we FAILED to read must never look
like a bank with nothing to show.

The bug this pins (2026-07-16): when a bank rate-limited us (429), the window
fetch returned the pages it had — indistinguishable from "fully fetched" — so a
refresh published SEB's BALANCE with none of its PAYMENTS. Rent and the loan
silently vanished from the dashboard and from the recurring total, and no error
was raised or logged anywhere.

Rule: the freshest window failing = the account failed. Older windows failing =
keep what we already fetched.

Run:  python3 functions/test_scan_ratelimit.py
"""
import datetime as dt
import json
import sys
import types

# `requests`/`jwt` only exist in the deployed runtime, and this test never makes
# a real call — every HTTP response is scripted below. Stub them so the module
# imports locally.
sys.modules.setdefault("jwt", types.SimpleNamespace(encode=lambda *a, **k: "t"))
sys.modules.setdefault("requests", types.SimpleNamespace(get=None, request=None))

import enable_banking as eb  # noqa: E402
from enable_banking import EnableBankingClient, EnableBankingError  # noqa: E402

TODAY = dt.date(2026, 7, 15)
NEWEST_FROM = "2026-06-15"  # window 0 = [today-30, today]


class _Resp:
    def __init__(self, status, payload=None):
        self.status_code = status
        self._payload = payload if payload is not None else {}
        self.text = json.dumps(self._payload)
        self.ok = 200 <= status < 300

    def json(self):
        return self._payload


def _client():
    # Bypass __init__ — it signs a JWT with a real private key.
    c = object.__new__(EnableBankingClient)
    c._token = "test-token"
    return c


def _txn(ref, date):
    return {"entry_reference": ref, "booking_date": date,
            "transaction_amount": {"amount": "10.00", "currency": "EUR"}}


def _install(handler):
    """Point the client's HTTP calls at [handler](params) -> _Resp."""
    eb.requests.get = lambda url, headers=None, params=None, timeout=None: \
        handler(params)
    eb.time.sleep = lambda _s: None


def _fetch(**kw):
    return _client().transactions("acc-1", months_back=2, window_days=30,
                                  today=TODAY, **kw)


def test_rate_limited_newest_window_raises():
    """429 on the freshest window → an ERROR, never an empty-but-happy result."""
    _install(lambda p: _Resp(429, {"message": "Too Many Requests"}))
    try:
        txns, diag = _fetch()
    except EnableBankingError as e:
        assert e.status == 429, f"expected a 429 error, got {e.status}"
        return
    raise AssertionError(
        f"rate-limited scan returned {len(txns)} txns + diag={diag} instead of "
        "raising — this is the bug: the caller publishes the balance with no "
        "payments")


def test_period_error_on_newest_window_raises():
    """A bank refusing the FRESHEST 30 days is broken, not out of history."""
    _install(lambda p: _Resp(400, {"message": "WRONG_TRANSACTIONS_PERIOD"}))
    try:
        txns, _ = _fetch()
    except EnableBankingError:
        return
    raise AssertionError(
        f"newest-window period error returned {len(txns)} txns instead of "
        "raising")


def test_rate_limited_older_window_keeps_fresh_data():
    """429 while walking BACK → keep the fresh windows already fetched."""
    def handler(p):
        if p["date_from"] == NEWEST_FROM:
            return _Resp(200, {"transactions": [_txn("a", "2026-07-01"),
                                                _txn("b", "2026-07-05")]})
        return _Resp(429, {"message": "Too Many Requests"})

    _install(handler)
    txns, diag = _fetch()
    assert len(txns) == 2, f"lost the fresh window: {txns}"
    assert diag["truncated"] is True, diag
    assert diag["windows"] == 1, diag


def test_history_exhausted_is_not_a_failure():
    """The bank having no data 2 months back is normal — keep what we have."""
    def handler(p):
        if p["date_from"] == NEWEST_FROM:
            return _Resp(200, {"transactions": [_txn("a", "2026-07-01")]})
        return _Resp(400, {"message": "WRONG_TRANSACTIONS_PERIOD"})

    _install(handler)
    txns, diag = _fetch()
    assert len(txns) == 1, txns
    assert diag["history_exhausted"] is True, diag
    assert diag["truncated"] is False, diag


def test_empty_account_still_reads_as_empty():
    """A genuinely quiet account (200, no txns) must NOT look like a failure."""
    _install(lambda p: _Resp(200, {"transactions": []}))
    txns, diag = _fetch()
    assert txns == [], txns
    assert diag["count"] == 0, diag


if __name__ == "__main__":
    for name, fn in sorted(globals().items()):
        if name.startswith("test_") and callable(fn):
            fn()
            print(f"  ok  {name}")
    print("test_scan_ratelimit: all green")
