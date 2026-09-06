"""Incremental refresh: fetch only the recent days, keep the rest from the phone.

The risk here is not speed, it is arithmetic. If the merge is wrong a transaction
is either counted twice or disappears, and both are silent — the dashboard still
renders, it just shows the wrong number. So these check the merge itself rather
than that it "worked".

Run:  ./venv/bin/python test_incremental_sync.py
"""
import datetime as dt
import os
import sys

sys.path.insert(0, os.path.dirname(__file__))
from known_cache import merge_known  # noqa: E402

TODAY = dt.date(2026, 7, 30)
FRESH_FROM = (TODAY - dt.timedelta(days=21)).isoformat()

fails = []


def check(ok, msg):
    if not ok:
        fails.append(msg)


def tx(ref, day, bank="Revolut", status="BOOK", amount=10.0):
    return {
        "entry_reference": ref,
        "booking_date": day,
        "status": status,
        "bank": bank,
        "transaction_amount": {"amount": f"{amount:.2f}", "currency": "EUR"},
    }


def acct(iban, bank="Revolut"):
    return {"iban": iban, "bank": bank, "name": "Acct", "currency": "EUR",
            "amount": 100.0}


def run(fresh_txns, cache_txns, *, diag, fresh_accts=None, fresh_from=FRESH_FROM):
    return merge_known(
        list(fresh_txns),
        list(fresh_accts if fresh_accts is not None else [acct("LT01")]),
        set(),
        diag,
        {"txns": list(cache_txns), "accounts": [acct("LT01")]},
        6,
        today=TODAY,
        fresh_from=fresh_from,
    )


ANSWERED = [{"bank": "Revolut"}]                      # no error key = answered
QUIET = [{"bank": "Revolut", "error": "429"}]
REVOKED = [{"bank": "Revolut", "revoked": True}]

# ── 1. older history survives a short fetch ─────────────────────────────────
fresh = [tx("new-1", "2026-07-28"), tx("new-2", "2026-07-20")]
cache = [tx("old-1", "2026-05-02"), tx("old-2", "2026-03-11"),
         tx("new-2", "2026-07-20")]  # also in the fresh window
txns, _a, _i, stale = run(fresh, cache, diag=ANSWERED)
refs = [t["entry_reference"] for t in txns]
check("old-1" in refs and "old-2" in refs,
      "older cached history was dropped — the dashboard would lose months")
check(refs.count("new-2") == 1,
      f"new-2 appears {refs.count('new-2')}x — a transaction inside the fresh "
      "window was re-added from cache")
check(len(refs) == len(set(refs)), f"duplicate references: {refs}")

# ── 2. a bank that answered is NOT marked stale ─────────────────────────────
check(stale == [],
      f"answered bank reported as stale {stale} — the UI would show "
      '"not updated" on a bank that just synced')

# ── 3. nothing inside the fresh window is ever reused ───────────────────────
# Same day, DIFFERENT reference: the cached copy was pending, the bank has since
# booked it under a new id. Reusing it would double the day.
fresh = [tx("booked-9", "2026-07-25", amount=40)]
cache = [tx("pending-9", "2026-07-25", amount=40)]
txns, *_ = run(fresh, cache, diag=ANSWERED)
refs = [t["entry_reference"] for t in txns]
check("pending-9" not in refs,
      "a cached entry inside the fresh window was reused — pending/booked churn "
      "double-counts the day")

# ── 4. pending cache entries are never reused, at any age ───────────────────
cache = [tx("p-old", "2026-04-01", status="PDNG")]
txns, *_ = run([], cache, diag=ANSWERED)
check("p-old" not in [t["entry_reference"] for t in txns],
      "a PENDING cached entry was reused — it may since have been cancelled")

# ── 5. revoked consent still wipes the bank ─────────────────────────────────
cache = [tx("old-1", "2026-05-02")]
txns, accts, _i, _s = run([], cache, diag=REVOKED, fresh_accts=[])
check(txns == [] and accts == [],
      "data survived a revoked consent — withdrawing access must stop exactly "
      "this")

# ── 6. quiet bank still served whole (the original behaviour) ───────────────
cache = [tx("old-1", "2026-05-02"), tx("recent", "2026-07-29")]
txns, _a, _i, stale = run([], cache, diag=QUIET, fresh_accts=[])
refs = [t["entry_reference"] for t in txns]
check("old-1" in refs and "recent" in refs,
      "a bank that failed lost its cached data — rent would vanish from the "
      "dashboard because one provider rate-limited us")
check(stale == ["Revolut"], f"a quiet bank must be flagged stale, got {stale}")

# ── 7. full scan (no fresh_from) behaves exactly as before ──────────────────
cache = [tx("old-1", "2026-05-02")]
txns, *_ = run([tx("new-1", "2026-07-28")], cache,
               diag=ANSWERED, fresh_from=None)
check("old-1" not in [t["entry_reference"] for t in txns],
      "without fresh_from an answered bank must NOT gain cached history — that "
      "is the old contract and other call sites rely on it")

# ── 8. the six-month window is still a limit ────────────────────────────────
cache = [tx("ancient", "2024-01-01")]
txns, *_ = run([], cache, diag=ANSWERED)
check("ancient" not in [t["entry_reference"] for t in txns],
      "cache reached outside months_back — the range would grow on its own")

print(f"checks run against merge_known, fresh_from={FRESH_FROM}")
if fails:
    print("\nFAILURES:")
    for f in fails:
        print("  ✗", f)
    sys.exit(1)
print("All incremental-sync assertions hold ✓")
