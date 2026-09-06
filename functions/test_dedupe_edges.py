"""Two ways a real bank breaks dedup, both of which get the money wrong silently.

  * A reference is only unique WITHIN an account. Banks that number entries per
    account hand two wallets the same "1", and deduping on the reference alone
    dropped one of two real transactions — money missing, no error anywhere.
  * A PENDING row books at a DIFFERENT amount. A fuel pump authorises 1 EUR and
    books 62; a hotel authorises the room and books the extras. Matching on the
    amount left both rows standing and counted the day twice.

Run:  ./venv/bin/python test_dedupe_edges.py
"""
import os
import sys

sys.path.insert(0, os.path.dirname(__file__))
from normalize import dedupe  # noqa: E402

fails = []


def check(ok, msg):
    if not ok:
        fails.append(msg)


def tx(ref, day, amount, merchant, *, status="BOOK", acct="a1", bank="Revolut"):
    return {
        "entry_reference": ref,
        "booking_date": day,
        "status": status,
        "_acct": acct,
        "_bank": bank,
        "credit_debit_indicator": "DBIT",
        "transaction_amount": {"amount": f"{amount:.2f}", "currency": "EUR"},
        "creditor": {"name": merchant},
        "remittance_information": [merchant],
    }


def refs(out):
    return sorted((t["entry_reference"], t.get("_acct")) for t in out)


# ── 1. the same reference in two accounts is two transactions ───────────────
out = dedupe([
    tx("1", "2026-07-10", 20, "MAXIMA", acct="wallet-eur"),
    tx("1", "2026-07-10", 35, "RIMI", acct="wallet-nok"),
])
check(len(out) == 2,
      f"a per-account reference collision dropped a real transaction: {refs(out)}")

# ── 2. within ONE account it is still a duplicate ──────────────────────────
out = dedupe([
    tx("1", "2026-07-10", 20, "MAXIMA", acct="wallet-eur"),
    tx("1", "2026-07-10", 20, "MAXIMA", acct="wallet-eur"),
])
check(len(out) == 1, f"overlapping paging windows duplicated: {refs(out)}")

# ── 3. pending settles at a DIFFERENT amount ───────────────────────────────
out = dedupe([
    tx("p1", "2026-07-10", 1.00, "CIRCLE K", status="PDNG"),
    tx("b1", "2026-07-11", 62.40, "CIRCLE K"),
])
check(len(out) == 1 and out[0]["entry_reference"] == "b1",
      f"a fuel pre-authorisation was counted on top of the real charge: {refs(out)}")

# ── 4. pending with no booked counterpart survives ─────────────────────────
out = dedupe([
    tx("p1", "2026-07-10", 1.00, "CIRCLE K", status="PDNG"),
    tx("b1", "2026-07-11", 62.40, "MAXIMA"),
])
check(len(out) == 2,
      "a pending with no settled version was dropped — the user would see money "
      "leave the balance with nothing to explain it")

# ── 5. one booked settles only ONE pending ─────────────────────────────────
# Two real visits to the same shop, one already booked and one still pending.
out = dedupe([
    tx("p1", "2026-07-10", 12.00, "MAXIMA", status="PDNG"),
    tx("p2", "2026-07-11", 30.00, "MAXIMA", status="PDNG"),
    tx("b1", "2026-07-11", 12.50, "MAXIMA"),
])
check(len(out) == 2,
      f"one booked row settled two pendings — a real purchase vanished: {refs(out)}")

# ── 6. a pending far from any booked row is left alone ─────────────────────
out = dedupe([
    tx("p1", "2026-06-01", 20.00, "MAXIMA", status="PDNG"),
    tx("b1", "2026-07-11", 20.00, "MAXIMA"),
])
check(len(out) == 2,
      "a pending five weeks from the booked row was treated as the same "
      "purchase — the window has to stay tight")

# ── 7. same merchant, different ACCOUNTS, are not paired ───────────────────
out = dedupe([
    tx("p1", "2026-07-10", 20.00, "MAXIMA", status="PDNG", acct="wallet-eur"),
    tx("b1", "2026-07-11", 20.00, "MAXIMA", acct="wallet-nok"),
])
check(len(out) == 2,
      "a pending in one wallet was settled by a booking in another")

# ── 9. an OLDER booked row must never "settle" a NEWER pending one ─────────
# Real report (2026-08-16): a frequent-merchant shopper (Circle K, Maxima)
# refreshed and saw nothing past a few days ago even though they'd bought
# something today. Root cause: the day-window used to be symmetric
# (abs(bd - d) <= 4), so an already-booked visit from days ago could "settle"
# today's still-pending visit to the SAME merchant — backwards, since a
# booked confirmation can only arrive at or after a charge went pending,
# never before it. Today's real purchase vanished, silently, every refresh.
out = dedupe([
    tx("b1", "2026-08-12", 23.86, "CIRCLE K MISKAS"),          # booked days ago
    tx("p1", "2026-08-16", 19.40, "CIRCLE K MISKAS", status="PDNG"),  # today
])
check(len(out) == 2,
      f"an older booked visit wrongly settled today's pending one: {refs(out)}")

# ── 8. transactions without any reference still dedupe ─────────────────────
a = tx("", "2026-07-10", 9.99, "SPOTIFY")
b = tx("", "2026-07-10", 9.99, "SPOTIFY")
a.pop("entry_reference"), b.pop("entry_reference")
check(len(dedupe([a, b])) == 1,
      "a bank that omits the reference duplicated across paging windows")

if fails:
    print("FAILURES:")
    for f in fails:
        print("  ✗", f)
    sys.exit(1)
print("All dedupe-edge assertions hold ✓")
