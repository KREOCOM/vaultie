"""Disconnecting ONE bank must not touch the others, and must not trust the caller.

`_disconnect_plan` decides which session and account ids a disconnect is allowed
to act on. That decision is the whole risk:

  * take the other banks' ids with it, and the user can no longer refresh the
    banks they kept;
  * act on an id the caller merely SUPPLIED, and a signed-in user can revoke
    somebody else's bank access — the hole delete_user_data was fixed for.

Run:  ./venv/bin/python test_disconnect_bank.py
"""
import os
import sys

sys.path.insert(0, os.path.dirname(__file__))
from main import _disconnect_plan  # noqa: E402

OWNED_SESSIONS = {"sess-revolut", "sess-seb"}
OWNED_ACCOUNTS = {"acc-rev-1", "acc-rev-2", "acc-seb-1"}

fails = []


def check(ok, msg):
    if not ok:
        fails.append(msg)


def plan(sessions, accounts):
    return _disconnect_plan(sessions, accounts, OWNED_SESSIONS, OWNED_ACCOUNTS)


# ── 1. one bank goes, the other is untouched ────────────────────────────────
s, a = plan(["sess-revolut"], ["acc-rev-1", "acc-rev-2"])
check(s == ["sess-revolut"], f"wrong sessions: {s}")
check(a == ["acc-rev-1", "acc-rev-2"], f"wrong accounts: {a}")
check("sess-seb" not in s and "acc-seb-1" not in a,
      "the OTHER bank was included — the user could no longer refresh the bank "
      "they kept")

# ── 2. ids the user does not own are ignored ────────────────────────────────
s, a = plan(["sess-someone-else"], ["acc-not-mine"])
check(s == [], f"revoked a session the user does not own: {s}")
check(a == [], f"forgot an account the user does not own: {a}")

# ── 3. a mixed request acts only on the owned half ──────────────────────────
s, a = plan(["sess-seb", "sess-someone-else"], ["acc-seb-1", "acc-not-mine"])
check(s == ["sess-seb"], f"mixed request took too much: {s}")
check(a == ["acc-seb-1"], f"mixed request took too much: {a}")

# ── 4. nothing in, nothing out ──────────────────────────────────────────────
check(plan([], []) == ([], []), "an empty request produced work to do")

# ── 5. duplicates collapse ──────────────────────────────────────────────────
s, a = plan(["sess-seb", "sess-seb"], ["acc-seb-1", "acc-seb-1"])
check(s == ["sess-seb"] and a == ["acc-seb-1"],
      f"duplicates were not collapsed: {s} {a}")

# ── 6. the result is ordered, so a caller cannot depend on request order ────
s1, a1 = plan(["sess-seb", "sess-revolut"], ["acc-rev-2", "acc-rev-1"])
s2, a2 = plan(["sess-revolut", "sess-seb"], ["acc-rev-1", "acc-rev-2"])
check(s1 == s2 and a1 == a2,
      f"order of the request changed the result: {s1}/{s2} {a1}/{a2}")

# ── 7. disconnecting every bank is allowed ──────────────────────────────────
# Not a special case: it is the existing "disconnect everything and start again"
# path, and it must not silently keep a session alive.
s, a = plan(sorted(OWNED_SESSIONS), sorted(OWNED_ACCOUNTS))
check(s == sorted(OWNED_SESSIONS) and a == sorted(OWNED_ACCOUNTS),
      f"disconnecting all banks dropped some ids: {s} {a}")

if fails:
    print("FAILURES:")
    for f in fails:
        print("  ✗", f)
    sys.exit(1)
print("All disconnect-bank assertions hold ✓")
