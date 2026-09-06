"""The server-side subscription check — including the ways it must NOT fail.

This gate protects everything the backend spends money on. It has two ways to be
wrong, and the second is worse than the first: letting a non-payer through costs
compute, but locking a PAYING user out breaks the app for someone who did
nothing wrong. These tests pin both directions. No network, no Firestore.
"""
import datetime as dt
import os
import sys

sys.path.insert(0, os.path.dirname(__file__))

import entitlement


# ── fakes ──────────────────────────────────────────────────────────────────

class _Snap:
    def __init__(self, data):
        self._d = data
        self.exists = data is not None

    def to_dict(self):
        return self._d


class _Doc:
    def __init__(self, store, uid):
        self._store, self._uid = store, uid

    def get(self):
        return _Snap(self._store.get(self._uid))

    def set(self, data, merge=False):
        self._store[self._uid] = {**(self._store.get(self._uid) or {}), **data}


class _Col:
    def __init__(self, store):
        self._store = store

    def document(self, uid):
        return _Doc(self._store, uid)


class _DB:
    def __init__(self, store=None):
        self.store = store if store is not None else {}

    def collection(self, _name):
        return _Col(self.store)


class _Resp:
    def __init__(self, status, payload=None):
        self.status_code = status
        self.ok = 200 <= status < 300
        self._payload = payload or {}

    def json(self):
        return self._payload


def _rc(active=True, expires=None):
    ent = {} if not active else {
        entitlement._ENTITLEMENT: {"expires_date": expires}}
    return _Resp(200, {"subscriber": {"entitlements": ent}})


def _patch(fn):
    entitlement.requests.get = fn


def _future():
    return (entitlement._now() + dt.timedelta(days=30)).isoformat().replace(
        "+00:00", "Z")


def _past():
    return (entitlement._now() - dt.timedelta(days=1)).isoformat().replace(
        "+00:00", "Z")


# ── the check itself ───────────────────────────────────────────────────────

def test_active_subscription_passes():
    _patch(lambda *a, **k: _rc(True, _future()))
    assert entitlement.is_premium("u1", "key", _DB()) is True


def test_expired_subscription_is_refused():
    _patch(lambda *a, **k: _rc(True, _past()))
    assert entitlement.is_premium("u1", "key", _DB()) is False


def test_no_entitlement_is_refused():
    _patch(lambda *a, **k: _rc(False))
    assert entitlement.is_premium("u1", "key", _DB()) is False


def test_unknown_user_is_refused():
    _patch(lambda *a, **k: _Resp(404))
    assert entitlement.is_premium("nobody", "key", _DB()) is False


def test_non_expiring_entitlement_passes():
    # Lifetime buyers and promotional grants have no expiry date.
    _patch(lambda *a, **k: _rc(True, None))
    assert entitlement.is_premium("u1", "key", _DB()) is True


def test_missing_uid_is_refused_without_calling_out():
    called = {"n": 0}

    def _boom(*a, **k):
        called["n"] += 1
        raise AssertionError("should not have asked RevenueCat")

    _patch(_boom)
    assert entitlement.is_premium("", "key", _DB()) is False
    assert called["n"] == 0


# ── caching, and the outage behaviour ──────────────────────────────────────

def test_fresh_cache_is_used_without_asking_again():
    db = _DB({"u1": {"active": True, "checkedAt": entitlement._now()}})
    _patch(lambda *a, **k: (_ for _ in ()).throw(
        AssertionError("cache should have answered")))
    assert entitlement.is_premium("u1", "key", db) is True


def test_a_paying_user_is_not_locked_out_when_revenuecat_is_down():
    # The failure that matters most: they paid, RevenueCat is unreachable, and
    # we have seen them before. Serve the stale answer rather than deny.
    stale = entitlement._now() - dt.timedelta(days=3)
    db = _DB({"u1": {"active": True, "checkedAt": stale}})
    _patch(lambda *a, **k: (_ for _ in ()).throw(OSError("network down")))
    assert entitlement.is_premium("u1", "key", db) is True


def test_unknown_user_is_denied_when_revenuecat_is_down():
    # No cache, no answer — deny. Falling open here would restore the hole.
    _patch(lambda *a, **k: (_ for _ in ()).throw(OSError("network down")))
    assert entitlement.is_premium("stranger", "key", _DB()) is False


def test_a_positive_answer_is_cached():
    db = _DB()
    _patch(lambda *a, **k: _rc(True, _future()))
    entitlement.is_premium("u1", "key", db)
    assert db.store["u1"]["active"] is True


def test_expiry_recheck_happens_once_the_cache_goes_stale():
    stale = entitlement._now() - dt.timedelta(days=2)
    db = _DB({"u1": {"active": True, "checkedAt": stale}})
    _patch(lambda *a, **k: _rc(True, _past()))  # since expired
    assert entitlement.is_premium("u1", "key", db) is False


def test_a_broken_cache_entry_does_not_grant_access():
    db = _DB({"u1": {"active": True}})  # no checkedAt
    _patch(lambda *a, **k: _rc(False))
    assert entitlement.is_premium("u1", "key", db) is False


def test_a_cached_negative_is_never_sticky():
    # THE "charged but denied for 24h" critical. A 404/False answer (a not-yet-seen
    # subscriber, RC propagation lag, or a purchase not yet aliased to the Firebase
    # uid) must NOT freeze into a 24h denial. A cached negative always re-asks, so
    # the moment RevenueCat says active, the paying user is recognised.
    db = _DB()
    _patch(lambda *a, **k: _Resp(404))            # RC: not a subscriber yet
    assert entitlement.is_premium("u1", "key", db) is False
    _patch(lambda *a, **k: _rc(True, _future()))  # RC: now active
    assert entitlement.is_premium("u1", "key", db) is True  # recognised at once


def test_a_cached_negative_denies_when_revenuecat_is_down():
    # A cached negative is not trusted, so it re-asks; if RC is unreachable and we
    # have no positive to fall back on, deny (fail closed) — never grant on a stale
    # negative, and never lock via one either (the next reachable call re-checks).
    db = _DB({"u1": {"active": False, "checkedAt": entitlement._now()}})
    _patch(lambda *a, **k: (_ for _ in ()).throw(OSError("network down")))
    assert entitlement.is_premium("u1", "key", db) is False


def test_a_cached_positive_is_not_trusted_past_its_expiry():
    # A subscription that lapsed WITHIN the cache TTL must not keep paid access for
    # the rest of the window: the cached positive is bounded by its own expiry, so
    # once it passes we re-ask RevenueCat rather than serve a stale "active".
    past = entitlement._now() - dt.timedelta(hours=1)
    db = _DB({"u1": {"active": True, "checkedAt": entitlement._now(),
                     "expiresAt": past}})
    _patch(lambda *a, **k: _rc(False))  # RevenueCat confirms it's gone
    assert entitlement.is_premium("u1", "key", db) is False


def test_expired_positive_is_denied_even_during_an_outage():
    # A subscription that lapsed within the TTL must be denied even when RevenueCat
    # is unreachable — the cached expiry is known locally, so the outage fallback
    # must not re-grant it.
    past = entitlement._now() - dt.timedelta(hours=1)
    db = _DB({"u1": {"active": True, "checkedAt": entitlement._now(),
                     "expiresAt": past}})
    _patch(lambda *a, **k: (_ for _ in ()).throw(OSError("network down")))
    assert entitlement.is_premium("u1", "key", db) is False


def test_a_cached_positive_within_expiry_is_still_trusted():
    future = entitlement._now() + dt.timedelta(days=10)
    db = _DB({"u1": {"active": True, "checkedAt": entitlement._now(),
                     "expiresAt": future}})
    _patch(lambda *a, **k: (_ for _ in ()).throw(
        AssertionError("cache should have answered")))
    assert entitlement.is_premium("u1", "key", db) is True


def main_():
    for name, fn in sorted(globals().items()):
        if name.startswith("test_") and callable(fn):
            fn()
            print(f"  ✓ {name}")
    print("\nSubscription gate holds both ways ✓")


if __name__ == "__main__":
    main_()
