"""Server-side "is this user actually paying?" check.

Vaultie is subscription-only, but until now the entitlement was checked ONLY on
the phone. Everything the backend does costs real money — a 12-month bank scan
across several accounts, AI enrichment, chat — and every one of those endpoints
was open to anyone with an account. A lapsed subscriber (or anyone who signed
up and never paid) could keep using the expensive half of the product; the
client-side gate they'd be bypassing is, after all, on their own device.

RevenueCat is the source of truth, reached over its REST API rather than a
webhook: a webhook needs dashboard configuration and can silently miss
deliveries, and this needs no extra moving parts. Answers are cached in
Firestore so the common path is one fast read, not an outbound HTTP call on
every scan.

Failure behaviour is deliberate. With a cached answer we trust it for
[_CACHE_TTL]; without one, and with RevenueCat unreachable, we DENY. Falling
open would restore the exact hole this file exists to close, and a subscription
app that hands out its paid work when a third party has a bad minute is not
protecting anything. The window is generous enough that an outage only touches
people who haven't opened the app in a day.
"""
import datetime as dt
import logging

import requests

_API = "https://api.revenuecat.com/v1/subscribers/"
_TIMEOUT = 8
_ENTITLEMENT = "Vaultie Pro"
_COLLECTION = "entitlements"

# How long a positive answer stays good without re-asking RevenueCat.
_CACHE_TTL = dt.timedelta(hours=24)


def _now():
    return dt.datetime.now(dt.timezone.utc)


def _norm_dt(v):
    """A tz-aware datetime, or None, from a Firestore value."""
    if not isinstance(v, dt.datetime):
        return None
    return v if v.tzinfo is not None else v.replace(tzinfo=dt.timezone.utc)


def _cached(db, uid):
    """(is_active, checked_at, expires_at) or (None, None, None) if unusable.
    ``expires_at`` is when the entitlement itself lapses (None = non-expiring)."""
    try:
        snap = db.collection(_COLLECTION).document(uid).get()
        if not snap.exists:
            return None, None, None
        d = snap.to_dict() or {}
        checked = _norm_dt(d.get("checkedAt"))
        if checked is None:
            return None, None, None
        return bool(d.get("active")), checked, _norm_dt(d.get("expiresAt"))
    except Exception:
        logging.exception("entitlement: cache read failed uid=%s", uid)
        return None, None, None


def _store(db, uid, active, expires=None):
    try:
        db.collection(_COLLECTION).document(uid).set(
            {"active": bool(active), "checkedAt": _now(), "expiresAt": expires},
            merge=True)
    except Exception:
        logging.exception("entitlement: cache write failed uid=%s", uid)


def _ask_revenuecat(uid, api_key):
    """``(active, expires_at)`` from RevenueCat, or None if it couldn't be reached.
    ``active`` is a bool; ``expires_at`` is a tz-aware datetime, or None for a
    non-expiring (lifetime / promotional) grant."""
    try:
        r = requests.get(_API + uid, timeout=_TIMEOUT,
                         headers={"Authorization": f"Bearer {api_key}",
                                  "accept": "application/json"})
    except Exception as e:  # noqa: BLE001
        logging.warning("entitlement: RevenueCat unreachable: %s", e)
        return None
    if r.status_code == 404:
        return (False, None)  # RevenueCat has never seen this user — not paying
    if not r.ok:
        logging.warning("entitlement: RevenueCat http %s", r.status_code)
        return None
    try:
        ents = (r.json().get("subscriber") or {}).get("entitlements") or {}
    except Exception:  # noqa: BLE001
        logging.exception("entitlement: unparseable RevenueCat response")
        return None
    ent = ents.get(_ENTITLEMENT)
    if not ent:
        return (False, None)
    expires = ent.get("expires_date")
    if expires is None:
        return (True, None)  # non-expiring (lifetime / promotional grant)
    try:
        # RevenueCat sends e.g. "2026-08-20T10:15:00Z".
        exp = dt.datetime.fromisoformat(str(expires).replace("Z", "+00:00"))
    except ValueError:
        logging.warning("entitlement: unparseable expiry %r", expires)
        return None
    return (exp > _now(), exp)


def is_premium(uid: str, api_key: str, db=None) -> bool:
    """Whether [uid] currently holds the Vaultie Pro entitlement.

    Reads the cache first, asks RevenueCat when it is missing or stale, and
    denies when neither can answer — see the module docstring for why.
    """
    if not uid:
        return False
    if db is None:
        from firebase_admin import firestore
        db = firestore.client()

    active, checked, expires = _cached(db, uid)
    # Only a cached POSITIVE is trusted within the TTL. A cached negative must NEVER
    # be sticky: a user who just paid — or whose RevenueCat identity had not yet
    # aliased to their Firebase uid at purchase time — would otherwise be denied
    # every paid endpoint for a full 24h even after the subscription is
    # unambiguously active. So a False/None cache always re-asks RevenueCat.
    if active is True and checked is not None and _now() - checked < _CACHE_TTL:
        # ...but never keep trusting a cached positive PAST its own expiry, or a
        # lapsed/cancelled subscriber kept paid access for up to the full TTL.
        if expires is None or _now() < expires:
            return True

    fresh = _ask_revenuecat(uid, api_key)
    if fresh is None:
        # Unreachable. Trust a cached POSITIVE — but NEVER past its own expiry: the
        # point of caching expiresAt is that a lapse is known locally without asking
        # RevenueCat, so an expired subscriber is denied even during an outage. With
        # no still-valid positive, deny.
        if active is True and (expires is None or _now() < expires):
            logging.warning("entitlement: serving stale positive cache for uid=%s", uid)
            return True
        return False
    fresh_active, fresh_expires = fresh
    # Cache positives (trusted for the TTL, bounded by their expiry). Reads never
    # trust a cached negative, so storing one only matters to clear a now-stale
    # positive when RevenueCat turns negative.
    if fresh_active:
        _store(db, uid, True, fresh_expires)
    elif active is True:
        _store(db, uid, False, None)
    return fresh_active
