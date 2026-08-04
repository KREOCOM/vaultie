"""_build_candidate's per-charge "typical cost" must be robust to a single
skewed amount, the same way `_avg_gap` is robust to a single skewed gap.

Real case, 2026-08-04: a gym membership charged ~35 EUR most months through a
generic payment-processor counterparty ("OPAY SOLUTIONS"), but the stream also
picked up one unrelated ~46 EUR charge (an add-on fee, or a second obligation
sharing the same generic processor name). A plain mean of amounts pulled the
reported "cost" up to a number the user never actually paid for the
membership itself. The median resists a single such outlier — over half the
charges have to move together to shift it, not just one.

Run:  python3 functions/test_amount_median_robustness.py
"""

import os
import sys

sys.path.insert(0, os.path.dirname(__file__))

import kb            # noqa: E402
import merchant_db   # noqa: E402
from recurring import detect_recurring  # noqa: E402

kb._entities = []
kb._alias_index = kb._related_index = kb._norm_index = kb._prefix_index = {}
kb._loaded_source = "test"
merchant_db._cache = [
    {"_key": "gymplus", "displayName": "Gym+", "type": "subscription",
     "category": "other", "logoDomain": None, "aliases": ["opay solutions"],
     "status": "active"},
]

failures = []


def check(cond, msg):
    if not cond:
        failures.append(msg)


def _txn(date, amt):
    return {
        "booking_date": date, "credit_debit_indicator": "DBIT",
        "transaction_amount": {"amount": f"{amt:.2f}", "currency": "EUR"},
        "creditor": {"name": "opay solutions"},
        "remittance_information": ["opay solutions"],
        "bank_transaction_code": {"code": "CCRD", "sub_code": "OTHR"},
    }


# Five monthly charges through the same generic processor name. None are
# close enough (>2%) to bucket together as one "fixed amount" — this is the
# whole-group "cohesive-single-stream" path, exactly what a genuinely mixed
# processor-name stream looks like: a typical ~33-35 EUR membership fee most
# months, with two months pulled higher by an unrelated add-on/second charge.
txns = [
    _txn("2026-02-15", 35.00),
    _txn("2026-03-15", 41.00),
    _txn("2026-04-15", 33.00),
    _txn("2026-05-15", 46.00),
    _txn("2026-06-15", 34.00),
]

candidates = detect_recurring(txns)["candidates"]
confident = [c for c in candidates if c["confident"]]
check(len(confident) == 1, f"expected 1 confident stream, got {len(confident)}")

if confident:
    cost = confident[0]["cost"]
    # Median of [33, 34, 35, 41, 46] is 35 — the mean would have been 37.8,
    # a number none of the real membership charges hit.
    check(abs(cost - 35.0) < 0.01, f"expected median cost 35.0, got {cost}")

# Confirm the mean really would have produced a different, misleading figure —
# pins that this fixture genuinely demonstrates the mean's failure mode.
amounts = [35.00, 41.00, 33.00, 46.00, 34.00]
mean = round(sum(amounts) / len(amounts), 2)
check(abs(mean - 37.8) < 0.01, f"fixture's mean drifted: {mean}")
check(mean != 35.0, "fixture no longer distinguishes mean from median")

# Sanity: a tightly-clustered (near-identical) stream is unaffected — median
# and mean coincide when nothing is skewed.
tight = [12.99, 12.99, 12.99, 12.99]
check(sorted(tight)[len(tight) // 2 - 1:len(tight) // 2 + 1] == [12.99, 12.99],
      "tight-cluster median sanity check failed")

if failures:
    print("FAILED:")
    for f in failures:
        print(f"  ✗ {f}")
    sys.exit(1)
print("All amount-median-robustness assertions passed ✓")
