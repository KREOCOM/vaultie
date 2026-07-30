"""Bank-independent normalisation of Enable Banking data.

Enable Banking already maps 2500+ banks onto one Berlin Group schema, but banks
POPULATE that schema differently: a field one bank fills, another leaves empty or
puts elsewhere. This layer maps a raw account/transaction onto the fields the rest
of Vaultie relies on, using a DOCUMENTED PRIORITY ORDER per field, so no downstream
stage (feed, resolver, recurring, balances) has to know which bank sent it.

Design rule: NO `if bank == "Swedbank"`. Every rule is keyed off the SHAPE of the
data, never the bank name. The one place a bank identity leaks in is the FX table
(currency codes), which is inherent, not a per-bank branch.

Applied ONCE at ingestion (main._build_result), it mutates each transaction so the
existing downstream code — which reads creditor.name, transaction_amount,
credit_debit_indicator, and a LIST remittance_information — sees clean, present
fields instead of an empty/mis-shaped one.
"""
import re

# ── remittance (list-or-string → text, and a safe list) ─────────────────────
def remittance_text(t) -> str:
    r = t.get("remittance_information")
    if isinstance(r, str):
        return r
    if isinstance(r, list):
        return " ".join(str(x) for x in r if x)
    return ""


# ── merchant recovery from a card-purchase descriptor ───────────────────────
# Several formats seen / plausible on EB:
#   Swedbank:  "PIRKINYS <card> <date> <time> <amt> EUR (474352) MAXIMA Klaipeda 000LT"
#   Santander: "COMPRA EN MERCADONA MADRID (901234) 000ES"
#   plain:     "MAXIMA KLAIPEDA" (no ref group at all)
_REF_RE = re.compile(r"\((\d{3,})\)")            # a (123456) terminal/auth ref
_TAIL_RE = re.compile(r"\s*\d{3}[A-Za-z]{2}\s*$")  # trailing "000LT" country tag
_STORE_CITIES = frozenset({
    "vilnius", "kaunas", "klaipeda", "klaipėda", "siauliai", "šiauliai",
    "panevezys", "panevėžys", "alytus", "marijampole", "marijampolė",
    "mazeikiai", "mažeikiai", "jonava", "utena", "kedainiai", "kėdainiai",
    "telsiai", "telšiai", "taurage", "tauragė", "ukmerge", "ukmergė",
    "visaginas", "plunge", "plungė", "kretinga", "silute", "šilutė",
    "radviliskis", "radviliškis", "palanga", "gargzdai", "gargždai",
    "druskininkai", "birstonas", "birštonas", "elektrenai", "elektrėnai",
    "vilkaviskis", "vilkaviškis", "kelme", "kelmė", "rokiskis", "rokiškis",
    "madrid", "barcelona", "oslo", "stockholm", "cork", "dublin",
})
# Descriptor verbs that precede the ref but are not the merchant.
_DESC_PREFIX = re.compile(r"^(pirkinys|purchase|compra en|compra|payment|pos)\b",
                          re.IGNORECASE)


# 3-letter ISO currency codes that appear as metadata tokens in a descriptor.
_CCY_TOKENS = frozenset({
    "eur", "usd", "gbp", "sek", "nok", "dkk", "pln", "chf", "czk", "isk",
    "huf", "ron", "bgn", "uah", "cad", "aud", "try", "jpy", "xxx",
})
_COUNTRY_TOKENS = frozenset({"lt", "lv", "ee", "es", "no", "se", "fi", "dk",
                             "de", "fr", "it", "pl", "nl", "ie"})


def _clean_merchant(chunk: str) -> str:
    """Keep the brand, drop descriptor noise — terminal/store ids (2+ digit run),
    dates/times/amounts (they carry digits too), currency + country tokens, cities;
    collapse an immediate repeat; Title-Case an ALLCAPS result. Single-digit brands
    ("7-Eleven", "1-2-3") survive. Falls back to the raw chunk if nothing is left."""
    out = []
    for raw in re.split(r"[\s/|]+", chunk):
        tok = raw.strip(".,-")
        low = tok.lower()
        if not tok or low in _STORE_CITIES or low in _CCY_TOKENS or low in _COUNTRY_TOKENS:
            continue
        if re.search(r"\d{2,}", tok):  # store/terminal id, date, time, amount, card
            continue
        out.append(tok)
    dedup = []
    for w in out:
        if not dedup or dedup[-1].lower() != w.lower():
            dedup.append(w)
    name = " ".join(dedup).strip()
    if not name:
        return chunk
    return name.title() if name.isupper() else name


def merchant_from_remittance(text: str):
    """Pull a merchant out of a card-purchase descriptor, or None. Bank-agnostic:
    the merchant sits AFTER the "(ref)" (Swedbank) or BEFORE it (Santander), so we
    don't rely on position — strip the purchase-verb prefix, the "(ref)" group(s),
    and the trailing country tag, then clean out card/date/amount/currency/city
    noise and keep the brand. Returns None when it isn't a card descriptor."""
    if not text:
        return None
    if not (_REF_RE.search(text) or _DESC_PREFIX.search(text)):
        return None  # not a card descriptor — don't mangle a plain memo
    s = _DESC_PREFIX.sub("", text, count=1)
    s = _REF_RE.sub(" ", s)
    s = _TAIL_RE.sub("", s).strip()
    chunk = _clean_merchant(s)
    return chunk if len(chunk) >= 3 else None


def _party_name(party) -> str:
    return (party.get("name") or "").strip() if isinstance(party, dict) else ""


def merchant_name(t) -> str:
    """The counterparty/merchant name, by PRIORITY (one implementation for all).

    1. structured counterparty (creditor for out, debtor for in)
    2. ultimate_creditor / ultimate_debtor
    3. a `merchant` object/string
    4. merchant embedded in the remittance descriptor
    5. a `note`
    6. the first remittance line (cleaned)
    7. "—"
    """
    dbit = t.get("credit_debit_indicator") != "CRDT"  # missing → treat as out-going
    primary = "creditor" if dbit else "debtor"
    ultimate = "ultimate_creditor" if dbit else "ultimate_debtor"
    for key in (primary, ultimate):
        n = _party_name(t.get(key))
        if n:
            return n
    mer = t.get("merchant")
    if isinstance(mer, dict) and _party_name(mer):
        return _party_name(mer)
    if isinstance(mer, str) and mer.strip():
        return mer.strip()
    text = remittance_text(t)
    from_r = merchant_from_remittance(text)
    if from_r:
        return from_r
    note = t.get("note")
    if isinstance(note, str) and note.strip():
        return _clean_merchant(note.strip())
    if text.strip():
        return _clean_merchant(text.strip()) or text.strip()
    return "—"


# ── amount + currency (transaction_amount OR bare amount) ───────────────────
def amount_value(t):
    ta = t.get("transaction_amount")
    raw = ta.get("amount") if isinstance(ta, dict) else t.get("amount")
    try:
        return abs(float(raw))
    except (TypeError, ValueError):
        return None


def currency_of(t):
    ta = t.get("transaction_amount")
    return (ta.get("currency") if isinstance(ta, dict) else None) or t.get("currency")


# ── one-shot per-transaction normalisation (mutates in place) ───────────────
def normalize_transaction(t: dict) -> dict:
    # 1. Direction: a missing/odd indicator silently flipped credits into negative
    #    expenses downstream. Default it to DBIT (documented data-gap) so the sign
    #    is at least consistent; EB provides it for real card/transfer rows.
    if t.get("credit_debit_indicator") not in ("DBIT", "CRDT"):
        t["credit_debit_indicator"] = "DBIT"
    # 2. remittance → LIST, so a string one isn't char-sliced by `[0]` accessors.
    r = t.get("remittance_information")
    if isinstance(r, str):
        t["remittance_information"] = [r] if r else []
    elif not isinstance(r, list):
        t["remittance_information"] = []
    # 3. transaction_amount from a bare `amount` (some ASPSPs use it) so `_amt`
    #    doesn't read 0 for every row.
    if not isinstance(t.get("transaction_amount"), dict) and t.get("amount") is not None:
        t["transaction_amount"] = {"amount": str(t.get("amount")),
                                   "currency": t.get("currency") or "EUR"}
    # 4. Fill the structured counterparty name from the priority chain so EVERY
    #    downstream stage (feed, resolver, recurring) sees the merchant, not "—".
    party = "creditor" if t["credit_debit_indicator"] == "DBIT" else "debtor"
    if not _party_name(t.get(party)):
        name = merchant_name(t)
        if name and name != "—":
            if not isinstance(t.get(party), dict):
                t[party] = {}
            t[party]["name"] = name
    return t


def normalize_transactions(txns) -> None:
    for t in txns:
        normalize_transaction(t)


# ── balances ────────────────────────────────────────────────────────────────
# Priority for the "spendable" figure, widest realistic set (Berlin Group):
# available first, then booked, then forward/opening, then anything.
_BAL_PRIORITY = ("ITAV", "CLAV", "XPCD", "CLBD", "ITBD", "FWAV",
                 "OPAV", "OPBD", "PRCD", "OTHR")


def pick_balance(balances):
    """Return (amount, currency) for the most spendable balance, or (0.0, None).

    The CURRENCY comes from the balance object (e.g. 'EUR'), NOT the account
    metadata — some banks tag the account 'XXX' ('no currency'). The type priority
    covers every common Berlin Group balance_type so a bank sending only ITBD/CLAV/
    FWAV never falls to an arbitrary first object."""
    if not balances:
        return 0.0, None

    def amt(b):
        try:
            return float((b.get("balance_amount") or {}).get("amount") or 0)
        except (TypeError, ValueError):
            return 0.0

    def ccy(b):
        return (b.get("balance_amount") or {}).get("currency")

    by_type = {str(b.get("balance_type") or "").upper(): b for b in balances}
    for pref in _BAL_PRIORITY:
        if pref in by_type:
            b = by_type[pref]
            return round(amt(b), 2), ccy(b)
    b = balances[0]
    return round(amt(b), 2), ccy(b)


def real_currency(*candidates):
    """First candidate that is a real currency (not None, not 'XXX'), else 'EUR'."""
    for c in candidates:
        if c and str(c).upper() != "XXX":
            return c
    return "EUR"


# ── dedup: pending+booked aware, id-optional ────────────────────────────────
def dedupe(txns):
    """Drop duplicate transactions robustly across banks.

    entry_reference-only dedup broke two ways: (1) a bank that omits it left
    overlapping paging windows duplicated; (2) a PENDING and its later BOOKED copy
    carry DIFFERENT references, so both survived and `_merge_day` summed them —
    double-counting the spend. Here: dedup on entry_reference/transaction_id when
    present, else a composite (date, amount, direction, merchant) key; then drop a
    PENDING row whenever a BOOKED row with the same (date, amount, merchant) exists."""
    seen = set()
    kept = []
    for t in txns:
        ref = t.get("entry_reference") or t.get("transaction_id")
        # Scoped to the ACCOUNT: a reference is only promised to be unique within
        # one account, and banks that number entries per account hand two wallets
        # the same "1". Unscoped, the second wallet's transaction was dropped as a
        # duplicate — money quietly missing rather than double-counted.
        acct = t.get("_acct") or t.get("_bank") or ""
        if ref:
            key = ("ref", acct, str(ref))
        else:
            key = ("cmp", acct, t.get("booking_date"), amount_value(t),
                   t.get("credit_debit_indicator"), merchant_name(t)[:24].lower())
        if key in seen:
            continue
        seen.add(key)
        kept.append(t)
    return _drop_settled_pendings(kept)


def _drop_settled_pendings(txns):
    """Remove PENDING rows whose BOOKED version has arrived.

    The old rule matched on (date, amount, merchant), which only works when the
    amount does not change. It routinely does: a fuel pump authorises 1 EUR and
    books 62, a hotel authorises the room and books the extras. Both rows then
    survived and the day was counted twice.

    So the match ignores the amount and pairs on (account, merchant) within a few
    days — but ONE-TO-ONE, so two genuine visits to the same shop cannot be
    collapsed into one. A booked row can settle exactly one pending.

    The residual error is the safer one: an unmatched pending is shown until it
    books, whereas the old behaviour invented spending that never happened.
    """
    from datetime import date as _date

    def key(t):
        return (t.get("_acct") or t.get("_bank") or "",
                merchant_name(t)[:24].lower())

    def day(t):
        try:
            return _date.fromisoformat((t.get("booking_date") or "")[:10])
        except ValueError:
            return None

    booked_by_key = {}
    for t in txns:
        if t.get("status") == "BOOK":
            booked_by_key.setdefault(key(t), []).append(t)

    settled = set()
    out = []
    for t in txns:
        if t.get("status") != "PDNG":
            out.append(t)
            continue
        d = day(t)
        match = None
        for b in booked_by_key.get(key(t), []):
            if id(b) in settled:
                continue  # this booked row already settled another pending
            bd = day(b)
            if d is None or bd is None or abs((bd - d).days) <= 4:
                match = b
                break
        if match is None:
            out.append(t)
        else:
            settled.add(id(match))
    return out
