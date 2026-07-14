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

import firebase_admin
from firebase_functions import https_fn, options
from firebase_functions.params import SecretParam

from dashboard import build_dashboard
from enable_banking import DEFAULT_COUNTRY, EnableBankingClient, EnableBankingError
from recurring import detect_recurring
from seed_merchants import seed as _run_seed


def _pick_balance(balances: list) -> float:
    """Choose the most 'spendable' balance from an account's balance list.

    Prefer interim-available (ITAV), then closing-booked (CLBD), else the first.
    Returns 0.0 when none are present.
    """
    if not balances:
        return 0.0
    def amt(b):
        try:
            return float((b.get("balance_amount") or {}).get("amount") or 0)
        except (TypeError, ValueError):
            return 0.0
    by_type = {str(b.get("balance_type") or "").upper(): b for b in balances}
    for pref in ("ITAV", "CLBD", "XPCD", "OTHR"):
        if pref in by_type:
            return round(amt(by_type[pref]), 2)
    return round(amt(balances[0]), 2)

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

_REGION = "europe-west1"


def _dedupe_transactions(txns: list) -> list:
    """Drop duplicate bank entries before detection.

    A single connection (especially a multi-account one like Revolut EUR+NOK)
    can return the same entry more than once — pagination windows that overlap,
    or a connection re-scanned within a session. Every Enable Banking entry
    carries a stable, unique ``entry_reference``; de-duplicating on it keeps the
    first sighting and discards exact repeats, so nothing is double-counted.
    Entries without a reference are kept as-is (can't safely be matched).
    """
    seen: set = set()
    out: list = []
    for t in txns:
        ref = t.get("entry_reference")
        if ref is None:
            out.append(t)
            continue
        if ref in seen:
            continue
        seen.add(ref)
        out.append(t)
    return out


def _require_auth(req: https_fn.CallableRequest) -> None:
    if req.auth is None:
        raise https_fn.HttpsError(
            code=https_fn.FunctionsErrorCode.UNAUTHENTICATED,
            message="Sign in required.",
        )


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


def _scan_accounts(client: EnableBankingClient, metas: list, *, months_back: int):
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
    for m in metas:
        uid = m.get("uid")
        if not uid:
            continue
        norm = _norm_iban(m.get("iban"))
        if norm:
            own_ibans.add(norm)
        bank = m.get("bank")
        is_revolut = "revolut" in str(m.get("name", "")).lower() \
            or "revolut" in str(bank or "").lower()
        try:
            acc_txns, diag = client.transactions(uid, months_back=months_back)
            all_txns.extend(acc_txns)
            bal = _pick_balance(client.balances(uid))
            summaries.append({
                "name": m["name"], "amount": bal, "sub": None,
                "icon": "R" if is_revolut else "bank",
                "currency": m["currency"], "bank": bank, "iban": m.get("iban"),
            })
            scan_diag.append({"account": m["name"], "bank": bank, **diag})
        except EnableBankingError as e:
            logging.warning("scan: account %r (%s) failed, skipping: %s",
                            m.get("name"), bank, e)
            scan_diag.append({"account": m["name"], "bank": bank, "error": str(e)})
    return all_txns, summaries, scan_diag, own_ibans


def _build_result(all_txns: list, summaries: list, own_ibans: set,
                  scan_diag: list, ai_enabled: bool) -> dict:
    """Shared tail for finish_bank_auth + refresh_dashboard: dedupe, detect
    recurring, build the (multi-bank-aware) dashboard, and package the response.
    Nothing is persisted server-side (privacy-first)."""
    raw = len(all_txns)
    all_txns = _dedupe_transactions(all_txns)
    if len(all_txns) != raw:
        logging.info("scan: deduped %d -> %d transactions", raw, len(all_txns))
    try:
        detection = detect_recurring(all_txns)
    except Exception:  # noqa: BLE001
        logging.exception("detect_recurring failed")
        detection = {"candidates": [], "frequent": []}
    ai_key = ANTHROPIC_API_KEY.value if ai_enabled else None
    try:
        dash = build_dashboard(all_txns, summaries, own_ibans=own_ibans,
                               ai_key=ai_key)
    except Exception:  # noqa: BLE001
        logging.exception("build_dashboard failed")
        dash = None
    logging.info("scan: accounts=%d txns=%d candidates=%d frequent=%d",
                 len(summaries), len(all_txns),
                 len(detection["candidates"]), len(detection["frequent"]))
    logging.info("scan scan_diag=%s", scan_diag)
    return {
        "accountCount": len(summaries),
        "transactionCount": len(all_txns),
        "candidates": detection["candidates"],
        "frequent": detection["frequent"],
        "dash": dash,
        "scanDiag": scan_diag,
    }


@https_fn.on_call(region=_REGION, secrets=[ENABLE_BANKING_PRIVATE_KEY])
def list_banks(req: https_fn.CallableRequest) -> dict:
    """Return the banks a user can connect to for ``country`` (default LT)."""
    _require_auth(req)
    country = (req.data or {}).get("country", DEFAULT_COUNTRY)
    try:
        aspsps = _client().list_aspsps(country)
    except EnableBankingError as e:
        raise https_fn.HttpsError(
            code=https_fn.FunctionsErrorCode.INTERNAL,
            message="Could not load banks.",
            details=str(e),
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
def start_bank_auth(req: https_fn.CallableRequest) -> dict:
    """Begin consent for ``aspspName`` and return the bank's authorization URL."""
    _require_auth(req)
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
        raise https_fn.HttpsError(
            code=https_fn.FunctionsErrorCode.INTERNAL,
            message="Could not start bank authorization.",
            details=str(e),
        )
    return {"url": url, "state": state}


@https_fn.on_call(
    region=_REGION,
    secrets=[ENABLE_BANKING_PRIVATE_KEY, ANTHROPIC_API_KEY],
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
        raise https_fn.HttpsError(
            code=https_fn.FunctionsErrorCode.INTERNAL,
            message="Could not fetch transactions.",
            details=str(e),
        )
    metas = [_account_meta(a, bank) for a in session.get("accounts", [])]
    all_txns, summaries, scan_diag, own_ibans = _scan_accounts(
        client, metas, months_back=months_back)
    ai_enabled = bool(data.get("aiEnrichment"))
    result = _build_result(all_txns, summaries, own_ibans, scan_diag, ai_enabled)
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
    secrets=[ENABLE_BANKING_PRIVATE_KEY, ANTHROPIC_API_KEY],
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
    reconnect for just that bank. Nothing is persisted server-side.
    """
    _require_auth(req)
    data = req.data or {}
    accounts_in = data.get("accounts") or []
    if not isinstance(accounts_in, list) or not accounts_in:
        raise https_fn.HttpsError(
            code=https_fn.FunctionsErrorCode.INVALID_ARGUMENT,
            message="accounts is required.",
        )
    months_back = _coerce_months(data.get("monthsBack", 12))
    ai_enabled = bool(data.get("aiEnrichment"))
    metas = [_account_meta(a, a.get("bank")) for a in accounts_in
             if isinstance(a, dict)]
    all_txns, summaries, scan_diag, own_ibans = _scan_accounts(
        _client(), metas, months_back=months_back)
    return _build_result(all_txns, summaries, own_ibans, scan_diag, ai_enabled)


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
