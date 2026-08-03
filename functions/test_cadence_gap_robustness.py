"""_avg_gap must be robust to a single missing observation.

Real case, 2026-08-04: a user's MOGO loan charged ~399 EUR every ~30 days,
but one month's charge went through a bank that was not yet connected — so
Vaultie only ever saw a 61-day gap where a 30-day one belonged. A mean of
[29, 29, 30, 61] is 37.25, just outside _classify_cadence's 25-35 "monthly"
band, so the whole stream fell to "custom" and its monthly-equivalent got
multiplied by the wrong (gap-derived) ratio — a real ~399 EUR/mo payment
displayed as ~326 EUR, though every individual charge was correct.

Run:  python3 functions/test_cadence_gap_robustness.py
"""

import datetime as dt
import os
import sys

sys.path.insert(0, os.path.dirname(__file__))

from recurring import _avg_gap, _classify_cadence  # noqa: E402

failures = []


def check(cond, msg):
    if not cond:
        failures.append(msg)


# The exact MOGO dates from the live case: Feb 15, Mar 16, Apr 14, May 14,
# Jul 14 — June's charge is invisible (routed through an unconnected bank),
# so the gap from May 14 to Jul 14 is ~61 days instead of ~30.
dates = [
    dt.date(2026, 2, 15),
    dt.date(2026, 3, 16),
    dt.date(2026, 4, 14),
    dt.date(2026, 5, 14),
    dt.date(2026, 7, 14),
]

gap = _avg_gap(dates)
check(gap == 29.5, f"expected median gap 29.5, got {gap}")

cycle, label = _classify_cadence(gap)
check(cycle == "monthly", f"one missing month misclassified cadence as {cycle!r}, not 'monthly'")

# A mean over the same dates would have produced 37.25 and "custom" — pin
# that this is genuinely the reason the fix matters, not a coincidence.
mean_gap = sum((dates[i + 1] - dates[i]).days for i in range(len(dates) - 1)) / (len(dates) - 1)
check(abs(mean_gap - 37.25) < 0.01, f"fixture's mean gap drifted: {mean_gap}")
mean_cycle, _ = _classify_cadence(mean_gap)
check(mean_cycle == "custom", "fixture no longer demonstrates the mean's failure mode")

# Sanity: a genuinely irregular ("custom") cadence must still classify as
# custom — the fix must not make everything look monthly.
irregular = [
    dt.date(2026, 1, 1),
    dt.date(2026, 2, 15),  # +45
    dt.date(2026, 4, 20),  # +64
]
irr_gap = _avg_gap(irregular)
irr_cycle, _ = _classify_cadence(irr_gap)
check(irr_cycle == "custom", f"genuinely irregular cadence now misclassified as {irr_cycle!r}")

if failures:
    print("FAILED:")
    for f in failures:
        print(f"  ✗ {f}")
    sys.exit(1)
print("All cadence-gap-robustness assertions passed ✓")
