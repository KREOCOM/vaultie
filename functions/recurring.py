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

import canonical
import fx
import merchant_db
import resolver
from resolver import NEEDS_EXTERNAL, RESOLVED, UNKNOWN

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


# Bank transaction codes that mean "the user moved their own money" rather than
# "the user paid someone". Kept in step with dashboard.py's Pervedimai section:
# exchanges, top-ups and cash. Transfers proper are handled by the own-IBAN
# check, which is more precise where an IBAN exists.
_MOVEMENT_CODES = {"EXCHANGE", "TOPUP", "CWDL", "ATM", "CSHW"}


# Description-only currency exchange (Revolut stamps no EXCHANGE code, only text).
# Kept in sync with dashboard._EXCHANGE_HINT — a monthly NOK→EUR conversion must
# not cluster into a phantom "bill" in the subscriptions total.
_EXCHANGE_HINT = re.compile(
    r"exchanged?\s+to\b|currency\s+exchange|valiut\w*\s+keit|konvertav|"
    r"[a-z]{3}\s*(?:→|->)\s*[a-z]{3}", re.I)


def _is_money_movement(t: dict) -> bool:
    """True when this transaction is the user shifting their own money."""
    code = ((t.get("bank_transaction_code") or {}).get("code") or "").upper()
    if code in _MOVEMENT_CODES:
        return True
    text = " ".join([str(t.get("note") or "")]
                    + [str(x) for x in (t.get("remittance_information") or [])])
    return bool(_EXCHANGE_HINT.search(text))


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
    """Absolute transaction amount, normalized to EUR so multi-currency
    (multi-bank) streams aggregate correctly — a Revolut NOK charge and a SEB EUR
    charge must be comparable before we cluster or sum them."""
    amt = t.get("transaction_amount") or t.get("amount")
    if isinstance(amt, dict):
        try:
            v = abs(float(amt.get("amount")))
        except (TypeError, ValueError):
            return None
        return fx.to_eur(v, amt.get("currency"))
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


def _amount_bucket(amount: float, existing) -> float:
    """The key [amount] belongs under: an existing near-equal one, or itself.

    "Near" is 2% of the larger amount. The tolerance must stay RELATIVE: an
    absolute floor of 0.50 EUR looks harmless but is 17% of a 2.99 charge, and it
    swallowed a one-off 3.49 App Store purchase into the 2.99 subscription — a
    non-subscription amount presented as recurring. 2% covers the drift this
    exists for (a 399 loan booked as 398) and nothing else.

    Returns the FIRST matching existing key, so a run of drifting amounts
    collapses onto whichever was seen first rather than chaining arbitrarily far.
    """
    for k in existing:
        span = max(abs(k), abs(amount))
        if span > 0 and abs(k - amount) <= max(0.02, span * 0.02):
            return k
    return amount


def _classify_cadence(gap_days: float):
    """Map an average gap to (billing cycle, human label).

    Every branch here feeds the monthly-commitment total, so a cycle that is
    merely *close enough* is a wrong number on the user's screen. Two branches
    used to collapse into "monthly" and both understated or overstated badly:

      * a 14-day gap was labelled "biweekly" but billed as monthly — a 30 €
        fortnightly charge counted as 30 €/month instead of 65 €;
      * ANY unrecognised gap fell through to "monthly" — a 600 € insurance paid
        twice a year (~182 days) counted as 600 EVERY MONTH instead of 100.

    Both now carry their own cycle, and anything still unrecognised is returned
    as "custom" so the callers derive from the real gap instead of assuming.
    """
    if 6 <= gap_days <= 8:
        return "weekly", "weekly"
    if 12 <= gap_days <= 16:
        return "biweekly", "biweekly"
    if 25 <= gap_days <= 35:
        return "monthly", "monthly"
    if 85 <= gap_days <= 95:
        return "quarterly", "quarterly"
    if 170 <= gap_days <= 195:
        return "semiannual", "semiannual"
    if 350 <= gap_days <= 380:
        return "yearly", "yearly"
    return "custom", f"~{round(gap_days)}d"


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
    if cycle == "biweekly":
        return last + dt.timedelta(days=14)
    if cycle == "quarterly":
        return _add_months(last, 3)
    if cycle == "semiannual":
        return _add_months(last, 6)
    if cycle == "yearly":
        return _add_months(last, 12)
    if cycle == "monthly":
        return _add_months(last, 1)
    # "custom": use the gap we actually measured. This line already existed and
    # was already right — it was simply unreachable, because the classifier never
    # returned anything but a known cycle. A half-yearly charge was therefore
    # projected one month out, five months early.
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
    """The TYPICAL gap between charges — median, not mean, of consecutive
    day-differences.

    A mean is wrecked by a single missing observation: one payment that went
    through a not-yet-connected bank (or was genuinely paid late) doubles ONE
    gap, and that alone can drag a true ~30-day monthly cadence up to ~37
    days — just outside the classifier's 25-35-day "monthly" band below —
    misclassifying the whole stream as "custom" and multiplying its
    monthly-equivalent by the wrong ratio. Confirmed live 2026-08-04: a real
    ~399 EUR/mo MOGO payment, with one month's charge sitting on a
    not-yet-connected second bank, displayed as ~326 EUR.

    The median tolerates that same single outlier: with gaps [29, 29, 30,
    61], the mean is 37.25 (misclassified as "custom") but the median is 29.5
    (correctly "monthly") — a late or cross-bank payment has to make up
    close to HALF the observed gaps before it can throw this off, not just
    one. For a short history (2-3 gaps) the median and the mean are the same
    value, so nothing changes there.
    """
    if len(dates) < 2:
        return None
    gaps = sorted((dates[i + 1] - dates[i]).days for i in range(len(dates) - 1))
    if not gaps:
        return None
    n = len(gaps)
    mid = n // 2
    return float(gaps[mid]) if n % 2 else (gaps[mid - 1] + gaps[mid]) / 2


def _median(values):
    """Middle value of a sorted list — robust to one skewed outlier.

    Same rationale as `_avg_gap`, applied to amounts instead of dates. A plain
    mean of every charge in a stream is wrecked by one anomalous amount (an
    add-on fee bundled into a single month, or two genuinely distinct
    obligations sharing one generic payment-processor counterparty name that
    merchant-name grouping folded together): a real ~35 EUR/mo membership with
    one unrelated ~46 EUR charge mixed in averaged to a number the user never
    actually paid. The median resists that — over half the charges have to
    move together to shift it, not just one. For a tightly-clustered stream
    (the overwhelming case: same price every time) median and mean coincide,
    so nothing changes there.
    """
    s = sorted(values)
    n = len(s)
    mid = n // 2
    return s[mid] if n % 2 else (s[mid - 1] + s[mid]) / 2


# ── Payment-stream segmentation (between merchant grouping and feature
#    extraction). Same merchant identity != same payment stream: one merchant
#    (APPLE, Google, PayPal, telecom…) can carry several independent repeated
#    relationships. We segment a merchant group into streams using ONLY signals
#    already in our data — amounts and dates — so features run per stream. ──

_AMOUNT_RATIO = 6.0        # max/min within a compatible (variable-recurring) stream;
                           # multi-FIXED-stream contamination is caught by L3a
                           # (exact-amount, ratio-independent), so this only gates
                           # whether weakly-separated amounts stay one variable stream
_MIN_GAP, _MAX_GAP = 5, 400  # plausible cadence band (≈weekly … yearly)
_CV_MAX = 0.6              # interval-regularity ceiling for ≥3 dates
_DAY_ANCHOR_MAX = 3.5      # day-of-month stdev accepted as "anchored"


def _iso(d):
    try:
        return dt.date.fromisoformat(str(d)[:10]) if d else None
    except ValueError:
        return None


def _interval_cv(dates):
    if len(dates) < 3:
        return None
    gaps = [(dates[i + 1] - dates[i]).days for i in range(len(dates) - 1)]
    m = sum(gaps) / len(gaps)
    if m <= 0:
        return None
    var = sum((g - m) ** 2 for g in gaps) / len(gaps)
    return (var ** 0.5) / m


def _day_anchor_stdev(dates):
    if len(dates) < 2:
        return None
    days = [d.day for d in dates]
    m = sum(days) / len(days)
    return (sum((x - m) ** 2 for x in days) / len(days)) ** 0.5


def _regular(dates):
    """A cadence-regular sequence: ≥2 dates, median gap in the cadence band, and
    (for ≥3) low interval CV OR a stable day-of-month anchor."""
    if len(dates) < 2:
        return False
    gaps = sorted((dates[i + 1] - dates[i]).days for i in range(len(dates) - 1))
    med = gaps[len(gaps) // 2]
    if not (_MIN_GAP <= med <= _MAX_GAP):
        return False
    if len(dates) == 2:
        return True
    cv = _interval_cv(dates)
    anch = _day_anchor_stdev(dates)
    return (cv is not None and cv <= _CV_MAX) or \
           (anch is not None and anch <= _DAY_ANCHOR_MAX)


def _amounts_compatible(amounts):
    a = [x for x in amounts if x]
    if len(a) < 2:
        return True
    lo = min(a)
    return lo > 0 and (max(a) / lo) <= _AMOUNT_RATIO


def _stream_credible(dates, amounts):
    """Whether a set of transactions is a credible single (fixed OR variable)
    recurring stream. Near-fixed amounts are credible at any regular cadence;
    varying amounts are credible ONLY at monthly-or-longer cadence — this is what
    separates a real variable subscription (utility/rent, ~monthly, small drift)
    from burst usage (Base44/Replit-style: varying amounts, short intervals)."""
    if not _regular(dates):
        return False
    a = [x for x in amounts if x]
    if len(a) < 2 or not _amounts_compatible(a):
        return False
    ratio = max(a) / min(a) if min(a) > 0 else 1e9
    if ratio <= 1.5:
        return True                       # near-fixed: any regular cadence
    gaps = sorted((dates[i + 1] - dates[i]).days for i in range(len(dates) - 1))
    return gaps[len(gaps) // 2] >= 20      # varying: monthly-or-longer only


def segment_streams(items, key):
    """Segment one merchant group's items into payment streams.

    ``items`` = list of ``(date, amount, merchant)``. Returns
    ``[(stream_items, reason, stream_id)]``. Deterministic and explainable:

      L3a  extract fixed-amount recurring sub-streams (same amount, ≥2, regular)
           — ratio-independent, so interleaved monthly streams are separated.
      then if none were found, test whole-group cohesion as ONE credible stream
           (keeps single fixed/variable subscriptions intact);
      else emit the fixed streams and split the residual into a variable stream
           (only with ≥3 credible points) or independent one-offs.
    """
    if len(items) <= 1:
        return [(items, "single", f"{key}#0")]
    dated = [(_iso(d), a) for d, a, _ in items]

    # L3a — fixed-amount recurring sub-streams, bucketed by NEAR-equal amount.
    #
    # Bucketing on the exact cent split one obligation in two whenever the amount
    # drifted: a MOGO loan booked as 399.00 and 398.00 in alternating months
    # became two interleaved streams, and because each only saw every OTHER
    # payment, each measured twice the real gap and was priced at half — 399/mo
    # was reported as 199/mo. The same split produced a phantom second MOGO row
    # from another bank at 163/mo. Amounts within ~2% (floor 0.50 EUR) are the
    # same charge; anything further apart stays separate, which is what keeps
    # iCloud at 2.99 from being merged with Apple One at 19.95.
    by_amt = defaultdict(list)
    for i, (d, a) in enumerate(dated):
        if a is not None:
            by_amt[_amount_bucket(round(a, 2), by_amt.keys())].append(i)
    fixed = []
    used = [False] * len(items)
    for amt, idxs in sorted(by_amt.items()):
        ds = sorted(d for d in (dated[i][0] for i in idxs) if d)
        if len(idxs) >= 2 and _regular(ds):
            fixed.append((amt, idxs))
            for i in idxs:
                used[i] = True
    residual = [i for i in range(len(items)) if not used[i]]

    streams = []
    sid = 0
    if not fixed:
        # No repeated fixed amount: is the WHOLE group one credible stream?
        if _stream_credible(_dates(items), [a for _, a, _ in items if a is not None]):
            return [(items, "cohesive-single-stream", f"{key}#0")]
        for i in residual:                # else: independent one-offs
            streams.append(([items[i]], "one-off/irregular", f"{key}#{sid}"))
            sid += 1
        return streams

    for amt, idxs in fixed:
        streams.append(([items[i] for i in idxs],
                        "fixed-amount %.2f" % amt, f"{key}#{sid}"))
        sid += 1
    res_ds = sorted(d for d in (dated[i][0] for i in residual) if d)
    res_amts = [items[i][1] for i in residual if items[i][1] is not None]
    # Residual becomes a variable stream only with ≥3 credible points; otherwise
    # each leftover is an independent one-off (never auto-recurring).
    if len(residual) >= 3 and _stream_credible(res_ds, res_amts):
        streams.append(([items[i] for i in residual],
                        "variable-recurring", f"{key}#{sid}"))
    else:
        for i in residual:
            streams.append(([items[i]], "one-off/irregular", f"{key}#{sid}"))
            sid += 1
    return streams


def _stream_diag(st_items, dates, reason, sid, key):
    """Explainable diagnostics for one payment stream."""
    amts = [a for _, a, _ in st_items if a is not None]
    gaps = [(dates[i + 1] - dates[i]).days for i in range(len(dates) - 1)]
    return {
        "streamId": sid,
        "streamReason": reason,
        "hardPartitionKey": key,
        "count": len(st_items),
        "dates": [d.isoformat() for d in dates],
        "amounts": amts,
        "intervals": gaps,
        "medianInterval": (sorted(gaps)[len(gaps) // 2] if gaps else None),
        "intervalCV": (round(_interval_cv(dates), 3) if _interval_cv(dates) is not None else None),
        "amountRatio": (round(max(amts) / min(amts), 2) if amts and min(amts) > 0 else None),
        "dayAnchorStdev": (round(_day_anchor_stdev(dates), 2) if _day_anchor_stdev(dates) is not None else None),
    }


# One-off / physical merchants (travel, fuel, lodging, salons, restaurants):
# never recurring, so kept OUT of the "Other merchants" list even once-seen.
_ONEOFF_HINTS = (
    "hotel", "hostel", "apartment", "booking", "airbnb", "ferry", "airport",
    "travel", "kelion", "viesbut", "viešbut", "degalin", "kuro", "orlen",
    "uno-x", "unox", "circle k", "circlek", "neste", "emsi", "fuel",
    "salon", "grozio", "grožio", "kirpykl", "beauty", "spa ",
    "restoran", "kavin", "bistro", "baras", "cafe", "coffee",
    "parking", "taxi",
)

# A single unknown charge is only worth showing if it looks like a digital
# service (a newly-started subscription), not a physical / one-off purchase.
_SERVICE_HINTS = (
    ".com", ".net", ".io", ".app", ".co", ".eu", "www", "subscription",
    "premium", "membership", "cloud", "hosting", "vpn", "media", "digital",
    "online", "saas", "unlimited",
)

# Categories that are everyday, variable spending — NOT recurring commitments.
# A merchant in one of these, seen only once, is treated as spending (it goes to
# the ``frequent`` list) even if the DB/AI mislabelled it a subscription. This is
# what stops a one-off fuel/ferry/shop charge from inflating the monthly total.
_SPENDING_CATEGORIES = {
    "groceries", "supermarket", "food", "dining", "restaurant", "restaurants",
    "cafe", "coffee", "fastfood", "takeaway", "delivery",
    "fuel", "gas", "petrol", "automotive", "auto", "car",
    "travel", "hotel", "hotels", "lodging", "accommodation", "airline",
    "flights", "ferry",
    "shopping", "retail", "clothing", "apparel", "electronics", "furniture",
    "convenience", "alcohol", "liquor", "tobacco", "pharmacy",
    # Missing entirely until a one-off bus ticket (mcc.py MCC 4131 -> "transport",
    # paid via Vipps) got auto-added as a "confirmed" monthly subscription at a
    # single occurrence: a known merchant hit with occ<2 only diverts to the
    # one-off "spending" bucket when its category is in this set, and no
    # transport-family category was ever in it.
    "transport", "taxi", "parking", "transit",
}


def _include_unknown(name: str, items) -> bool:
    """Whether an unknown merchant is worth showing in "Other merchants"."""
    low = name.lower()
    if any(h in low for h in _ONEOFF_HINTS):
        return False              # travel / fuel / lodging / salon / dining
    if len(items) >= 2:
        return True               # repeated → plausibly recurring
    # Single charge: drop large one-offs; keep only service-looking small ones.
    if max(a for _, a, _ in items) >= 50:
        return False
    return any(h in low for h in _SERVICE_HINTS)


def _category_for_unknown(raw_name: str, avg: float) -> str:
    low = raw_name.lower()
    if any(k in low for k in _FINANCE_HINTS):
        return "finance"
    if avg > RENT_MIN:
        return "housing"
    return "other"


# First char uppercase (incl. LT), then >=2 lowercase — a single capitalised NAME
# token like "Sulajeva" / "Petrauskas". An ALL-CAPS brand ("NETFLIX") or a dotted
# domain ("apple.com") deliberately does NOT match.
_PERSON_TOKEN_RE = re.compile(r"^[A-ZŠŽĖČĄĮŲŪ][a-zšžėčąįųū\-]{2,}$")


def _bare_person_like(canon_g: dict, name: str) -> bool:
    """A bare single-token surname on a transfer with NO card-acceptor / web-domain
    evidence — i.e. a P2P to a private individual whose descriptor is just their
    name. ``_looks_like_person`` misses this because it demands two tokens; a bare
    surname on a CARD purchase is still excluded here by the acceptor/domain guard,
    so a one-word merchant stays a merchant. Heuristic (a bare capitalised brand
    paid by SEPA and unknown to the DB could slip through), but in this domain P2P
    transfers dominate the single-token-no-acceptor case, and known brands are DB
    hits that never reach here."""
    rmt = canon_g.get("remittance") or {}
    if rmt.get("acceptor") or rmt.get("domain"):
        return False
    toks = [x for x in re.split(r"\s+", (name or "").strip()) if x]
    return len(toks) == 1 and bool(_PERSON_TOKEN_RE.match(toks[0]))


# Distinctive Lithuanian SURNAME endings (ASCII, matched after _FOLD). Unlike the
# bare -a/-ė that Maxima, Norfa, Litena, Camelia also end in, these are almost never
# brand names, so a 2–4 token counterparty carrying one is a natural person, not a
# merchant. Validated on real names + brands in test_lt_person.py (13/13 people
# caught, 0 brands mistaken). Folding means ALLCAPS / diacritic-stripped bank forms
# ("GABRIELE MAZEIKAITE", "Rasa Konciute") still match.
_LT_SURNAME_END = ("iene", "aite", "yte", "iute", "ute", "ske", "evicius",
                   "avicius", "icius", "auskas", "iauskas", "inskas", "ynas",
                   "unas", "evas", "ovas", "eva", "ova", "auske", "inske",
                   "aitis", "utis")
_LT_PERSON_LEGAL = {"uab", "ab", "mb", "vsi", "ii", "kub", "tub", "zub", "vi",
                    "si", "llc", "pay", "ltd", "oy", "ou"}

# Payment processors / aggregators — when one of these is the counterparty, its
# name must NOT be shown as the merchant (the real merchant is the domain).
_PROC_TOKENS = ("opay", "paysera", "montonio", "maksekeskus", "makecommerce",
                "neopay", "kevin", "sumup", "stripe", "adyen", "paypal", "klarna")


def _lt_person(name: str) -> bool:
    """A Lithuanian personal name (first name + surname) by its DISTINCTIVE surname
    ending: 2–4 tokens, no legal form, no digits, at least one token ending in a
    surname suffix after folding diacritics. Pure name-shape — the caller still
    gates on transfer context (no card acceptor/domain), so a card merchant that
    happens to match can never be mistaken for a person."""
    toks = [t for t in re.split(r"[\s.*/\\]+", (name or "").strip()) if t]
    if not (2 <= len(toks) <= 4):
        return False
    folded = [t.lower().translate(_FOLD) for t in toks]
    if any(t in _LT_PERSON_LEGAL for t in folded):
        return False
    if any(any(c.isdigit() for c in t) for t in toks):
        return False
    return any(t.endswith(_LT_SURNAME_END) for t in folded)


def _name_tokens(name: str) -> frozenset:
    """Folded (lowercased, diacritics stripped) token set of a name — used to
    match a transfer counterparty against the user's own account-holder names."""
    toks = [t for t in re.split(r"[\s.*/\\]+", (name or "").strip()) if t]
    return frozenset(t.lower().translate(_FOLD) for t in toks)


# Business words that a bare (no legal form) company name carries but a person's
# name never does. A two-word counterparty that looks person-shaped BUT contains
# one of these is a business, not a person, so it stays a bill/subscription — this
# is what keeps "Artus Grupė", "Teva Baltics", "Verslo Vartai", "Vilniaus Vandenys"
# out of the person→transfer rule while foreign personal names (John Smith) go
# through it. ASCII-folded (matched after _FOLD), so diacritics/caps don't matter.
_BUSINESS_TOKENS = frozenset({
    "grupe", "group", "baltic", "baltics", "baltija", "baltijos", "vartai",
    "sprendimai", "sistema", "sistemos", "system", "systems", "servisas",
    "serviso", "service", "services", "prekyba", "prekybos", "trade", "trading",
    "statyba", "statybos", "build", "construction", "transportas", "transport",
    "logistika", "logistics", "studija", "studio", "studios", "klinika", "clinic",
    "clinics", "medicina", "vandenys", "vanduo", "energija", "energy",
    "energetika", "bankas", "bank", "draudimas", "insurance", "investicijos",
    "invest", "capital", "holding", "holdings", "solutions", "solution", "media",
    "telecom", "telekomas", "consulting", "consult", "partners", "partneriai",
    "technologijos", "technologies", "tech", "software", "digital", "parduotuve",
    "shop", "store", "market", "marketas", "express", "cargo", "auto", "motors",
    "gamyba", "factory", "fabrikas", "pramone", "turtas", "realty", "estate",
    "properties", "finance", "finansai", "credit", "kreditas", "leasing",
    "lizingas", "grozis", "sportas", "fitness", "klubas", "centras", "center",
})


def _has_business_token(name: str) -> bool:
    """True when a name carries a company word (see [_BUSINESS_TOKENS])."""
    return bool(_name_tokens(name) & _BUSINESS_TOKENS)


def _looks_person_shaped(name: str) -> bool:
    """A generic personal-name SHAPE — 2–4 alphabetic tokens, no legal form, no
    digits (foreign names included). Mirrors entity._looks_like_person, but is
    evaluated here against the RAW remittance name too: when a bank fills only the
    remittance (no structured creditor.name), canonical's party_kind_hint is empty,
    so a foreign 'John Smith' otherwise slipped through as a housing bill."""
    toks = [t for t in re.split(r"[\s.*/\\]+", (name or "").strip()) if t]
    if not (2 <= len(toks) <= 4):
        return False
    folded = [t.lower().translate(_FOLD) for t in toks]
    if any(t in _LT_PERSON_LEGAL for t in folded):
        return False
    if any(any(c.isdigit() for c in t) for t in toks):
        return False
    return all(re.match(r"^[A-Za-zĄČĘĖĮŠŲŪŽąčęėįšųūž.'\-]+$", t) for t in toks)


# ── Recurring stream LIFECYCLE (Plaid/Tink-style) ───────────────────────────
# A historical recurring pattern is NOT an active future commitment forever. A
# finished tax plan / paid-off loan / cancelled subscription keeps its history
# but must drop out of the monthly & annual projection once the expected charges
# stop arriving. Tolerances scale with each stream's OWN cadence, so a yearly
# bill isn't declared dead after two months.
_CYCLE_DAYS = {"weekly": 7, "biweekly": 14, "monthly": 30, "quarterly": 91,
               "semiannual": 182, "yearly": 365}
# per-charge cost → monthly-equivalent, so the projection is a true monthly sum
# regardless of billing frequency (a €600 yearly bill counts as €50/mo, not €600).
_CYCLE_PER_MONTH = {"weekly": 4.345, "biweekly": 2.174, "monthly": 1.0,
                    "quarterly": 1 / 3.0, "semiannual": 1 / 6.0,
                    "yearly": 1 / 12.0}

_DAYS_PER_MONTH = 365.25 / 12  # 30.44


def _per_month(cycle: str, gap_days) -> float:
    """How many times a month this stream charges.

    Falls back to the measured gap rather than to 1.0. `.get(cycle, 1.0)` meant
    every unrecognised cadence was quietly priced as monthly, which is where the
    600 €-a-month "insurance" came from.
    """
    known = _CYCLE_PER_MONTH.get(cycle)
    if known is not None:
        return known
    if gap_days and gap_days > 0:
        return _DAYS_PER_MONTH / gap_days
    return 1.0


def _lifecycle(last: dt.date, cycle: str, occ: int, today: dt.date,
               gap_days=None):
    """Return ``(status, days_since_last)`` for a recurring stream.

      early  — <2 sightings: detected but unproven (Plaid EARLY_DETECTION).
      active — last charge within ~2 cycles: at most the current expected
               charge is pending/late. ONLY active streams feed the projection.
      late   — 2–3.5 cycles since last: one clearly-missed cycle (ending?).
      ended  — >3.5 cycles: the stream has stopped (Plaid TOMBSTONED).

    Uncertain by nature (a paused sub may resume), so nothing is deleted — the
    status just steers whether it counts as a future commitment; the user can
    always override it.
    """
    # Tolerances scale with the stream's OWN cadence. A "custom" cadence has no
    # entry here, and defaulting it to 30 days declared every long-cycle stream
    # dead within a couple of months — so a half-yearly bill dropped out of the
    # projection and simply stopped being counted.
    cd = _CYCLE_DAYS.get(cycle) or (round(gap_days) if gap_days else 30)
    days = (today - last).days
    if occ < 2:
        return "early", days
    if days <= cd * 2.0:
        return "active", days
    if days <= cd * 3.5:
        return "late", days
    return "ended", days


def _build_candidate(display, mtype, category, logo, items, dates, *,
                     needs_review, auto_detected, confident, today=None):
    today = today or dt.date.today()
    amounts = [a for _, a, _ in items]
    typical = round(_median(amounts), 2)
    occ = len(items)
    gap = _avg_gap(dates)
    if gap is not None:
        cycle, label = _classify_cadence(gap)
    else:
        # Seen once → don't fake a "monthly" cadence (that is exactly what
        # inflated the totals). Mark it a single sighting for the user to
        # confirm; billing math still needs a cycle, so keep monthly internally.
        gap, cycle, label = 30.0, "monthly", "once"
    last = dates[-1] if dates else today
    status, days_since = _lifecycle(last, cycle, occ, today, gap)
    # Monthly-equivalent of this stream's typical charge (the projection unit).
    monthly = round(typical * _per_month(cycle, gap), 2)
    # TWO charges are ONE interval, and one interval is not a cadence. When that
    # lone interval also matches no known cycle, "custom" prices the stream off
    # the measured gap: two MOGO payments of 399 EUR, 74 days apart, became a
    # confident "163 EUR/mo" — an amount the user has never paid, silently added
    # to the monthly commitment, and sitting next to the SAME loan detected from
    # another bank. The monthly-equivalent arithmetic is right; the confidence is
    # not. Ask instead of assuming: flag it for review so the user is asked,
    # rather than it appearing as a settled commitment.
    #
    # ONLY the review flag. It stays counted while it waits, which is this
    # codebase's existing rule for everything uncertain ("possible" merchants are
    # counted and flagged too). Clearing `confident` instead looks tempting and is
    # wrong twice over: dashboard.py:860 uses `confident` to decide what enters
    # the recurring list at all, so it would DELETE the stream rather than
    # question it — and a two-charge Apple bill 36 days apart lands in this same
    # branch, because the monthly window stops at 35 days.
    #
    # A recognised cycle seen twice (a yearly bill, ~365 days apart) is NOT
    # affected — that gap identifies itself, it isn't inferred from one sample.
    if occ < 3 and cycle == "custom":
        needs_review = True
    return {
        "name": display,
        "type": mtype,                      # subscription | bill | transfer
        "autoDetected": auto_detected,      # known merchant vs user-review
        "confident": confident,             # ≥2 sightings → a real pattern
        "cost": typical,                     # typical per-charge amount (median)
        "monthlyAmount": monthly,           # per-charge normalized to a month
        "currency": "EUR",
        "billingCycle": cycle,
        "cadenceLabel": label,
        "status": status,                   # early | active | late | ended
        "active": status == "active",       # only these feed the projection
        "daysSinceLast": days_since,
        "category": category,
        "logoDomain": logo,
        "occurrences": occ,
        "amountVaries": min(amounts) != max(amounts),
        "lastChargeDate": last.isoformat() if dates else None,
        "nextBillingDate": _next_billing(last, cycle, gap).isoformat(),
        "needsReview": needs_review,
    }


def detect_recurring(transactions: list, *, min_occurrences: int = MIN_OCC_UNKNOWN,
                     classify_unknown=None, corpus=None, today=None,
                     own_ibans=None, own_names=None):
    """Return ``{"candidates": [...], "frequent": [...], "debug": {...}}``.

    Every outgoing merchant becomes a candidate (even seen once), tagged
    ``autoDetected``. Frequent-spending merchants go to ``frequent`` only.

    ``classify_unknown`` (optional) is a pluggable, privacy-neutral hook —
    a callable ``(name, amount) -> hit-tuple | None`` in the same 4-tuple shape
    ``merchant_db.match`` returns — for classifying merchants the DB doesn't
    know. A hit is treated exactly like a DB hit; ``one_time`` answers are
    hidden. When it is absent (the production default) or returns ``None`` we
    fall back to the keyword heuristic below. Production passes no classifier, so
    detection stays fully on-server with no third-party data flow; the hook
    exists only so tests can inject a local stub.
    """
    today = today or dt.date.today()
    # The user's OWN account IBANs (multi-bank). A recurring transfer between the
    # user's own accounts (e.g. a monthly SEB→Revolut top-up) is NOT a bill and
    # must never become a recurring commitment.
    own = {str(i).replace(" ", "").upper() for i in (own_ibans or []) if i}
    # The user's OWN account-holder names. Many banks — SEB especially — put only
    # a NAME on a transfer between the user's own accounts, with NO counterparty
    # IBAN, so the IBAN check below can't catch "me moving money to myself". That
    # left a €350 SEB→SEB self-transfer to "Osvaldas Sulajevas" surfacing as a
    # monthly bill. Matching the holder name closes it: a DBIT whose counterparty
    # IS one of the user's own account names is an own transfer, never a bill or
    # subscription — you do not subscribe to yourself. Only names with 2+ tokens
    # are used, so a generic product label ("Sąskaita") can never match anything.
    own_name_toks = [ts for ts in (_name_tokens(n) for n in (own_names or []))
                     if len(ts) >= 2]
    groups = defaultdict(list)
    group_hit = {}
    group_canon = {}
    freq_amounts = defaultdict(list)
    freq_meta = {}
    n_dbit = 0
    n_skipped = 0
    n_ai_hidden = 0
    n_unknown = 0
    n_needs_external = 0
    id_src = defaultdict(int)          # identity-source coverage (canonical Stage 1)
    # Build the per-creditor corpus once so the resolver's processor detection
    # (N distinct merchants behind one creditor) works across the whole batch.
    # A caller with the SAME transaction set may pass a prebuilt corpus to avoid
    # rebuilding it (e.g. build_dashboard → _subs); identical input → identical
    # corpus, so no behaviour change.
    if corpus is None:
        dbit_txns = [t for t in transactions
                     if t.get("credit_debit_indicator") == "DBIT"]
        corpus = resolver.build_corpus(dbit_txns)
    for t in transactions:
        if t.get("credit_debit_indicator") != "DBIT":
            continue  # never surface income / incoming credits
        n_dbit += 1
        raw = counterparty_name(t)
        amount = amount_value(t)
        if not raw or amount is None:
            n_skipped += 1
            continue
        # Stage 1 — stable counterparty identity from structured fields.
        canon = canonical.build_canonical(t)
        # Money movement is never a subscription, whatever its rhythm.
        #
        # A currency exchange, a top-up or a cash withdrawal is the user moving
        # their own money. Someone who converts to EUR whenever they need it
        # produces a run of similar amounts, which is exactly what the detector
        # is built to notice — so "Exchanged to EUR, 860 €" was being presented
        # as a monthly bill. The IBAN check below only catches transfers between
        # known accounts; an in-app exchange has no counterparty IBAN at all,
        # so it sailed straight through. Same vocabulary dashboard.py files
        # under "Pervedimai".
        if _is_money_movement(t):
            n_skipped += 1
            continue
        # Own-account transfer (SEB↔Revolut etc.): never a recurring bill.
        if own:
            cpi = (canon.get("counterparty") or {}).get("iban")
            if cpi and str(cpi).replace(" ", "").upper() in own:
                n_skipped += 1
                continue
        # Same, by holder NAME — for banks that send a self-transfer with a name
        # but no counterparty IBAN (the IBAN check above can't see it).
        if own_name_toks:
            cp_toks = _name_tokens(raw)
            if len(cp_toks) >= 2 and any(
                    cp_toks <= o or o <= cp_toks for o in own_name_toks):
                n_skipped += 1
                continue
        id_src[canon["identity_source"]] += 1
        # Stage 2 — optional brand/merchant enrichment (KB string resolver). Used
        # for display/category/routing only; identity does NOT depend on it.
        merchant, hit, res = resolver.resolve_hit(t, corpus, classify_unknown)
        if hit is None:
            if res["status"] == NEEDS_EXTERNAL:
                n_needs_external += 1
            else:
                n_unknown += 1

        # NOTE: we do NOT skip "person-like" counterparties here. _looks_like_person
        # is a weak heuristic that also flags 2-word BUSINESS names (e.g. "Artus
        # Grupe", "Verslo Vartai") — skipping them dropped real recurring bills
        # like rent. People are instead kept as candidates; a genuine one-off P2P
        # transfer is demoted to "transfer" below (excluded from the total), while
        # a CONFIDENT regular payment stays a bill/commitment. The user is the
        # final authority via the recurring manager (toggle off what isn't real).

        # A "frequent-spending" match only makes sense for small everyday amounts
        # (groceries, coffee). A LARGE payment that fuzzy-matched a frequent brand
        # on a shared token — e.g. rent "Artus Grupė MB" wrongly hitting a
        # supermarket "Artus" — is a BILL, not everyday spending. Drop the bogus
        # frequent match so it flows into recurring with its real name instead of
        # silently vanishing.
        if hit is not None and hit[1] == "frequent" and (amount or 0) >= 150:
            hit = None
            n_unknown += 1

        if hit is not None and hit[1] == "frequent":
            fk = hit[0].lower()
            freq_amounts[fk].append(amount)
            freq_meta[fk] = hit
            continue
        if hit is not None and hit[1] == "one_time":
            n_ai_hidden += 1                 # AI: one-off purchase → never shown
            continue

        # Group by the STRONGEST stable identity. A structured counterparty IBAN /
        # scheme id keys the group directly (brand-independent) so a repeated
        # payment to an unknown merchant still clusters — cold start, unseen
        # country. Otherwise fall back to the KB brand canonical (collapses card
        # acceptor variants) and then to the normalized name (LAST RESORT).
        _idkey = canon.get("identity_key") or ""
        if canon["identity_source"] in (canonical.S_IBAN, canonical.S_SCHEME) \
                or _idkey.startswith("dom:"):
            # Structured IBAN/scheme, OR a web-domain identity (dom:gymplius.lt) —
            # the domain groups every processor/name variant of one merchant into
            # a single stream, ahead of the KB name (which varies: Gym+/GymPlius).
            key = _idkey
        elif hit is not None:
            key = "k:" + hit[0].lower()          # canonical brand → collapses variants
        else:
            mk = _merchant_key(merchant)
            if not mk:
                n_skipped += 1
                continue
            key = "u:" + mk
        groups[key].append((booking_date(t), amount, merchant))
        group_hit[key] = hit
        group_canon.setdefault(key, canon)

    candidates = []
    counters = {"filtered": 0, "spending": 0, "streams": 0}
    _RECUR = ("fixed-amount", "variable-recurring", "cohesive-single-stream")

    def _emit(st_items, st_reason, st_id, key, hit, canon_g, src, conf, stable,
              force_unconfident=False):
        """Build + append one candidate for a payment stream. Returns None or a
        routing tag ('spending'/'filtered'). ``force_unconfident`` marks a merged
        non-recurring residual so it can never present as recurring."""
        dates = _dates(st_items)
        amounts = [a for _, a, _ in st_items]
        occ = len(st_items)
        confident = (occ >= 2) and not force_unconfident
        if hit is not None:
            display, mtype, category, logo = hit
            cat_low = (category or "").lower()
            if occ < 2 and not stable and cat_low in _SPENDING_CATEGORIES:
                fk = display.lower()
                freq_amounts[fk] = list(amounts)
                freq_meta[fk] = hit
                return "spending"
            typ = "bill" if mtype == "bill" else "subscription"
            cand = _build_candidate(
                display, typ, category, logo, st_items, dates,
                needs_review=(mtype == "possible" or not confident),
                auto_detected=True, confident=confident, today=today)
        else:
            cp_name = (canon_g.get("counterparty") or {}).get("name")
            raw_name = st_items[0][2]
            if not stable and not _include_unknown(raw_name, st_items):
                return "filtered"
            avg = round(sum(amounts) / len(amounts), 2)
            category = _category_for_unknown(raw_name, avg)

            # EVERYDAY-SPENDING GUARD. An unrecognised card counterparty (no DB hit,
            # no IBAN/scheme id) in the generic "other" category, whose stream is
            # NOT a credible recurring pattern (amounts vary and/or the cadence is
            # irregular) and whose name is not a digital service, is spending at a
            # local shop/café we simply don't know — "Skani mėsa" (a butcher stall),
            # "Tiltų" (a bar). By SHAPE it is indistinguishable from a subscription
            # except that a subscription bills a near-constant amount on a regular
            # monthly+ cadence; without that evidence it belongs in `frequent`, not
            # the subscription list. Bank-agnostic: keyed on the stream, never a name.
            #
            # ALSO route a WEEKLY-cadence unknown to spending, even when the amounts
            # are near-constant: a subscription bills monthly-or-longer, so a regular
            # sub-monthly charge at an unrecognised merchant is a shop/café visited
            # weekly (groceries, coffee), not a subscription — "Uab Litena Parduotuvė"
            # (two shop payments a week apart read as a weekly €462/mo sub). The user
            # confirms the residual few; the point is not to DEFAULT them to a sub.
            _gaps = sorted((dates[i + 1] - dates[i]).days
                           for i in range(len(dates) - 1)) if len(dates) >= 2 else []
            _sub_monthly = bool(_gaps) and _gaps[len(_gaps) // 2] < 20
            if not stable and category == "other" \
                    and not any(h in raw_name.lower() for h in _SERVICE_HINTS) \
                    and (_sub_monthly or not _stream_credible(dates, amounts)):
                fk = _merchant_key(raw_name) or raw_name.lower()
                if fk:
                    freq_amounts[fk] = list(amounts)
                    freq_meta[fk] = (_clean_name(raw_name), "frequent", "other", None)
                    return "spending"

            # A confidently-detected Lithuanian personal name (first name + surname
            # ending) on a NON-card transfer is a person, full stop — never a bill or
            # subscription, whatever the amount. This overrides the housing/finance
            # exception below, which was surfacing "Lina Gliožerienė" / "Gabrielė
            # Mažeikaitė" as €200-a-month "bills". Card purchases (acceptor/domain
            # present) are excluded, so a brand is never read as a person.
            rmt = canon_g.get("remittance") or {}
            is_card = bool(rmt.get("acceptor") or rmt.get("domain"))
            lt_person = not is_card and _lt_person(cp_name or raw_name)

            is_person = (canon_g.get("counterparty") or {}).get(
                "party_kind_hint") == "person_like" \
                or _bare_person_like(canon_g, cp_name or raw_name)
            # A person-to-person transfer is a transfer, not a bill — however
            # regularly it repeats. Sending family money every month, splitting
            # rent with a flatmate, repaying a friend: none of these are
            # subscriptions, and showing them as such is the single most obvious
            # "this app is broken" bug for a new user paying an actual person.
            #
            # The exception is a genuine COMMITMENT to a private individual —
            # rent to a landlord, a loan repayment. Those surface as housing or
            # finance from the memo (`_category_for_unknown`), so they stay bills;
            # only person-like streams that are NEITHER become transfers. This
            # replaces the old rule that kept CONFIDENT person streams as bills,
            # which is exactly what surfaced a personal transfer as a
            # subscription.
            bare_person = _bare_person_like(canon_g, cp_name or raw_name)
            # A company word (Grupė, Baltics, Sistemos, Vandenys…) marks a business
            # that merely looks person-shaped — it OVERRIDES every person signal,
            # including a distinctive-surname false hit ("Teva Baltics" → "teva"
            # ends "eva"). A generic two-word name on a non-card transfer counts as
            # a person too, which closes the foreign-name gap (a €300/mo "John
            # Smith" no longer becomes a housing bill).
            is_business = _has_business_token(cp_name or raw_name)
            # `is_person` relies on party_kind_hint, which canonical builds from the
            # structured creditor.name only. Also test the RAW name shape so a
            # foreign/generic person whose name the bank put ONLY in the remittance
            # (no creditor.name) is still caught, not booked as a housing bill.
            generic_person = ((is_person or _looks_person_shaped(cp_name or raw_name))
                              and not is_card)
            if not is_business and (lt_person or bare_person or generic_person):
                # HARD RULE: a personal name is a person-to-person transfer — NEVER
                # a bill or subscription, whatever the amount or memo. The old code
                # kept a person as a BILL when the amount/memo read "housing/finance"
                # (rent to a landlord); that one exception is exactly what surfaced
                # real people (a €350 self-transfer, monthly family money, splitting
                # rent, foreign names >€200) under Sąskaitos / Prenumeratos. You do
                # not subscribe to a person. The money still shows in the feed as a
                # transfer — it is simply never a recurring commitment.
                typ = "transfer"
            else:
                typ = "bill" if category in ("housing", "finance") else "subscription"
                if stable and typ == "subscription":
                    typ = "bill"   # deliberate transfers lean bill, not subscription
            # Display name: for a web-domain identity whose counterparty is a
            # PROCESSOR (OPAY, Paysera…), show the merchant domain-brand instead of
            # the processor's name ("UAB OPAY SOLUTIONS" → "Gymplius"). When the
            # counterparty already IS the merchant (card "APPLE.COM/BILL",
            # "www.savasld.lt"), keep that name so it still matches its feed rows.
            _gk = str(canon_g.get("identity_key") or "")
            _cpl = (cp_name or "").lower()
            _is_proc = any(p in _cpl for p in _PROC_TOKENS)
            if _gk.startswith("dom:") and _is_proc:
                disp = _gk[4:].rsplit(".", 1)[0].replace("-", " ").title()
            elif stable:
                disp = cp_name
            else:
                disp = _clean_name(st_items[0][2])
            cand = _build_candidate(disp, typ, category, None, st_items, dates,
                                    needs_review=True, auto_detected=False,
                                    confident=confident, today=today)
        if force_unconfident:
            cand["cadenceLabel"] = "irregular"   # no fake cadence for a residual
        cand["identitySource"] = src
        cand["identityConfidence"] = conf
        cand["stream"] = _stream_diag(st_items, dates, st_reason, st_id, key)
        candidates.append(cand)
        return None

    for key, items in groups.items():
        hit = group_hit[key]
        canon_g = group_canon.get(key, {})
        src = canon_g.get("identity_source")
        conf = canon_g.get("identity_confidence")
        stable = src in (canonical.S_IBAN, canonical.S_SCHEME) \
            or str(canon_g.get("identity_key") or "").startswith("dom:")
        # Segment the merchant group into payment streams. Each RECURRING stream
        # is emitted separately (so one merchant's one-off can never inherit
        # another stream's recurrence); the merchant's non-recurring one-offs are
        # merged into ONE explicitly not-confident residual (avoids fragmenting a
        # merchant's irregular activity into many single-transaction candidates).
        residual = []
        for st_items, st_reason, st_id in segment_streams(items, key):
            counters["streams"] += 1
            if not st_reason.startswith(_RECUR):
                residual.extend(st_items)
                continue
            tag = _emit(st_items, st_reason, st_id, key, hit, canon_g, src, conf, stable)
            if tag:
                counters[tag] += 1
        if residual:
            tag = _emit(residual, "non-recurring residual", f"{key}#res", key,
                        hit, canon_g, src, conf, stable, force_unconfident=True)
            if tag:
                counters[tag] += 1
    n_filtered = counters["filtered"]
    n_spending = counters["spending"]
    n_streams = counters["streams"]

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

    # Confident recurring first, then known merchants, then frequency and cost.
    candidates.sort(
        key=lambda c: (not c["confident"], not c["autoDetected"],
                       -c["occurrences"], -c["cost"]))

    n_auto = sum(1 for c in candidates if c["autoDetected"])
    n_confident = sum(1 for c in candidates if c["confident"])
    logging.info(
        "detect_recurring: dbit=%d skipped=%d merchants=%d auto=%d confident=%d "
        "spending=%d filtered=%d aiHidden=%d unknown=%d needsExternal=%d "
        "candidates=%d frequent=%d",
        n_dbit, n_skipped, len(groups), n_auto, n_confident, n_spending,
        n_filtered, n_ai_hidden, n_unknown, n_needs_external,
        len(candidates), len(frequent),
    )
    debug = {
        "txns": len(transactions),
        "dbit": n_dbit,
        "skippedNoName": n_skipped,
        "merchants": len(groups),
        "auto": n_auto,
        "confident": n_confident,
        "spending": n_spending,
        "manual": len(candidates) - n_auto,
        "filtered": n_filtered,
        "aiHidden": n_ai_hidden,
        "unknown": n_unknown,
        "needsExternal": n_needs_external,
        "identitySources": dict(id_src),
        "streams": n_streams,
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
