"""Recurring-payment detection (Vaultie 3.0).

The user picks what's recurring — so we return EVERY outgoing merchant grouped
(even seen once), tagged ``autoDetected`` when the Firestore merchant DB knows
it. Income (credit) and known frequent-spending merchants (groceries, fast
food, fuel…) are never returned as candidates; the latter go into a separate
``frequent`` list for context.

Merchant variants collapse via two mechanisms:
  * card-processor prefixes are stripped ("PAYPAL*APPMYWEB" → "APPMYWEB"),
  * known merchants group by their canonical DB name, so "DRIBBBLE*",
    "DRIBBBLE PRO STANDARD" and "DRIBBBLE" become one.

Raw transactions are never returned or stored.
"""

import datetime as dt
import logging
import re
from collections import defaultdict

import merchant_db

MIN_OCC_UNKNOWN = 2  # kept for signature compatibility; no longer gates output
RENT_MIN = 200.0
FREQUENT_MIN = 1

_FINANCE_HINTS = ("paskol", "lizing", "kredit", "loan", "leasing", "financing")

_KEY_STOPWORDS = {
    "uab", "ab", "mb", "vsi", "vši", "iį", "as", "oy", "ltd", "inc", "llc",
    "payment", "purchase", "card", "pos", "pirkimas", "mokejimas", "mokėjimas",
    "sepa", "transfer", "pavedimas", "sąskaita", "saskaita", "ref", "no",
    "pvm", "sf", "www", "com", "lt", "lv", "ee",
}

# Fold LT diacritics so "Artusgrupė" and "Artusgrupe" collapse to one key.
_FOLD = str.maketrans("ąčęėįšųūž", "aceeisuuz")


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


def _clean_merchant(name: str) -> str:
    """The real merchant behind a card-processor prefix.

    "PAYPAL*APPMYWEB", "SUMUP *Coffee", "IZ *Shop" → the part after the "*".
    """
    if "*" in name:
        after = name.split("*", 1)[1].strip()
        if len(after) >= 2:
            return after
    return name.strip()


def _merchant_key(name: str) -> str:
    """Canonical key for an UNKNOWN merchant: fold diacritics, drop digits and
    special characters, drop legal-form / plumbing stopwords."""
    low = name.lower().translate(_FOLD)
    low = re.sub(r"\d+", " ", low)
    low = re.sub(r"[^a-z0-9]+", " ", low)
    tokens = [t for t in low.split() if len(t) > 1 and t not in _KEY_STOPWORDS]
    return " ".join(tokens[:4]).strip()


def _clean_name(raw: str) -> str:
    """A tidy display name for an unknown merchant (trim long ref numbers)."""
    s = re.sub(r"\b\d{3,}\b", " ", raw)
    s = re.sub(r"\s{2,}", " ", s).strip(" -/,*")
    return s or raw.strip()


def _classify_cadence(gap_days: float):
    if 6 <= gap_days <= 8:
        return "weekly", "weekly"
    if 12 <= gap_days <= 16:
        return "monthly", "biweekly"
    if 25 <= gap_days <= 35:
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
    last_day = 31 if month == 12 else (
        dt.date(year, month + 1, 1) - dt.timedelta(days=1)).day
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


def _category_for_unknown(raw_name: str, avg: float) -> str:
    low = raw_name.lower()
    if any(k in low for k in _FINANCE_HINTS):
        return "finance"
    if avg > RENT_MIN:
        return "housing"
    return "other"


def _build_candidate(display, mtype, category, logo, items, dates, *,
                     needs_review, auto_detected):
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
        "autoDetected": auto_detected,      # known merchant vs user-review
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


def detect_recurring(transactions: list, *, min_occurrences: int = MIN_OCC_UNKNOWN):
    """Return ``{"candidates": [...], "frequent": [...], "debug": {...}}``.

    Every outgoing merchant becomes a candidate (even seen once), tagged
    ``autoDetected``. Frequent-spending merchants go to ``frequent`` only.
    """
    groups = defaultdict(list)
    group_hit = {}
    freq_amounts = defaultdict(list)
    freq_meta = {}
    n_dbit = 0
    n_skipped = 0
    for t in transactions:
        if t.get("credit_debit_indicator") != "DBIT":
            continue  # never surface income / incoming credits
        n_dbit += 1
        raw = counterparty_name(t)
        amount = amount_value(t)
        if not raw or amount is None:
            n_skipped += 1
            continue
        merchant = _clean_merchant(raw)
        hit = merchant_db.match(merchant)

        if hit is not None and hit[1] == "frequent":
            fk = hit[0].lower()
            freq_amounts[fk].append(amount)
            freq_meta[fk] = hit
            continue

        if hit is not None:
            key = "k:" + hit[0].lower()          # canonical → collapses variants
        else:
            mk = _merchant_key(merchant)
            if not mk:
                n_skipped += 1
                continue
            key = "u:" + mk
        groups[key].append((booking_date(t), amount, merchant))
        group_hit[key] = hit

    candidates = []
    for key, items in groups.items():
        hit = group_hit[key]
        dates = _dates(items)
        amounts = [a for _, a, _ in items]
        if hit is not None:
            display, mtype, category, logo = hit
            typ = "bill" if mtype == "bill" else "subscription"
            candidates.append(
                _build_candidate(display, typ, category, logo, items, dates,
                                 needs_review=(mtype == "possible"),
                                 auto_detected=True)
            )
        else:
            avg = round(sum(amounts) / len(amounts), 2)
            category = _category_for_unknown(items[0][2], avg)
            typ = "bill" if category in ("housing", "finance") else "subscription"
            candidates.append(
                _build_candidate(_clean_name(items[0][2]), typ, category, None,
                                 items, dates, needs_review=True,
                                 auto_detected=False)
            )

    frequent = [
        {
            "name": freq_meta[fk][0],
            "category": freq_meta[fk][2],
            "logoDomain": freq_meta[fk][3],
            "occurrences": len(amts),
            "totalSpent": round(sum(amts), 2),
        }
        for fk, amts in freq_amounts.items()
        if len(amts) >= FREQUENT_MIN
    ]

    # Auto-detected first, then by frequency and cost.
    candidates.sort(
        key=lambda c: (not c["autoDetected"], -c["occurrences"], -c["cost"]))

    n_auto = sum(1 for c in candidates if c["autoDetected"])
    logging.info(
        "detect_recurring: dbit=%d skipped=%d merchants=%d auto=%d manual=%d "
        "candidates=%d frequent=%d",
        n_dbit, n_skipped, len(groups), n_auto, len(candidates) - n_auto,
        len(candidates), len(frequent),
    )
    debug = {
        "txns": len(transactions),
        "dbit": n_dbit,
        "skippedNoName": n_skipped,
        "merchants": len(groups),
        "auto": n_auto,
        "manual": len(candidates) - n_auto,
        "candidates": len(candidates),
        "frequent": len(frequent),
        "groups": sorted(
            (
                {
                    "key": key,
                    "occ": len(items),
                    "min": round(min(a for _, a, _ in items), 2),
                    "max": round(max(a for _, a, _ in items), 2),
                    "auto": group_hit[key] is not None,
                }
                for key, items in groups.items()
            ),
            key=lambda g: -g["max"],
        )[:50],
    }
    return {"candidates": candidates, "frequent": frequent, "debug": debug}
