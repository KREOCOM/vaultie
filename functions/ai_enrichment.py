"""Stage-3 AI merchant classification — the long-tail fallback.

Runs ONLY for business merchants the deterministic pipeline (keyword rules → KB
→ offline global index) could not classify, and ONLY when the user has opted in.

PRIVACY (enforced by the caller + here):
  * receives the merchant NAME surface only — never amount, IBAN, account/user
    id, transaction date, or any raw transaction payload;
  * a light person-name guard drops likely P2P names so people are never sent;
  * results are cached in Firestore (``merchant_ai_cache``) so each distinct
    merchant is classified once and the answer is reused for every user — the
    cache doubles as a crowdsourced merchant KB, keeping calls (and cost) rare.

No new pip dependency: the Anthropic API is called over plain HTTPS (requests).
"""

import json
import logging
import re
import time

import requests

_ANTHROPIC_URL = "https://api.anthropic.com/v1/messages"
_MODEL = "claude-haiku-4-5-20251001"  # fast + cheap; classification only
_TIMEOUT = 12

# Category vocabulary — must line up with dashboard.CAT_MAP.
_CATEGORIES = [
    "groceries", "restaurant", "cafe", "fuel", "transport", "taxi", "parking",
    "automotive", "retail", "clothing", "electronics", "home_improvement",
    "pharmacy", "health", "fitness", "taxes", "banking", "finance", "insurance",
    "connectivity", "utilities", "housing", "rent", "entertainment", "software",
    "travel", "education", "other",
]
_CATSET = set(_CATEGORIES)

_COMPANY_MARKERS = ("uab", "mb", "ab", "vsi", "ltd", "llc", "gmbh", "oy", "as",
                    "inc", "sia", "ou", "corp", ".lt", ".com", ".eu", "*")

_mem = {}   # in-instance positive memo (per warm instance)
_neg = set()  # in-instance negative memo: keys that failed / were unclassifiable
# this warm instance — avoids re-hammering the API on the repeated classification
# passes and during a provider outage.


def _norm(s):
    return re.sub(r"[^a-z0-9]+", "", (s or "").lower())


_BUSINESS_WORDS = ("cafe", "kavine", "kavinė", "bar", "pub", "shop", "store",
                   "parduotuv", "salon", "spa", "auto", "market", "express",
                   "hotel", "klinik", "klub", "centr", "sport", "grill", "pizza",
                   "sushi", "kebab", "bistro", "resto", "pharm", "vaistin", "gym")


def _looks_person(name):
    """Light guard so a P2P name never reaches the API even if mis-routed.
    Business-signal words override it (a two-word 'Caif Cafe' is not a person)."""
    low = name.lower()
    if any(w in low for w in _BUSINESS_WORDS):
        return False
    parts = name.split()
    if len(parts) not in (2, 3):
        return False
    if any(m in low for m in _COMPANY_MARKERS) or any(c.isdigit() for c in name):
        return False
    return all(re.sub(r"[-']", "", p).isalpha() and len(p) > 1 for p in parts)


def _db():
    try:
        from firebase_admin import firestore
        return firestore.client()
    except Exception:
        return None


def _cache_get(key):
    if key in _mem:
        return _mem[key]
    db = _db()
    if db is None:
        return None
    try:
        doc = db.collection("merchant_ai_cache").document(key).get()
        if doc.exists:
            v = doc.to_dict() or {}
            _mem[key] = v
            return v
    except Exception:
        pass
    return None


def _cache_put(key, val):
    _mem[key] = val
    db = _db()
    if db is None:
        return
    try:
        db.collection("merchant_ai_cache").document(key).set(val)
    except Exception:
        pass


def classify(surface, api_key):
    """Return (canonical_name, category) for a business merchant name, or None.

    ``surface`` MUST be a merchant name only (no user/transaction data).
    """
    if not surface or not api_key:
        return None
    surface = surface.strip()
    if _looks_person(surface):   # never classify a person via the API
        return None
    key = _norm(surface)
    if not key:
        return None

    cached = _cache_get(key)
    if cached is not None:
        return (cached.get("canonical") or surface, cached.get("category") or "other")
    if key in _neg:
        return None  # already failed this instance — don't call the API again

    prompt = (
        "You categorise a payment merchant/payee name into ONE category and give "
        "its clean brand name. This is a business name only; there is no personal "
        "data.\n"
        f'Name: "{surface}"\n'
        f"Allowed categories: {', '.join(_CATEGORIES)}\n"
        "Rules: pick the single best category; if it is not a recognisable "
        'business, use "other". Reply with ONLY compact JSON, no prose: '
        '{"canonical":"<clean name>","category":"<one category>"}'
    )
    payload = json.dumps({"model": _MODEL, "max_tokens": 80,
                          "messages": [{"role": "user", "content": prompt}]})
    headers = {"x-api-key": api_key, "anthropic-version": "2023-06-01",
               "content-type": "application/json"}
    for attempt in range(3):
        try:
            r = requests.post(_ANTHROPIC_URL, timeout=_TIMEOUT,
                              headers=headers, data=payload)
        except Exception as e:  # network / timeout — brief backoff, then retry
            logging.warning("ai_enrichment request failed for %r: %s", surface[:40], e)
            time.sleep(0.8 * (attempt + 1))
            continue
        if r.status_code == 429:  # rate limited — back off and retry the call
            logging.warning("ai_enrichment rate-limited (attempt %d)", attempt + 1)
            time.sleep(1.5 * (attempt + 1))
            continue
        if not r.ok:  # other HTTP error — not retryable
            logging.warning("ai_enrichment http %s: %s", r.status_code, r.text[:200])
            break
        try:
            txt = r.json()["content"][0]["text"]
            m = re.search(r"\{.*\}", txt, re.S)
            if not m:
                break
            obj = json.loads(m.group(0))
        except Exception as e:  # malformed response — not retryable
            logging.warning("ai_enrichment parse failed for %r: %s", surface[:40], e)
            break
        cat = (obj.get("category") or "other").strip().lower()
        if cat not in _CATSET:
            cat = "other"
        canon = (obj.get("canonical") or surface).strip() or surface
        _cache_put(key, {"canonical": canon, "category": cat})
        return (canon, cat)

    # All retries exhausted or a non-retryable error — remember the failure for
    # this warm instance so the repeated passes don't re-hit the API.
    _neg.add(key)
    return None
