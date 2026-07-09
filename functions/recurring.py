"""Recurring-payment detection — ported from ``banksync.py`` ``step_recurring``.

Pure functions over Enable Banking transaction dicts, with no network or
Firebase dependency, so they can be unit-tested against the DEMO_TRANSACTIONS
fixture (see ``test_recurring.py``). Output maps 1:1 onto the app's
``Subscription`` model.
"""

import datetime as dt
import logging
import re
from collections import defaultdict

# Minimal merchant enrichment so imported items look polished in the app.
# Each entry: name-substring -> (clean display name, category, logo domain).
_MERCHANT_HINTS = [
    ("spotify", ("Spotify", "Music", "spotify.com")),
    ("netflix", ("Netflix", "Streaming", "netflix.com")),
    ("youtube", ("YouTube Premium", "Streaming", "youtube.com")),
    ("disney", ("Disney+", "Streaming", "disneyplus.com")),
    ("hbo", ("HBO Max", "Streaming", "hbomax.com")),
    ("amazon", ("Amazon", "Streaming", "amazon.com")),
    ("icloud", ("iCloud+", "Cloud", "icloud.com")),
    ("dropbox", ("Dropbox", "Cloud", "dropbox.com")),
    ("google", ("Google", "Software", "google.com")),
    ("apple", ("Apple", "Software", "apple.com")),
    ("gym", ("Gym", "Fitness", None)),
]


def counterparty_name(t: dict):
    """Best-effort merchant/counterparty name across ASPSP shapes.

    Card payments frequently omit creditor/debtor and carry the merchant only
    in the remittance info or a proprietary field, so we widen the search well
    beyond the SEPA creditor name to avoid dropping those recurring payments.
    """
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
    # Card / proprietary fields some ASPSPs use for the merchant name.
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


def _classify_cadence(gap_days: float):
    """Map an average day-gap to a Vaultie ``BillingCycle`` + a human label.

    The app has no biweekly cycle, so ~14-day cadences are surfaced as monthly
    with a ``biweekly`` label the UI can show for transparency.
    """
    if 6 <= gap_days <= 8:
        return "weekly", "weekly"
    if 12 <= gap_days <= 16:
        return "monthly", "biweekly"
    if 26 <= gap_days <= 35:
        return "monthly", "monthly"
    if 85 <= gap_days <= 95:
        return "quarterly", "quarterly"
    if 350 <= gap_days <= 380:
        return "yearly", "yearly"
    return "monthly", f"~{round(gap_days)}d"


def _enrich(raw_name: str):
    low = raw_name.lower()
    for needle, hint in _MERCHANT_HINTS:
        if needle in low:
            return hint
    return raw_name.strip(), "Other", None


# Legal-form / payment-plumbing tokens that carry no merchant identity, dropped
# from the grouping key so "UAB X" and "X" collapse together.
_KEY_STOPWORDS = {
    "uab", "ab", "mb", "vsi", "vši", "iį", "as", "oy", "ltd", "inc", "llc",
    "payment", "purchase", "card", "pos", "pirkimas", "mokejimas", "mokėjimas",
    "sepa", "transfer", "pavedimas", "sąskaita", "saskaita", "ref", "no",
}


def _merchant_key(name: str) -> str:
    """Canonical merchant key that collapses per-transaction variants.

    Real bank statements append reference numbers, dates and card-auth codes to
    the counterparty name, so grouping on the exact string splits one merchant
    into many singletons. We lowercase, strip digits and punctuation, drop
    legal-form / plumbing stopwords, and keep the first few identifying words.
    """
    low = name.lower()
    low = re.sub(r"\d+", " ", low)  # reference numbers, dates, auth codes
    low = re.sub(r"[^a-z0-9ąčęėįšųūž]+", " ", low)
    tokens = [t for t in low.split() if len(t) > 1 and t not in _KEY_STOPWORDS]
    return " ".join(tokens[:4]).strip()


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


def detect_recurring(transactions: list, *, min_occurrences: int = 2) -> list:
    """Return recurring-payment candidates ready to map onto ``Subscription``.

    Groups outgoing (DBIT) payments by (counterparty, rounded amount); any group
    seen ``min_occurrences`` times or more is treated as recurring.
    """
    groups = defaultdict(list)
    n_dbit = 0
    n_skipped = 0
    for t in transactions:
        if t.get("credit_debit_indicator") != "DBIT":
            continue  # only outgoing payments
        n_dbit += 1
        name = counterparty_name(t)
        amount = amount_value(t)
        if name is None or amount is None:
            n_skipped += 1
            continue
        # Group on a normalised merchant key (collapses reference-number
        # variants) plus the rounded amount, keeping the raw name for display.
        mkey = _merchant_key(name)
        if not mkey:
            n_skipped += 1
            continue
        key = (mkey, round(amount, 0))
        groups[key].append((booking_date(t), amount, name))

    candidates = []
    for items in groups.values():
        if len(items) < min_occurrences:
            continue
        items.sort(key=lambda x: x[0] or "")
        amounts = [a for _, a, _ in items]
        avg = round(sum(amounts) / len(amounts), 2)
        raw_name = items[0][2]

        dates = []
        for d, _, _ in items:
            if d:
                try:
                    dates.append(dt.date.fromisoformat(d[:10]))
                except ValueError:
                    pass
        dates.sort()

        if len(dates) >= 2:
            gaps = [(dates[i + 1] - dates[i]).days for i in range(len(dates) - 1)]
            gap = sum(gaps) / len(gaps)
        else:
            gap = 30.0
        cycle, cadence_label = _classify_cadence(gap)
        last = dates[-1] if dates else dt.date.today()

        display, category, logo = _enrich(raw_name)
        candidates.append(
            {
                "name": display,
                "rawName": raw_name,
                "cost": avg,
                "currency": "EUR",
                "billingCycle": cycle,
                "cadenceLabel": cadence_label,
                "category": category,
                "logoDomain": logo,
                "occurrences": len(items),
                "amountVaries": min(amounts) != max(amounts),
                "lastChargeDate": last.isoformat(),
                "nextBillingDate": _next_billing(last, cycle, gap).isoformat(),
            }
        )

    # Most-frequent, then most-expensive first — best candidates on top.
    candidates.sort(key=lambda c: (-c["occurrences"], -c["cost"]))

    # Diagnostic funnel — counts only, no personal data — so we can see WHERE
    # payments drop out (fetched → outgoing → named → grouped → recurring).
    logging.info(
        "detect_recurring funnel: txns=%d dbit=%d skipped_no_name=%d "
        "groups=%d recurring=%d min_occ=%d",
        len(transactions),
        n_dbit,
        n_skipped,
        len(groups),
        len(candidates),
        min_occurrences,
    )
    return candidates
