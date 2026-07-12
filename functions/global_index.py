"""Offline GLOBAL merchant search index — the big open-data merchant catalogue
Vaultie falls back to when the in-memory main KB (merchant_kb.v2.json) abstains.

This is the "millions of names" fallback: a build-time compiled catalogue of every
supported European country's physical merchants (Overture Places, brand-collapsed
and store-format-collapsed exactly like the LT enrichment), stored as an indexed
SQLite file that is queried FROM DISK — never loaded whole into application memory.

The resolver consults it ONLY on the UNKNOWN / NEEDS_EXTERNAL fallback path; any
hit is returned as ordinary candidate entities and re-scored by the EXISTING
resolver ranking / completeness / abstention. No runtime network. No country
guessing — the index is global, so a LT user buying in NO/PL/PT resolves the same
way with no per-country runtime layer selection.
"""

import json
import os
import re
import sqlite3
import unicodedata

# Default location of the compiled index (bundled with the Cloud Function). The
# POC harness overrides this before first use.
_DB = os.path.join(os.path.dirname(__file__), "kb", "merchant_index.sqlite")
_conn = None
_missing = False

# MUST match kb._norm / the offline build normalizer so folded surfaces line up.
_SPECIAL = {"ø": "o", "œ": "oe", "æ": "ae", "ß": "ss", "đ": "d", "ł": "l",
            "þ": "th", "ð": "d"}


def _norm(s):
    s = (s or "").lower()
    for k, v in _SPECIAL.items():
        s = s.replace(k, v)
    s = unicodedata.normalize("NFKD", s)
    s = "".join(c for c in s if not unicodedata.combining(c))
    return re.sub(r"[^a-z0-9]+", "", s)


def _c():
    """Lazy read-only connection. Absent DB -> disabled (returns no hits)."""
    global _conn, _missing
    if _conn is not None:
        return _conn
    if _missing or not os.path.exists(_DB):
        _missing = True
        return None
    _conn = sqlite3.connect(f"file:{_DB}?mode=ro", uri=True, check_same_thread=False)
    return _conn


def available():
    return _c() is not None


def reset():
    """Drop the cached connection (tests / harness re-point _DB)."""
    global _conn, _missing
    if _conn is not None:
        _conn.close()
    _conn, _missing = None, False


def lookup(surface):
    """Return [(entity_dict, match_kind)] for a candidate surface — normalized-exact
    match against the compiled catalogue. Same return shape as kb.lookup so the
    resolver ranker consumes it unchanged. Empty list = miss."""
    conn = _c()
    if conn is None or not surface:
        return []
    n = _norm(surface)
    if len(n) < 3:
        return []
    row = conn.execute("SELECT entity FROM merchants WHERE norm = ?", (n,)).fetchone()
    if row is None:
        return []
    e = json.loads(row[0])
    return [(e, "brand" if e.get("is_brand") else "exact")]
