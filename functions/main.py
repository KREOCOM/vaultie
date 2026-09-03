"""Vaultie 2.0 — Enable Banking Cloud Functions (Python).

Three callable endpoints, every one requiring a signed-in Firebase user:

  * ``list_banks``       — banks available for a country (default LT)
  * ``start_bank_auth``  — begin a bank consent flow, return the bank's auth URL
  * ``finish_bank_auth`` — exchange the returned code, pull transactions, and
                           return detected recurring-payment candidates

The Enable Banking RSA private key is injected from the Firebase Secret
``ENABLE_BANKING_PRIVATE_KEY`` and never leaves the server. Raw bank
transactions are processed in memory and are never returned or persisted (GDPR).

Deploy region is ``europe-west1`` (close to LT users).
"""

import datetime as dt
import json
import logging
import re
import uuid
from concurrent.futures import ThreadPoolExecutor

import firebase_admin
import requests
from firebase_functions import https_fn, options
from firebase_functions.params import SecretParam

from dashboard import build_dashboard
from enable_banking import DEFAULT_COUNTRY, EnableBankingClient, EnableBankingError
from entitlement import is_premium as _is_premium
from finance_chat import chat as _finance_chat
from finance_chat import month_report as _month_report
from known_cache import merge_known as _merge_known
import normalize
from receipt_scan import scan as _scan_receipt
from recurring import detect_recurring
from seed_merchants import seed as _run_seed
from stock_quote import profile as _stock_profile
from stock_quote import quote as _stock_quote
from stock_quote import search as _stock_search

# Cloud Run leaves the root logger at WARNING, so every logging.info() below —
# including the per-scan "accounts=… txns=… scan_diag=…" line that is the only
# record of what a bank actually returned — was silently dropped. Diagnosing a
# scan without it means guessing.
logging.getLogger().setLevel(logging.INFO)


# Initialize the Admin SDK so the callable framework can verify the caller's
# Firebase Auth ID token. Without this the token is rejected and every call
# fails as UNAUTHENTICATED ("default Firebase app does not exist").
if not firebase_admin._apps:
    firebase_admin.initialize_app()

# Set once with:  firebase functions:secrets:set ENABLE_BANKING_PRIVATE_KEY < key.pem
ENABLE_BANKING_PRIVATE_KEY = SecretParam("ENABLE_BANKING_PRIVATE_KEY")

# One-time admin token guarding the seed endpoint.
# Set with:  firebase functions:secrets:set SEED_TOKEN
SEED_TOKEN = SecretParam("SEED_TOKEN")

# Investavimas tab prototype (2026-08-28) — see stock_quote.py's own doc.
# Free tier: 60 req/min, covers quote + symbol search + company profile.
# Set with:  firebase functions:secrets:set FINNHUB_API_KEY
FINNHUB_API_KEY = SecretParam("FINNHUB_API_KEY")

# Stage-3 AI merchant classification (opt-in only). Used solely to classify
# unresolved BUSINESS merchant names — never amounts/IBANs/identifiers/people.
ANTHROPIC_API_KEY = SecretParam("ANTHROPIC_API_KEY")

# RevenueCat v1 SECRET key (not the public SDK key the app ships). Lets the
# backend verify a subscription itself instead of trusting the phone.
# Set once with:  firebase functions:secrets:set REVENUECAT_API_KEY
REVENUECAT_API_KEY = SecretParam("REVENUECAT_API_KEY")

_REGION = "europe-west1"

# ⚠️ TEMP — bypasses the server-side subscription gate so a tester (wife's
# Swedbank run) can use the paid endpoints without an App Store purchase. Pairs
# with the client kBypassPaywall flag. SET BACK TO False before any real release.
_TEST_BYPASS_PREMIUM = False


def _dedupe_summaries(summaries: list) -> list:
    """One balance card per physical account, keyed on IBAN.

    Reconnecting a bank makes Enable Banking mint a NEW session with NEW account
    UIDs for the SAME physical accounts, so a few reconnects leave several
    sessions all pointing at one account — and each one produced its own balance
    card. The IBAN is the account's stable identity across sessions; the UID is
    not. Accounts with no IBAN (rare) fall back to their UID so they aren't all
    collapsed into one. Balances are NOT summed — these are the same money seen
    twice, not two accounts.
    """
    out: list = []
    seen: set = set()
    for s in summaries:
        # Identity = IBAN + CURRENCY. Reconnecting an account mints a new session
        # UID for the SAME wallet (same IBAN + currency) → collapse those. But a
        # Revolut EUR wallet and its NOK wallet SHARE one IBAN and are DIFFERENT
        # accounts — keying on IBAN alone dropped one of them (and its balance).
        iban = _norm_iban(s.get("iban"))
        if iban:
            key = f"{iban}|{(s.get('currency') or '').upper()}"
        else:
            # No IBAN (some non-LT ASPSPs): the old `id(s)` key was unique per
            # object, so it deduped NOTHING — reconnect churn (a fresh session UID
            # for the same physical account) left two balance cards that got summed
            # into net worth, double-counting the money. Key on the account's
            # stable identity instead — bank + name + currency survives a new UID.
            key = ("noiban|"
                   f"{(s.get('bank') or '').lower().strip()}|"
                   f"{(s.get('name') or '').lower().strip()}|"
                   f"{(s.get('currency') or '').upper()}")
        if key in seen:
            continue
        seen.add(key)
        out.append(s)
    if len(out) != len(summaries):
        logging.info("scan: deduped %d -> %d account summaries",
                     len(summaries), len(out))
    # Relabel every account from its IBAN, fresh OR cache-served. A cached
    # summary keeps whatever label it was stored with (often the generic
    # "Bankas" from a connect flow that dropped the name), so normalising here
    # is what makes the label — and therefore the logo — correct everywhere.
    for s in out:
        derived = _bank_from_iban(s.get("iban"))
        if derived:
            s["bank"] = derived
            if "revolut" in derived.lower():
                s["icon"] = "R"
    return out


def _require_auth(req: https_fn.CallableRequest) -> None:
    if req.auth is None:
        raise https_fn.HttpsError(
            code=https_fn.FunctionsErrorCode.UNAUTHENTICATED,
            message="Sign in required.",
        )


def _uid(req: https_fn.CallableRequest) -> str:
    """The authenticated caller's uid. Always use this — never a uid from the
    request body, which the caller controls."""
    return req.auth.uid


def _begin(req: https_fn.CallableRequest, name: str) -> str:
    """Open a log record for one call and return its correlation id.

    Support used to be impossible: no log line carried a uid, so given "my bank
    won't connect" there was no way to find that user's attempt among everyone
    else's. The id ties every line of one call together; the uid ties it to the
    person who wrote in.
    """
    rid = uuid.uuid4().hex[:8]
    logging.info("call=%s rid=%s uid=%s", name, rid, _uid(req))
    return rid


def _check_daily_cap(uid: str, name: str, limit: int, rid: str) -> None:
    """Cheap insurance against a runaway client (a retry loop, a stuck
    button, a bug) hammering a paid AI endpoint all day on one account.

    Not meant to constrain real use — these limits are set well above
    anything a real person would hit in a day; they exist only to put a
    ceiling under a bug. One Firestore doc per uid+day, incremented per
    call; a `get` + `set` (not a transaction) is good enough here since the
    only realistic race is the same signed-in user's own two near-
    simultaneous taps, and losing that race just means the cap is off by
    one for one day.
    """
    from firebase_admin import firestore
    today = dt.date.today().isoformat()
    ref = firestore.client().collection("ai_daily_usage").document(
        f"{uid}_{today}")
    snap = ref.get()
    count = int((snap.to_dict() or {}).get(name, 0)) if snap.exists else 0
    if count >= limit:
        logging.warning(
            "call=%s rid=%s uid=%s daily cap reached (%d/%d)",
            name, rid, uid, count, limit)
        raise https_fn.HttpsError(
            code=https_fn.FunctionsErrorCode.RESOURCE_EXHAUSTED,
            message="Daily limit reached — please try again tomorrow.",
        )
    ref.set({name: firestore.Increment(1), "uid": uid, "date": today},
             merge=True)


# Firebase uid of the App Review demo account (appreview@vaultieapp.com). See
# _require_premium below and lib/services/review_account.dart on the client.
#
# The uid, not the email — so this must be re-read from Firebase Authentication
# whenever the demo account is recreated. It was missed once already: moving the
# address off vaultie.app (a domain we do not own) meant a NEW account with a
# NEW uid, the server kept denying the old one, and the reviewer's first tap on
# the AI chat would have returned "permission denied".
_REVIEW_UID = "iO6gSjDDj1gp69kPz1hDFI0tP3l2"


def _require_premium(req: https_fn.CallableRequest) -> None:
    """Refuse the paid endpoints to users without a subscription.

    Everything behind this costs real money to run — a multi-account 12-month
    scan, AI enrichment, chat. The entitlement used to be checked only on the
    phone, which is the one place the person being checked controls: someone
    whose subscription lapsed kept the expensive half of a subscription-only
    product, and nothing server-side noticed.
    """
    # ⚠️ TEMP TEST BYPASS — allow the paid endpoints during the wife's Swedbank
    # test (she can't complete the App Store purchase). Pairs with the client
    # kBypassPaywall flag. REVERT before any real release.
    #
    # 2026-08-16: this is a global switch — if it's ever flipped True and
    # forgotten before a deploy, EVERY user gets every paid endpoint for
    # free, silently, with nothing in the logs pointing at why. Can't narrow
    # this to a single allowlisted uid (like _REVIEW_UID below) without
    # knowing the actual tester's uid, so instead: every single bypass now
    # logs loudly, every call, so a forgotten-on flag is impossible to miss
    # in Cloud Logging instead of being a silent, invisible landmine.
    if _TEST_BYPASS_PREMIUM:
        logging.warning(
            "⚠️ _TEST_BYPASS_PREMIUM is active for uid=%s — premium "
            "check skipped. This flag must be False before any real release.",
            _uid(req))
        return
    # App Review's demo account. One hard-coded uid, nothing else.
    #
    # The reviewer signs in to a fully populated dashboard, and the first thing
    # anyone does with a finance app is open the AI chat — which is behind this
    # gate and answered "server unreachable", because the account holds no
    # RevenueCat entitlement. A feature that fails in front of a reviewer is a
    # rejection; there is no way to explain it in the notes afterwards.
    #
    # Narrow on purpose: a single uid, no email matching, no flag anyone can
    # flip. Its data is the bundled sample month, so nothing here exposes a real
    # user's information — only the compute the reviewer needs to see it work.
    if _uid(req) == _REVIEW_UID:
        return
    if _is_premium(_uid(req), REVENUECAT_API_KEY.value):
        return
    raise https_fn.HttpsError(
        code=https_fn.FunctionsErrorCode.PERMISSION_DENIED,
        message="An active Vaultie Pro subscription is required.",
    )


@https_fn.on_call(region=_REGION, secrets=[REVENUECAT_API_KEY])
def check_entitlement(req: https_fn.CallableRequest) -> dict:
    """Whether the signed-in user actually holds Vaultie Pro, per the SAME
    RevenueCat-backed check every paid endpoint enforces (see
    ``_require_premium``/``entitlement.py``) — not a new, separate opinion.

    Exists because the paywall gate right after sign-in used to trust ONLY
    the on-device RevenueCat SDK state. That SDK observes every StoreKit
    transaction on the PHONE, not the signed-in account: on a device that
    ever held a real entitlement (a reviewer's test device, a family
    member's shared Apple ID, a QA phone with a promotional grant), signing
    in as a brand-new, never-paid account could read as premium client-side
    and skip the paywall — only to have the very next paid action (starting
    a bank connection) rejected by this exact same server check, with no
    explanation the person could act on. Calling this once right after
    sign-in lets the client catch that mismatch before it looks broken.
    """
    return {"premium": _is_premium(_uid(req), REVENUECAT_API_KEY.value)}


# The one thing this backend stores. Everything else — transactions, balances,
# the built dashboard — stays in memory and on the phone.
_BANK_LINKS = "bank_links"

# 2026-08-16: a SECOND thing this backend stores, briefly — see
# _remember_auth_state/_consume_auth_state below. Not a data-retention
# exception to the comment above (nothing here is the user's financial
# data), it closes a real gap: start_bank_auth generated an OAuth `state`
# and handed it back to the client, but finish_bank_auth never checked it
# against anything — so it exchanged ANY code a caller supplied for
# accounts bound to THAT caller's uid, with nothing proving the code
# actually came from a consent flow that uid itself started. A deep link
# crafted with someone else's valid code (obtained from their own,
# unrelated consent flow) would have linked their bank account into
# whichever signed-in victim tapped it.
_BANK_AUTH_STATES = "bank_auth_states"

# 2026-09-01: found in audit — client.delete_session() is best-effort by
# design (a bank momentarily unreachable must never block a user from
# disconnecting locally or deleting their account), but until now a failed
# revoke left NOTHING behind once the surrounding flow finished: disconnect
# removes the session from _BANK_LINKS regardless, and delete_user_data goes
# on to delete the uid's _BANK_LINKS/_BANK_AUTH_STATES/entitlements docs (and
# the client wipes local Hive + deletes the Firebase Auth account) in the
# same flow. A real, standing PSD2 consent could end up with no trace
# anywhere in Vaultie's own systems that it still needs revoking — it just
# lives at the bank for up to the 90-day consent ceiling. This is a
# top-level (not per-uid) collection specifically so it survives the uid
# document being deleted, so a failed revoke can still be found and retried
# later (manually, or by a future scheduled job) instead of vanishing.
_ORPHANED_SESSIONS = "orphaned_bank_sessions"


def _log_orphaned_session(uid: str, session_id: str, *, reason: str) -> None:
    """Best-effort record of a session revoke that failed even after retries —
    never raises, since a logging failure must not be allowed to interrupt the
    disconnect/delete flow it's trying to leave a trail for."""
    try:
        from firebase_admin import firestore
        firestore.client().collection(_ORPHANED_SESSIONS).add({
            "uid": uid,
            "sessionId": session_id,
            "reason": reason,
            "loggedAt": firestore.SERVER_TIMESTAMP,
        })
    except Exception:  # noqa: BLE001
        logging.exception(
            "orphaned_bank_sessions: failed to log uid=%s sid=%s", uid, session_id)


def _remember_accounts(uid: str, account_uids: list,
                       session_id: str | None = None) -> None:
    """Record which Enable Banking accounts (and session) this user consented to.

    Stored deliberately, and it is the minimum that closes a real hole: without
    it the backend cannot tell WHOSE accounts it is being asked to fetch, so any
    signed-in user could read anyone else's transactions just by supplying their
    account uid. Only opaque account identifiers are written — no transactions,
    no balances, no IBANs.

    The ``session_id`` is recorded for the same reason: on account deletion the
    server revokes bank consents, and it must only ever revoke sessions THIS user
    created — never a session id the caller merely supplied (see delete_user_data).
    """
    ids = sorted({str(a) for a in account_uids if a})
    session_id = str(session_id) if session_id else None
    if not ids and not session_id:
        return
    try:
        from firebase_admin import firestore
        payload = {}
        if ids:
            payload["accounts"] = firestore.ArrayUnion(ids)
        if session_id:
            payload["sessions"] = firestore.ArrayUnion([session_id])
        firestore.client().collection(_BANK_LINKS).document(uid).set(
            payload, merge=True)
    except Exception:
        # Don't fail a connection the user just completed — their data is in
        # this response and they should see it. The next refresh will deny and
        # ask them to reconnect, which runs this write again. Denying later is
        # the safe direction to fail in.
        logging.exception("bank_links: could not record ownership for uid=%s", uid)


def _remember_auth_state(uid: str, state: str) -> None:
    """Ties a start_bank_auth-issued `state` to the caller who requested it, so
    finish_bank_auth can later prove the code it's about to exchange belongs to
    THIS user's own just-started consent. One document per uid: a new
    start_bank_auth simply overwrites it, silently invalidating an abandoned
    prior attempt — the real usage pattern is one auth flow in flight at a
    time. Deliberately NOT wrapped in try/except (unlike _remember_accounts
    above): if this write fails, finish_bank_auth would reject the state check
    anyway, so failing start_bank_auth loudly here is more honest than
    proceeding into a connection attempt that can only end in a confusing
    "couldn't verify" error after the user already sat through the bank's
    consent pages."""
    from firebase_admin import firestore
    firestore.client().collection(_BANK_AUTH_STATES).document(uid).set({
        "state": state,
        "createdAt": dt.datetime.now(dt.timezone.utc).isoformat(),
    })


_AUTH_STATE_TTL = dt.timedelta(minutes=30)


def _auth_state_fresh(created_iso, now: "dt.datetime | None" = None) -> bool:
    """Pure freshness check, factored out so it's testable with no Firestore —
    30 min is generous for actually completing a bank's consent pages, tight
    enough that a leaked/replayed state is useless soon after."""
    try:
        created = dt.datetime.fromisoformat(created_iso)
    except (TypeError, ValueError):
        return False
    now = now or dt.datetime.now(dt.timezone.utc)
    return now - created <= _AUTH_STATE_TTL


def _consume_auth_state(uid: str, state: str) -> bool:
    """True iff `state` matches the one THIS uid's own start_bank_auth issued,
    and it's still fresh (see _auth_state_fresh). Deletes the record either
    way it resolves: single-use, so the same state can never be presented
    twice even if this first check fails."""
    from firebase_admin import firestore
    ref = firestore.client().collection(_BANK_AUTH_STATES).document(uid)
    snap = ref.get()
    try:
        ref.delete()
    except Exception:
        logging.exception("bank_auth_states: cleanup delete failed uid=%s", uid)
    if not snap.exists or not state:
        return False
    data = snap.to_dict() or {}
    if data.get("state") != state:
        return False
    return _auth_state_fresh(data.get("createdAt"))


def _owned_accounts(uid: str) -> set:
    """The Enable Banking account uids this user is allowed to fetch.

    Raises on lookup failure rather than returning an empty set: an empty set is
    indistinguishable from "owns nothing", and falling open here would restore
    exactly the hole this function exists to close.
    """
    try:
        from firebase_admin import firestore
        snap = firestore.client().collection(_BANK_LINKS).document(uid).get()
    except Exception as e:
        logging.exception("bank_links: ownership lookup failed for uid=%s", uid)
        raise https_fn.HttpsError(
            code=https_fn.FunctionsErrorCode.UNAVAILABLE,
            message="Could not verify your bank connections. Please try again.",
        ) from e
    if not snap.exists:
        return set()
    return {str(a) for a in (snap.to_dict() or {}).get("accounts") or [] if a}


def _authorised_metas(requested: list, owned: set) -> list:
    """Keep only the requested accounts this user actually connected.

    An account with no uid is dropped too — there is nothing to check it
    against, and letting it through would mean fetching an account we cannot
    attribute to anyone.
    """
    return [m for m in requested if m.get("uid") and m["uid"] in owned]


def _owned_sessions(uid: str) -> set:
    """The Enable Banking session ids this user created (recorded at connect).

    Unlike _owned_accounts this returns an empty set on lookup failure rather
    than raising: session revocation on account deletion is best-effort and must
    never block the erasure. An empty set simply means nothing is revoked — the
    safe direction (we only ever revoke sessions we can prove belong to the user).
    """
    try:
        from firebase_admin import firestore
        snap = firestore.client().collection(_BANK_LINKS).document(uid).get()
    except Exception:  # noqa: BLE001
        logging.exception("bank_links: session lookup failed for uid=%s", uid)
        return set()
    if not snap.exists:
        return set()
    return {str(s) for s in (snap.to_dict() or {}).get("sessions") or [] if s}


def _authorised_sessions(requested: list, owned: set) -> list:
    """Keep only the session ids this user is recorded as owning.

    delete_user_data revokes bank consents from a list the CLIENT supplies. Left
    untrusted, a signed-in user could pass someone else's opaque session id and
    revoke that person's bank access (an IDOR). Intersecting with the sessions we
    recorded for THIS user at connect closes that: a caller can only ever revoke
    their own. (A connection made before sessions were recorded isn't in `owned`,
    so its consent is left for the ~90-day cliff — the safe direction to miss in.)
    """
    return [str(s) for s in requested if str(s) in owned]


def _client() -> EnableBankingClient:
    return EnableBankingClient(ENABLE_BANKING_PRIVATE_KEY.value)


def _coerce_months(raw) -> int:
    """Coerce the client's ``monthsBack`` to an int, defaulting to 12.

    The Flutter callable SDK serialises a Dart int as a protobuf Int64Value
    wrapper — {"@type": ".../Int64Value", "value": "12"} — not a bare number, so
    a plain int() blows up. Unwrap it, then coerce defensively.
    """
    if isinstance(raw, dict):
        raw = raw.get("value", 12)
    try:
        return int(raw)
    except (TypeError, ValueError):
        return 12


# Lithuanian bank identifier (IBAN chars 5-9) → bank name. The IBAN carries the
# bank deterministically, so this labels an account correctly no matter what the
# connect flow passed as the bank name — which turned out to be fragile (a
# hand-off cancel could drop it, leaving accounts labelled the generic "Bankas"
# with no logo). Only the majors are listed; an unknown code falls back to
# whatever label the client sent.
_LT_BANK_BY_CODE = {
    "70440": "SEB",             # confirmed from real data
    "73000": "Swedbank",
    "40100": "Luminor",
    "21400": "Luminor",
    "32500": "Revolut",         # Revolut Payments UAB — confirmed from real data
    "72900": "Citadele",
    "71800": "Šiaulių bankas",
    "30100": "Medicinos bankas",
    "37500": "Urbo bankas",
}


def _bank_from_iban(iban):
    """Bank name from a Lithuanian IBAN's bank code, or None if not recognised."""
    n = _norm_iban(iban)
    if not n or not n.startswith("LT") or len(n) < 9:
        return None
    return _LT_BANK_BY_CODE.get(n[4:9])


def _mask_iban(v):
    """Mask an IBAN-shaped value so a real IBAN never lands in Cloud Logging.
    Used everywhere an account label/iban is logged (a nameless account's label
    falls back to its IBAN in _account_meta)."""
    s = str(v or "")
    return (s[:4] + "…") if re.match(
        r"^[A-Z]{2}\d{2}[A-Z0-9]{6,}$", s.replace(" ", "")) else s


def _mask_label(v):
    """Mask an account LABEL before it reaches Cloud Logging — unconditionally,
    unlike _mask_iban above.

    2026-08-16 fix: an account's label isn't always IBAN-shaped — Enable
    Banking sends whatever nickname the bank has for it, which can just as
    easily be the account holder's own first name ("OSVALDAS", "ZIVILE",
    seen literally in real test fixtures). _mask_iban's regex only matches
    IBAN-looking strings, so a plain name passed straight through into the
    scan-failure warning logs and the scan_diag summary log unmasked. This
    truncates ANY label the same way, whatever it looks like."""
    s = str(v or "")
    return (s[:2] + "…") if len(s) > 2 else s


def _norm_iban(iban) -> str | None:
    """Uppercase, strip spaces — so own-account IBANs compare regardless of
    formatting."""
    if not iban:
        return None
    return str(iban).replace(" ", "").upper()


def _consent_valid_until(session: dict, *, now=None) -> str:
    """When this bank consent lapses, as an ISO-8601 UTC string.

    PSD2 access is granted for a fixed window (we ask for 90 days in
    ``enable_banking.start_auth``) and then the bank simply stops answering:
    the figures quietly stop moving and nothing tells the user why. Handing the
    date to the client is what lets it warn BEFORE that happens.

    The bank's own answer wins — it, not us, decides what it granted, and some
    ASPSPs shorten the window. When the session carries no usable date we fall
    back to the 90 days we asked for, because a date that is approximately right
    still produces a timely warning, whereas returning nothing produces silence
    exactly where silence is the failure being prevented.
    """
    # Defensive at every step: this is a third party's JSON, and a bank sending
    # `access` as anything but an object must not take the connection down
    # AFTER the consent has already been granted — the code is spent by then and
    # the user would have to walk the whole bank login again.
    access = session.get("access") if isinstance(session, dict) else None
    raw = access.get("valid_until") if isinstance(access, dict) else None
    if isinstance(raw, str) and raw.strip():
        try:
            dt.datetime.fromisoformat(raw.strip().replace("Z", "+00:00"))
            return raw.strip()
        except ValueError:
            logging.warning("consent: unparseable valid_until %r", raw)
    base = now or dt.datetime.now(dt.timezone.utc)
    return (base + dt.timedelta(days=90)).replace(microsecond=0).isoformat()


def _account_meta(acc: dict, bank: str | None) -> dict:
    """Normalise an Enable Banking account object OR a stored client account ref
    to the fields the scan core needs: uid, name, currency, iban, bank, sub."""
    uid = acc.get("uid") or acc.get("account_uid")
    acct_id = acc.get("account_id") if isinstance(acc.get("account_id"), dict) else {}
    iban = acc.get("iban") or acct_id.get("iban")
    name = acc.get("name") or acc.get("product") or iban or "Sąskaita"
    currency = acc.get("currency") or acct_id.get("currency") or "EUR"
    return {"uid": uid, "name": name, "currency": currency,
            "iban": iban, "bank": bank, "sub": _account_sub(acc)}


# Enable Banking's `cash_account_type` (Berlin Group / ISO 20022 external code
# set — required on every account object). A "Total balance" that quietly sums
# a checking and a savings account into one figure reads as "money I can
# spend today" when a large share of it is deliberately locked away — this is
# the label the client already had a slot for (`sub`, dashboard_preview.dart)
# but nothing ever populated. Only the types worth calling out explicitly;
# an ordinary current/checking account gets no label (the common case, and
# labelling it too would just be noise next to every other account).
_CASH_ACCOUNT_TYPE_LABEL = {
    "SVGS": "Taupomoji",
    "CARD": "Kortelės sąskaita",
    "LOAN": "Paskolos sąskaita",
}


def _account_sub(acc: dict) -> str | None:
    t = (acc.get("cash_account_type") or "").upper()
    return _CASH_ACCOUNT_TYPE_LABEL.get(t)


def _psu_available(req) -> dict:
    """The PSU headers we can honestly supply for THIS call, from the phone's own
    request to us.

    These say "the user is right here, asking" — the difference between an
    uncapped request and one that counts against the bank's 4-a-day unattended
    limit. They must describe the END USER, so the IP comes from the phone's
    request (X-Forwarded-For's first hop), never from this function's egress IP,
    which is a datacenter address the bank has every reason to distrust.

    Every caller we have — connect, pull-to-refresh, opening the app — is a real
    user action, so claiming user-presence here is accurate. A future scheduled
    background sync must NOT use these.
    """
    try:
        raw = getattr(req, "raw_request", None)
        if raw is None:
            return {}
        h = raw.headers
        fwd = (h.get("X-Forwarded-For") or "").split(",")[0].strip()
        ip = fwd or (raw.remote_addr or "")
        if not ip:
            return {}
        out = {"Psu-Ip-Address": ip, "Psu-Http-Method": "GET"}
        for src, dst in (("User-Agent", "Psu-User-Agent"),
                         ("Accept", "Psu-Accept"),
                         ("Accept-Charset", "Psu-Accept-Charset"),
                         ("Accept-Encoding", "Psu-Accept-Encoding"),
                         ("Accept-Language", "Psu-Accept-Language")):
            v = h.get(src)
            if v:
                out[dst] = v
        return {k: v for k, v in out.items() if v}
    except Exception:  # noqa: BLE001 — never let header plumbing break a scan
        logging.exception("psu: could not read the caller's headers")
        return {}


def _fresh_days(data: dict) -> int | None:
    """How many days of NEW data the phone is asking for, or None for a full scan.

    Clamped: below a week and a bank that posts late (or a missed sync) leaves a
    hole; above ~90 days there is nothing left to save. Anything unparseable
    means "just do the full scan" — the safe direction.
    """
    raw = (data or {}).get("freshDays")
    try:
        n = int(raw)
    except (TypeError, ValueError):
        return None
    if n <= 0:
        return None
    return max(7, min(n, 90))


# How many accounts to hit Enable Banking for at once. Each account costs two
# blocking HTTP round-trips (balance, then transactions) to the ASPSP behind
# Enable Banking, and those round-trips are the whole latency — nothing here is
# CPU work. Scanned one account at a time, four accounts (one bank + a
# multi-currency Revolut) meant four accounts' worth of real-bank latency added
# up in series, which is most of where "sync takes about a minute" came from.
# Bounded rather than unlimited so a user with a dozen accounts doesn't open a
# dozen simultaneous connections to one ASPSP and get rate-limited for it.
_SCAN_WORKERS = 6


def _scan_one_account(client: EnableBankingClient, m: dict, *, months_back: int,
                      psu_available: dict | None, today=None):
    """Balance + transactions for ONE account. Never raises — every failure path
    returns a result dict, so a thread pool can run these concurrently and the
    caller just merges whatever comes back, in order, with no exception to catch
    at the boundary between threads."""
    bank = _bank_from_iban(m.get("iban")) or m.get("bank") or "Bankas"
    is_revolut = "revolut" in str(m.get("name", "")).lower() \
        or "revolut" in str(bank or "").lower()
    psu = client.psu_headers_for(bank, DEFAULT_COUNTRY, psu_available or {}) \
        if psu_available else {}
    try:
        # Balance FIRST — before the heavy transaction paging burns through the
        # bank's rate limit. Swedbank has a low cap: fetched after ~2 min of
        # paging it returned 429 → silently 0. Fresh at the top, it succeeds.
        bal, bal_ccy = normalize.pick_balance(client.balances(m["uid"], psu=psu))
        # `today` — without it this fell back to the SERVER's own UTC date
        # (EnableBankingClient.transactions' own `today or dt.date.today()`
        # default), never the caller-computed client-local one already
        # threaded into _merge_known/_build_result a few lines up from here.
        # Cloud Run's UTC clock runs behind Lithuania's by 2-3 hours, so the
        # "freshest window" (`d_to = today`) could end a few hours short of
        # the user's actual today — on top of, not instead of, Enable
        # Banking's own reporting lag for a transaction made minutes ago.
        acc_txns, diag = client.transactions(m["uid"], months_back=months_back,
                                             psu=psu, today=today)
        for t in acc_txns:
            # Tag every entry with the bank it came from: it's what lets the
            # phone's cache be merged back per-bank when one bank goes quiet.
            t["_bank"] = bank
            # ALSO the account. A bank's entry_reference is only promised to be
            # unique within one account — several number their entries per
            # account, so two wallets at the same bank can both return "1".
            # Deduping on the reference alone then silently DROPPED one of two
            # real transactions.
            t["_acct"] = m["uid"]
        ccy = normalize.real_currency(bal_ccy, m.get("currency"))
        return {
            "ok": True, "bank": bank, "txns": acc_txns, "currency": ccy,
            "summary": {
                "name": m["name"], "amount": bal, "sub": m.get("sub"),
                "icon": "R" if is_revolut else "bank",
                "currency": ccy, "bank": bank, "iban": m.get("iban"),
                # This account's own uid — lets _build_result fill in a missing
                # transaction currency (see there) from the RIGHT account
                # instead of a dashboard-wide guess.
                "uid": m.get("uid"),
            },
            "diag": {"account": m["name"], "bank": bank, **diag},
        }
    except EnableBankingError as e:
        logging.warning("scan: account %r (%s) failed, skipping: %s",
                        _mask_label(m.get("name")), bank, e)
        status = getattr(e, "status", None)
        return {
            "ok": False, "bank": bank,
            "diag": {
                "account": m["name"], "bank": bank, "error": str(e),
                # Account identity so the client can drop ONLY the revoked
                # wallet, not every same-named bank connection (a Revolut
                # EUR + NOK pair shares an IBAN, so name/IBAN alone would wipe
                # both).
                "iban": m.get("iban"), "currency": m.get("currency"),
                "rateLimited": status == 429,
                # 401/403 means the bank is refusing us, not failing: the
                # consent expired or the user withdrew it in their bank. That
                # has to be told apart from a quiet bank, because the two
                # deserve opposite treatment — one gets its cached data
                # re-served, the other must stop being shown at all.
                "revoked": status in (401, 403),
            },
        }
    except Exception as e:  # noqa: BLE001
        # 2026-08-16: this docstring promised "never raises" but only
        # EnableBankingError was ever caught — a raw network fault
        # (requests.exceptions.Timeout/ConnectionError, a malformed JSON
        # body, anything the enable_banking.py client didn't wrap) escaped
        # this function, propagated through _scan_accounts' thread pool,
        # and crashed the WHOLE finish_bank_auth/refresh_dashboard call —
        # a user with 3 banks lost their entire dashboard because ONE bank
        # timed out, instead of losing just that one bank's data like every
        # other failure mode here already correctly does. Treated the same
        # as a quiet (not revoked, not rate-limited) failure — the client
        # already has a path for that (cached data re-served).
        logging.warning("scan: account %r (%s) failed with an unexpected "
                        "error, skipping: %s", _mask_label(m.get("name")), bank, e)
        return {
            "ok": False, "bank": bank,
            "diag": {
                "account": m["name"], "bank": bank, "error": str(e),
                "iban": m.get("iban"), "currency": m.get("currency"),
                "rateLimited": False, "revoked": False,
            },
        }


def _scan_accounts(client: EnableBankingClient, metas: list, *, months_back: int,
                   psu_available: dict | None = None, today=None):
    """Fetch transactions + current balance for each account BY UID (no session
    needed — Enable Banking addresses accounts directly, so this works for a
    freshly-created session AND for a stored multi-bank refresh weeks later).

    Accounts are scanned CONCURRENTLY — the work is blocking I/O to a real
    bank's servers, not CPU, so running them in series meant a user's total wait
    was every account's latency added together. `ex.map` preserves input order,
    so the merge below is deterministic regardless of which account's request
    actually finishes first.

    Per-account isolation: one account failing (timeout / expired consent) never
    aborts the rest — it's logged into ``scan_diag`` and the scan carries on with
    a partial-but-usable result.

    Returns ``(all_txns, account_summaries, scan_diag, own_ibans)`` where
    ``own_ibans`` is the set of the user's OWN account IBANs across every bank —
    the basis for neutralising own-account (SEB↔Revolut) transfers.
    """
    all_txns: list = []
    summaries: list = []
    scan_diag: list = []
    own_ibans: set = set()
    seen_uids: set = set()
    to_fetch: list = []
    for m in metas:
        uid = m.get("uid")
        if not uid:
            continue
        # The same account can arrive twice — a bank reconnected under a second
        # label, or a stale stored ref alongside a fresh one. Transactions are
        # de-duplicated later, but balances are not: scanning it twice appends
        # the summary twice and shows the user more money than they have.
        if uid in seen_uids:
            continue
        seen_uids.add(uid)
        norm = _norm_iban(m.get("iban"))
        if norm:
            own_ibans.add(norm)
        to_fetch.append(m)

    if not to_fetch:
        return all_txns, summaries, scan_diag, own_ibans

    with ThreadPoolExecutor(max_workers=min(_SCAN_WORKERS, len(to_fetch))) as ex:
        results = list(ex.map(
            lambda m: _scan_one_account(client, m, months_back=months_back,
                                        psu_available=psu_available, today=today),
            to_fetch))

    for m, r in zip(to_fetch, results):
        scan_diag.append(r["diag"])
        if not r["ok"]:
            continue
        all_txns.extend(r["txns"])
        # Carry the REAL balance currency back onto the account meta so the
        # stored connection can tell a Revolut EUR wallet from its NOK wallet:
        # the two share ONE IBAN and the account object frequently reports no
        # currency (→ defaulted to EUR), which made connecting one wipe the
        # other. The balance always carries the true currency.
        m["currency"] = r["currency"]
        summaries.append(r["summary"])
    return all_txns, summaries, scan_diag, own_ibans


def _client_today(data: dict):
    """The phone's local date, or None to fall back to the server's.

    Cloud Run runs in UTC and the user does not. At 01:30 on a Monday in
    Lithuania it is still Sunday 22:30 UTC, so "this week" was computed as the
    PREVIOUS week and the whole week view shifted seven days; in the first hours
    of a month, "this month" was still last month. Recurring due dates and their
    active/late status flipped depending on the hour the scan happened to run.
    The date has to come from the device, because only it knows where the user
    is.
    """
    raw = data.get("today")
    if not raw:
        return None
    try:
        return dt.date.fromisoformat(str(raw)[:10])
    except (TypeError, ValueError):
        logging.warning("today: unusable value %r from client", raw)
        return None


def _build_result(all_txns: list, summaries: list, own_ibans: set,
                  scan_diag: list, ai_enabled: bool, stale_banks=None,
                  today=None) -> dict:
    """Shared tail for finish_bank_auth + refresh_dashboard: dedupe, detect
    recurring, build the (multi-bank-aware) dashboard, and package the response.
    Nothing is persisted server-side (privacy-first)."""
    raw = len(all_txns)
    # Normalise FIRST (fills empty names, string→list remittance, missing indicator,
    # bare amount) so dedup's composite key + every downstream stage see clean data.
    normalize.normalize_transactions(all_txns)
    all_txns = normalize.dedupe(all_txns)
    if len(all_txns) != raw:
        logging.info("scan: deduped %d -> %d transactions", raw, len(all_txns))
    summaries = _dedupe_summaries(summaries)
    # Fill in a transaction's OWN currency when Enable Banking's amount object
    # carries none at all — seen live on a DNB "Overføring Innland" domestic
    # transfer, though card purchases on the same account always have one.
    # detect_recurring AND build_dashboard both convert through fx.py's
    # to_eur, which treats a missing currency as EUR at rate 1.0 (no
    # conversion) — so an unfixed NOK transfer was valued as if its number
    # were already euros, off by ~11x. Fixed once here, before either
    # downstream stage runs, using the account the transaction actually came
    # from (every transaction is tagged "_acct" at scan time) rather than one
    # dashboard-wide guess, which degrades to EUR for anyone with more than
    # one account currency — a Swedbank EUR account + a DNB NOK account is
    # exactly that case, live.
    _acct_cur = {s.get("uid"): (s.get("currency") or "").upper()
                 for s in summaries if s.get("uid")}
    for t in all_txns:
        ta = t.get("transaction_amount")
        if isinstance(ta, dict) and not ta.get("currency"):
            ta["currency"] = _acct_cur.get(t.get("_acct")) or "EUR"
    # How much of this scan carried an MCC — the universal category signal. Some
    # banks send it on every card purchase (Revolut), some send none (older
    # banks). Logging it per scan is how we learn, from real usage, which banks
    # cover the long tail via MCC and which lean entirely on the name resolver.
    _dbit = [t for t in all_txns if t.get("credit_debit_indicator") == "DBIT"]
    _with_mcc = sum(1 for t in _dbit if t.get("merchant_category_code"))
    if _dbit:
        logging.info("scan: mcc coverage %d/%d card txns (%.0f%%)",
                     _with_mcc, len(_dbit), 100 * _with_mcc / len(_dbit))
    # The user's own account-holder names (for self-transfers a bank sends with a
    # name but no counterparty IBAN — see detect_recurring's own_name match).
    own_names = [s.get("name") for s in summaries if s.get("name")]
    try:
        detection = detect_recurring(all_txns, own_ibans=own_ibans,
                                     own_names=own_names, today=today)
    except Exception:  # noqa: BLE001
        logging.exception("detect_recurring failed")
        detection = {"candidates": [], "frequent": []}
    ai_key = ANTHROPIC_API_KEY.value if ai_enabled else None
    try:
        dash = build_dashboard(all_txns, summaries, own_ibans=own_ibans,
                               ai_key=ai_key, today=today)
    except Exception:  # noqa: BLE001
        logging.exception("build_dashboard failed")
        dash = None
    logging.info("scan: accounts=%d txns=%d candidates=%d frequent=%d",
                 len(summaries), len(all_txns),
                 len(detection["candidates"]), len(detection["frequent"]))
    # Redact before logging: a nameless account's label falls back to its IBAN in
    # `_account_meta`, and the error-path diag entries carry a raw `iban` field —
    # both would leak a real IBAN into Cloud Logging. Mask anything IBAN-shaped in
    # BOTH the account label and the iban field.
    def _redact(d):
        r = dict(d)
        if "account" in r:
            r["account"] = _mask_label(r["account"])
        if "iban" in r:
            r["iban"] = _mask_iban(r["iban"])
        return r
    logging.info("scan scan_diag=%s", [_redact(d) for d in scan_diag])
    return {
        "accountCount": len(summaries),
        "transactionCount": len(all_txns),
        "candidates": detection["candidates"],
        "frequent": detection["frequent"],
        "dash": dash,
        "scanDiag": scan_diag,
        # What the phone should keep and hand back on the next scan, so a bank
        # that goes quiet then can be filled in from here instead of vanishing.
        # Booked only: pending entries still move, and a cancelled one must not
        # be able to live on in a cache.
        "known": {
            "txns": [t for t in all_txns if t.get("status") == "BOOK"],
            "accounts": summaries,
        },
        # Banks whose data in THIS payload came from that cache, not the bank.
        "staleBanks": stale_banks or [],
    }


@https_fn.on_call(region=_REGION, secrets=[ENABLE_BANKING_PRIVATE_KEY])
def list_banks(req: https_fn.CallableRequest) -> dict:
    """Return the banks a user can connect to for ``country`` (default LT)."""
    _require_auth(req)
    rid = _begin(req, "list_banks")
    country = (req.data or {}).get("country", DEFAULT_COUNTRY)
    try:
        aspsps = _client().list_aspsps(country)
    except EnableBankingError as e:
        # The three endpoints where connecting a bank actually breaks
        # used to log NOTHING — the detail went only to the phone, so a
        # user reporting "it won't connect" left no trace to look at.
        logging.exception("list_banks failed rid=%s status=%s", rid,
                          getattr(e, "status", None))
        raise https_fn.HttpsError(
            code=https_fn.FunctionsErrorCode.INTERNAL,
            message="Could not load banks.",
        )
    banks = [
        {
            "name": a.get("name"),
            "country": a.get("country", country),
            "logo": a.get("logo"),
            "sandbox": bool(a.get("sandbox")),
        }
        for a in aspsps
        if a.get("name")
    ]
    return {"banks": banks}


# PROTOTYPE (2026-08-27) — see stock_quote.py's own docstring. Isolated on
# purpose: this function, that module, and investing_tab.dart are the whole
# feature's surface, so it can be deleted cleanly (this one registration
# line included, plus stock_search/stock_profile below) if the feature
# doesn't work out.
#
# 2026-08-28: deliberately NOT behind _require_auth, unlike every other
# function here. A ticker's public market price isn't this user's data the
# way a bank balance is — there's nothing to protect. Requiring auth anyway
# caused the real bug this comment replaced: any build without a real signed-
# in session (the design-preview sandbox, tested live) got UNAUTHENTICATED
# on every single quote, and _totalCard's spinner had no "all failed" state
# to fall back to — it just spun forever, reading as "broken" rather than
# "rejected". Confirmed directly against the deployed endpoint (curl, no
# token) that UNAUTHENTICATED came back in 150ms, not a hang — so the fix
# belongs here, not in a timeout.
@https_fn.on_call(region=_REGION, secrets=[FINNHUB_API_KEY])
def stock_quote(req: https_fn.CallableRequest) -> dict:
    """Current price + previous close for one ticker symbol."""
    symbol = str((req.data or {}).get("symbol") or "").strip()
    if not symbol:
        raise https_fn.HttpsError(
            code=https_fn.FunctionsErrorCode.INVALID_ARGUMENT,
            message="Missing symbol.",
        )
    result = _stock_quote(symbol, FINNHUB_API_KEY.value)
    if result is None:
        raise https_fn.HttpsError(
            code=https_fn.FunctionsErrorCode.NOT_FOUND,
            message="Could not fetch a price for that symbol.",
        )
    return result


@https_fn.on_call(region=_REGION, secrets=[FINNHUB_API_KEY])
def stock_search(req: https_fn.CallableRequest) -> dict:
    """Live ticker search (any global stock, not a fixed list) — see
    stock_quote.py's search() for why results are filtered to bare US
    listings. Same no-auth reasoning as stock_quote: public data."""
    query = str((req.data or {}).get("query") or "").strip()
    return {"results": _stock_search(query, FINNHUB_API_KEY.value)}


@https_fn.on_call(region=_REGION, secrets=[FINNHUB_API_KEY])
def stock_profile(req: https_fn.CallableRequest) -> dict:
    """The one extra call made when a user PICKS a search result (not per
    row) — resolves a real brand domain for CategoryIcon's existing
    merchant-logo proxy to fetch a logo from."""
    symbol = str((req.data or {}).get("symbol") or "").strip()
    result = _stock_profile(symbol, FINNHUB_API_KEY.value)
    return result or {}


@https_fn.on_call(region=_REGION, secrets=[ENABLE_BANKING_PRIVATE_KEY])
def delete_user_data(req: https_fn.CallableRequest) -> dict:
    """Erase a user's server-side footprint and REVOKE their bank consents.

    The client calls this from the "delete account" flow BEFORE Firebase auth
    deletion (which needs the still-valid token). It is deliberately NOT premium-
    gated — a lapsed user must still be able to delete themselves. The bank side is
    best-effort: a session we cannot reach is logged, never blocks the erasure. The
    "delete account" dialog promises the bank connection is severed; this is what
    makes that true (and closes the GDPR right-to-erasure gap where the Enable
    Banking consent lived on for ~90 days and the bank_links record forever).
    """
    _require_auth(req)
    uid = _uid(req)
    session_ids = [str(s) for s in ((req.data or {}).get("sessionIds") or []) if s]
    # IDOR guard: revoke ONLY sessions this user is recorded as owning, never a
    # session id the caller merely supplied — otherwise a signed-in user could
    # pass someone else's session id and revoke their bank access.
    to_revoke = _authorised_sessions(session_ids, _owned_sessions(uid))
    revoked = 0
    if to_revoke:
        try:
            client = _client()
            for sid in to_revoke:
                if client.delete_session(sid):
                    revoked += 1
                else:
                    _log_orphaned_session(uid, sid, reason="delete_user_data: revoke failed")
        except Exception:  # noqa: BLE001
            logging.exception("delete_user_data: session revoke error uid=%s", uid)
            for sid in to_revoke:
                _log_orphaned_session(uid, sid, reason="delete_user_data: revoke exception")
    # Local import mirrors the sibling functions (_remember_accounts / _owned_accounts);
    # `firestore` is not a module-level name, so without this the whole callable
    # raised NameError and never deleted the documents it exists to erase.
    from firebase_admin import firestore
    db = firestore.client()
    # bank_auth_states added 2026-08-16 for the OAuth state check — omitted
    # from this cleanup loop at the time, so a user who started (but never
    # finished) a bank connection and then deleted their account left a
    # stray document behind. Harmless on its own (a random token + timestamp,
    # useless after 30 min — see _auth_state_fresh), but a real exception to
    # "delete_user_data erases everything."
    for coll in (_BANK_LINKS, _BANK_AUTH_STATES, "entitlements"):
        try:
            db.collection(coll).document(uid).delete()
        except Exception:  # noqa: BLE001
            logging.exception("delete_user_data: %s cleanup failed uid=%s", coll, uid)
    logging.info("delete_user_data uid=%s revoked=%d/%d owned sessions (%d requested)",
                 uid, revoked, len(to_revoke), len(session_ids))
    return {"revoked": revoked, "sessions": len(to_revoke)}


def _disconnect_plan(session_ids, account_uids, owned_sessions, owned_accounts):
    """Which ids a disconnect may actually touch: ``(sessions, accounts)``.

    Pure, so it can be tested — and it is the part worth testing. Everything the
    caller sent is filtered against what the user is RECORDED as owning: without
    that, a signed-in user could pass someone else's session id and revoke their
    bank access, which is the hole delete_user_data was fixed for.

    Returned sorted so a caller cannot depend on request order.
    """
    # set() before sorting: _authorised_sessions preserves what the caller sent,
    # so a repeated id meant revoking the same session twice.
    sessions = sorted(set(_authorised_sessions(session_ids, owned_sessions)))
    accounts = sorted({a for a in account_uids if a in owned_accounts})
    return sessions, accounts


@https_fn.on_call(region=_REGION, secrets=[ENABLE_BANKING_PRIVATE_KEY])
def disconnect_bank(req: https_fn.CallableRequest) -> dict:
    """Revoke ONE bank's consent and forget its accounts, leaving the rest alone.

    Until this existed the only way out was "disconnect everything and start
    again": someone with two banks who wanted rid of one had to drop both and
    walk the consent flow again for the one they were keeping. Enable Banking
    also bills per connected user, so a consent nobody wants is a standing cost.

    Deliberately NOT premium-gated. Withdrawing access to your own bank data is
    the one thing a lapsed subscriber must always be able to do — the same
    reasoning as delete_user_data.

    Same IDOR guard as delete_user_data: only sessions and accounts this user is
    RECORDED as owning are touched, never an id the caller merely supplied.
    """
    _require_auth(req)
    uid = _uid(req)
    data = req.data or {}
    session_ids = [str(s) for s in (data.get("sessionIds") or []) if s]
    account_uids = [str(a) for a in (data.get("accountUids") or []) if a]
    if not session_ids and not account_uids:
        raise https_fn.HttpsError(
            code=https_fn.FunctionsErrorCode.INVALID_ARGUMENT,
            message="Nothing to disconnect.",
        )
    to_revoke, to_forget = _disconnect_plan(
        session_ids, account_uids, _owned_sessions(uid), _owned_accounts(uid))
    revoked = 0
    if to_revoke:
        try:
            client = _client()
            for sid in to_revoke:
                if client.delete_session(sid):
                    revoked += 1
                else:
                    _log_orphaned_session(uid, sid, reason="disconnect_bank: revoke failed")
        except Exception:  # noqa: BLE001
            # Best-effort, exactly as in delete_user_data: a session we cannot
            # reach must not block the user from removing the bank locally. The
            # consent then lapses at the ~90-day cliff, which is the safe
            # direction to fail in.
            logging.exception("disconnect_bank: revoke error uid=%s", uid)
            for sid in to_revoke:
                _log_orphaned_session(uid, sid, reason="disconnect_bank: revoke exception")
    from firebase_admin import firestore
    try:
        doc = firestore.client().collection(_BANK_LINKS).document(uid)
        payload = {}
        if to_forget:
            payload["accounts"] = firestore.ArrayRemove(to_forget)
        if to_revoke:
            payload["sessions"] = firestore.ArrayRemove(to_revoke)
        if payload:
            # ArrayRemove, never a document delete: the OTHER banks' accounts live
            # in the same record, and dropping it would lock the user out of
            # refreshing the banks they kept.
            doc.set(payload, merge=True)
    except Exception:  # noqa: BLE001
        logging.exception("disconnect_bank: bank_links cleanup failed uid=%s", uid)
    logging.info("disconnect_bank uid=%s revoked=%d/%d accounts_forgotten=%d",
                 uid, revoked, len(to_revoke), len(to_forget))
    return {"revoked": revoked, "forgotten": len(to_forget)}


@https_fn.on_call(region=_REGION,
                  secrets=[ENABLE_BANKING_PRIVATE_KEY, REVENUECAT_API_KEY])
def start_bank_auth(req: https_fn.CallableRequest) -> dict:
    """Begin consent for ``aspspName`` and return the bank's authorization URL."""
    _require_auth(req)
    # Premium-gate the START too, not just finish_bank_auth: otherwise a lapsed
    # user could create a real 90-day bank consent and only be refused AFTER
    # approving at the bank — burning a consent slot for nothing.
    _require_premium(req)
    rid = _begin(req, "start_bank_auth")
    data = req.data or {}
    name = data.get("aspspName")
    if not name:
        raise https_fn.HttpsError(
            code=https_fn.FunctionsErrorCode.INVALID_ARGUMENT,
            message="aspspName is required.",
        )
    country = data.get("country", DEFAULT_COUNTRY)
    client = _client()
    try:
        app = client.application()
        redirects = app.get("redirect_urls", [])
        if not redirects:
            raise https_fn.HttpsError(
                code=https_fn.FunctionsErrorCode.FAILED_PRECONDITION,
                message="No redirect URL is registered for this Enable Banking app.",
            )
        # Use the client's requested redirect only if it is actually registered
        # for this app (Enable Banking rejects unregistered URLs); otherwise fall
        # back to the first registered one.
        requested = data.get("redirectUrl")
        redirect_url = requested if requested in redirects else redirects[0]
        url, state = client.start_auth(name, country, redirect_url)
    except EnableBankingError as e:
        # The three endpoints where connecting a bank actually breaks
        # used to log NOTHING — the detail went only to the phone, so a
        # user reporting "it won't connect" left no trace to look at.
        logging.exception("start_bank_auth failed rid=%s status=%s", rid,
                          getattr(e, "status", None))
        raise https_fn.HttpsError(
            code=https_fn.FunctionsErrorCode.INTERNAL,
            message="Could not start bank authorization.",
        )
    # Tie this state to the caller BEFORE handing it back — finish_bank_auth
    # verifies it later (see _consume_auth_state). Outside the try/except
    # above on purpose: a failure here should surface as this call failing,
    # not as a silently-unprotected auth flow.
    _remember_auth_state(_uid(req), state)
    return {"url": url, "state": state}


@https_fn.on_call(
    region=_REGION,
    secrets=[ENABLE_BANKING_PRIVATE_KEY, ANTHROPIC_API_KEY, REVENUECAT_API_KEY],
    # The 12-month windowed scan (many bank pages) plus classification can run
    # well past the 60s default on a cold start — give it room, and more memory
    # for a faster cold start + the in-RAM merchant KB.
    timeout_sec=300,
    memory=options.MemoryOption.MB_512,
    # Firebase's own default cap (visible in the console as "Min/Max
    # Instances": 0/20, identical across every function — nobody set it, it's
    # the platform default for a Blaze free-trial project) means at most 20
    # of THIS function can run at once. Every other endpoint here finishes in
    # seconds, so 20 cycles through a burst fast regardless. This one can hold
    # an instance for up to the 5-minute timeout above (a real 12-month scan),
    # so it is the one place a synchronised traffic spike — e.g. a social post
    # everyone taps within the same minute — turns into a queue. Raised well
    # clear of any realistic launch-week burst; costs nothing unless the
    # capacity is actually used.
    max_instances=200,
)
def finish_bank_auth(req: https_fn.CallableRequest) -> dict:
    """Exchange the redirect ``code``, fetch transactions, detect recurring ones.

    Returns only the recurring-payment *candidates* — never the raw transactions.
    """
    _require_auth(req)
    rid = _begin(req, "finish_bank_auth")
    _require_premium(req)
    data = req.data or {}
    code = data.get("code")
    if not code:
        raise https_fn.HttpsError(
            code=https_fn.FunctionsErrorCode.INVALID_ARGUMENT,
            message="code is required.",
        )
    # Proves this code came from a consent flow THIS caller's OWN
    # start_bank_auth started (see _consume_auth_state) — without it, any
    # signed-in caller could exchange a code obtained through someone else's
    # unrelated auth flow and bind those accounts to themselves.
    if not _consume_auth_state(_uid(req), data.get("state")):
        logging.warning("finish_bank_auth: state check failed rid=%s uid=%s",
                        rid, _uid(req))
        raise https_fn.HttpsError(
            code=https_fn.FunctionsErrorCode.PERMISSION_DENIED,
            message="This bank connection could not be verified — please try connecting again.",
        )
    # Fetch newest window first (see EnableBankingClient.transactions): recent
    # data is always retrieved even on oldest-first banks, and the deeper history
    # feeds salary + subscription detection.
    #
    # 12 months. The service runs at 300s/512Mi so a cold-start 12-month scan
    # fits. NOTE: `firebase deploy` resets Cloud Run back to 60s/256Mi (a
    # firebase-tools Python-discovery bug), so ALWAYS restore it afterwards via
    # `functions/deploy.sh` (gcloud run services update … --timeout=300 …), or a
    # cold 12-month scan will DEADLINE_EXCEEDED.
    months_back = _coerce_months(data.get("monthsBack", 12))
    bank = data.get("bank")  # the bank the user just connected (for the label)

    client = _client()
    # Creating the session is the one hard prerequisite — if it fails there is
    # nothing to scan, so this stays a fatal error.
    try:
        session = client.create_session(code)
    except EnableBankingError as e:
        # The three endpoints where connecting a bank actually breaks
        # used to log NOTHING — the detail went only to the phone, so a
        # user reporting "it won't connect" left no trace to look at.
        logging.exception("finish_bank_auth failed rid=%s status=%s", rid,
                          getattr(e, "status", None))
        raise https_fn.HttpsError(
            code=https_fn.FunctionsErrorCode.INTERNAL,
            message="Could not fetch transactions.",
        )
    metas = [_account_meta(a, bank) for a in session.get("accounts", [])]
    # Bind these accounts to the caller before fetching anything. This is the
    # only moment we can prove ownership — the consent that produced `code` was
    # granted by the person holding this Firebase session.
    _remember_accounts(_uid(req), [m.get("uid") for m in metas],
                       session_id=session.get("session_id"))
    # Computed before the scan (not after, as it used to be) — the fetch
    # window itself needs the caller's real local date, same as
    # _merge_known/_build_result below already get.
    today = _client_today(data)
    all_txns, summaries, scan_diag, own_ibans = _scan_accounts(
        client, metas, months_back=months_back, psu_available=_psu_available(req),
        today=today)
    ai_enabled = bool(data.get("aiEnrichment"))
    # This scan only covers the bank being connected, so the phone's cache of the
    # OTHER banks is what keeps them whole in the combined payload.
    all_txns, summaries, own_ibans, stale = _merge_known(
        all_txns, summaries, own_ibans, scan_diag, data.get("known") or {},
        months_back, today=today)
    result = _build_result(all_txns, summaries, own_ibans, scan_diag, ai_enabled,
                           stale_banks=stale, today=today)
    # `connection` lets the client STORE this bank (session id + account uids +
    # IBANs) so it can be re-fetched later — without another login — and merged
    # with other banks by refresh_dashboard. The account IBANs are the user's own
    # and stay on-device (same privacy model as the rest of the scan).
    result["connection"] = {
        "sessionId": session.get("session_id"),
        "bank": bank,
        # So the app can warn before the bank stops answering — see
        # _consent_valid_until.
        "validUntil": _consent_valid_until(session),
        "accounts": [
            {"uid": m["uid"], "iban": m["iban"], "name": m["name"],
             "currency": m["currency"], "sub": m.get("sub")}
            for m in metas if m.get("uid")
        ],
    }
    return result


@https_fn.on_call(
    region=_REGION,
    secrets=[ENABLE_BANKING_PRIVATE_KEY, ANTHROPIC_API_KEY, REVENUECAT_API_KEY],
    timeout_sec=300,
    memory=options.MemoryOption.MB_512,
    # Same reasoning as finish_bank_auth's max_instances: this is the OTHER
    # endpoint that can hold an instance for minutes (every multi-bank
    # refresh, and the background 12-month deepen after every connect), and
    # it fires for every signed-in user on app open / pull-to-refresh, not
    # just new connections. See finish_bank_auth for the full rationale.
    max_instances=200,
)
def refresh_dashboard(req: https_fn.CallableRequest) -> dict:
    """Re-fetch ALL of a user's connected banks by account UID (no re-login) and
    build ONE combined dashboard.

    The client sends the accounts it stored at connect time:
    ``{accounts: [{uid, bank, iban, name, currency}, …], monthsBack, aiEnrichment}``.
    Enable Banking addresses accounts directly, so as long as each bank's consent
    is still valid (~90 days) this needs no user interaction. An account whose
    consent expired surfaces in ``scanDiag[].error`` so the client can prompt a
    reconnect for just that bank.

    The requested accounts are checked against the ones this user actually
    connected (see [_remember_accounts]). They arrive from the phone, so without
    that check any signed-in user could read anyone else's bank history simply
    by naming their account uid.
    """
    _require_auth(req)
    rid = _begin(req, "refresh_dashboard")
    _require_premium(req)
    data = req.data or {}
    accounts_in = data.get("accounts") or []
    if not isinstance(accounts_in, list) or not accounts_in:
        raise https_fn.HttpsError(
            code=https_fn.FunctionsErrorCode.INVALID_ARGUMENT,
            message="accounts is required.",
        )
    months_back = _coerce_months(data.get("monthsBack", 12))
    ai_enabled = bool(data.get("aiEnrichment"))
    uid = _uid(req)
    owned = _owned_accounts(uid)
    requested = [_account_meta(a, a.get("bank")) for a in accounts_in
                 if isinstance(a, dict)]
    metas = _authorised_metas(requested, owned)
    if len(metas) != len(requested):
        # Either someone is probing with account uids that aren't theirs, or a
        # user connected before ownership was recorded. Both end the same way:
        # we refuse, and the client asks them to reconnect.
        logging.warning(
            "refresh_dashboard rid=%s uid=%s requested %d accounts, owns %d",
            rid, uid, len(requested), len(metas))
    if not metas:
        raise https_fn.HttpsError(
            code=https_fn.FunctionsErrorCode.PERMISSION_DENIED,
            message="These bank connections aren't linked to your account. "
                    "Please reconnect your bank.",
        )
    today = _client_today(data)
    known = data.get("known") or {}
    # ── Incremental refresh ──────────────────────────────────────────────────
    # The phone sends how many days it actually needs from the bank. Everything
    # older it already holds, and a booked transaction never changes, so asking
    # the bank for six months on every refresh re-downloads data we have.
    #
    # Only when the phone HAS that history: a cache with no transactions (fresh
    # install, first refresh after a wipe) falls back to the full window, or the
    # dashboard would come back holding three weeks and nothing else.
    fresh_days = _fresh_days(data)
    has_history = bool(isinstance(known, dict) and known.get("txns"))
    fetch_months = months_back
    fresh_from = None
    if fresh_days and has_history:
        fresh_from = (today - dt.timedelta(days=fresh_days)).isoformat()
        fetch_months = max(1, (fresh_days + 29) // 30)
    all_txns, summaries, scan_diag, own_ibans = _scan_accounts(
        _client(), metas, months_back=fetch_months,
        psu_available=_psu_available(req), today=today)
    all_txns, summaries, own_ibans, stale = _merge_known(
        all_txns, summaries, own_ibans, scan_diag, known,
        months_back, today=today, fresh_from=fresh_from)
    return _build_result(all_txns, summaries, own_ibans, scan_diag, ai_enabled,
                         stale_banks=stale, today=today)


@https_fn.on_call(
    region=_REGION,
    secrets=[ANTHROPIC_API_KEY, REVENUECAT_API_KEY],
    timeout_sec=60,
    memory=options.MemoryOption.MB_256,
)
def finance_chat(req: https_fn.CallableRequest) -> dict:
    """Answer a signed-in user's question about their own finances.

    The client sends ``{summary, messages}`` — a compact, PII-free finance
    summary it built from the on-device dashboard, plus the conversation so far.
    Nothing is persisted; the summary lives only for this request. Uses Haiku
    (cheap) with the ANTHROPIC secret; if the key/credits are unavailable the
    chat module returns a graceful fallback rather than raising.
    """
    _require_auth(req)
    rid = _begin(req, "finance_chat")
    _require_premium(req)
    _check_daily_cap(_uid(req), "finance_chat", 40, rid)
    data = req.data or {}
    reply = _finance_chat(
        summary=str(data.get("summary") or ""),
        history=data.get("messages") or [],
        api_key=ANTHROPIC_API_KEY.value,
        # The phone's UI language. The chat used to infer the reply language from
        # the question, but with Lithuanian finance data it drifted to LT even for
        # an English question — so the app language is passed in explicitly (as
        # month_summary already does). Defaults to LT for older clients.
        lang=str(data.get("lang") or "lt"),
    )
    return {"reply": reply}


@https_fn.on_call(
    region=_REGION,
    secrets=[ANTHROPIC_API_KEY, REVENUECAT_API_KEY],
    timeout_sec=60,
    memory=options.MemoryOption.MB_256,
)
def month_summary(req: https_fn.CallableRequest) -> dict:
    """Write a short AI narrative for one month's review card.

    The client sends ``{stats}`` — a compact, PII-free block of numbers it
    computed on-device (income, spending, net, top categories, savings rate,
    vs last month). Returns ``{text}`` (empty on failure so the client falls
    back to its own templated summary). Nothing is persisted.
    """
    _require_auth(req)
    rid = _begin(req, "month_summary")
    _require_premium(req)
    _check_daily_cap(_uid(req), "month_summary", 5, rid)
    data = req.data or {}
    text = _month_report(
        stats=str(data.get("stats") or ""),
        api_key=ANTHROPIC_API_KEY.value,
        # The phone's UI language. Nothing in a monthly summary is written by
        # the user, so the language can't be inferred from it the way the chat
        # infers it from the question — it has to be passed in. Defaults to
        # Lithuanian for older clients that don't send it.
        lang=str(data.get("lang") or "lt"),
    )
    return {"text": text}


@https_fn.on_call(
    region=_REGION,
    secrets=[ANTHROPIC_API_KEY, REVENUECAT_API_KEY],
    # 45s was too tight: a vision call generating up to 4000 tokens can
    # legitimately run longer than a text-only chat reply, and
    # receipt_scan's own retry loop (2 attempts x _TIMEOUT=45s) can already
    # approach 90s on its own — the function's own budget must cover that,
    # or its timeout fires the request before the retry loop even gets a
    # chance to. Keep in sync with receipt_scan._TIMEOUT if either changes.
    timeout_sec=110,
    memory=options.MemoryOption.MB_256,
)
def scan_receipt(req: https_fn.CallableRequest) -> dict:
    """Parse a photographed paper receipt into categorised line items, to
    PRE-FILL the client's manual split editor (Phase 1 of transaction
    splitting — see dashboard_preview.dart _SplitTransactionScreen).

    The client sends ``{image, mediaType}`` — a base64 photo of the receipt
    (JPEG/PNG). Nothing is persisted server-side; the image lives only for
    this one request, same contract as finance_chat. Returns
    ``{items: [{name, price, category}], total, merchant}`` (merchant is the
    store/restaurant name if legible, else null); an empty items list on any
    failure so the client falls back to its own empty manual editor rather
    than erroring out.
    """
    _require_auth(req)
    rid = _begin(req, "scan_receipt")
    _require_premium(req)
    _check_daily_cap(_uid(req), "scan_receipt", 25, rid)
    data = req.data or {}
    image_b64 = str(data.get("image") or "")
    media_type = str(data.get("mediaType") or "image/jpeg")
    # ~6 MB decoded — guards against an oversized upload eating the call's
    # timeout/memory budget before it ever reaches the API.
    if len(image_b64) > 8_000_000:
        logging.warning("scan_receipt rid=%s image too large (%d chars)",
                         rid, len(image_b64))
        return {"items": [], "total": 0, "merchant": None}
    result = _scan_receipt(image_b64, media_type, ANTHROPIC_API_KEY.value)
    if result is None:
        return {"items": [], "total": 0, "merchant": None}
    return result


@https_fn.on_request(region=_REGION, secrets=[SEED_TOKEN])
def seed_merchants(req: https_fn.Request) -> https_fn.Response:
    """One-time admin endpoint: (re)seed the Firestore merchant DB from the
    bundled merchants_seed.json. Guarded by the SEED_TOKEN secret:

        curl "https://europe-west1-vaultie-1a2c4.cloudfunctions.net/seed_merchants?key=<token>"
    """
    if req.args.get("key") != SEED_TOKEN.value:
        return https_fn.Response("forbidden", status=403)
    try:
        result = _run_seed()
    except Exception as e:  # noqa: BLE001
        logging.exception("seed_merchants failed")
        return https_fn.Response(f"error: {e}", status=500)
    return https_fn.Response(
        json.dumps(result), status=200,
        headers={"Content-Type": "application/json"},
    )


# A bare domain only — no path, no query, nothing a client could smuggle a
# request to an arbitrary internal or third-party URL through.
_DOMAIN_RE = re.compile(
    r"^[a-z0-9]([a-z0-9-]{0,61}[a-z0-9])?(\.[a-z0-9]([a-z0-9-]{0,61}[a-z0-9])?)+$"
)

# Tried in order; first one that actually returns an image wins. Clearbit's
# logos are the nicer, higher-resolution ones for known brands; Google's
# favicon service is the long-tail fallback — small, but it has practically
# every domain that has ever had a website.
_LOGO_SOURCES = (
    "https://logo.clearbit.com/{domain}",
    "https://www.google.com/s2/favicons?domain={domain}&sz=128",
)


@https_fn.on_request(region=_REGION)
def merchant_logo(req: https_fn.Request) -> https_fn.Response:
    """Public logo proxy: GET /merchant_logo?domain=mql5.com

    The resolver (dashboard.py / recurring.py) already guesses a merchant's
    domain from the raw bank descriptor server-side — this is the other half:
    turning that domain into an actual image without the CLIENT ever calling
    a third-party logo service directly. Only a bare domain name crosses this
    boundary, resolved here on the server and never tied to a specific user
    or transaction; Clearbit/Google only ever see "someone, somewhere, wants
    mql5.com's logo," the same as they would for any website visitor.
    Cache-Control lets repeat requests for a domain skip the third-party
    round trip entirely once the client's own image cache has it.
    """
    domain = (req.args.get("domain") or "").strip().lower()
    if not domain or len(domain) > 253 or not _DOMAIN_RE.match(domain):
        return https_fn.Response("bad domain", status=400)
    for source in _LOGO_SOURCES:
        try:
            resp = requests.get(source.format(domain=domain), timeout=5)
            resp.raise_for_status()
            if len(resp.content) < 100:  # a 1×1 placeholder, not a real logo
                continue
        except Exception:
            continue
        return https_fn.Response(
            resp.content, status=200,
            headers={
                "Content-Type": resp.headers.get("Content-Type", "image/png"),
                "Cache-Control": "public, max-age=2592000",
            },
        )
    return https_fn.Response(status=404)
