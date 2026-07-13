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
import re
from collections import OrderedDict, defaultdict

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
    "restaurant":    ("Kavinės, restoranai", "food",      "dining",  "Maistas, gėrimai",   "green"),
    "food":          ("Kavinės, restoranai", "food",      "dining",  "Maistas, gėrimai",   "green"),
    "cafe":          ("Kavinės, restoranai", "food",      "coffee",  "Maistas, gėrimai",   "green"),
    "alcohol":       ("Alkoholis, tabakas",  "food",      "bottle",  "Maistas, gėrimai",   "green"),
    "fuel":          ("Kuras",               "fuel",      "fuel",    "Transportas",        "blue"),
    "gas_station":   ("Kuras",               "fuel",      "fuel",    "Transportas",        "blue"),
    "transport":     ("Transportas",         "transport", "taxi",    "Transportas",        "blue"),
    "taxi":          ("Taksi",               "transport", "taxi",    "Transportas",        "blue"),
    "automotive":    ("Automobilis",         "transport", "taxi",    "Transportas",        "blue"),
    "parking":       ("Parkavimas",          "transport", "taxi",    "Transportas",        "blue"),
    "retail":        ("Apsipirkimas",        "shopping",  "monitor", "Apsipirkimas",       "teal"),
    "shopping":      ("Apsipirkimas",        "shopping",  "monitor", "Apsipirkimas",       "teal"),
    "electronics":   ("Elektronika, prekės", "shopping",  "monitor", "Apsipirkimas",       "teal"),
    "clothing":      ("Drabužiai",           "shopping",  "monitor", "Apsipirkimas",       "teal"),
    "pharmacy":      ("Vaistinė",            "health",    "health",  "Sveikata, sportas",  "orange"),
    "health":        ("Sveikata",            "health",    "health",  "Sveikata, sportas",  "orange"),
    "fitness":       ("Sportas",             "fitness",   "health",  "Sveikata, sportas",  "orange"),
    "taxes":         ("Mokesčiai",           "taxes",     "doc",     "Finansai",           "red"),
    "banking":       ("Bankas, komisiniai",  "finance",   "money",   "Finansai",           "red"),
    "finance":       ("Bankas, komisiniai",  "finance",   "money",   "Finansai",           "red"),
    "insurance":     ("Draudimas",           "vehicle",   "shield",  "Būstas, sąskaitos",  "olive"),
    "connectivity":  ("Ryšys, internetas",   "housing",   "home",    "Būstas, sąskaitos",  "olive"),
    "internet":      ("Ryšys, internetas",   "housing",   "home",    "Būstas, sąskaitos",  "olive"),
    "utilities":     ("Komunaliniai",        "housing",   "home",    "Būstas, sąskaitos",  "olive"),
    "housing":       ("Būstas, nuoma",       "housing",   "house",   "Būstas, sąskaitos",  "olive"),
    "entertainment": ("Pramogos",            "entertainment", "fun", "Pramogos",           "cyan"),
    "software":      ("Prenumeratos",        "entertainment", "monitor", "Pramogos",       "cyan"),
    "travel":        ("Kelionės",            "entertainment", "fun", "Pramogos",           "cyan"),
    "education":     ("Mokslas",             "invest",    "doc",     "Švietimas",          "purple"),
    "childcare":     ("Vaikai, ugdymas",     "invest",    "doc",     "Švietimas",          "purple"),
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
      "google storage", "delfiplius", "delfi plius"), _SUBS),
    (("netflix", "spotify", "hbo", "max help", "disney", "viaplay", "go3", "twitch",
      "steam", "playstation", "xbox", "nintendo", "cinema", "forum cinemas", "apollo kin"), _ENTM),
    (("oanda", "trading212", "trading 212", "fxflat", "swissquote", "interactive brokers",
      "photon global", "revolut trading", "etoro", "binance", "coinbase"), _INVEST),
    (("vmi ", "valstybine mokesciu", "sodra", "epaslaug", "e.paslaug", "regitra",
      "mokesciu inspekcija"), _TAX),
    (("telia", "bite", "tele2", "pildyk", "ignitis", "eso ", "vandenys",
      "elektros skyr", "teo ", "cgates", "init"), _UTIL),
    (("senukai", "kesko", "verslo vartai", "varlė", "varle", "pigu", "technorama",
      "avitela", "kilobaitas", "elektromarkt", "topocentras", "media markt"), _ELEC),
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
    (("maxima", "rimi", "iki ", "lidl", "aibė", "aibe", "norfa", "prisma", "coop",
      "rema 1000", "minipreco", "minimani", "joker ", "t-market", "grocer",
      "maisto prek", "parduotuv", "spar ", "hemkop", "kiwi ", "meny "), _GROC),
    (("mcdonald", "hesburger", "kfc", "burger king", "litriukas", "pocien", "skoniai",
      "birzu duona", "duona myli", "kavin", "restoran", "pizza", "sushi", "coffee",
      "caffe", "cili", "charlie", "vero cafe", "baras", "bardakas", " pub", "uzeiga",
      "bistro", "delano", "subway", "bhaji", "kebab", "kepyk", "prezo", "mcdroval"), _DINE),
]

_FINANCE_HINTS = ["mogo", "general financing", "sb lizing", "swedbank lizing",
                  "citadele faktoring", "luminor lizing", "paskola", "lizing"]
_HOUSING_HINTS = ["artus", "nuoma", "rent", "busto adm", "namu prieziur"]


def _amt(t):
    v = float((t.get("transaction_amount") or {}).get("amount") or 0)
    return v if t.get("credit_debit_indicator") == "CRDT" else -v


def _name(t):
    if t.get("credit_debit_indicator") == "DBIT":
        n = (t.get("creditor") or {}).get("name")
    else:
        n = (t.get("debtor") or {}).get("name")
    return (n or (t.get("remittance_information") or [""])[0] or "—").strip()


def _norm(n):
    return re.sub(r"\s+", " ", re.sub(r"[^a-z ]", "", n.lower())).strip()[:16]


_COMPANY_MARKERS = ["uab", "mb", "ab", "vsi", "všį", "grupe", "grupė", "ltd", "llc",
                    "oy", "oü", " as ", "inc", "gmbh", "sia", "ou", "corp", ".lt", ".com"]


def _is_person_name(n):
    """A counterparty that looks like an individual (P2P transfer). Case-insensitive
    — SEB sends surnames lowercased ("Milda dirsiene") and names uppercased
    ("INGRIDA ČELEDINĖ"), both are people."""
    parts = n.split()
    if len(parts) not in (2, 3):
        return False
    if any(k in n.lower() for k in _COMPANY_MARKERS):
        return False
    return all(re.sub(r"[-']", "", p).isalpha() and len(p) > 1 for p in parts)


# ── bank_transaction_code vocabularies (Revolut uses its own names; SEB and most
#    banks use ISO 20022 4-letter codes). Normalised so classification is
#    bank-agnostic. ──
_EXCHANGE_CODES = {"EXCHANGE"}
_REFUND_CODES = {"CARD_REFUND", "CARD_CREDIT", "RRTN"}
_TOPUP_CODES = {"TOPUP"}
_CASH_CODES = {"CWDL", "ATM", "CSHW"}
_FEE_CODES = {"MDOP", "MCOP", "CHRG", "COMM"}
# credit transfers in/out (P2P, SEPA) — NOT card purchases
_XFER_CODES = {"ICDT", "RCDT", "MSCT", "ISCT", "RSCT", "ICHQ", "RCHQ", "TRANSFER", "SCT"}
_FEE_HINTS = ["komisin", "aptarnavim", "paslaugų planas", "paslaugu planas",
              "mokestis už", "sąskaitos mokest", "account fee", "service fee"]


def _salary_sources(txns):
    """Normalised counterparty names that pay you like an EMPLOYER: a recurring
    (>=3 distinct months), substantial, NON-person incoming credit — in whatever
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
        if code in _EXCHANGE_CODES | _REFUND_CODES | _TOPUP_CODES:
            continue  # conversions / refunds / top-ups are not employer pay
        if _amt(t) < 300:
            continue
        name = _name(t)
        if _is_person_name(name):
            continue  # a person sending you money is not an employer
        months_by[_norm(name)].add(t["booking_date"][:7])
    return {k for k, mos in months_by.items() if len(mos) >= 3}


def _classify(t, resolve_cat, salary_refs):
    """Return (canonical, cat_lt, col, icon, section, section_color, pos, is_transfer).

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

    # currency exchange is ALWAYS just a conversion of your own money — never
    # income and never spending (moving money between your own currencies).
    if code in _EXCHANGE_CODES:
        return (name, "Valiutos keitimas", "transfer", "swap", "Pervedimai", "indigo", amt > 0, True)
    if code in _REFUND_CODES:
        return (name, "Grąžinimas", "income", "swap", "Pajamos", "amber", True, False)
    if code in _TOPUP_CODES:
        return (name, "Sąskaitos papildymas", "transfer", "swap", "Pervedimai", "indigo", amt > 0, True)
    if code in _CASH_CODES:
        return (name, "Grynieji", "transfer", "swap", "Pervedimai", "indigo", amt > 0, True)

    # credit transfers (SEPA / P2P, in or out) — before merchant matching, so a
    # person is never sent to the merchant resolver
    if code in _XFER_CODES or (not code and _is_person_name(name)):
        # a recurring, substantial, non-person INCOMING transfer from the same
        # source = your salary (booked on the real payday, in whatever currency).
        if amt > 0 and _norm(name) in salary_refs:
            return (name, "Atlyginimas", "income", "income", "Pajamos", "amber", True, False)
        if any(k in nl for k in _FINANCE_HINTS):
            return (name, "Paskola, lizingas", "finance", "money", "Finansai", "red", amt > 0, False)
        if any(k in nl for k in _HOUSING_HINTS):
            return (name, "Būstas, nuoma", "housing", "house", "Būstas, sąskaitos", "olive", amt > 0, False)
        if _is_person_name(name):
            return (name, "Asmeninis pervedimas", "transfer", "person", "Pervedimai", "indigo", amt > 0, True)
        return (name, "Pervedimas", "transfer", "swap", "Pervedimai", "indigo", amt > 0, True)

    # known merchant by name (BEFORE the fee check, so an oddly-coded Apple/Google
    # — e.g. MCOP/MDOP — isn't swallowed as a bank fee)
    for kws, mapped in NAME_OVERRIDES:
        if any(k in nl for k in kws):
            cat_lt, col, ic, sec, secc = mapped
            return (name, cat_lt, col, ic, sec, secc, amt > 0, False)

    # bank fees / charges
    if code in _FEE_CODES or any(k in nl for k in _FEE_HINTS):
        return (name, "Bankas, komisiniai", "finance", "money", "Finansai", "red", amt > 0, False)

    # ── unknown business → resolver (KB first, global index fallback) ──
    canonical, category = resolve_cat(t)
    cat_lt, col, ic, sec, secc = CAT_MAP.get((category or "other").lower(), OTHER)
    return (canonical or name, cat_lt, col, ic, sec, secc, amt > 0, False)


def build_dashboard(transactions, accounts, today=None, ai_key=None):
    """transactions: deduped Enable Banking list. accounts: [{name, balance, sub,
    icon, currency}]. ai_key: Anthropic key when the user opted into AI
    enrichment (Stage 3); None disables it. Returns the dash_data dict."""
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

    def resolve_cat(t):
        # Stage 2: deterministic resolver (KB → offline global index).
        try:
            _, hit, _ = resolver.resolve_hit(t, corpus)
            if hit:
                return hit[0], hit[2]  # canonical_name, category
        except Exception:
            pass
        # Stage 3: AI enrichment (opt-in only) for the unresolved business tail.
        # resolve_cat is reached ONLY from the merchant branch, so this is never a
        # person/P2P name; ai_enrichment also guards against person names + caches.
        if ai_key:
            try:
                import ai_enrichment
                res = ai_enrichment.classify(_name(t), ai_key)
                if res:
                    return res
            except Exception:
                pass
        return _name(t), "other"

    # ── flat `all` list ──
    all_rows = []
    sample = []  # DEBUG: (name, code, final cat/section) to inspect sorting
    for t in sorted(txns, key=lambda x: x["booking_date"], reverse=True):
        canonical, cat, col, ic, sec, secc, pos, _tr = _classify(t, resolve_cat, salary_refs)
        if len(sample) < 30:
            sample.append({
                "nm": _name(t)[:28],
                "code": (t.get("bank_transaction_code") or {}).get("code"),
                "cat": cat, "sec": sec,
            })
        y, m, day = map(int, t["booking_date"].split("-"))
        all_rows.append({
            "nm": _name(t), "mkey": (canonical or _name(t)).lower()[:24],
            "d": t["booking_date"], "wd": LT_WD[dt.date(y, m, day).weekday()][:3],
            "md": f"{LT_GEN[m]} {day}", "cat": cat, "col": col, "ic": ic,
            "sec": sec, "secc": secc, "a": round(_amt(t), 2),
            "amb": False, "badges": (["res"] if t.get("status") == "PDNG" else []),
            "pos": pos,
        })

    # ── month → day feed (latest 2 months), merging same merchant same day ──
    months = _month_feed(txns, salary_refs, resolve_cat)

    # ── this-week category bars ──
    week = _week(txns, salary_refs, resolve_cat, today)

    # ── subscriptions & bills: reuse the recurring engine's confident candidates ──
    subs = _subs(txns)

    # ── balance ──
    balance = _balance_block(all_rows, accounts)
    recent = [p["v"] for p in balance["series"]][-26:]

    return {
        "all": all_rows,
        "months": months,
        "week": week,
        "subs": subs,
        "spark": [round(x) for x in recent],
        "balance": balance,
        "budgets": {"Maisto prekės": 390.0, "Kavinės, restoranai": 150.0,
                    "Kuras": 220.0, "Alkoholis, tabakas": 120.0},
        "meta": {"count": len(txns),
                 "range": f"{min(t['booking_date'] for t in txns)}..{max(t['booking_date'] for t in txns)}",
                 "sample": sample},
    }


def _merge_day(day_txns, salary_refs, resolve_cat):
    merged = OrderedDict()
    for t in day_txns:
        _canon, cat, col, ic, sec, secc, pos, _tr = _classify(t, resolve_cat, salary_refs)
        key = _norm(_name(t))
        if key not in merged:
            merged[key] = {"nm": _name(t), "cat": cat, "ic": ic, "col": col,
                           "sec": sec, "secc": secc, "a": 0.0, "count": 0,
                           "badges": (["res"] if t.get("status") == "PDNG" else []),
                           "amb": False, "pos": pos}
        merged[key]["a"] += _amt(t)
        merged[key]["count"] += 1
    return merged


def _month_feed(txns, salary_refs, resolve_cat):
    bydate = defaultdict(list)
    for t in txns:
        bydate[t["booking_date"]].append(t)
    months = OrderedDict()
    for dtk in sorted(bydate, reverse=True):
        y, m, day = map(int, dtk.split("-"))
        mkey = f"{y}-{m:02d}"
        months.setdefault(mkey, {"name": LT_MON[m], "y": y, "m": m, "total": 0.0, "days": []})
        merged = _merge_day(bydate[dtk], salary_refs, resolve_cat)
        daytot = sum(x["a"] for x in merged.values())
        wd = LT_WD[dt.date(y, m, day).weekday()]
        months[mkey]["days"].append({
            "date": dtk, "label": f"{wd}, {day} d.", "wd": wd, "day": day,
            "total": round(daytot, 2),
            "tx": [{"nm": x["nm"], "cat": x["cat"], "ic": x["ic"], "col": x["col"],
                    "a": round(x["a"], 2), "count": x["count"] if x["count"] > 1 else 0,
                    "badges": x["badges"], "amb": x["amb"], "pos": x["pos"]}
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


def _week(txns, salary_refs, resolve_cat, today):
    latest = max(t["booking_date"] for t in txns)
    ly, lm, ld = map(int, latest.split("-"))
    d0 = dt.date(ly, lm, ld)
    monday = d0 - dt.timedelta(days=d0.weekday())
    bydate = defaultdict(list)
    for t in txns:
        bydate[t["booking_date"]].append(t)
    days, wtot = [], 0.0
    for i in range(7):
        dd = monday + dt.timedelta(days=i)
        secagg = {}
        for t in bydate.get(dd.isoformat(), []):
            if t.get("credit_debit_indicator") != "DBIT":
                continue
            _canon, _cat, _col, _ic, sec, secc, _pos, is_tr = _classify(t, resolve_cat, salary_refs)
            if is_tr or sec in ("Pajamos", "Pervedimai"):
                continue
            e = secagg.setdefault(sec, {"label": sec, "color": SECTION_BAR.get(sec, "indigo"),
                                        "icon": SEC_ICON.get(sec, "money"), "amount": 0.0})
            e["amount"] += -_amt(t)
        cats = [secagg[l] for l in SEC_ORDER if l in secagg]
        for c in cats:
            c["amount"] = round(c["amount"], 2)
        total = round(sum(c["amount"] for c in cats), 2)
        days.append({"lbl": ["Pr", "An", "Tr", "Kt", "Pn", "Št", "Sk"][i], "total": total,
                     "cats": cats, "dlabel": f"{LT_GEN[dd.month]} {dd.day}"})
        wtot += total
    return {"total": round(wtot, 2), "days": days,
            "range": f"{monday.isoformat()}..{(monday + dt.timedelta(days=6)).isoformat()}"}


def _subs(txns):
    try:
        det = detect_recurring(txns)
    except Exception:
        return {"items": [], "total": 0}
    items = []
    for c in det.get("candidates", []):
        # only confident, money-out recurring (not one-off residuals)
        if c.get("confident") and c.get("cost", 0) > 0 and c.get("occurrences", 0) >= 2:
            items.append([c.get("name", "—"), round(float(c["cost"]), 2)])
    items.sort(key=lambda x: -x[1])
    return {"items": items, "total": round(sum(a for _, a in items), 2)}


def _balance_block(all_rows, accounts):
    """Daily cumulative series anchored so the end == summed account balance."""
    end = round(sum(float(a.get("amount") or 0) for a in accounts), 2) if accounts else 0.0
    by_day = OrderedDict()
    for r in sorted(all_rows, key=lambda x: x["d"]):
        by_day[r["d"]] = by_day.get(r["d"], 0.0) + r["a"]
    run, cum = 0.0, OrderedDict()
    for dtk, tot in by_day.items():
        run += tot
        cum[dtk] = run
    base = end - run if cum else end
    series = [{"d": k, "v": round(base + v, 2)} for k, v in cum.items()]
    return {
        "current": end,
        "series": series,
        "accounts": accounts or [],
        "start": series[0]["d"] if series else None,
        "end": series[-1]["d"] if series else None,
        "days": len(series),
    }
