"""Unit test for the recurring REVIEW flag in dashboard._subs — no network.

Product model (Option B): every recurring-SHAPED stream is COUNTED by default,
but streams the engine can't confidently name/classify (unknown merchant, or KB
'possible') carry ``needsReview=True``. The client turns those into a short
review queue where the user confirms ("yes, my rent") or removes them — the
monthly total is NOT reduced until the user rejects one.

This locks that:
  * uncertain streams are FLAGGED (needsReview) but still in ``items`` + total;
  * confident known streams are NOT flagged;
  * one-off / single-charge merchants never get the flag (queue stays short).

Run:  python3 functions/test_subs_review.py
"""

import datetime
import os
import sys

sys.path.insert(0, os.path.dirname(__file__))

import kb  # noqa: E402
import merchant_db  # noqa: E402
import dashboard  # noqa: E402

# Same hermetic pinning as test_recurring.py: empty KB → every lookup falls
# through to the merchant_db seed below (keeps this a LOGIC test, not a test of
# the live Wikidata artifact).
kb._entities = []
kb._alias_index = kb._related_index = kb._norm_index = kb._prefix_index = {}
kb._loaded_source = "test-empty"

merchant_db._cache = [
    {"_key": "spotify", "displayName": "Spotify", "type": "subscription",
     "category": "entertainment", "logoDomain": "spotify.com",
     "aliases": ["spotify"], "status": "active"},
    {"_key": "telia", "displayName": "Telia", "type": "bill",
     "category": "connectivity", "logoDomain": None,
     "aliases": ["telia"], "status": "active"},
    {"_key": "applecombill", "displayName": "Apple", "type": "possible",
     "category": "entertainment", "logoDomain": "apple.com",
     "aliases": ["apple.com", "apple"], "status": "active"},
]


def _txn(date, amount, name, indicator="DBIT"):
    return {
        "booking_date": date,
        "credit_debit_indicator": indicator,
        "transaction_amount": {"amount": f"{amount:.2f}", "currency": "EUR"},
        "creditor": {"name": name} if indicator == "DBIT" else None,
        "debtor": {"name": name} if indicator == "CRDT" else None,
        "remittance_information": [name],
    }


DEMO = [
    # Confident, known subscription/bill → items, auto-counted.
    _txn("2026-05-05", 9.99, "Spotify AB"),
    _txn("2026-06-05", 9.99, "Spotify AB"),
    _txn("2026-05-08", 11.99, "UAB Telia 8842"),
    _txn("2026-06-08", 11.99, "UAB Telia 8842"),
    # KB 'possible', seen 2× → recurring-shaped but uncertain → review.
    _txn("2026-05-20", 22.99, "APPLE.COM/BILL"),
    _txn("2026-06-25", 22.99, "APPLE.COM/US"),
    # Unknown merchant, repeated (rent-like) → manual candidate → review.
    _txn("2026-05-03", 1200.00, "MB Artusgrupė"),
    _txn("2026-05-31", 1200.00, "MB Artusgrupe"),
    # One-off unknown → must NOT reach review (seen once, not recurring-shaped).
    _txn("2026-06-18", 12.00, "SOMECLOUD.IO"),
    # Income → never a candidate anywhere.
    _txn("2026-06-01", 2100.00, "Employer UAB", indicator="CRDT"),
]


def main() -> int:
    res = dashboard._subs(DEMO, today=datetime.date(2026, 7, 1))
    by_name = {it["name"]: it for it in res["items"]}
    item_names = set(by_name)
    review_names = {n for n, it in by_name.items() if it.get("needsReview")}
    failures = []

    def check(cond, msg):
        if not cond:
            failures.append(msg)

    # Confident, known → counted, NOT flagged for review.
    check("Spotify" in item_names, "Spotify not in items")
    check("Spotify" not in review_names, "Spotify wrongly flagged needsReview")
    check("Telia" in item_names, "Telia not in items")
    check("Telia" not in review_names, "Telia wrongly flagged needsReview")

    # Uncertain (possible / unknown) → still counted, but FLAGGED for review.
    check("Apple" in item_names, "Apple not in items")
    check("Apple" in review_names, "Apple (possible) not flagged needsReview")
    check("MB Artusgrupė" in item_names, "unknown recurring not in items")
    check("MB Artusgrupė" in review_names, "unknown recurring not flagged")

    # A single-charge / one-off never gets flagged (queue stays short).
    check(not any("somecloud" in n.lower() for n in review_names),
          "one-off SomeCloud wrongly flagged for review")

    # Uncertain streams ARE in the total by default (Option B) — the user
    # removes them if wrong; the heuristic never silently drops them.
    check(res["total"] > 1200, f"uncertain rent should be counted, total={res['total']}")
    check(all("needsReview" in it for it in res["items"]),
          "some item missing needsReview flag")

    print(f"items={sorted(item_names)}")
    print(f"flagged(needsReview)={sorted(review_names)}  total={res['total']}")

    if failures:
        print("\nFAILURES:")
        for f in failures:
            print(f"  ✗ {f}")
        return 1
    print("\nAll review-queue assertions passed ✓")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
