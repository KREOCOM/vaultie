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

    # L3a — fixed-amount recurring sub-streams.
    by_amt = defaultdict(list)
    for i, (d, a) in enumerate(dated):
        if a is not None:
            by_amt[round(a, 2)].append(i)
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


# ── Recurring stream LIFECYCLE (Plaid/Tink-style) ───────────────────────────
# A historical recurring pattern is NOT an active future commitment forever. A
# finished tax plan / paid-off loan / cancelled subscription keeps its history
# but must drop out of the monthly & annual projection once the expected charges
# stop arriving. Tolerances scale with each stream's OWN cadence, so a yearly
# bill isn't declared dead after two months.
_CYCLE_DAYS = {"weekly": 7, "monthly": 30, "quarterly": 91, "yearly": 365}
# per-charge cost → monthly-equivalent, so the projection is a true monthly sum
# regardless of billing frequency (a €600 yearly bill counts as €50/mo, not €600).
_CYCLE_PER_MONTH = {"weekly": 4.345, "monthly": 1.0,
                    "quarterly": 1 / 3.0, "yearly": 1 / 12.0}


def _lifecycle(last: dt.date, cycle: str, occ: int, today: dt.date):
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
    cd = _CYCLE_DAYS.get(cycle, 30)
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
    avg = round(sum(amounts) / len(amounts), 2)
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
    status, days_since = _lifecycle(last, cycle, occ, today)
    # Monthly-equivalent of this stream's typical charge (the projection unit).
    monthly = round(avg * _CYCLE_PER_MONTH.get(cycle, 1.0), 2)
    return {
        "name": display,
        "type": mtype,                      # subscription | bill | transfer
        "autoDetected": auto_detected,      # known merchant vs user-review
        "confident": confident,             # ≥2 sightings → a real pattern
        "cost": avg,                        # typical per-charge amount
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
                     own_ibans=None):
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
        # Own-account transfer (SEB↔Revolut etc.): never a recurring bill.
        if own:
            cpi = (canon.get("counterparty") or {}).get("iban")
            if cpi and str(cpi).replace(" ", "").upper() in own:
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
        if canon["identity_source"] in (canonical.S_IBAN, canonical.S_SCHEME):
            key = canon["identity_key"]
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
            if not stable and not _include_unknown(st_items[0][2], st_items):
                return "filtered"
            avg = round(sum(amounts) / len(amounts), 2)
            category = _category_for_unknown(st_items[0][2], avg)
            typ = "bill" if category in ("housing", "finance") else "subscription"
            if stable and typ == "subscription":
                typ = "bill"       # deliberate transfers lean bill, not subscription
            # Weak person-like hint: a repeated transfer to a non-merchant party
            # keeps its temporal-recurrence signal but must NOT be classified as a
            # subscription/bill purely from a stable IBAN + recurrence. Fall back
            # to "transfer" (not a final government/tax semantic — just safer).
            if (canon_g.get("counterparty") or {}).get("party_kind_hint") == "person_like":
                typ = "transfer"
            disp = cp_name if stable else _clean_name(st_items[0][2])
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
        stable = src in (canonical.S_IBAN, canonical.S_SCHEME)
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
