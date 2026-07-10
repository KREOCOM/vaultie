"""Recurring-payment detection (Vaultie 3.0).

Two paths, driven by the Firestore merchant DB (see merchant_db.py) and the
rules in functions/merchants_seed.json:

  1. Known merchant (DB hit) — recurring on sight (min 1 occurrence). Its ``type``
     comes from the DB: ``subscription`` / ``bill`` are imported; ``frequent``
     is NEVER recurring (surfaced separately if seen >=2× in the window);
     ``possible`` is treated as a subscription needing review.
  2. Unknown merchant — needs >=2 payments of a similar amount (+/-15%) at a
     recognised cadence. A large regular payment (>200 EUR, possibly to a
     person) is treated as rent → a housing bill.

Each candidate carries ``type`` and ``needsReview``. Raw transactions are never
returned or stored.
"""

import datetime as dt
import logging
import re
from collections import defaultdict

import merchant_db

# Detection rules — mirror functions/merchants_seed.json "rules".
MIN_OCC_UNKNOWN = 2
INTERVAL_MIN = 25
INTERVAL_MAX = 35
AMOUNT_VARIANCE = 0.15
RENT_MIN = 200.0
FREQUENT_MIN = 2

_FINANCE_HINTS = ("paskol", "lizing", "kredit", "loan", "leasing", "financing")

_KEY_STOPWORDS = {
    "uab", "ab", "mb", "vsi", "vši", "iį", "as", "oy", "ltd", "inc", "llc",
    "payment", "purchase", "card", "pos", "pirkimas", "mokejimas", "mokėjimas",
    "sepa", "transfer", "pavedimas", "sąskaita", "saskaita", "ref", "no",
    "pvm", "sf",
}


def counterparty_name(t: dict):
    """Best-effort merchant/counterparty name across ASPSP shapes."""
    for key in ("creditor", "debtor", "ultimate_creditor", "ultimate_debtor"):
        party = t.get(key)
        if isinstance(party, dict) and party.get("name"):
            return party["name"]
    rti = t.get("remittance_information")
    if isinstance(rti, list) and rti:
        joined = " ".join(str(x) for x in rti if x).strip()
        if joined:
            return joined
    if isinstance(rti, str) and rti.strip():
        return rti
    for key in ("merchant", "creditor_agent", "additional_information"):
        party = t.get(key)
        if isinstance(party, dict) and party.get("name"):
            return party["name"]
        if isinstance(party, str) and party.strip():
            return party
    return None


def amount_value(t: dict):
    amt = t.get("transaction_amount") or t.get("amount")
    if isinstance(amt, dict):
        try:
            return abs(float(amt.get("amount")))
        except (TypeError, ValueError):
            return None
    try:
        return abs(float(amt))
    except (TypeError, ValueError):
        return None


def booking_date(t: dict):
    return t.get("booking_date") or t.get("value_date") or t.get("transaction_date")


def _merchant_key(name: str) -> str:
    low = name.lower()
    low = re.sub(r"\d+", " ", low)
    low = re.sub(r"[^a-z0-9ąčęėįšųūž]+", " ", low)
    tokens = [t for t in low.split() if len(t) > 1 and t not in _KEY_STOPWORDS]
    return " ".join(tokens[:4]).strip()


def _clean_name(raw: str) -> str:
    s = re.sub(r"\b\d{3,}\b", " ", raw)
    s = re.sub(r"\s{2,}", " ", s).strip(" -/,")
    return s or raw.strip()


def _classify_cadence(gap_days: float):
    if 6 <= gap_days <= 8:
        return "weekly", "weekly"
    if 12 <= gap_days <= 16:
        return "monthly", "biweekly"
    if INTERVAL_MIN <= gap_days <= INTERVAL_MAX:
        return "monthly", "monthly"
    if 85 <= gap_days <= 95:
        return "quarterly", "quarterly"
    if 350 <= gap_days <= 380:
        return "yearly", "yearly"
    return "monthly", f"~{round(gap_days)}d"


def _add_months(d: dt.date, months: int) -> dt.date:
    zero = d.month - 1 + months
    year = d.year + zero // 12
    month = zero % 12 + 1
    if month == 12:
        last_day = 31
    else:
        last_day = (dt.date(year, month + 1, 1) - dt.timedelta(days=1)).day
    return dt.date(year, month, min(d.day, last_day))


def _next_billing(last: dt.date, cycle: str, gap_days: float) -> dt.date:
    if cycle == "weekly":
        return last + dt.timedelta(days=7)
    if cycle == "quarterly":
        return _add_months(last, 3)
    if cycle == "yearly":
        return _add_months(last, 12)
    if cycle == "monthly":
        return _add_months(last, 1)
    return last + dt.timedelta(days=round(gap_days))


def _dates(items):
    ds = []
    for d, _, _ in items:
        if d:
            try:
                ds.append(dt.date.fromisoformat(d[:10]))
            except ValueError:
                pass
    ds.sort()
    return ds


def _avg_gap(dates):
    if len(dates) < 2:
        return None
    gaps = [(dates[i + 1] - dates[i]).days for i in range(len(dates) - 1)]
    return sum(gaps) / len(gaps) if gaps else None


def _amount_cluster(items):
    best = []
    for _, center, _ in items:
        lo, hi = center * (1 - AMOUNT_VARIANCE), center * (1 + AMOUNT_VARIANCE)
        grp = [it for it in items if lo <= it[1] <= hi]
        if len(grp) > len(best):
            best = grp
    return best or items


def _build_candidate(display, mtype, category, logo, items, dates, *, needs_review):
    amounts = [a for _, a, _ in items]
    avg = round(sum(amounts) / len(amounts), 2)
    gap = _avg_gap(dates)
    if gap is not None:
        cycle, label = _classify_cadence(gap)
    else:
        gap, cycle, label = 30.0, "monthly", "monthly"
    last = dates[-1] if dates else dt.date.today()
    return {
        "name": display,
        "type": mtype,                      # subscription | bill
        "cost": avg,
        "currency": "EUR",
        "billingCycle": cycle,
        "cadenceLabel": label,
        "category": category,
        "logoDomain": logo,
        "occurrences": len(items),
        "amountVaries": min(amounts) != max(amounts),
        "lastChargeDate": last.isoformat() if dates else None,
        "nextBillingDate": _next_billing(last, cycle, gap).isoformat(),
        "needsReview": needs_review,
    }


def _category_for_unknown(raw_name: str, avg: float) -> str:
    low = raw_name.lower()
    if any(k in low for k in _FINANCE_HINTS):
        return "finance"
    if avg > RENT_MIN:
        return "housing"
    return "other"


def detect_recurring(transactions: list, *, min_occurrences: int = MIN_OCC_UNKNOWN):
    """Return ``{"candidates": [...], "frequent": [...]}``.

    ``candidates`` are importable recurring payments (type subscription/bill);
    ``frequent`` are frequent-spending merchants (never recurring) surfaced for
    the feed only.
    """
    by_merchant = defaultdict(list)
    n_dbit = 0
    n_skipped = 0
    for t in transactions:
        if t.get("credit_debit_indicator") != "DBIT":
            continue
        n_dbit += 1
        name = counterparty_name(t)
        amount = amount_value(t)
        if not name or amount is None:
            n_skipped += 1
            continue
        mkey = _merchant_key(name)
        if not mkey:
            n_skipped += 1
            continue
        by_merchant[mkey].append((booking_date(t), amount, name))

    candidates = []
    frequent = []
    n_known = 0
    n_algo = 0
    for items in by_merchant.values():
        raw_name = items[0][2]
        dates = _dates(items)
        hit = merchant_db.match(raw_name)

        if hit is not None:
            display, mtype, category, logo = hit
            if mtype == "frequent":
                # Never recurring — surface as frequent spending only.
                if len(items) >= FREQUENT_MIN:
                    amounts = [a for _, a, _ in items]
                    frequent.append({
                        "name": display,
                        "category": category,
                        "logoDomain": logo,
                        "occurrences": len(items),
                        "totalSpent": round(sum(amounts), 2),
                    })
                continue
            # Known subscription / bill / possible → recurring on sight.
            typ = "bill" if mtype == "bill" else "subscription"
            needs = mtype == "possible"
            candidates.append(
                _build_candidate(display, typ, category, logo, items, dates,
                                 needs_review=needs)
            )
            n_known += 1
            continue

        # Unknown merchant — pattern algorithm.
        cluster = _amount_cluster(items)
        if len(cluster) < min_occurrences:
            continue
        cdates = _dates(cluster)
        gap = _avg_gap(cdates)
        if gap is None:
            continue
        _, label = _classify_cadence(gap)
        if label.startswith("~"):
            continue  # irregular — not convincingly recurring
        avg = round(sum(a for _, a, _ in cluster) / len(cluster), 2)
        category = _category_for_unknown(raw_name, avg)
        # Rent-like (large, housing) reads as a bill; otherwise a subscription.
        typ = "bill" if category in ("housing", "finance") else "subscription"
        candidates.append(
            _build_candidate(_clean_name(raw_name), typ, category, None, cluster,
                             cdates, needs_review=True)
        )
        n_algo += 1

    candidates.sort(key=lambda c: (-c["occurrences"], -c["cost"]))
    logging.info(
        "detect_recurring: dbit=%d skipped_no_name=%d merchants=%d "
        "known=%d algorithm=%d candidates=%d frequent=%d",
        n_dbit, n_skipped, len(by_merchant), n_known, n_algo,
        len(candidates), len(frequent),
    )
    return {"candidates": candidates, "frequent": frequent}
