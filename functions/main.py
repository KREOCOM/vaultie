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

import firebase_admin
from firebase_functions import https_fn, options
from firebase_functions.params import SecretParam

from dashboard import build_dashboard
from enable_banking import DEFAULT_COUNTRY, EnableBankingClient, EnableBankingError
from entitlement import is_premium as _is_premium
from finance_chat import chat as _finance_chat
from finance_chat import month_report as _month_report
from known_cache import merge_known as _merge_known
import normalize
from recurring import detect_recurring
from seed_merchants import seed as _run_seed

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
    if _TEST_BYPASS_PREMIUM:
        return
    if _is_premium(_uid(req), REVENUECAT_API_KEY.value):
        return
    raise https_fn.HttpsError(
        code=https_fn.FunctionsErrorCode.PERMISSION_DENIED,
        message="An active Vaultie Pro subscription is required.",
    )


# The one thing this backend stores. Everything else — transactions, balances,
# the built dashboard — stays in memory and on the phone.
_BANK_LINKS = "bank_links"


def _remember_accounts(uid: str, account_uids: list) -> None:
    """Record which Enable Banking accounts this user consented to.

    Stored deliberately, and it is the minimum that closes a real hole: without
    it the backend cannot tell WHOSE accounts it is being asked to fetch, so any
    signed-in user could read anyone else's transactions just by supplying their
    account uid. Only opaque account identifiers are written — no transactions,
    no balances, no IBANs.
    """
    ids = sorted({str(a) for a in account_uids if a})
    if not ids:
        return
    try:
        from firebase_admin import firestore
        firestore.client().collection(_BANK_LINKS).document(uid).set(
            {"accounts": firestore.ArrayUnion(ids)}, merge=True)
    except Exception:
        # Don't fail a connection the user just completed — their data is in
        # this response and they should see it. The next refresh will deny and
        # ask them to reconnect, which runs this write again. Denying later is
        # the safe direction to fail in.
        logging.exception("bank_links: could not record ownership for uid=%s", uid)


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


def _norm_iban(iban) -> str | None:
    """Uppercase, strip spaces — so own-account IBANs compare regardless of
    formatting."""
    if not iban:
        return None
    return str(iban).replace(" ", "").upper()


def _account_meta(acc: dict, bank: str | None) -> dict:
    """Normalise an Enable Banking account object OR a stored client account ref
    to the fields the scan core needs: uid, name, currency, iban, bank."""
    uid = acc.get("uid") or acc.get("account_uid")
    acct_id = acc.get("account_id") if isinstance(acc.get("account_id"), dict) else {}
    iban = acc.get("iban") or acct_id.get("iban")
    name = acc.get("name") or acc.get("product") or iban or "Sąskaita"
    currency = acc.get("currency") or acct_id.get("currency") or "EUR"
    return {"uid": uid, "name": name, "currency": currency,
            "iban": iban, "bank": bank}


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


def _scan_accounts(client: EnableBankingClient, metas: list, *, months_back: int,
                   psu_available: dict | None = None):
    """Fetch transactions + current balance for each account BY UID (no session
    needed — Enable Banking addresses accounts directly, so this works for a
    freshly-created session AND for a stored multi-bank refresh weeks later).

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
        # Prefer the bank the IBAN identifies — it's authoritative and can't be
        # lost the way the client-passed label can. Fall back to that label (and
        # then a generic word) only when the IBAN isn't a recognised LT one.
        bank = _bank_from_iban(m.get("iban")) or m.get("bank") or "Bankas"
        is_revolut = "revolut" in str(m.get("name", "")).lower() \
            or "revolut" in str(bank or "").lower()
        psu = client.psu_headers_for(bank, DEFAULT_COUNTRY, psu_available or {}) \
            if psu_available else {}
        try:
            # Balance FIRST — before the heavy transaction paging burns through the
            # bank's rate limit. Swedbank has a low cap: fetched after ~2 min of
            # paging it returned 429 → silently 0. Fresh at the top, it succeeds.
            bal, bal_ccy = normalize.pick_balance(client.balances(uid, psu=psu))
            acc_txns, diag = client.transactions(uid, months_back=months_back,
                                                 psu=psu)
            # Tag every entry with the bank it came from: it's what lets the
            # phone's cache be merged back per-bank when one bank goes quiet.
            for t in acc_txns:
                t["_bank"] = bank
            all_txns.extend(acc_txns)
            # Prefer the balance's own currency; 'XXX' ("no currency") isn't real.
            ccy = normalize.real_currency(bal_ccy, m.get("currency"))
            # Carry the REAL balance currency back onto the account meta so the
            # stored connection can tell a Revolut EUR wallet from its NOK wallet:
            # the two share ONE IBAN and the account object frequently reports no
            # currency (→ defaulted to EUR), which made connecting one wipe the
            # other. The balance always carries the true currency.
            m["currency"] = ccy
            summaries.append({
                "name": m["name"], "amount": bal, "sub": None,
                "icon": "R" if is_revolut else "bank",
                "currency": ccy, "bank": bank, "iban": m.get("iban"),
            })
            scan_diag.append({"account": m["name"], "bank": bank, **diag})
        except EnableBankingError as e:
            logging.warning("scan: account %r (%s) failed, skipping: %s",
                            m.get("name"), bank, e)
            # A rate-limited bank is a "come back in a bit", not a broken
            # connection — the client must say so rather than send the user to
            # reconnect (which would burn even more of the bank's quota).
            status = getattr(e, "status", None)
            scan_diag.append({
                "account": m["name"], "bank": bank, "error": str(e),
                # Account identity so the client can drop ONLY the revoked wallet,
                # not every same-named bank connection (a Revolut EUR + NOK pair
                # shares an IBAN, so name/IBAN alone would wipe both).
                "iban": m.get("iban"), "currency": m.get("currency"),
                "rateLimited": status == 429,
                # 401/403 means the bank is refusing us, not failing: the consent
                # expired or the user withdrew it in their bank. That has to be
                # told apart from a quiet bank, because the two deserve opposite
                # treatment — one gets its cached data re-served, the other must
                # stop being shown at all.
                "revoked": status in (401, 403),
            })
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
    # Redact the per-account label before logging: when a bank returns no name,
    # `_account_meta` falls back to the IBAN, so logging it raw would leak a real
    # IBAN into Cloud Logging. Mask anything IBAN-shaped.
    def _safe_acct(v):
        s = str(v or "")
        return (s[:4] + "…") if re.match(
            r"^[A-Z]{2}\d{2}[A-Z0-9]{6,}$", s.replace(" ", "")) else s
    logging.info("scan scan_diag=%s",
                 [{**d, "account": _safe_acct(d.get("account"))} for d in scan_diag])
    return {
        "accountCount": len(summaries),
        "transactionCount": len(all_txns),
        "candidates": detection["candidates"],
        "frequent": detection["frequent"],
        "dash": dash,
        "scanDiag": scan_diag,
        # Banks that refused us outright — expired or withdrawn consent. Split
        # out from scanDiag so the phone doesn't have to know which HTTP codes
        # mean "gone": these connections should be dropped locally and the user
        # asked to reconnect, unlike a merely quiet bank.
        "revokedBanks": sorted({d.get("bank") for d in scan_diag
                                if d.get("revoked") and d.get("bank")}),
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
    revoked = 0
    if session_ids:
        try:
            client = _client()
            for sid in session_ids:
                if client.delete_session(sid):
                    revoked += 1
        except Exception:  # noqa: BLE001
            logging.exception("delete_user_data: session revoke error uid=%s", uid)
    db = firestore.client()
    for coll in (_BANK_LINKS, "entitlements"):
        try:
            db.collection(coll).document(uid).delete()
        except Exception:  # noqa: BLE001
            logging.exception("delete_user_data: %s cleanup failed uid=%s", coll, uid)
    logging.info("delete_user_data uid=%s revoked=%d/%d sessions", uid, revoked,
                 len(session_ids))
    return {"revoked": revoked, "sessions": len(session_ids)}


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
    return {"url": url, "state": state}


@https_fn.on_call(
    region=_REGION,
    secrets=[ENABLE_BANKING_PRIVATE_KEY, ANTHROPIC_API_KEY, REVENUECAT_API_KEY],
    # The 12-month windowed scan (many bank pages) plus classification can run
    # well past the 60s default on a cold start — give it room, and more memory
    # for a faster cold start + the in-RAM merchant KB.
    timeout_sec=300,
    memory=options.MemoryOption.MB_512,
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
    _remember_accounts(_uid(req), [m.get("uid") for m in metas])
    all_txns, summaries, scan_diag, own_ibans = _scan_accounts(
        client, metas, months_back=months_back, psu_available=_psu_available(req))
    ai_enabled = bool(data.get("aiEnrichment"))
    # This scan only covers the bank being connected, so the phone's cache of the
    # OTHER banks is what keeps them whole in the combined payload.
    today = _client_today(data)
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
        "accounts": [
            {"uid": m["uid"], "iban": m["iban"], "name": m["name"],
             "currency": m["currency"]}
            for m in metas if m.get("uid")
        ],
    }
    return result


@https_fn.on_call(
    region=_REGION,
    secrets=[ENABLE_BANKING_PRIVATE_KEY, ANTHROPIC_API_KEY, REVENUECAT_API_KEY],
    timeout_sec=300,
    memory=options.MemoryOption.MB_512,
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
    all_txns, summaries, scan_diag, own_ibans = _scan_accounts(
        _client(), metas, months_back=months_back, psu_available=_psu_available(req))
    today = _client_today(data)
    all_txns, summaries, own_ibans, stale = _merge_known(
        all_txns, summaries, own_ibans, scan_diag, data.get("known") or {},
        months_back, today=today)
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
    data = req.data or {}
    reply = _finance_chat(
        summary=str(data.get("summary") or ""),
        history=data.get("messages") or [],
        api_key=ANTHROPIC_API_KEY.value,
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
