"""Run MANY synthetic users through the dashboard and assert the rules that must
hold for every one of them.

Why this exists: every bug found so far came from ONE real dataset (one person,
three accounts). The worry that follows is fair — with a hundred users and
hundreds of accounts, which failures are waiting? Reasoning about that does not
answer it. Generating a few hundred plausible users and checking invariants does.

These are not "does it detect nicely" tests. They are the statements that must
never be false, whatever the data:

  1. One merchant at one PRICE is one commitment. The same charge must not be
     split in two — that is the MOGO 399/398 shape that reported 199/mo. Two
     genuinely different prices at one merchant stay separate on purpose.
  2. No invented amount. A stream's monthly figure must be explainable by charges
     that actually happened: never more than the largest single charge scaled by
     its own cadence.
  3. The total is the sum of its parts.
  4. A person is never a bill.
  5. A stream seen twice with an unrecognised gap is ASKED about, not presented
     as settled.

Run:  ./venv/bin/python test_corpus_invariants.py
"""
import datetime as dt
import os
import random
import sys

sys.path.insert(0, os.path.dirname(__file__))
from dashboard import build_dashboard  # noqa: E402

TODAY = dt.date(2026, 7, 20)
ACCOUNTS = [{"name": "SEB", "balance": 1500, "sub": "", "icon": "bank",
             "currency": "EUR"}]

# Cadence -> per-month factor the engine uses, for invariant 2.
PER_MONTH = {"weekly": 4.345, "biweekly": 2.174, "monthly": 1.0,
             "quarterly": 1 / 3.0, "semiannual": 1 / 6.0, "yearly": 1 / 12.0}

fails = []
seen_profiles = 0


def check(ok, msg):
    if not ok:
        fails.append(msg)


def tx(amount, date, ref, merchant, income=False):
    return {
        "entry_reference": ref,
        "booking_date": date.isoformat(),
        "credit_debit_indicator": "CRDT" if income else "DBIT",
        "transaction_amount": {"amount": f"{abs(amount):.2f}", "currency": "EUR"},
        ("debtor" if income else "creditor"): {"name": merchant},
        "remittance_information": [merchant],
        "bank_transaction_code": {"code": "CCRD", "sub_code": "OTHR"},
    }


def monthly_series(rng, merchant, amount, months, *, drift=0.0, day=None,
                   gap_days=None, income=False):
    """A recurring charge. `drift` lets the amount wobble like a real loan or a
    utility bill; `gap_days` overrides the monthly spacing."""
    out = []
    day = day or rng.randint(1, 28)
    start = TODAY - dt.timedelta(days=30 * months)
    for i in range(months):
        when = (start + dt.timedelta(days=(gap_days or 30) * i))
        if when > TODAY:
            break
        amt = amount + (rng.uniform(-drift, drift) if drift else 0.0)
        out.append(tx(round(amt, 2), when, f"{merchant}-{i}-{rng.random()}",
                      merchant, income=income))
    return out


def make_user(seed):
    """One plausible person: salary, rent, a loan, insurance, some subscriptions,
    phone top-ups, and everyday noise."""
    rng = random.Random(seed)
    t = []
    # income
    t += monthly_series(rng, "UAB DARBDAVYS", rng.choice([1400, 1900, 2600]),
                        8, income=True)
    # rent — a round number that never drifts
    t += monthly_series(rng, "SAVININKAS UAB", rng.choice([450, 600, 850]), 8)
    # a loan booked with cent drift — the MOGO shape
    loan = rng.choice([199.0, 399.0, 512.0])
    t += monthly_series(rng, rng.choice(["MOGO", "GOGO.LT", "GENERAL FINANCING"]),
                        loan, 7, drift=1.5)
    # insurance, quarterly
    t += monthly_series(rng, "BTA DRAUDIMAS", rng.choice([48.0, 120.0]), 3,
                        gap_days=91)
    # subscriptions, one of which gets more expensive halfway
    t += monthly_series(rng, "SPOTIFY", 9.99, 4)
    # A genuine price RISE: cheaper for the older months, dearer for the recent
    # ones, never both in the same month. (Generating them overlapping made two
    # concurrent subscriptions, which is a different thing entirely — the first
    # run of this file failed on exactly that mistake in the generator.)
    for i in range(6):
        when = TODAY - dt.timedelta(days=30 * (5 - i))
        t.append(tx(12.99 if i < 3 else 15.99, when, f"nf-{i}-{seed}",
                    "NETFLIX.COM"))
    # phone top-ups at wildly different amounts — must NOT merge
    for amt in (5.0, 12.0, 25.0):
        t += monthly_series(rng, "PILDYK", amt, rng.randint(2, 5))
    # a person paying you back, and one you pay
    t += [tx(rng.choice([20, 50, 133]), TODAY - dt.timedelta(days=rng.randint(1, 90)),
             f"p-{seed}-{i}", rng.choice(["Rimvydas Lebrikas", "Ingrida Petrauskė",
                                          "John Smith", "Karl Svensson"]),
             income=bool(i % 2)) for i in range(4)]
    # everyday noise
    shops = ["MAXIMA LT", "RIMI SIAURES", "CIRCLE K", "AIBE", "LIDL"]
    for i in range(60):
        t += [tx(round(rng.uniform(1.5, 60), 2),
                 TODAY - dt.timedelta(days=rng.randint(0, 180)),
                 f"s-{seed}-{i}", rng.choice(shops))]
    return t


def norm(name):
    return " ".join(str(name or "").split()).lower()


PERSON_HINTS = ["rimvydas", "ingrida", "john smith", "karl svensson"]

for seed in range(120):
    seen_profiles += 1
    dash = build_dashboard(make_user(seed), ACCOUNTS, today=TODAY, ai_key=None)
    subs = dash["subs"]
    items = subs["items"]

    # ── 1. one merchant at one PRICE is one commitment ─────────────────────
    # Not "one merchant, one stream": iCloud at 2.99 and Apple One at 19.95 are
    # deliberately separate, and so are 5 EUR and 25 EUR phone top-ups. What must
    # never happen is the SAME charge split in two — the MOGO 399/398 shape.
    by_merchant = {}
    for it in items:
        by_merchant.setdefault(norm(it["name"]), []).append(it)
    for name, group in by_merchant.items():
        for a_i in range(len(group)):
            for b_i in range(a_i + 1, len(group)):
                x, y = group[a_i], group[b_i]
                if (x.get("billingCycle") or x.get("cadence")) != \
                   (y.get("billingCycle") or y.get("cadence")):
                    continue
                cx, cy = float(x.get("cost") or 0), float(y.get("cost") or 0)
                span = max(abs(cx), abs(cy))
                if span > 0 and abs(cx - cy) <= span * 0.05:
                    check(False,
                          f"seed {seed}: '{name}' split into two streams at "
                          f"{cx} and {cy} — same charge, counted twice")

    # ── 2. no invented amount ─────────────────────────────────────────────
    for it in items:
        cost = float(it.get("cost") or 0)
        cad = it.get("billingCycle") or it.get("cadence") or "monthly"
        factor = PER_MONTH.get(cad)
        if factor is None:
            continue                      # "custom" is gap-derived; covered by 5
        ceiling = cost * factor * 1.05 + 0.01
        check(float(it["monthly"]) <= ceiling,
              f"seed {seed}: '{it['name']}' monthly {it['monthly']} exceeds "
              f"{ceiling:.2f} (cost {cost} x {cad})")

    # ── 3. the total is the sum of its parts ──────────────────────────────
    active_sum = round(sum(float(i["monthly"]) for i in items if i.get("active")), 2)
    check(abs(active_sum - float(subs["total"])) < 0.05,
          f"seed {seed}: total {subs['total']} != sum of active {active_sum}")

    # ── 4. a person is never a bill ───────────────────────────────────────
    for it in items:
        n = norm(it["name"])
        check(not any(h in n for h in PERSON_HINTS),
              f"seed {seed}: person '{it['name']}' presented as {it.get('type')}")

    # ── 5. two charges at an unknown gap are ASKED about ──────────────────
    for it in items:
        occ = it.get("occurrences")
        cad = it.get("billingCycle") or it.get("cadence")
        if occ is not None and occ < 3 and cad == "custom":
            check(it.get("needsReview") is True,
                  f"seed {seed}: '{it['name']}' ({occ}x, custom gap) presented "
                  f"as settled at {it['monthly']}/mo")

print(f"profiles checked: {seen_profiles}")
if fails:
    print(f"\nFAILURES ({len(fails)}) — showing first 25:")
    for f in fails[:25]:
        print("  ✗", f)
    sys.exit(1)
print("All corpus invariants hold ✓")
