"""Accounts are scanned concurrently, not one after another.

Found from a real complaint: "sync takes about a minute, Bilance does it in
10-15 seconds". `_scan_accounts` fetched balance + transactions for each
account in a plain `for` loop — pure blocking I/O to a real bank's servers, so
a user with four accounts (one bank plus a 3-wallet Revolut) paid for four
accounts' worth of real-bank latency, added together in series, on every open
of the app.

This pins three things a parallel rewrite could easily get wrong:
  1. wall-clock time scales with the SLOWEST account, not the sum of all of
     them — the actual fix;
  2. output order is deterministic (input order), regardless of which
     account's fake network call happens to return first;
  3. one account failing still never drops the others, exactly as the
     sequential version guaranteed.

Run:  ./venv/bin/python test_scan_accounts_concurrent.py
"""
import os
import sys
import time

sys.path.insert(0, os.path.dirname(__file__))
from enable_banking import EnableBankingError  # noqa: E402
from main import _scan_accounts  # noqa: E402

failures = []


def check(label, cond, detail=""):
    if not cond:
        failures.append(f"{label}{(' — ' + detail) if detail else ''}")


class FakeClient:
    """Stands in for EnableBankingClient. Each account's balances()/
    transactions() call sleeps for a configured duration, so the test can tell
    a parallel scan from a sequential one by wall-clock time alone — no mocking
    of internals, no timing hacks inside main.py."""

    def __init__(self, delays, fail_uids=frozenset(), raise_uids=frozenset()):
        self.delays = delays          # {uid: seconds}
        self.fail_uids = fail_uids    # uids whose transactions() call raises EnableBankingError
        self.raise_uids = raise_uids  # uids whose transactions() call raises a RAW exception
                                       # (network fault, not a shaped bank error)

    def psu_headers_for(self, *a, **k):
        return {}

    def balances(self, uid, *, psu=None):
        time.sleep(self.delays.get(uid, 0) / 2)
        return [{"balance_amount": {"amount": "100.00", "currency": "EUR"},
                 "balance_type": "CLBD"}]

    def transactions(self, uid, *, months_back=6, psu=None, today=None):
        time.sleep(self.delays.get(uid, 0) / 2)
        if uid in self.fail_uids:
            raise EnableBankingError(401, f"/accounts/{uid}/transactions", "revoked")
        if uid in self.raise_uids:
            raise TimeoutError("connection timed out")
        return ([{"entry_reference": f"{uid}-1",
                  "transaction_amount": {"amount": "-5.00", "currency": "EUR"},
                  "credit_debit_indicator": "DBIT", "booking_date": "2026-07-01"}],
                {"pages": 1})


def meta(n, iban=None):
    return {"uid": f"acct{n}", "name": f"Account {n}",
            "iban": iban or f"LT{n:018d}", "currency": "EUR", "bank": "SEB"}


# ── 1. wall-clock scales with the slowest account, not the sum ─────────────
metas = [meta(1), meta(2), meta(3), meta(4)]
delays = {"acct1": 0.3, "acct2": 0.3, "acct3": 0.3, "acct4": 0.3}
client = FakeClient(delays)

t0 = time.monotonic()
txns, summaries, diag, own_ibans = _scan_accounts(client, metas, months_back=6)
elapsed = time.monotonic() - t0

sequential_would_be = sum(delays.values())  # 1.2s
check("four accounts scan in well under the sequential sum",
      elapsed < sequential_would_be * 0.6,
      f"elapsed={elapsed:.2f}s, sequential would be ~{sequential_would_be:.2f}s")
check("all four accounts still produced a summary", len(summaries) == 4,
      f"got {len(summaries)}")
check("all four accounts' transactions are present", len(txns) == 4,
      f"got {len(txns)}")

# ── 2. output order is deterministic — the slowest account is FIRST here,
#      so if order followed completion instead of input, this would catch it
metas2 = [meta(10), meta(11), meta(12)]
delays2 = {"acct10": 0.3, "acct11": 0.05, "acct12": 0.15}
client2 = FakeClient(delays2)
_txns2, summaries2, _diag2, _own2 = _scan_accounts(client2, metas2, months_back=6)
check("summaries preserve input order despite different account speeds",
      [s["name"] for s in summaries2] == ["Account 10", "Account 11", "Account 12"],
      f"got {[s['name'] for s in summaries2]}")

# ── 3. one account failing never drops the others ───────────────────────────
metas3 = [meta(20), meta(21), meta(22)]
client3 = FakeClient({}, fail_uids={"acct21"})
_txns3, summaries3, diag3, _own3 = _scan_accounts(client3, metas3, months_back=6)
check("the failing account is excluded from summaries",
      "Account 21" not in [s["name"] for s in summaries3])
check("the other two accounts still succeeded",
      {"Account 20", "Account 22"} <= {s["name"] for s in summaries3},
      f"got {[s['name'] for s in summaries3]}")
check("the failure is recorded in scan_diag with its status",
      any(d.get("account") == "Account 21" and d.get("revoked") for d in diag3),
      f"diag={diag3}")
check("scan_diag has one entry per account, success or failure",
      len(diag3) == 3, f"got {len(diag3)}")

# ── 3b. a RAW (non-EnableBankingError) exception never crashes the scan ─────
# 2026-08-16 regression: _scan_one_account's docstring promised "never
# raises", but only EnableBankingError was ever caught — a genuine network
# fault (timeout, connection reset) escaped uncaught, propagated through
# ex.map's thread pool, and crashed the WHOLE finish_bank_auth/
# refresh_dashboard call. A user with 3 banks lost their entire dashboard
# because ONE bank timed out.
metas3b = [meta(23), meta(24), meta(25)]
client3b = FakeClient({}, raise_uids={"acct24"})
_txns3b, summaries3b, diag3b, _own3b = _scan_accounts(client3b, metas3b, months_back=6)
check("a raw exception doesn't propagate out of _scan_accounts",
      True)  # reaching this line at all is the assertion — a crash would abort the test
check("the account whose fetch raised is excluded from summaries",
      "Account 24" not in [s["name"] for s in summaries3b])
check("the other two accounts still succeeded despite the raw exception",
      {"Account 23", "Account 25"} <= {s["name"] for s in summaries3b},
      f"got {[s['name'] for s in summaries3b]}")
check("the raw-exception failure is still recorded in scan_diag",
      any(d.get("account") == "Account 24" and "timed out" in (d.get("error") or "")
          for d in diag3b),
      f"diag={diag3b}")

# ── 4. dedup and own_ibans are unaffected by concurrency ────────────────────
dupe_metas = [meta(30), meta(30), meta(31)]  # acct30 listed twice
client4 = FakeClient({})
txns4, summaries4, _diag4, own4 = _scan_accounts(client4, dupe_metas, months_back=6)
check("a duplicate account uid is scanned once, not twice",
      len(summaries4) == 2, f"got {len(summaries4)}")
check("own_ibans still collects every unique account's IBAN",
      len(own4) == 2, f"got {own4}")

if failures:
    print("FAILED:")
    for f in failures:
        print("  ✗ " + f)
    sys.exit(1)
print(f"ok — 4 accounts scanned in {elapsed:.2f}s (sequential would be "
      f"~{sequential_would_be:.2f}s); order, isolation and dedup all hold")
