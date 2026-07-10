"""Seed the Firestore ``merchants`` collection from ``merchants_seed.json``.

Maps the flat type-lists in the JSON (subscription / bill / never_subscription /
possible_subscription) onto merchant docs (see docs/VAULTIE_3.0_PLAN.md and
merchant_db.py). Categories aren't in the source file, so they're guessed from
the merchant name; ``type`` is the primary axis and comes straight from the list.

Run via the guarded ``seed_merchants`` HTTP function in main.py.
"""

import json
import os
import re

_SEED_PATH = os.path.join(os.path.dirname(__file__), "merchants_seed.json")

# list name -> merchant type stored in the DB
_LIST_TYPE = {
    "subscription": "subscription",
    "bill": "bill",
    "never_subscription": "frequent",
    "possible_subscription": "possible",
}

# Ordered (keyword, category) for guessing a secondary category from the name.
_CAT_KEYWORDS = [
    ("draudim", "insurance"), ("insurance", "insurance"), ("gjensidige", "insurance"),
    ("compensa", "insurance"), ("seesam", "insurance"), ("balcia", "insurance"),
    ("balta", "insurance"), ("ergo", "insurance"), ("bta", "insurance"),
    ("pzu", "insurance"), ("lamie", "insurance"), ("inges", "insurance"),
    ("telia", "connectivity"), ("tele2", "connectivity"), ("bit", "connectivity"),
    ("pildyk", "connectivity"), ("cgates", "connectivity"), ("init", "connectivity"),
    ("elisa", "connectivity"), ("lmt", "connectivity"), ("emt", "connectivity"),
    ("tet", "connectivity"), ("lattelecom", "connectivity"), ("home3", "connectivity"),
    ("delta", "connectivity"),
    ("ignitis", "utilities"), ("eso", "utilities"), ("lesto", "utilities"),
    ("vanden", "utilities"), ("vesi", "utilities"), ("energ", "utilities"),
    ("šilum", "utilities"), ("silum", "utilities"), ("sadales", "utilities"),
    ("latvenergo", "utilities"), ("elering", "utilities"), ("siltums", "utilities"),
    ("soojus", "utilities"), ("tikls", "utilities"),
    ("paskol", "finance"), ("lizing", "finance"), ("leasing", "finance"),
    ("mogo", "finance"), ("bigbank", "finance"), ("ferratum", "finance"),
    ("credit", "finance"), ("saldo", "finance"), ("inbank", "finance"),
    ("bank", "finance"), ("citadele", "finance"), ("lhv", "finance"),
    ("signet", "finance"), ("luminor", "finance"), ("swedbank", "finance"),
    ("bankas", "finance"),
    ("administrat", "housing"), ("bendrija", "housing"), ("daugiabu", "housing"),
    ("namo", "housing"), ("šildym", "housing"), ("sildym", "housing"),
    ("aws", "entertainment"), ("azure", "entertainment"), ("cloud", "entertainment"),
    ("stripe", "entertainment"), ("montonio", "entertainment"),
    ("gym", "health"), ("fitness", "health"), ("sport", "health"),
]


def _guess_category(name: str, mtype: str) -> str:
    low = name.lower()
    for needle, cat in _CAT_KEYWORDS:
        if needle in low:
            return cat
    if mtype in ("subscription", "possible"):
        return "entertainment"  # most subscriptions are digital services
    if mtype == "frequent":
        return "other"
    return "other"  # bills with no keyword hit


def _key(raw: str, used: set) -> str:
    base = re.sub(r"[^a-z0-9]+", "", raw.lower()) or "m"
    key = base[:40]
    i = 2
    while key in used:
        key = f"{base[:38]}{i}"
        i += 1
    used.add(key)
    return key


def _display(raw: str) -> str:
    # Title-case words, keep short tokens/domains readable.
    parts = raw.split()
    out = []
    for p in parts:
        out.append(p if (p.isupper() and len(p) <= 4) else p.capitalize())
    return " ".join(out)


def build_docs(data: dict):
    """Return list of (key, doc) for every merchant string in the seed file."""
    used = set()
    docs = []
    for list_name, mtype in _LIST_TYPE.items():
        for raw in data.get("merchants", {}).get(list_name, []):
            raw = str(raw).strip()
            if not raw:
                continue
            alias = raw.lower()
            doc = {
                "displayName": _display(raw),
                "type": mtype,
                "category": _guess_category(raw, mtype),
                "logoDomain": None,
                "aliases": [alias],
                "matchMode": "word" if len(alias) <= 4 else "substring",
                "source": "curated",
                "status": "active",
                "verifiedCount": 0,
            }
            docs.append((_key(raw, used), doc))
    return docs


def seed():
    """Write all merchant docs + the detection rules config to Firestore."""
    from firebase_admin import firestore
    with open(_SEED_PATH, encoding="utf-8") as f:
        data = json.load(f)
    db = firestore.client()
    docs = build_docs(data)

    written = 0
    batch = db.batch()
    col = db.collection("merchants")
    for i, (key, doc) in enumerate(docs, 1):
        batch.set(col.document(key), doc)
        written += 1
        if i % 400 == 0:  # Firestore batch limit is 500
            batch.commit()
            batch = db.batch()
    batch.commit()

    # Store the tunable rules alongside the merchants.
    if "rules" in data:
        db.collection("config").document("detection").set(data["rules"])

    return {"merchants": written, "version": data.get("version")}
