"""Recurring-payment detection — ported from ``banksync.py`` ``step_recurring``.

Pure functions over Enable Banking transaction dicts, with no network or
Firebase dependency, so they can be unit-tested against the DEMO_TRANSACTIONS
fixture (see ``test_recurring.py``). Output maps 1:1 onto the app's
``Subscription`` model.
"""

import datetime as dt
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
    for key in ("creditor", "debtor"):
        party = t.get(key)
        if isinstance(party, dict) and party.get("name"):
            return party["name"]
    rti = t.get("remittance_information")
    if isinstance(rti, list) and rti:
        return rti[0]
    if isinstance(rti, str) and rti:
        return rti
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
    for t in transactions:
        if t.get("credit_debit_indicator") != "DBIT":
            continue  # only outgoing payments
        name = counterparty_name(t)
        amount = amount_value(t)
        if name is None or amount is None:
            continue
        key = (name.lower().strip(), round(amount, 0))
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
    return candidates
