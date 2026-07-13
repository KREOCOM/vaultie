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
from firebase_functions import https_fn
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


@https_fn.on_call(region=_REGION, secrets=[ENABLE_BANKING_PRIVATE_KEY])
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
    # Ask for a long window (2 years); combined with strategy=longest the ASPSP
    # returns the most it will give right after authorization. It caps to its
    # own max, so an over-generous date_from is safe.
    history_days = int(data.get("historyDays", 730))
    date_from = (dt.date.today() - dt.timedelta(days=history_days)).isoformat()

    client = _client()
    try:
        session = client.create_session(code)
        accounts = session.get("accounts", [])
        all_txns: list = []
        account_summaries: list = []
        scan_diag: list = []
        for acc in accounts:
            uid = acc.get("uid") or acc.get("account_uid")
            if not uid:
                continue
            acc_txns, diag = client.transactions(uid, date_from=date_from)
            all_txns.extend(acc_txns)
            # current balance for the account (closing-booked / available)
            bal = _pick_balance(client.balances(uid))
            name = (acc.get("name") or acc.get("product")
                    or (acc.get("account_id") or {}).get("iban") or "Sąskaita")
            currency = ((acc.get("currency"))
                        or (acc.get("account_id") or {}).get("currency") or "EUR")
            account_summaries.append({
                "name": name, "amount": bal, "sub": None,
                "icon": "R" if "revolut" in str(name).lower() else "bank",
                "currency": currency,
            })
            scan_diag.append({"account": name, **diag})
    except EnableBankingError as e:
        raise https_fn.HttpsError(
            code=https_fn.FunctionsErrorCode.INTERNAL,
            message="Could not fetch transactions.",
            details=str(e),
        )

    # De-duplicate before anything reads the list, so counts, totals and
    # recurring detection all see each real entry exactly once.
    _raw_count = len(all_txns)
    all_txns = _dedupe_transactions(all_txns)
    if len(all_txns) != _raw_count:
        logging.info("finish_bank_auth: deduped %d -> %d transactions",
                     _raw_count, len(all_txns))

    # Detection runs entirely on-server against the curated/crowdsourced merchant
    # DB and local keyword heuristics — no transaction-derived data is sent to any
    # third party, and nothing is persisted (privacy-first; see policy §6).
    detection = detect_recurring(all_txns)
    candidates = detection["candidates"]
    frequent = detection["frequent"]

    # Full dashboard payload — every transaction classified into the 9-section
    # model + feed/week/subs/balance, so the app can land straight in the
    # dashboard. Built defensively: a failure here must not break the scan.
    try:
        dash = build_dashboard(all_txns, account_summaries)
    except Exception:  # noqa: BLE001
        logging.exception("build_dashboard failed")
        dash = None
    # Counts only — never transaction content — so nothing sensitive is logged.
    logging.info(
        "finish_bank_auth: accounts=%d txns=%d candidates=%d frequent=%d "
        "history_days=%d",
        len(accounts), len(all_txns), len(candidates), len(frequent),
        history_days,
    )
    # Privacy-first: raw transactions are processed transiently and are NEVER
    # returned or stored. Only detected candidates + frequent-merchant summaries
    # go to the client, which persists only what the user chooses to import.
    logging.info("finish_bank_auth scan_diag=%s", scan_diag)
    return {
        "accountCount": len(accounts),
        "transactionCount": len(all_txns),
        "candidates": candidates,
        "frequent": frequent,
        "dash": dash,
        "scanDiag": scan_diag,
    }


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
