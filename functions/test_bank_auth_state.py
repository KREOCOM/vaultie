"""finish_bank_auth used to exchange ANY code a caller supplied for accounts
bound to that caller's uid, with nothing proving the code came from a consent
flow that uid itself started (start_bank_auth's own `state` was generated,
handed to the client, and then never checked again). A deep link crafted with
someone else's valid code — obtained from their own, unrelated auth flow —
could link their bank account into whichever signed-in victim tapped it.

_consume_auth_state's Firestore round-trip isn't unit-testable without a live
Firestore (same convention as _owned_accounts elsewhere in this file — no
mock is worth the false confidence it'd give). This pins the one genuinely
pure piece: the freshness window, where an off-by-one or timezone slip would
either lock users out of a slow bank consent page or leave a stale state
exchangeable indefinitely.

Run:  ./venv/bin/python test_bank_auth_state.py
"""
import datetime as dt
import os
import sys

sys.path.insert(0, os.path.dirname(__file__))
import main  # noqa: E402

fails = []


def check(ok, msg):
    if not ok:
        fails.append(msg)


now = dt.datetime(2026, 8, 16, 12, 0, 0, tzinfo=dt.timezone.utc)

check(main._auth_state_fresh(now.isoformat(), now=now),
      "a state created RIGHT NOW must be fresh")
check(main._auth_state_fresh((now - dt.timedelta(minutes=29)).isoformat(), now=now),
      "29 minutes old — a slow bank consent page — must still be accepted")
check(not main._auth_state_fresh((now - dt.timedelta(minutes=31)).isoformat(), now=now),
      "31 minutes old must be rejected — the whole point of a TTL")
check(not main._auth_state_fresh(None, now=now),
      "a missing createdAt must never be treated as fresh")
check(not main._auth_state_fresh("not-a-timestamp", now=now),
      "a malformed createdAt must never be treated as fresh")

if fails:
    print("FAILURES:")
    for f in fails:
        print("  ✗", f)
    sys.exit(1)
print("All bank-auth-state freshness assertions hold ✓")
