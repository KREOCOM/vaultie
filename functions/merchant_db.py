"""In-memory cache of the global ``merchants`` Firestore collection + matching.

The collection is tiny (~a few hundred docs), so it is loaded once per warm
function instance — one Firestore read on cold start, not one per request.
Any load failure degrades gracefully to an empty DB, so detection still runs
(algorithm path only) instead of erroring.

Schema (see docs/VAULTIE_3.0_PLAN.md):
    merchants/{key}: displayName, type, category, logoDomain, aliases[],
                     matchMode ("substring"|"word"), source, status, ...
"""

import logging
import re

from firebase_admin import firestore

_cache = None  # list[dict] | None
_word_re = {}  # alias -> compiled regex


def _load():
    global _cache
    if _cache is not None:
        return _cache
    try:
        db = firestore.client()
        _cache = []
        for doc in db.collection("merchants").where("status", "==", "active").stream():
            m = doc.to_dict() or {}
            m["_key"] = doc.id
            _cache.append(m)
        logging.info("merchant_db loaded: %d active merchants", len(_cache))
    except Exception as e:  # noqa: BLE001
        logging.warning("merchant_db load failed (%s) — using empty DB", e)
        _cache = []
    return _cache


def _matches(low: str, alias: str, mode: str) -> bool:
    # Whole-word match for short/ambiguous aliases (e.g. "iki", "eso"), else
    # a plain substring match.
    if mode == "word" or len(alias) <= 4:
        pat = _word_re.get(alias)
        if pat is None:
            pat = re.compile(
                r"(^|[^a-z0-9ąčęėįšųūž])" + re.escape(alias) +
                r"([^a-z0-9ąčęėįšųūž]|$)"
            )
            _word_re[alias] = pat
        return pat.search(low) is not None
    return alias in low


def match(name: str):
    """Return (displayName, type, category, logoDomain) for [name], or None."""
    low = name.lower()
    for m in _load():
        mode = m.get("matchMode", "substring")
        aliases = m.get("aliases") or [m.get("_key", "")]
        for alias in aliases:
            if alias and _matches(low, str(alias).lower(), mode):
                return (
                    m.get("displayName") or name,
                    m.get("type", "subscription"),
                    m.get("category", "other"),
                    m.get("logoDomain"),
                )
    return None


def reset_cache():
    """Drop the in-memory cache (e.g. after a seed) so the next call reloads."""
    global _cache
    _cache = None
