"""Recurring-payment detection.

Two detection paths:

  1. Whitelist — known recurring merchants (streaming, SaaS, insurance,
     telecom, utilities, LT media…) are recurring on sight, even from a single
     charge.
  2. Algorithm — unknown merchants qualify when >=2 payments share a similar
     amount (+/-20%) at a regular cadence. A large regular payment (>200 EUR)
     is treated as rent/housing (may go to a person).

Never surfaces one-off spend (fast food, shops) or one-off person transfers.
Output maps onto the app's ``Subscription`` model; each candidate also carries
``needsReview`` so the UI can flag anything the algorithm (not the whitelist)
inferred. Raw transactions are never returned or stored.
"""

import datetime as dt
import logging
import re
from collections import defaultdict

# Known recurring merchants: (name substring, (display, category_key, logo)).
# category_key is an app ExpenseCategory key. Short terms (<=4 chars) match only
# as a whole word (see _term_match) to avoid false hits.
_WHITELIST = [
    # -- Streaming & media --
    ("netflix", ("Netflix", "entertainment", "netflix.com")),
    ("spotify", ("Spotify", "entertainment", "spotify.com")),
    ("youtube", ("YouTube", "entertainment", "youtube.com")),
    ("disney", ("Disney+", "entertainment", "disneyplus.com")),
    ("hbo", ("HBO Max", "entertainment", "hbomax.com")),
    ("tidal", ("Tidal", "entertainment", "tidal.com")),
    ("deezer", ("Deezer", "entertainment", "deezer.com")),
    ("icloud", ("iCloud+", "entertainment", "icloud.com")),
    ("itunes", ("Apple", "entertainment", "apple.com")),
    ("apple.com", ("Apple", "entertainment", "apple.com")),
    ("apple", ("Apple", "entertainment", "apple.com")),
    ("google", ("Google", "entertainment", "google.com")),
    ("amazon", ("Amazon", "entertainment", "amazon.com")),
    # -- Software / SaaS --
    ("adobe", ("Adobe", "entertainment", "adobe.com")),
    ("microsoft", ("Microsoft", "entertainment", "microsoft.com")),
    ("dropbox", ("Dropbox", "entertainment", "dropbox.com")),
    ("notion", ("Notion", "entertainment", "notion.so")),
    ("figma", ("Figma", "entertainment", "figma.com")),
    ("github", ("GitHub", "entertainment", "github.com")),
    ("openai", ("OpenAI", "entertainment", "openai.com")),
    ("chatgpt", ("OpenAI", "entertainment", "openai.com")),
    ("replit", ("Replit", "entertainment", "replit.com")),
    ("base44", ("Base44", "entertainment", None)),
    ("dribbble", ("Dribbble", "entertainment", "dribbble.com")),
    ("canva", ("Canva", "entertainment", "canva.com")),
    ("slack", ("Slack", "entertainment", "slack.com")),
    ("zoom", ("Zoom", "entertainment", "zoom.us")),
    ("linkedin", ("LinkedIn", "entertainment", "linkedin.com")),
    # -- Insurance --
    ("lietuvos draudimas", ("Lietuvos draudimas", "insurance", None)),
    ("seb draudimas", ("SEB draudimas", "insurance", None)),
    ("swed draudimas", ("Swedbank draudimas", "insurance", None)),
    ("gjensidige", ("Gjensidige", "insurance", None)),
    ("compensa", ("Compensa", "insurance", None)),
    ("seesam", ("Seesam", "insurance", None)),
    ("balcia", ("Balcia", "insurance", None)),
    ("ergo", ("ERGO", "insurance", None)),
    ("bta", ("BTA", "insurance", None)),
    ("draudimas", ("Draudimas", "insurance", None)),
    # -- Telecom / internet --
    ("telia", ("Telia", "connectivity", None)),
    ("tele2", ("Tele2", "connectivity", None)),
    ("pildyk", ("Pildyk", "connectivity", None)),
    ("cgates", ("Cgates", "connectivity", None)),
    ("bite", ("Bitė", "connectivity", None)),
    ("bitė", ("Bitė", "connectivity", None)),
    ("init", ("Init", "connectivity", None)),
    ("delta", ("Delta", "connectivity", None)),
    # -- Utilities --
    ("ignitis", ("Ignitis", "utilities", None)),
    ("vilniaus vandenys", ("Vilniaus vandenys", "utilities", None)),
    ("kauno vandenys", ("Kauno vandenys", "utilities", None)),
    ("energijos taupymo", ("Energijos taupymas", "utilities", None)),
    ("lesto", ("ESO", "utilities", None)),
    ("eso", ("ESO", "utilities", None)),
    # -- LT media / news --
    ("žinių radijas", ("Žinių radijas", "entertainment", None)),
    ("delfi", ("Delfi", "entertainment", "delfi.lt")),
    ("go3", ("Go3", "entertainment", "go3.lt")),
    ("tv3", ("TV3", "entertainment", "tv3.lt")),
    ("lnk", ("LNK", "entertainment", None)),
    ("ltv", ("LRT", "entertainment", None)),
    ("lrt", ("LRT", "entertainment", None)),
    # -- LT retail / delivery (user-listed known recurring) --
    ("barbora", ("Barbora", "other", "barbora.lt")),
    ("pigu", ("Pigu", "other", "pigu.lt")),
    # -- International misc --
    ("paypal", ("PayPal", "other", "paypal.com")),
    ("linkedin", ("LinkedIn", "entertainment", "linkedin.com")),
    ("meta", ("Meta", "entertainment", None)),
    ("twitter", ("X", "entertainment", "x.com")),
]

# One-off spend that must NEVER surface as recurring (fast food, shops).
_NEVER = [
    "hesburger", "mcdonald", "burger", "kebab", "pizza", "cafe", "café",
    "restoranas", "kavine", "kavinė", "užeiga", "uzeiga",
    "maxima", "rimi", "lidl", "iki", "norfa", "aibe", "kaufland",
    "senukai", "ikea", "lastmile",
]

# Loan / leasing keywords for the algorithm path → Finance.
_FINANCE_HINTS = ("paskol", "lizing", "kredit", "loan", "leasing", "financing")

_KEY_STOPWORDS = {
    "uab", "ab", "mb", "vsi", "vši", "iį", "as", "oy", "ltd", "inc", "llc",
    "payment", "purchase", "card", "pos", "pirkimas", "mokejimas", "mokėjimas",
    "sepa", "transfer", "pavedimas", "sąskaita", "saskaita", "ref", "no",
    "pvm", "sf",
}


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


def _term_match(low: str, term: str) -> bool:
    """Substring match, but whole-word for short (<=4) ambiguous terms."""
    if len(term) <= 4:
        return re.search(
            r"(^|[^a-z0-9ąčęėįšųūž])" + re.escape(term) +
            r"([^a-z0-9ąčęėįšųūž]|$)",
            low,
        ) is not None
    return term in low


def _whitelist_match(low: str):
    for term, hint in _WHITELIST:
        if _term_match(low, term):
            return hint
    return None


def _is_never_recurring(low: str) -> bool:
    return any(_term_match(low, t) for t in _NEVER)


def _merchant_key(name: str) -> str:
    """Canonical merchant key that collapses per-transaction variants."""
    low = name.lower()
    low = re.sub(r"\d+", " ", low)
    low = re.sub(r"[^a-z0-9ąčęėįšųūž]+", " ", low)
    tokens = [t for t in low.split() if len(t) > 1 and t not in _KEY_STOPWORDS]
    return " ".join(tokens[:4]).strip()


def _clean_name(raw: str) -> str:
    """Trim long reference numbers from a raw merchant name for display."""
    s = re.sub(r"\b\d{3,}\b", " ", raw)
    s = re.sub(r"\s{2,}", " ", s).strip(" -/,")
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
    """Largest subset of items whose amounts sit within +/-20% of a centre."""
    best = []
    for _, center, _ in items:
        lo, hi = center * 0.8, center * 1.2
        grp = [it for it in items if lo <= it[1] <= hi]
        if len(grp) > len(best):
            best = grp
    return best or items


def _build_candidate(display, category, logo, items, dates, *, needs_review):
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
    # A large regular payment (possibly to a person) is most likely rent.
    if avg > 200:
        return "housing"
    return "other"


def detect_recurring(transactions: list, *, min_occurrences: int = 2) -> list:
    """Return recurring-payment candidates via whitelist + pattern detection."""
    by_merchant = defaultdict(list)
    n_dbit = 0
    n_skipped = 0
    for t in transactions:
        if t.get("credit_debit_indicator") != "DBIT":
            continue  # only outgoing payments
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
    n_whitelist = 0
    n_algo = 0
    for items in by_merchant.values():
        raw_name = items[0][2]
        low = raw_name.lower()
        if _is_never_recurring(low):
            continue

        # Path 1 — known merchant: recurring on sight, even a single charge.
        wl = _whitelist_match(low)
        if wl is not None:
            display, category, logo = wl
            candidates.append(
                _build_candidate(display, category, logo, items, _dates(items),
                                 needs_review=False)
            )
            n_whitelist += 1
            continue

        # Path 2 — unknown merchant: needs a similar-amount cluster at a
        # recognised cadence (rent = large regular payment, possibly to a person).
        cluster = _amount_cluster(items)
        if len(cluster) < min_occurrences:
            continue
        cdates = _dates(cluster)
        gap = _avg_gap(cdates)
        if gap is None:
            continue
        _, label = _classify_cadence(gap)
        if label.startswith("~"):
            continue  # irregular interval — not convincingly recurring
        avg = round(sum(a for _, a, _ in cluster) / len(cluster), 2)
        category = _category_for_unknown(raw_name, avg)
        candidates.append(
            _build_candidate(_clean_name(raw_name), category, None, cluster,
                             cdates, needs_review=avg > 5)
        )
        n_algo += 1

    # Most-frequent, then most-expensive first — best candidates on top.
    candidates.sort(key=lambda c: (-c["occurrences"], -c["cost"]))
    logging.info(
        "detect_recurring: dbit=%d skipped_no_name=%d merchants=%d "
        "whitelist=%d algorithm=%d total=%d",
        n_dbit, n_skipped, len(by_merchant), n_whitelist, n_algo,
        len(candidates),
    )
    return candidates
