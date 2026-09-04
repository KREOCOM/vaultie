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
    # Caught live: fetchone() came back an empty tuple `()`, not None — `row[0]`
    # threw IndexError, and because nothing here was defensive, that ONE bad
    # merchant lookup took the WHOLE recurring-detection pass down with it (a
    # real user's dashboard came back with subs_active=0 for every subscription
    # they had, not just the one merchant that failed to resolve). `_conn` is
    # opened with check_same_thread=False specifically so it CAN be touched from
    # more than one thread, but a single sqlite3 connection is not actually safe
    # for concurrent execute()/fetchone() from different threads at once — this
    # is almost certainly that: two lookups landing on the same connection at
    # the same moment, one's cursor state clobbering the other's. `if not row`
    # (catches () same as None) plus a hard try/except make a single corrupted
    # read a silent miss for that one merchant instead of a crash for everyone.
    try:
        row = conn.execute(
            "SELECT entity FROM merchants WHERE norm = ?", (n,)).fetchone()
        if not row:
            return []
        e = json.loads(row[0])
    except Exception:
        return []
    return [(e, "brand" if e.get("is_brand") else "exact")]
