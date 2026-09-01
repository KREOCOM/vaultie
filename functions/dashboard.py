"""Build the Vaultie dashboard payload from a user's real bank transactions.

Given the (already de-duplicated) Enable Banking transactions + account balances
for one connection, this produces the exact ``dash_data`` JSON the app's new
dashboard renders — every transaction classified into Vaultie's 9-section model,
plus month/day feed, this-week category bars, detected subscriptions & bills,
the balance series, and headline totals.

Classification reuses the production resolver (KB/heuristics) for merchant
category, and the transaction's ``bank_transaction_code`` for non-merchant flows
(salary via currency exchange, top-ups, transfers, refunds). Nothing here is
persisted server-side — the payload goes straight back to the user's device.
"""

import datetime as dt
import logging
import math
import re
from collections import Counter, OrderedDict, defaultdict

import mcc as mcc_module
import normalize
import resolver
from recurring import detect_recurring

LT_MON = {1: "Sausis", 2: "Vasaris", 3: "Kovas", 4: "Balandis", 5: "Gegužė",
          6: "Birželis", 7: "Liepa", 8: "Rugpjūtis", 9: "Rugsėjis", 10: "Spalis",
          11: "Lapkritis", 12: "Gruodis"}
LT_GEN = {1: "Sausio", 2: "Vasario", 3: "Kovo", 4: "Balandžio", 5: "Gegužės",
          6: "Birželio", 7: "Liepos", 8: "Rugpjūčio", 9: "Rugsėjo", 10: "Spalio",
          11: "Lapkričio", 12: "Gruodžio"}
LT_WD = ["Pirmadienis", "Antradienis", "Trečiadienis", "Ketvirtadienis",
         "Penktadienis", "Šeštadienis", "Sekmadienis"]

# resolver category -> (cat_lt, col, icon_key, section_label, section_color)
# col/icon_key match the app's _catColors / _catIcons; section_* the 9-section model.
CAT_MAP = {
    "groceries":     ("Maisto prekės",       "food",      "cart",    "Maistas, gėrimai",   "green"),
    "supermarket":   ("Maisto prekės",       "food",      "cart",    "Maistas, gėrimai",   "green"),
    "grocery_store":     ("Maisto prekės",   "food",      "cart",    "Maistas, gėrimai",   "green"),  # Overture
    "convenience_store": ("Maisto prekės",   "food",      "cart",    "Maistas, gėrimai",   "green"),  # Overture
    "restaurant":    ("Kavinės, restoranai", "food",      "dining",  "Maistas, gėrimai",   "green"),
    "fast_food_restaurant": ("Kavinės, restoranai", "food", "dining", "Maistas, gėrimai",  "green"),  # Overture
    "bakery":        ("Kavinės, restoranai", "food",      "dining",  "Maistas, gėrimai",   "green"),  # Overture (kepykla → maistas)
    "food":          ("Kavinės, restoranai", "food",      "dining",  "Maistas, gėrimai",   "green"),
    "cafe":          ("Kavinės, restoranai", "food",      "coffee",  "Maistas, gėrimai",   "green"),
    "alcohol":       ("Alkoholis, tabakas",  "food",      "bottle",  "Maistas, gėrimai",   "green"),
    "fuel":          ("Kuras",               "fuel",      "fuel",    "Transportas",        "blue"),
    "gas_station":   ("Kuras",               "fuel",      "fuel",    "Transportas",        "blue"),
    "transport":     ("Transportas",         "transport", "taxi",    "Transportas",        "blue"),
    "taxi":          ("Taksi",               "transport", "taxi",    "Transportas",        "blue"),
    "automotive":    ("Automobilis",         "transport", "taxi",    "Transportas",        "blue"),
    "car_wash":      ("Automobilis",         "transport", "taxi",    "Transportas",        "blue"),  # Overture (automobilio plovykla)
    "parking":       ("Parkavimas",          "transport", "taxi",    "Transportas",        "blue"),
    "retail":        ("Apsipirkimas",        "shopping",  "monitor", "Apsipirkimas",       "teal"),
    "shopping":      ("Apsipirkimas",        "shopping",  "monitor", "Apsipirkimas",       "teal"),
    "electronics":   ("Elektronika, prekės", "shopping",  "monitor", "Apsipirkimas",       "teal"),
    "clothing":      ("Drabužiai",           "shopping",  "monitor", "Apsipirkimas",       "teal"),
    "pharmacy":      ("Vaistinė",            "health",    "health",  "Sveikata, sportas",  "orange"),
    "health":        ("Sveikata",            "health",    "health",  "Sveikata, sportas",  "orange"),
    "fitness":       ("Sportas",             "fitness",   "health",  "Sveikata, sportas",  "orange"),
    "gym":           ("Sportas",             "fitness",   "health",  "Sveikata, sportas",  "orange"),  # Overture
    "taxes":         ("Mokesčiai",           "taxes",     "doc",     "Finansai",           "red"),
    "banking":       ("Bankas, komisiniai",  "finance",   "money",   "Finansai",           "red"),
    "finance":       ("Bankas, komisiniai",  "finance",   "money",   "Finansai",           "red"),
    "insurance":     ("Draudimas",           "vehicle",   "shield",  "Būstas, sąskaitos",  "olive"),
    "connectivity":  ("Ryšys, internetas",   "housing",   "home",    "Būstas, sąskaitos",  "olive"),
    "internet":      ("Ryšys, internetas",   "housing",   "home",    "Būstas, sąskaitos",  "olive"),
    "utilities":     ("Komunaliniai",        "housing",   "home",    "Būstas, sąskaitos",  "olive"),
    "housing":       ("Būstas, nuoma",       "housing",   "house",   "Būstas, sąskaitos",  "olive"),
    "rent":          ("Nuoma",               "housing",   "house",   "Būstas, sąskaitos",  "olive"),
    "mortgage":      ("Būsto paskola",       "housing",   "house",   "Būstas, sąskaitos",  "olive"),
    "home_improvement": ("Namų prekės",      "shopping",  "monitor", "Apsipirkimas",       "teal"),
    "hardware":      ("Namų prekės",         "shopping",  "monitor", "Apsipirkimas",       "teal"),
    "entertainment": ("Pramogos",            "entertainment", "fun", "Pramogos",           "cyan"),
    "software":      ("Prenumeratos",        "entertainment", "monitor", "Pramogos",       "cyan"),
    "travel":        ("Kelionės",            "entertainment", "fun", "Pramogos",           "cyan"),
    "education":     ("Mokslas",             "invest",    "doc",     "Švietimas",          "purple"),
    "childcare":     ("Vaikai, ugdymas",     "invest",    "doc",     "Švietimas",          "purple"),
    # 2026-09-01: added per explicit request — a one-off payment to a
    # tradesperson (plumber, electrician, general home repair) had no
    # category anywhere in the taxonomy at all, client or server; always
    # fell through to generic "Kita". Multiple keys (like fuel/gas_station
    # above) hedge against which exact category string a data source uses.
    "plumber":       ("Namų priežiūra, meistrai", "housing", "tools", "Būstas, sąskaitos", "olive"),
    "electrician":   ("Namų priežiūra, meistrai", "housing", "tools", "Būstas, sąskaitos", "olive"),
    "handyman":      ("Namų priežiūra, meistrai", "housing", "tools", "Būstas, sąskaitos", "olive"),
    "home_service":  ("Namų priežiūra, meistrai", "housing", "tools", "Būstas, sąskaitos", "olive"),
    "hair_salon":    ("Grožis, kirpykla",     "health",    "scissors", "Sveikata, sportas", "orange"),
    "hairdresser":   ("Grožis, kirpykla",     "health",    "scissors", "Sveikata, sportas", "orange"),
    "beauty_salon":  ("Grožis, kirpykla",     "health",    "scissors", "Sveikata, sportas", "orange"),
    "nail_salon":    ("Grožis, kirpykla",     "health",    "scissors", "Sveikata, sportas", "orange"),
    "veterinarian":  ("Naminiai gyvūnai",     "shopping",  "pets",    "Apsipirkimas",       "teal"),
    "pet_store":     ("Naminiai gyvūnai",     "shopping",  "pets",    "Apsipirkimas",       "teal"),
    "pet_grooming":  ("Naminiai gyvūnai",     "shopping",  "pets",    "Apsipirkimas",       "teal"),
}
OTHER = ("Kita", "other", "swap", "Kita", "indigo")

# Curated merchant-name overrides for entities the generic classifier gets wrong.
# A robot can't infer that "UAB Mogo LT" only does loans (they also sell cars),
# so we pin known Lithuanian brands by name. Checked before the resolver category.
# Each: (name-substrings) -> (cat_lt, col, icon, section, section_color).
# Ordered, most-specific first — this is the proven keyword coverage (ported from
# the original LT classifier). It runs as merchant stage-1; anything it doesn't
# match falls through to the resolver (KB → global index).
_FUEL = ("Kuras", "fuel", "fuel", "Transportas", "blue")
_GROC = ("Maisto prekės", "food", "cart", "Maistas, gėrimai", "green")
_DINE = ("Kavinės, restoranai", "food", "dining", "Maistas, gėrimai", "green")
_ALCO = ("Alkoholis, tabakas", "food", "bottle", "Maistas, gėrimai", "green")
_SUBS = ("Prenumeratos", "entertainment", "monitor", "Pramogos", "cyan")
_ENTM = ("Pramogos", "entertainment", "fun", "Pramogos", "cyan")
_TRAVEL = ("Kelionės", "entertainment", "fun", "Pramogos", "cyan")
_TAXI = ("Taksi", "transport", "taxi", "Transportas", "blue")
_AUTO = ("Automobilis", "transport", "taxi", "Transportas", "blue")
_SHARE = ("Paspirtukai, dalinimasis", "transport", "scooter", "Transportas", "blue")
_PARK = ("Parkavimas", "transport", "taxi", "Transportas", "blue")
_GYM = ("Sportas", "fitness", "health", "Sveikata, sportas", "orange")
_HEALTH = ("Sveikata", "health", "health", "Sveikata, sportas", "orange")
_ELEC = ("Elektronika, prekės", "shopping", "monitor", "Apsipirkimas", "teal")
_LOAN = ("Paskola, lizingas", "finance", "money", "Finansai", "red")
_INVEST = ("Investicijos", "finance", "doc", "Finansai", "red")
_INSUR = ("Draudimas", "vehicle", "shield", "Būstas, sąskaitos", "olive")
_UTIL = ("Ryšys, internetas", "housing", "home", "Būstas, sąskaitos", "olive")
_TAX = ("Mokesčiai", "taxes", "doc", "Finansai", "red")
_KITA = ("Kita", "other", "swap", "Kita", "indigo")

NAME_OVERRIDES = [
    (("mogo", "general financ", "sb lizing", "swedbank lizing", "citadele faktoring",
      "luminor lizing", "credit24", "vivus", "smscredit", "bobocash", "momentum credit",
      "delca invest", "paskol", "lizing"), _LOAN),
    (("savasld", "draudim", "insur", "ergo", "gjensidige", "balcia", "compensa",
      "seesam", "lietuvos draudimas", "pzu"), _INSUR),
    (("hotel", "hotell", "viesbut", "viešbut", "airbnb", "booking.com", "hostel",
      "hostal", "gjestehus", "guesthouse"), _TRAVEL),
    (("omio", "openferry", "viking line", "ferryscanner", "ryanair", "stena line",
      "wizz", "flixbus", "easyjet", "trainline", "autobusu stot", "flyr", "sas "), _TRAVEL),
    (("paysera",), _KITA),  # payment gateway — too ambiguous
    (("apple.com", "itunes", "anthropic", "openai", "chatgpt", "dribbble", "figma",
      "github", "adobe", "notion", "midjourney", "canva", "dropbox", "slack",
      "zoom.us", "patreon", "google *", "google play", "youtubepremium",
      "google storage", "delfiplius", "delfi plius",
      # AI / dev / creator SaaS tools — a card payment to one of these can only be
      # a software service (monthly plan or credit top-up), never a shop or a
      # person, so pin them to software rather than let a varying-amount stream
      # fall through to "Kita". Names are visible on card payments (unlike Apple
      # Pay's bundled apple.com).
      "base44", "replit", "lovable", "loveable", "capcut", "cursor", "vercel",
      "supabase", "netlify", "render.com", "railway", "elevenlabs", "perplexity",
      "runway", "descript", "framer", "webflow", "wix", "squarespace", "jetbrains",
      "grammarly", "elementor", "wondershare", "heygen", "leonardo.ai", "gamma.app",
      "mailchimp", "substack", "calendly", "linear.app", "1password", "grok"), _SUBS),
    (("netflix", "spotify", "hbo", "max help", "disney", "viaplay", "go3", "twitch",
      "steam", "playstation", "xbox", "nintendo", "cinema", "forum cinemas", "apollo kin"), _ENTM),
    (("oanda", "trading212", "trading 212", "fxflat", "swissquote", "interactive brokers",
      "photon global", "revolut trading", "etoro", "binance", "coinbase"), _INVEST),
    (("vmi ", "valstybine mokesciu", "sodra", "epaslaug", "e.paslaug", "regitra",
      "mokesciu inspekcija"), _TAX),
    (("telia", "bite", "tele2", "pildyk", "ignitis", "eso ", "vandenys",
      "elektros skyr", "teo ", "cgates", "init"), _UTIL),
    # NOTE: keep this list to UNAMBIGUOUS electronics retailers only. Senukai /
    # Kesko = home-improvement/DIY, "Verslo vartai" = generic — they were wrongly
    # pinned here; now they fall through to the resolver → AI, which categorises
    # them correctly instead of forcing "electronics".
    (("varlė", "varle", "technorama", "avitela", "kilobaitas", "elektromarkt",
      "topocentras", "media markt"), _ELEC),
    # Car services (wash / detailing / service / tyres) — a clear name keyword is
    # enough; "Ainava auto SPA" shouldn't land in generic shopping.
    (("auto spa", "autospa", "plovykl", "autoservis", "auto servis", "autocentr",
      "padangos", "padangu", "detailing", "car wash", "automobiliu dal"), _AUTO),
    (("gympl", "lemon gym", "impuls klub", "impuls sport", "fitness", "wellness",
      "sporto klub", "gym "), _GYM),
    (("vaistin", "pharm", "benu", "camelia", "gintarine", "eurovaistine", "klinik",
      "odontolog", "medicin", "ordinacij"), _HEALTH),
    (("royal smoke", "smoke", "vyno", "vynoteka", "alko", "tabak", "garrafeira"), _ALCO),
    (("bolt rentals", "citybee", "spark", "boldas", "ride "), _SHARE),
    (("bolt.eu", "bolt ", "uber", "taksi", "trafi"), _TAXI),
    (("parking", "stova", "up202", "parkin", "easypark", "skypark"), _PARK),
    (("circle k", "viada", "neste", "orlen", "1-2-3", "123 ", "lukoil", "emsi",
      "baltic petroleum", "st1", "yx ", "uno-x", "uno x", "okq8", "7-eleven", "shell",
      "bensinautomat", "circlek", "gulf ", "amic", "dus ", "degalin"), _FUEL),
    # NB: no bare "parduotuv" here — "parduotuvė" just means "shop" (a carpet or
    # electronics store is one too), so it must NOT force groceries. Only real
    # grocery signals: chain names + "maisto prek" (grocery goods). A generic
    # "UAB X, parduotuvė" falls through to the resolver → AI → "Kita".
    (("maxima", "rimi", "iki ", "lidl", "aibė", "aibe", "norfa", "prisma", "coop",
      "rema 1000", "minipreco", "minimani", "joker ", "t-market", "grocer",
      "maisto prek", "spar ", "hemkop", "kiwi ", "meny "), _GROC),
    (("mcdonald", "hesburger", "kfc", "burger king", "litriukas", "pocien", "skoniai",
      "birzu duona", "duona myli", "kavin", "restoran", "pizza", "sushi", "coffee",
      "caffe", "cili", "charlie", "vero cafe", "baras", "bardakas", " pub", "uzeiga",
      "bistro", "delano", "subway", "bhaji", "kebab", "kepyk", "prezo", "mcdroval"), _DINE),
]

# Canonical brand for NAME_OVERRIDES keywords whose bank descriptor carries a
# unique per-charge ref (ride/order id), so same-day charges share one merge key
# and collapse into a single "Brand N×" feed row. Keyed by the matched keyword.
_BRAND_CANON = {
    "bolt.eu": "Bolt",
    "bolt ": "Bolt",
    "uber": "Uber",
}

_FINANCE_HINTS = ["mogo", "general financing", "sb lizing", "swedbank lizing",
                  "citadele faktoring", "luminor lizing", "paskola", "lizing"]
_HOUSING_HINTS = ["artus", "nuoma", "rent", "busto adm", "namu prieziur"]


# Static FX → EUR base (approximate, MVP). A live rates source is future work.
# Everything in the dashboard is normalised to EUR so a multi-currency consent
# (e.g. an EUR account + a NOK salary account) yields a meaningful combined
# balance / income / expenses instead of adding raw NOK and EUR numbers. The FX
# table lives in fx.py so the recurring engine normalises the same way.
from fx import to_eur as _to_eur  # noqa: E402


def _ymd(value):
    """``(year, month, day)`` from a bank's booking date, or None if unusable.

    Banks send more date shapes than the bare ISO day this once assumed — some
    append a time, some an offset. It used to be ``map(int, s.split("-"))``, so
    a single odd row raised ValueError out of build_dashboard and the caller
    turned the WHOLE dashboard into null. One bad row must cost that row only.
    Mirrors the parsing recurring.py already does defensively.
    """
    try:
        d = dt.date.fromisoformat(str(value)[:10])
    except (TypeError, ValueError):
        return None
    return d.year, d.month, d.day


def _amt(t):
    ta = t.get("transaction_amount") or {}
    try:
        v = float(ta.get("amount") or 0)
    except (TypeError, ValueError):
        # A non-numeric amount is a broken row, not a free transaction — but it
        # must not take the whole dashboard down with it (see _ymd).
        #
        # 2026-08-16 fix: this used to log the raw value (%r) — a real
        # transaction amount, unmasked, reaching Cloud Logging, unlike every
        # other sensitive field in this file. Digits are swapped for "X" so
        # the FORMAT that broke parsing is still visible (comma-decimal,
        # scientific notation, a stray currency symbol, empty string) without
        # exposing the actual figure.
        raw = ta.get("amount")
        shape = re.sub(r"\d", "X", str(raw))[:24] if raw is not None else "None"
        logging.warning("dashboard: unparseable amount, shape=%r type=%s",
                        shape, type(raw).__name__)
        v = 0.0
    # Direction comes SOLELY from the credit/debit indicator; magnitude is abs().
    # A bank/cached row that signs the amount itself (DBIT with amount "-5.00")
    # otherwise flipped: -v made it +5, so a debit read as income/refund.
    v = abs(v) if t.get("credit_debit_indicator") == "CRDT" else -abs(v)
    return _to_eur(v, ta.get("currency"))


def _raw_amt_cur(t, default_cur="EUR"):
    """The transaction's OWN signed amount and currency, before any EUR
    conversion — e.g. (461.50, "NOK"), not the EUR-normalized figure [_amt]
    returns for aggregation.

    The client re-converts EUR -> the user's chosen display currency using a
    LIVE rate (fx_rates.dart, ECB via frankfurter.app), while this server
    converted -> EUR using [fx.py]'s static, approximate table. Those two
    rates do not agree, so round-tripping a NOK transaction through EUR and
    back to NOK came out ~6% off the real number — silently, on every single
    transaction in a non-EUR account. When the client's display currency
    matches this row's OWN currency, it uses these fields directly and skips
    both conversions, so what a NOK account holder sees is the exact NOK
    figure their bank shows, not a double-converted approximation of it.

    ``default_cur`` is what to call this transaction's currency when Enable
    Banking's own amount object carries none — some transaction types (a DNB
    domestic transfer, seen live) omit it even though card purchases on the
    same account always have one. The caller passes the account's own
    currency here; only a genuinely mixed-currency multi-account consent
    falls back to the hardcoded "EUR" default.
    """
    ta = t.get("transaction_amount") or {}
    try:
        v = float(ta.get("amount") or 0)
    except (TypeError, ValueError):
        v = 0.0
    v = abs(v) if t.get("credit_debit_indicator") == "CRDT" else -abs(v)
    return v, (ta.get("currency") or default_cur).upper()


def _name(t):
    if t.get("credit_debit_indicator") == "DBIT":
        n = (t.get("creditor") or {}).get("name")
    else:
        n = (t.get("debtor") or {}).get("name")
    return (n or (t.get("remittance_information") or [""])[0] or "—").strip()


def _txn_epoch(t):
    """Best-effort transaction UTC epoch seconds, or None.

    PSD2 gives only a date — no time of day. But Revolut's ``entry_reference`` is
    a time-ordered id whose first 8 hex chars ARE the Unix timestamp (verified:
    they decode to the booking date + a real HH:MM). Other banks (SEB) use a plain
    numeric ref with no time, so this returns None and the row stays date-only.
    Guarded by a 2020-2035 sanity window so a non-timestamp id is never misread."""
    ref = t.get("entry_reference")
    if not isinstance(ref, str) or len(ref) < 9 or ref[8] != "-":
        return None
    try:
        ts = int(ref[:8], 16)
    except ValueError:
        return None
    return ts if 1_577_836_800 <= ts <= 2_051_222_400 else None


def _norm(n):
    return re.sub(r"\s+", " ", re.sub(r"[^a-z ]", "", n.lower())).strip()[:16]


# Legal-form / company markers matched as WHOLE TOKENS (word boundary), so the
# same letters buried in a person's name ("ab" in "Fabijonas", "ou" in "Roubaite")
# don't misflag them as a company. Domain suffixes stay substrings by nature.
_COMPANY_WORD_MARKERS = frozenset((
    "uab", "mb", "ab", "vsi", "všį", "grupe", "grupė", "ltd", "llc", "oy", "oü",
    "as", "inc", "gmbh", "sia", "ou", "corp"))
_COMPANY_AFFIX_MARKERS = (".lt", ".com")
_TOKEN_RE = re.compile(r"\w+", re.UNICODE)


def _is_person_name(n):
    """A counterparty that looks like an individual (P2P transfer). Case-insensitive
    — SEB sends surnames lowercased ("Milda dirsiene") and names uppercased
    ("INGRIDA ČELEDINĖ"), both are people."""
    parts = n.split()
    if len(parts) not in (2, 3):
        return False
    low = n.lower()
    if set(_TOKEN_RE.findall(low)) & _COMPANY_WORD_MARKERS:
        return False
    if any(a in low for a in _COMPANY_AFFIX_MARKERS):
        return False
    return all(re.sub(r"[-']", "", p).isalpha() and len(p) > 1 for p in parts)


# ── bank_transaction_code vocabularies (Revolut uses its own names; SEB and most
#    banks use ISO 20022 4-letter codes). Normalised so classification is
#    bank-agnostic. ──
_EXCHANGE_CODES = {"EXCHANGE"}
# A currency conversion of the user's OWN money. Banks label it inconsistently:
# some stamp a bank_transaction_code (EXCHANGE), Revolut/others only put it in the
# description ("Exchanged to EUR", "NOK → EUR"). Detect BOTH so a conversion is
# never mistaken for income or spending — generic across banks and currency pairs.
_EXCHANGE_HINT = re.compile(
    r"exchanged?\s+to\b|currency\s+exchange|valiut\w*\s+keit|konvertav|"
    r"[a-z]{3}\s*(?:→|->)\s*[a-z]{3}", re.I)


def _is_exchange(t):
    """True when this is a same-owner currency conversion (any bank, any pair)."""
    code = ((t.get("bank_transaction_code") or {}).get("code") or "").upper()
    if code in _EXCHANGE_CODES:
        return True
    text = " ".join([str(t.get("note") or "")]
                    + [str(x) for x in (t.get("remittance_information") or [])])
    return bool(_EXCHANGE_HINT.search(text))
_REFUND_CODES = {"CARD_REFUND", "CARD_CREDIT", "RRTN"}
_TOPUP_CODES = {"TOPUP"}
_CASH_CODES = {"CWDL", "ATM", "CSHW"}
_FEE_CODES = {"MDOP", "MCOP", "CHRG", "COMM"}
# credit transfers in/out (P2P, SEPA) — NOT card purchases
_XFER_CODES = {"ICDT", "RCDT", "MSCT", "ISCT", "RSCT", "ICHQ", "RCHQ", "TRANSFER", "SCT"}
# Positive-proof card-purchase codes: the counterparty is a merchant, never a
# person (card payments don't go P2P). Lets the AI person-guard be safely skipped
# for these — and ONLY these — so real 2–3-word merchant names aren't dropped.
# Deliberately narrow (fail-closed); widen only after observing real bank codes.
_CARD_CODES = {"CCRD"}
_FEE_HINTS = ["komisin", "aptarnavim", "paslaugų planas", "paslaugu planas",
              "mokestis už", "sąskaitos mokest", "account fee", "service fee"]


def _salary_sources(txns):
    """Normalised counterparty names that pay you like an EMPLOYER: a recurring
    (>=2 distinct months), substantial, NON-person incoming credit — in whatever
    account/currency it actually lands. This is the real salary signal.

    A currency EXCHANGE is NOT salary — it is you converting money you already
    have, and it happens on a different date than payday, so treating it as
    income would book the salary in the wrong month and inflate any conversion.
    """
    months_by = defaultdict(set)
    for t in txns:
        if t.get("credit_debit_indicator") != "CRDT":
            continue
        code = ((t.get("bank_transaction_code") or {}).get("code") or "").upper()
        if code in _EXCHANGE_CODES | _REFUND_CODES:
            continue  # conversions / refunds are not employer pay
        # TOPUP is deliberately NOT excluded: Revolut codes an incoming salary as
        # a top-up, so a recurring, substantial, non-person credit from the same
        # named source IS the salary. The amount + non-person guards keep genuine
        # self-top-ups (card/own money) out.
        if _amt(t) < 300:
            continue
        name = _name(t)
        if _is_person_name(name):
            continue  # a person sending you money is not an employer
        months_by[_norm(name)].add(t["booking_date"][:7])
    # >=2 distinct months: a freshly-connected wallet (e.g. a Norwegian NOK
    # salary wallet) often exposes only 2-3 months of history, so requiring 3
    # silently zeroed a real salary. Two substantial, non-person credits from the
    # same source across two months is already a strong employer-pay signal.
    return {k for k, mos in months_by.items() if len(mos) >= 2}


def _cp_iban_norm(t):
    """Counterparty IBAN (the OTHER side of the transaction), uppercased and
    space-stripped, for comparison against the user's own-account IBAN set. For
    an incoming (CRDT) transaction the counterparty is the debtor; for an
    outgoing (DBIT) one it's the creditor."""
    d = t.get("credit_debit_indicator")
    acc = t.get("debtor_account") if d == "CRDT" else t.get("creditor_account")
    iban = acc.get("iban") if isinstance(acc, dict) else None
    return iban.replace(" ", "").upper() if iban else None


def _classify(t, resolve_cat, salary_refs, own_ibans=None):
    """Return (canonical, cat_lt, col, icon, section, section_color, pos, is_transfer,
    logo_domain). logo_domain is the resolver's guess at the merchant's own domain
    (e.g. "mql5.com"), for the client to show a real brand logo when it has one —
    None everywhere except the final merchant-resolver branch, which is the only
    one with a domain to offer.

    Identify the *flow* from the (normalised) transaction code FIRST — currency
    exchange, refund, top-up, cash, fee, or a credit transfer (P2P). Only actual
    CARD purchases (and unknown non-person codes) reach the merchant resolver,
    so ``resolve_cat`` (KB → global index) is called lazily and NEVER sees a
    person/P2P transfer. This keeps SEB's ISO codes (ICDT/RCDT = transfers,
    CCRD = card, MDOP = fee) correctly sorted and keeps people out of merchant
    resolution.
    """
    code = ((t.get("bank_transaction_code") or {}).get("code") or "").upper()
    name = _name(t); nl = name.lower(); amt = _amt(t)

    # Own-account transfer: the counterparty is one of the user's OWN connected
    # accounts (e.g. SEB → Revolut, or between two accounts at one bank). Never
    # income, never spending, and — unlike a P2P transfer from another person —
    # excluded from "Gauta" too (see client _receivedOf), because it's just the
    # user's own money moving. Detected purely from the IBAN set, so it needs the
    # multi-bank context (own_ibans); with none passed this is a no-op.
    if own_ibans:
        cpi = _cp_iban_norm(t)
        if cpi and cpi in own_ibans:
            return (name, "Savas pervedimas", "transfer", "swap",
                    "Pervedimai", "indigo", amt > 0, True, None)

    # currency exchange is ALWAYS just a conversion of your own money — never
    # income and never spending (moving money between your own currencies).
    # Detected by code OR description ("Exchanged to EUR"), so Revolut-style FX
    # conversions no longer land in "Pervedimai" as if they were real transfers.
    if _is_exchange(t):
        return (name, "Valiutos keitimas", "transfer", "swap", "Pervedimai", "indigo", amt > 0, True, None)
    # A recurring employer credit is INCOME even when the bank codes it as a
    # TOP-UP (Revolut stamps NOK salary inflows as TOPUP → "Sąskaitos
    # papildymas") or a plain transfer. Check it BEFORE the top-up/refund/cash/
    # transfer branches so the code can't hide the salary.
    if amt > 0 and _norm(name) in salary_refs:
        return (name, "Atlyginimas", "income", "income", "Pajamos", "amber", True, False, None)
    if code in _REFUND_CODES:
        return (name, "Grąžinimas", "income", "swap", "Pajamos", "amber", True, False, None)
    if code in _TOPUP_CODES:
        return (name, "Sąskaitos papildymas", "transfer", "swap", "Pervedimai", "indigo", amt > 0, True, None)
    if code in _CASH_CODES:
        return (name, "Grynieji", "transfer", "swap", "Pervedimai", "indigo", amt > 0, True, None)

    # credit transfers (SEPA / P2P, in or out) — before merchant matching, so a
    # person is never sent to the merchant resolver
    if code in _XFER_CODES or (not code and _is_person_name(name)):
        # a recurring, substantial, non-person INCOMING transfer from the same
        # source = your salary (booked on the real payday, in whatever currency).
        if amt > 0 and _norm(name) in salary_refs:
            return (name, "Atlyginimas", "income", "income", "Pajamos", "amber", True, False, None)
        # A PERSON IS NEVER A BILL — and this check has to come before the
        # keyword hints, not after them.
        #
        # The hints are substring matches, so they fired on ordinary Lithuanian
        # names long before the person check was reached: "rent" is inside
        # "Renata", "artus" is inside "Bartuška". Those transfers were filed as
        # "Būstas, nuoma" with is_transfer=False, which did two kinds of damage:
        # a friend appeared among the household bills, and — because a positive
        # amount in a non-income section is read as a REFUND — money received
        # from that person was SUBTRACTED from spending. Spend 800 €, get 500 €
        # back from Renata, and the dashboard reported 300 € spent.
        #
        # Ordering it first is safe for real companies: _is_person_name rejects
        # anything carrying a company marker, and "grupė" is one — so "Artus
        # Grupė" still reaches the housing hint below.
        if _is_person_name(name):
            return (name, "Asmeninis pervedimas", "transfer", "person", "Pervedimai", "indigo", amt > 0, True, None)
        if any(k in nl for k in _FINANCE_HINTS):
            return (name, "Paskola, lizingas", "finance", "money", "Finansai", "red", amt > 0, False, None)
        if any(k in nl for k in _HOUSING_HINTS):
            return (name, "Būstas, nuoma", "housing", "house", "Būstas, sąskaitos", "olive", amt > 0, False, None)
        # An OUTGOING transfer to something that is neither a person nor one of
        # the user's own accounts is a PAYMENT — the money is gone.
        #
        # Filing all of it as a "transfer" deleted real spending from every
        # total at once: the week bars, the month figure, the categories and the
        # budget. It matters here more than the rule's authors could have known,
        # because paying a company by bank transfer is how invoices, utilities
        # and payment gateways (Paysera, OPAY) are normally settled in this
        # market — so a large share of ordinary spending simply vanished. The
        # transaction still appeared in the feed with its amount, which is how
        # this was found: a day whose header read −11,48 € drew an empty bar.
        #
        # Only the OUTGOING leg changes, and only after every safer reading has
        # been ruled out above: own IBAN, exchange, salary, refund, top-up, cash
        # and person all return before this. An INCOMING credit we cannot
        # attribute stays a transfer — it may be the user's own money arriving
        # from a bank whose IBAN we were never given, and calling that income
        # would inflate the month from the other end.
        if amt < 0:
            return (name, "Pervedimas", "other", "swap", "Kita", "indigo", False, False, None)
        return (name, "Pervedimas", "transfer", "swap", "Pervedimai", "indigo", True, True, None)

    # known merchant by name (BEFORE the fee check, so an oddly-coded Apple/Google
    # — e.g. MCOP/MDOP — isn't swallowed as a bank fee)
    for kws, mapped in NAME_OVERRIDES:
        matched = next((k for k in kws if k in nl), None)
        if matched:
            cat_lt, col, ic, sec, secc = mapped
            # Some banks bake a unique ride/order ref into the descriptor
            # ("Bolt.euo2607161334", "Bolt.eu/r/2605221012"), so every charge got a
            # different merge key and same-day rides never collapsed. A canonical
            # brand name for those keywords fixes it (Bolt taxi → one "Bolt" row).
            #
            # Everything else in NAME_OVERRIDES used to keep the RAW structured
            # creditor/debtor name verbatim — fine when the bank sends one
            # cleanly ("Maxima"), but a bank that bakes a store/terminal id into
            # it ("Maxima Lt X587") never collapsed with the clean version from
            # a different bank: same real purchase, two different-looking rows,
            # and the client's own top-merchants grouping (_merchantKey) keys
            # off this exact string, so they'd count as two separate merchants
            # there too. clean_merchant_display reuses the SAME store/terminal-id
            # stripping merchant_from_remittance already does for descriptor
            # text — but ONLY when the name actually carries a 2+ digit run
            # (the real signature of a baked-in store/terminal/card id).
            # Unconditionally running every name through it was tried first and
            # reverted: _clean_merchant splits on "/" and rejoins with a space,
            # which turned the already-correct "APPLE.COM/BILL" into
            # "Apple.Com Bill" and broke that stream's recurring sid
            # (test_series_id.py). Gating on a real digit run leaves anything
            # with no such noise — "APPLE.COM/BILL", "Vilniaus Taksi UAB",
            # "7-Eleven" — completely untouched.
            disp = _BRAND_CANON.get(matched) or (
                normalize.clean_merchant_display(name)
                if re.search(r"\d{2,}", name) else name)
            return (disp, cat_lt, col, ic, sec, secc, amt > 0, False, None)

    # bank fees / charges
    if code in _FEE_CODES or any(k in nl for k in _FEE_HINTS):
        return (name, "Bankas, komisiniai", "finance", "money", "Finansai", "red", amt > 0, False, None)

    # ── merchant → category ──
    #
    # MCC is the most reliable category signal the bank gives us: the card
    # network's own code for what KIND of merchant this is, independent of the
    # name, so it categorises every shop in Europe without a merchant list. It
    # only arrives on card purchases and only from banks that pass it through
    # (Revolut yes, some banks no), so it is the FIRST signal, not the only one.
    # The name resolver still runs — it supplies the canonical name and logo, and
    # its own category is the fallback when there is no MCC.
    mcc_cat = mcc_module.category_for_mcc(t.get("merchant_category_code"))
    canonical, category, logo_domain = resolve_cat(t)
    final = (mcc_cat or category or "other").lower()
    cat_lt, col, ic, sec, secc = CAT_MAP.get(final, OTHER)
    return (canonical or name, cat_lt, col, ic, sec, secc, amt > 0, False, logo_domain)


def build_dashboard(transactions, accounts, today=None, ai_key=None, own_ibans=None):
    """transactions: deduped Enable Banking list. accounts: [{name, balance, sub,
    icon, currency}]. ai_key: Anthropic key when the user opted into AI
    enrichment (Stage 3); None disables it. own_ibans: the user's own account
    IBANs across all connected banks — transfers to/from them are tagged "Savas
    pervedimas" (own-account, excluded from Gauta). Returns the dash_data dict."""
    today = today or dt.date.today()
    txns = [t for t in transactions if t.get("booking_date")]
    if not txns:
        return {"all": [], "months": [], "week": None, "subs": {"items": [], "total": 0},
                "spark": [], "balance": _balance_block([], accounts), "budgets": {},
                "meta": {"count": 0}}

    salary_refs = _salary_sources(txns)  # employer names (recurring inflow)

    # resolver corpus (built from debit merchant txns, as recurring does)
    dbit = [t for t in txns if t.get("credit_debit_indicator") == "DBIT"]
    try:
        corpus = resolver.build_corpus(dbit)
    except Exception:
        corpus = None

    _resolve_memo = {}

    def resolve_cat(t):
        # Memoized per transaction: _classify runs 3× over the same objects
        # (all / month feed / week) and this is the expensive stage (resolver +
        # optional AI). Same object → identical result, so cache by id(t). This
        # cuts the resolver/AI work ~3× per transaction with no output change.
        tid = id(t)
        cached = _resolve_memo.get(tid)
        if cached is not None:
            return cached
        result = None
        weak = False
        res = {}
        # Stage 2: deterministic resolver (KB → offline global index).
        try:
            _, hit, res = resolver.resolve_hit(t, corpus)
            if hit:
                result = (hit[0], hit[2], hit[3])  # canonical_name, category, logo_domain
                # A low-coverage RESOLVED match may still be WRONG (e.g. a fuzzy
                # global-index hit that lands Senukai in "electronics"). Flag the
                # weakest ones so AI can re-check them below.
                weak = float((res or {}).get("explanation_coverage") or 1.0) < 0.5
        except Exception:
            pass
        # Stage 3: AI enrichment (opt-in only) for the unresolved tail AND the
        # weakest matches. resolve_cat is reached ONLY from the merchant branch,
        # so this is never a person/P2P name; ai_enrichment also guards against
        # person names + caches. AI's answer overrides a weak resolver guess.
        # Feed the resolver's CLEAN surface (processor-prefix/card-line stripped),
        # not the raw descriptor, and key the AI cache on its identity_key so
        # descriptor variants of one business are classified — and paid for —
        # once (Feature A: cache cardinality tracks real merchants, not bank
        # descriptor variants). Falls back to the raw name if the resolver threw.
        if (result is None or weak) and ai_key:
            try:
                import ai_enrichment
                surface = (res or {}).get("surface") or _name(t)
                code = ((t.get("bank_transaction_code") or {}).get("code") or "").upper()
                res_ai = ai_enrichment.classify(
                    surface, ai_key, cache_key=(res or {}).get("identity_key"),
                    merchant_context=(code in _CARD_CODES))
                if res_ai:
                    # AI enrichment doesn't offer a domain — the resolver is
                    # the only stage that does.
                    result = (*res_ai, None)
            except Exception:
                pass
        if result is None:
            result = (_name(t), "other", None)
        _resolve_memo[tid] = result
        return result

    # Fallback currency for a transaction whose OWN transaction_amount carries
    # no currency code — caught live: a DNB "Overføring Innland" (domestic
    # transfer) came back from Enable Banking with no `currency` field on the
    # amount at all (card purchases always have one; this transfer type
    # apparently doesn't). _raw_amt_cur used to default that to "EUR"
    # unconditionally, so a NOK account's own internal transfer got tagged
    # EUR — the client's raw/display-currency match then failed for exactly
    # this row, and it fell through to the old double-converted (backend
    # static rate x client live rate, ~6% off) figure that every OTHER
    # transaction on the same account had already stopped doing. Default to
    # the account's own currency instead of a hardcoded one — "EUR" only when
    # the accounts genuinely disagree with each other (a real mixed-currency
    # consent), which is the one case with no single right answer anyway.
    _acct_curs = {(a.get("currency") or "").upper() for a in (accounts or [])} - {""}
    _fallback_cur = _acct_curs.pop() if len(_acct_curs) == 1 else "EUR"

    # ── flat `all` list ──
    all_rows = []
    skipped = 0
    for t in sorted(txns, key=lambda x: str(x.get("booking_date") or ""), reverse=True):
        ymd = _ymd(t.get("booking_date"))
        if ymd is None:
            skipped += 1
            continue
        canonical, cat, col, ic, sec, secc, pos, _tr, dom = _classify(t, resolve_cat, salary_refs, own_ibans)
        y, m, day = ymd
        raw_amt, raw_cur = _raw_amt_cur(t, default_cur=_fallback_cur)
        all_rows.append({
            "nm": _name(t), "mkey": (canonical or _name(t)).lower()[:24],
            "d": t["booking_date"], "wd": LT_WD[dt.date(y, m, day).weekday()][:3],
            "md": f"{LT_GEN[m]} {day}", "cat": cat, "col": col, "ic": ic,
            "sec": sec, "secc": secc, "a": round(_amt(t), 2),
            "amb": False, "badges": (["res"] if t.get("status") == "PDNG" else []),
            "pos": pos, "ts": _txn_epoch(t), "dom": dom,
            "raw": round(raw_amt, 2), "cur": raw_cur,
            # Which account this row came from (main.py stamps "_acct" =
            # the account's own uid at scan time) — used by _balance_block
            # to build each account's OWN balance series. Rides along in
            # the client's transaction feed too (all_rows is returned
            # as-is) — harmless, just the same uid the client already sees
            # on that account's own summary.
            "acct": t.get("_acct"),
        })
    if skipped:
        # Dropping a row silently is how a bank's odd date format turns into
        # "some payments are missing" with nothing to point at.
        logging.warning("dashboard: skipped %d row(s) with an unusable "
                        "booking_date", skipped)

    # ── month → day feed (latest 2 months), merging same merchant same day ──
    months = _month_feed(txns, salary_refs, resolve_cat, own_ibans,
                          default_cur=_fallback_cur)

    # ── this-week category bars ──
    week = _week(txns, salary_refs, resolve_cat, today, own_ibans)

    # ── subscriptions & bills: reuse the recurring engine's confident candidates ──
    subs = _subs(txns, corpus, own_ibans, today)

    # Stamp a "rec" badge on every row of an ACTIVE recurring merchant (same ones
    # feeding the projection), so the client's subscription pill lights up on
    # real data — but a finished/ended stream (paid-off loan, closed tax plan)
    # does NOT get the badge. Matched by the canonical merge key so it can't
    # false-positive onto unrelated merchants.
    rec_keys = {str(it["name"]).lower()[:24] for it in subs.get("items", [])
                if it.get("active") and it.get("type") != "transfer"}
    if rec_keys:
        for r in all_rows:
            if r["mkey"] in rec_keys:
                r["badges"] = r["badges"] + ["rec"]

    # Stamp each row with the SERIES id (sid) of the active recurring stream it
    # belongs to — matched by merchant key AND per-charge amount (±8%) — so a
    # user-assigned subscription name (e.g. an anonymous Apple stream → "ChatGPT")
    # is applied ONLY to that stream's charges, never to a one-off Apple purchase
    # at a different amount that merely shares the merchant.
    active_series = [(str(it["name"]).lower()[:24], float(it.get("cost") or 0),
                      it.get("sid")) for it in subs.get("items", [])
                     if it.get("active") and it.get("sid")
                     and it.get("type") != "transfer"]
    if active_series:
        for r in all_rows:
            amt = abs(r["a"])
            for mk, cost, sid in active_series:
                if r["mkey"] == mk and cost > 0 and abs(amt - cost) <= cost * 0.08:
                    r["sid"] = sid
                    break

    # ── balance ──
    balance = _balance_block(all_rows, accounts)
    recent = [p["v"] for p in balance["series"]][-26:]

    # ── anonymous classification diagnostics (aggregate counts ONLY) ──
    #
    # No merchant name, amount, or identity crosses this line — just how many
    # rows landed where. Added specifically because live testers reported
    # patterns (a cancelled sub still "active", a real one missing, a bank fee
    # not read as one) that are impossible to reason about from code alone and
    # impossible to check per-user without breaking the "your data never
    # leaves your phone" promise. This is the one place that's still true:
    # only counts, aggregated across everyone, land in Cloud Logging.
    try:
        cat_counts = Counter(r["cat"] for r in all_rows)
        sub_items = subs.get("items", [])
        logging.info(
            "dash_stats txns=%d kita=%d fees=%d subs_active=%d "
            "subs_needs_review=%d subs_total=%d top_cats=%s",
            len(all_rows),
            cat_counts.get("Kita", 0),
            cat_counts.get("Bankas, komisiniai", 0),
            sum(1 for i in sub_items if i.get("active")),
            sum(1 for i in sub_items if i.get("needsReview")),
            len(sub_items),
            dict(cat_counts.most_common(8)),
        )
    except Exception:
        pass  # diagnostics must never take the real dashboard down

    return {
        "all": all_rows,
        "months": months,
        "week": week,
        "subs": subs,
        "spark": [round(x) for x in recent],
        "balance": balance,
        # Canonical headline figures — the single source of truth every screen
        # reads so the same concept shows the same number everywhere.
        "totals": _totals(all_rows),
        # No auto/example budgets — they confused users ("where did this limit
        # come from?"). Budgets are user-created (Planning tab), with a suggested
        # limit from the user's real average spend they accept or edit.
        "budgets": {},
        # Only non-sensitive counts here — the debug fields (sample rows, salary
        # sources, income/incoming-transfer dumps) were removed so no
        # transaction-derived data leaks in the payload.
        "meta": {"count": len(txns),
                 "range": f"{min(t['booking_date'] for t in txns)}..{max(t['booking_date'] for t in txns)}"},
    }


def _merge_day(day_txns, salary_refs, resolve_cat, own_ibans=None, default_cur="EUR"):
    merged = OrderedDict()
    for t in day_txns:
        _canon, cat, col, ic, sec, secc, pos, _tr, dom = _classify(t, resolve_cat, salary_refs, own_ibans)
        key = _norm(_name(t))
        raw_amt, raw_cur = _raw_amt_cur(t, default_cur=default_cur)
        if key not in merged:
            merged[key] = {"nm": _name(t), "cat": cat, "ic": ic, "col": col,
                           "sec": sec, "secc": secc, "a": 0.0, "count": 0,
                           "badges": (["res"] if t.get("status") == "PDNG" else []),
                           "amb": False, "pos": pos, "ts": _txn_epoch(t), "dom": dom,
                           "raw": 0.0, "cur": raw_cur}
        # A merged row's "raw" figure is only meaningful when every leg shares
        # ONE currency — a same-day multi-currency merge (rare, but a Revolut
        # multi-currency account can do it) falls back to the EUR-derived "a"
        # on the client rather than silently sum unlike currencies together.
        if merged[key]["cur"] != raw_cur:
            merged[key]["cur"] = None
        merged[key]["raw"] += raw_amt
        merged[key]["a"] += _amt(t)
        merged[key]["count"] += 1
        if merged[key]["count"] > 1:
            merged[key]["ts"] = None  # several charges merged → no single time
    return merged


def _month_feed(txns, salary_refs, resolve_cat, own_ibans=None, default_cur="EUR"):
    bydate = defaultdict(list)
    for t in txns:
        bydate[t["booking_date"]].append(t)
    months = OrderedDict()
    for dtk in sorted(bydate, reverse=True):
        ymd = _ymd(dtk)
        if ymd is None:
            continue
        y, m, day = ymd
        mkey = f"{y}-{m:02d}"
        months.setdefault(mkey, {"name": LT_MON[m], "y": y, "m": m, "total": 0.0, "days": []})
        merged = _merge_day(bydate[dtk], salary_refs, resolve_cat, own_ibans,
                             default_cur=default_cur)
        # Canonical day "spent" (expenses only, refunds net down; transfers/income
        # excluded) — a positive number, matching the client + month header. Was a
        # raw signed sum that included transfers/income (the old "−2127" trap).
        daytot = sum(-x["a"] for x in merged.values() if _flow(x) in ("expense", "refund"))
        wd = LT_WD[dt.date(y, m, day).weekday()]
        months[mkey]["days"].append({
            "date": dtk, "label": f"{wd}, {day} d.", "wd": wd, "day": day,
            "total": round(daytot, 2),
            "tx": [{"nm": x["nm"], "cat": x["cat"], "ic": x["ic"], "col": x["col"],
                    "a": round(x["a"], 2), "count": x["count"] if x["count"] > 1 else 0,
                    "badges": x["badges"], "amb": x["amb"], "pos": x["pos"],
                    "ts": x["ts"], "dom": x["dom"],
                    "raw": round(x["raw"], 2), "cur": x["cur"]}
                   for x in merged.values()]})
        months[mkey]["total"] += daytot
    for mk in months:
        months[mk]["total"] = round(months[mk]["total"], 2)
    return list(months.values())[:2]


SECTION_BAR = {"Maistas, gėrimai": "green", "Transportas": "blue", "Apsipirkimas": "teal",
               "Būstas, sąskaitos": "olive", "Sveikata, sportas": "orange",
               "Pramogos": "cyan", "Finansai": "red", "Švietimas": "purple", "Kita": "indigo"}
SEC_ICON = {"Maistas, gėrimai": "food", "Transportas": "car", "Apsipirkimas": "bag",
            "Būstas, sąskaitos": "home", "Sveikata, sportas": "health", "Pramogos": "fun",
            "Finansai": "money", "Švietimas": "edu", "Kita": "money"}
SEC_ORDER = ["Maistas, gėrimai", "Transportas", "Apsipirkimas", "Būstas, sąskaitos",
             "Sveikata, sportas", "Pramogos", "Finansai", "Švietimas", "Kita"]


def _week(txns, salary_refs, resolve_cat, today, own_ibans=None):
    # Anchor to the CURRENT calendar week (today's Monday) so "this week's
    # spending" is genuinely this week, not the week of the latest transaction.
    monday = today - dt.timedelta(days=today.weekday())
    bydate = defaultdict(list)
    for t in txns:
        bydate[t["booking_date"]].append(t)
    days, wtot, gtot = [], 0.0, 0.0
    for i in range(7):
        dd = monday + dt.timedelta(days=i)
        secagg = {}
        # Money that LEFT the account on this day without being spending: a
        # transfer to a person, cash withdrawn. It is drawn on the bar — so a
        # day whose balance clearly moved is never blank — but it is added to no
        # total, so spending, categories, budgets and the savings rate are
        # untouched by it.
        #
        # Own-account moves and currency conversions are deliberately NOT
        # counted: that money never left the user, and drawing a 500 € bar for
        # SEB → Revolut would read as a 500 € spending day, which is a worse lie
        # than the empty bar this exists to fix.
        gone = 0.0
        for t in bydate.get(dd.isoformat(), []):
            _canon, cat, _col, _ic, sec, secc, _pos, is_tr, _dom = _classify(t, resolve_cat, salary_refs, own_ibans)
            if is_tr or sec in ("Pajamos", "Pervedimai"):
                a = _amt(t)
                if a < 0 and cat not in ("Savas pervedimas", "Valiutos keitimas"):
                    gone += -a
                continue
            a = _amt(t)
            # Refunds net the week down, exactly as they net the month down.
            # This loop used to skip every non-DBIT row, so week bars were GROSS
            # while every other screen was net — the same week showed two
            # different numbers depending on where you looked.
            if _flow({"sec": sec, "cat": cat, "a": a}) not in ("expense", "refund"):
                continue
            e = secagg.setdefault(sec, {"label": sec, "color": SECTION_BAR.get(sec, "indigo"),
                                        "icon": SEC_ICON.get(sec, "money"), "amount": 0.0})
            e["amount"] += -a
        cats = [secagg[l] for l in SEC_ORDER if l in secagg]
        # 2026-08-16 fix: `total` used to be summed AFTER each category was
        # floored to 0 below — so an uncoded refund (no bank-recognised
        # CARD_REFUND/CARD_CREDIT/RRTN code; _flow() only catches it via the
        # amount-sign heuristic, and "plenty of merchants don't use [refund
        # codes]" per _subs' own note) stayed in its ORIGINAL spending
        # section instead of being routed to Pajamas, got floored away
        # there, and vanished from the day/week total instead of netting it
        # down. A €25 purchase + a same-day €120 uncoded refund in
        # "Apsipirkimas" has a true net of -95 €, but the old code summed
        # max(25-120, 0)=0 for that section — the day (and the week) read
        # as if €95 of real, already-netted money simply wasn't there,
        # silently disagreeing with the client's own independent
        # _computeWeek/_sumExpenses fallback (dashboard_preview.dart), which
        # never floors and was always right. Sum the TRUE (unfloored) net
        # for the headline total; only the per-category DISPLAY amount
        # (below, a bar segment can't honestly go negative) gets floored.
        total = round(sum(c["amount"] for c in cats), 2)
        for c in cats:
            c["amount"] = round(max(c["amount"], 0.0), 2)
        # `total` stays SPENDING — every existing consumer depends on that, and
        # the month figure, categories and budget are all built on it. `gone` is
        # additional information the bar may draw; nothing sums the two but the
        # chart itself.
        days.append({"lbl": ["Pr", "An", "Tr", "Kt", "Pn", "Št", "Sk"][i], "total": total,
                     "gone": round(gone, 2),
                     "cats": cats, "dlabel": f"{LT_GEN[dd.month]} {dd.day}"})
        wtot += total
        gtot += gone
    return {"total": round(wtot, 2), "gone": round(gtot, 2), "days": days,
            "range": f"{monday.isoformat()}..{(monday + dt.timedelta(days=6)).isoformat()}"}


def _fold_name(s):
    """Group key for a payee: lowercased, de-accented, collapsed whitespace, with
    an exactly-repeated tail dropped ("Zivile Sulajeva Sulajeva" → "…sulajeva")."""
    s = re.sub(r"\s+", " ", str(s or "").strip().lower())
    w = s.split(" ")
    if len(w) >= 2 and w[-1] == w[-2]:
        w = w[:-1]
    return "".join(w).translate(str.maketrans("ąčęėįšųūž", "aceeisuuz"))


def _collapse_recurring(cands):
    """Fold multiple streams of the SAME payee into one real obligation:

      * near-equal amounts — a loan/bill booked as 399 & 398 is ONE payment
        (within ~8%);
      * INTEGER-MULTIPLE amounts — a €35.90 gym membership paid late as €71.80
        (2 months at once) is still one €35.90/mo obligation, not €71.80. The
        larger charge is treated as covering N periods.

    Genuinely distinct amounts under one payee (Apple 9.99 + 2.99 — not near-equal
    and not a clean multiple) stay separate. Any ACTIVE leg keeps the merged
    stream active (a recent catch-up proves a "late" base is still live), and the
    unit (smallest) amount becomes the monthly.
    """
    by_name = defaultdict(list)
    for c in cands:
        by_name[_fold_name(c.get("name", "—"))].append(c)
    out = []
    for _key, group in by_name.items():
        # smallest amount first → the unit/base is kept, multiples fold into it
        group.sort(key=lambda c: float(c.get("monthlyAmount") or c.get("cost") or 0))
        kept = []  # [dict, base_monthly]
        for c in group:
            m = float(c.get("monthlyAmount") or c.get("cost") or 0)
            folded = False
            for k in kept:
                base = k[1]
                if base <= 0:
                    continue
                ratio = m / base
                mult = round(ratio)
                near_equal = abs(ratio - 1) <= 0.08
                catch_up = 2 <= mult <= 6 and abs(ratio - mult) <= 0.08
                # A price CHANGE (Netflix 9.99 → 10.99): same payee & cadence, a
                # plausible non-multiple ratio, and exactly ONE leg still active —
                # the other is the superseded old price that ended. Without this the
                # two prices counted as TWO concurrent subscriptions (~double). Two
                # genuinely concurrent subs (Apple 9.99 + 2.99, both active) are NOT
                # merged because neither is inactive.
                same_cadence = (c.get("billingCycle", "monthly")
                                == (k[0].get("cycle") or "monthly"))
                one_active = (bool(k[0]["active"])
                              != (c.get("status") == "active"))
                price_change = (not near_equal and not catch_up and same_cadence
                                and one_active and 0.34 <= ratio <= 3.0)
                if near_equal or catch_up or price_change:
                    # a 2× charge covers ~2 periods; a price change is one period
                    k[0]["occ"] += int(c.get("occurrences", 0)) * (
                        mult if catch_up else 1)
                    if c.get("status") == "active":
                        k[0]["status"], k[0]["active"] = "active", True
                    if (c.get("lastChargeDate") or "") > (k[0]["lastCharge"] or ""):
                        k[0]["lastCharge"] = c.get("lastChargeDate")
                    # Any uncertain leg makes the merged obligation uncertain.
                    if c.get("needsReview"):
                        k[0]["needsReview"] = True
                    # On a price change, the obligation is the CURRENTLY ACTIVE
                    # price — adopt the incoming leg's amount when it is the active one.
                    if price_change and c.get("status") == "active":
                        k[0]["monthly"] = round(m, 2)
                        k[0]["cost"] = round(float(c.get("cost", 0)), 2)
                        k[1] = m
                    folded = True
                    break
            if folded:
                continue
            kept.append([{
                "name": c.get("name", "—"),
                "monthly": round(m, 2),
                "cost": round(float(c.get("cost", 0)), 2),
                "cycle": c.get("billingCycle", "monthly"),
                "cadence": c.get("cadenceLabel"),   # weekly/monthly/… or "~Nd"/"once"
                "status": c.get("status", "active"),
                "active": c.get("status") == "active",
                "type": c.get("type", "subscription"),
                "occ": int(c.get("occurrences", 0)),
                "lastCharge": c.get("lastChargeDate"),
                "category": c.get("category"),
                # Recurring-shaped but uncertain (unknown merchant / KB 'possible').
                # Still counted, but the client surfaces these in a review queue so
                # the user can confirm ("yes, my rent") or remove ("not a sub").
                "needsReview": bool(c.get("needsReview")),
            }, m])
        out.extend(k[0] for k in kept)
    return out


def _amount_band(cost) -> int:
    """A coarse, order-of-magnitude band for an amount.

    Bands are geometric (each ~3.2x the previous), so the tolerance scales with
    the amount instead of being a fixed number of cents that means everything at
    3 EUR and nothing at 300 EUR.

    The width is set by what has to survive: a subscription's price rise. Narrower
    bands (1.78x) looked tidier and failed the real case — 12.99 -> 14.99 straddled
    a boundary and moved the id. A stream now has to get more than three times
    dearer before it loses its identity, while 2.99 and 19.95 at the same merchant
    still land apart.
    """
    amount = abs(float(cost or 0))
    if amount < 0.01:
        return 0
    return int(round(math.log10(amount) * 2))


def _series_id(name, cadence, cost):
    """Stable identity for ONE recurring stream, so a user's decisions about it —
    a name they typed, "don't count this", "this one is still active" — survive
    every re-scan.

    Keyed by merchant + cadence + amount BAND, not exact cents. Exact cents made
    the id move under the user twice over:

      * `cost` is the AVERAGE per-charge amount, so it shifts as history arrives.
        Connecting a bank runs a fast 3-month scan and then a deeper 12-month one;
        the deeper scan changed the average, changed the id, and every verdict
        recorded against the old id stopped matching. That is why the "check your
        recurring payments" sheet asked the same questions twice.
      * a price change is ONE subscription at a new price (see test_price_change),
        but it moved the id — so a payment the user had excluded silently came
        back the month their subscription got more expensive.

    Two Apple subscriptions at genuinely different prices still land in different
    bands and stay separately named. Two within ~78% of each other now share an
    id; that is the deliberate trade — bank data cannot tell them apart anyway,
    and losing a user's decision is the worse failure."""
    key = re.sub(r"\s+", " ", str(name or "—").strip().lower())[:24]
    return f"{key}|{cadence or ''}|b{_amount_band(cost)}"


def _subs(txns, corpus=None, own_ibans=None, today=None):
    """Confident recurring streams + the ACTIVE monthly projection.

    ``total`` is the real monthly COMMITMENT: the sum of the monthly-equivalent
    amount of every stream that is still ACTIVE (recent enough for its own
    cadence) AND a genuine bill/subscription — never a transfer, never a
    finished/late stream. A paid-off loan or a finished tax plan stays in
    ``items`` (flagged ``status``) but drops out of the total, so the projection
    reflects future commitments — not history (Plaid/Tink lifecycle model). Each
    item is monthly-normalized (a yearly bill counts as /12), so the total is a
    true €/month figure whatever the billing frequency.
    """
    try:
        # Reuse build_dashboard's corpus (same filtered txns → same corpus) so
        # detect_recurring doesn't rebuild it a third time. No output change.
        det = detect_recurring(txns, corpus=corpus, own_ibans=own_ibans, today=today)
    except Exception:
        return {"items": [], "total": 0, "activeCount": 0}
    raw = [c for c in det.get("candidates", [])
           if c.get("confident") and c.get("occurrences", 0) >= 2
           and c.get("cost", 0) > 0]
    items = _collapse_recurring(raw)
    # Transfers (person-to-person, own-account moves, currency exchange) are NEVER
    # bills or subscriptions and must never appear in the recurring manager or the
    # "review your recurring payments" inbox — showing a person's name there is the
    # exact broken-feeling bug. They are already out of `total`; drop them from
    # `items` too so a person is never surfaced in a recurring context at all.
    items = [it for it in items if it.get("type") != "transfer"]
    for it in items:
        it["sid"] = _series_id(it.get("name"), it.get("cadence"), it.get("cost"))
    active = [it for it in items if it["active"]]
    total = round(sum(it["monthly"] for it in active), 2)
    # active first, then by monthly cost
    items.sort(key=lambda x: (not x["active"], -x["monthly"]))
    return {"items": items, "total": total, "activeCount": len(active)}


def _flow(r):
    """Canonical money bucket for a classified row: expense / refund / income /
    transfer.

    Direction is the authoritative signal for income vs expense — a stray
    incoming credit the classifier couldn't name (e.g. a one-off payment, or
    salary before the ≥3-month rule kicks in) is money IN, so it must count as
    income, never as a negative expense. Only the money-movement flows
    (transfers) and refunds are special-cased first."""
    if r["sec"] == "Pervedimai":
        return "transfer"       # own-account / P2P / exchange / cash / top-up
    if r["cat"] == "Grąžinimas":
        return "refund"         # money back — reduces spend, is NOT income
    # Money coming back from a RECOGNISED spending category is a refund, whatever
    # the bank called it. Only three transaction codes are recognised as refunds
    # (_REFUND_CODES), and plenty of merchants don't use them — a returned jacket
    # then landed here as "income", so `net = income − expenses` was wrong by
    # twice the refund and the savings rate was inflated at both ends.
    #
    # BUT "Kita" is not a spending category — it's "we couldn't attribute this".
    # An incoming credit we couldn't tie to any merchant is far more likely money
    # IN — freelance, interest, a one-off payment — than a refund (refunds come
    # from places you shopped, which we'd have recognised). Treating those as
    # refunds subtracted them from expenses and added 0 to income, deflating both
    # sides and distorting the savings rate. So an unattributed credit is income.
    # (Person-to-person and own-account credits are already "Pervedimai"; genuine
    # income lands in "Pajamos" — neither reaches here.)
    if r["a"] > 0 and r["sec"] not in ("Pajamos", "Pervedimai", "Kita"):
        return "refund"
    return "income" if r["a"] > 0 else "expense"


def _totals(all_rows):
    """THE single source of truth for headline money figures.

    Every screen must read these instead of re-summing `all` with its own rule,
    so the same concept shows the same number everywhere (no "250 here / 230
    there"). EUR only for now — multi-currency FX is a separate step.

    Rules:
      * expense  = genuine spending outflow; a REFUND nets it down
      * income   = genuine incoming (salary / real credits); NOT refunds
      * transfer = own-account / P2P / exchange / cash / top-up — EXCLUDED from
                   both income and expenses (moving money ≠ earning/spending)
      * net      = income − expenses
    ``byCategory`` and ``bySection`` sum EXACTLY to ``expenses`` (refunds sit in
    a dedicated "Grąžinimai" bucket). Returned per month ('YYYY-MM') + 'all'.
    """
    def _blank():
        return {"expenses": 0.0, "income": 0.0,
                "cats": defaultdict(float), "secs": defaultdict(float)}

    periods = defaultdict(_blank)
    agg = _blank()

    def _add(b, flow, r):
        a = r["a"]
        if flow in ("expense", "refund"):
            spend = -a  # debit a<0 → +spend; refund credit a>0 → −spend (nets down)
            b["expenses"] += spend
            b["cats"][r["cat"]] += spend
            b["secs"]["Grąžinimai" if flow == "refund" else r["sec"]] += spend
        elif flow == "income":
            b["income"] += a

    for r in all_rows:
        flow = _flow(r)
        _add(agg, flow, r)
        _add(periods[r["d"][:7]], flow, r)

    def _finalize(b):
        exp = round(b["expenses"], 2)
        inc = round(b["income"], 2)
        return {
            "expenses": exp,
            "income": inc,
            "net": round(inc - exp, 2),
            "byCategory": sorted(([c, round(v, 2)] for c, v in b["cats"].items()),
                                 key=lambda x: -x[1]),
            "bySection": sorted(([s, round(v, 2)] for s, v in b["secs"].items()),
                                key=lambda x: -x[1]),
        }

    return {"all": _finalize(agg),
            "months": {mk: _finalize(b) for mk, b in periods.items()}}


def _daily_cumulative_series(rows, end_amount):
    """The shared "walk backward from today's balance" math both the combined
    and the per-account series (below) use — factored out so per-account
    isn't a second, drifting copy of the same logic."""
    by_day = OrderedDict()
    for r in sorted(rows, key=lambda x: x["d"]):
        by_day[r["d"]] = by_day.get(r["d"], 0.0) + r["a"]
    run, cum = 0.0, OrderedDict()
    for dtk, tot in by_day.items():
        run += tot
        cum[dtk] = run
    base = end_amount - run if cum else end_amount
    return [{"d": k, "v": round(base + v, 2)} for k, v in cum.items()]


def _balance_block(all_rows, accounts):
    """Daily cumulative series anchored so the end == summed account balance.

    Per-account balances are converted to EUR (see _to_eur) so a mixed-currency
    consent sums correctly; the original currency is kept as `origCurrency`.

    2026-08-16: each account also gets its OWN series — same walk-backward
    math, filtered to just that account's rows (tagged "acct" = the uid
    `t["_acct"]` was stamped with at scan time — see main.py's
    _scan_one_account) and anchored to that account's OWN current amount
    instead of the household total. Lets the client show "what happened in
    THIS bank" when a user taps one account chip, instead of always falling
    back to the combined household chart — a tap on SEB used to open the
    exact same graph as a tap on Revolut, which read as broken once there
    were two real banks connected instead of one.
    """
    accounts = [
        {**a,
         "amount": round(_to_eur(float(a.get("amount") or 0), a.get("currency")), 2),
         # Original native-currency balance, preserved BEFORE "amount" above
         # overwrites it with the EUR conversion — same "raw" convention the
         # transaction rows already use, so the client can show this account's
         # OWN figure directly when its display currency matches, instead of
         # re-deriving it by reconverting the EUR amount with a live rate that
         # disagrees with the static one used above (the same ~6% drift
         # already fixed for transaction rows, never applied to balances).
         "raw": a.get("amount"),
         "origCurrency": a.get("currency"),
         "currency": "EUR"}
        for a in (accounts or [])
    ]
    end = round(sum(float(a.get("amount") or 0) for a in accounts), 2) if accounts else 0.0
    series = _daily_cumulative_series(all_rows, end)
    for a in accounts:
        uid = a.get("uid")
        own_rows = [r for r in all_rows if uid and r.get("acct") == uid]
        # No rows tagged for this account (uid missing on old cached data, or
        # a brand-new account with no transactions yet) — no per-account
        # series rather than a flat line that would just repeat today's
        # balance backward and look like real history.
        a["series"] = _daily_cumulative_series(own_rows, a["amount"]) if own_rows else []
    return {
        "current": end,
        "series": series,
        "accounts": accounts or [],
        "start": series[0]["d"] if series else None,
        "end": series[-1]["d"] if series else None,
        "days": len(series),
    }
