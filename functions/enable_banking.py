"""Thin Enable Banking API client — ported from the proven ``banksync.py`` PoC.

Every request is authorized with a short-lived RS256 JWT signed by the
application's RSA private key. That key is injected at call time from a Firebase
Secret and never lives in source or on the device.
"""

import datetime as dt
import json
import logging
import time
import uuid

import jwt
import requests

# Public identifier — it is the ``.pem`` filename and the JWT ``kid`` header, so
# it is NOT a secret. Only the private key itself is sensitive. This is the
# PRODUCTION application, registered with the https redirect
# https://vaultie-1a2c4.web.app/banking/callback. (Sandbox app was
# c070330a-2b2d-4cc8-843b-cde49c3dd881.)
APP_ID = "5f8b2d4c-e3db-4c88-9e66-7898e1df023d"
BASE_URL = "https://api.enablebanking.com"
DEFAULT_COUNTRY = "LT"

_TIMEOUT = 30  # seconds


class EnableBankingError(RuntimeError):
    """Raised when the Enable Banking API returns a non-2xx response."""

    def __init__(self, status: int, path: str, body: str):
        super().__init__(f"[HTTP {status}] {path}: {body[:300]}")
        self.status = status


def _is_period_error(e: "EnableBankingError") -> bool:
    """True when the bank refuses a window because it has no transactions that
    far back (PSD2 history limit). Documented error name is
    ``WRONG_TRANSACTIONS_PERIOD``; some banks return a plain 4xx. Used to stop
    the backward window walk gracefully instead of treating it as a hard failure.
    """
    return "WRONG_TRANSACTIONS_PERIOD" in str(e).upper()


def _build_jwt(private_key: str) -> str:
    """Create a short-lived RS256 JWT signed with the app's private key."""
    now = int(time.time())
    payload = {
        "iss": "enablebanking.com",
        "aud": "api.enablebanking.com",
        "iat": now,
        "exp": now + 3600,  # max allowed is 24h
    }
    headers = {"typ": "JWT", "alg": "RS256", "kid": APP_ID}
    return jwt.encode(payload, private_key, algorithm="RS256", headers=headers)


class EnableBankingClient:
    """Stateless-ish client; holds one signed token for the life of a request."""

    def __init__(self, private_key: str):
        self._token = _build_jwt(private_key)

    def _headers(self) -> dict:
        return {
            "Authorization": f"Bearer {self._token}",
            "Content-Type": "application/json",
        }

    def _request(self, method: str, path: str, *, params=None, body=None):
        resp = requests.request(
            method,
            f"{BASE_URL}{path}",
            headers=self._headers(),
            params=params,
            data=json.dumps(body) if body is not None else None,
            timeout=_TIMEOUT,
        )
        if not resp.ok:
            raise EnableBankingError(resp.status_code, path, resp.text)
        return resp.json() if resp.text else {}

    # -- high-level calls (mirror the PoC steps) ---------------------------

    def application(self) -> dict:
        """The registered application, incl. its ``redirect_urls``."""
        return self._request("GET", "/application")

    def list_aspsps(self, country: str = DEFAULT_COUNTRY) -> list:
        data = self._request("GET", "/aspsps", params={"country": country})
        return data.get("aspsps", [])

    def start_auth(
        self,
        aspsp_name: str,
        aspsp_country: str,
        redirect_url: str,
        *,
        valid_days: int = 90,  # PSD2 AIS consent lifetime — 10 was far too short
                               # (bank access expired after ~10 days, silently
                               # dropping that bank's data). 90 is the standard
                               # re-consent window banks accept.
        psu_type: str = "personal",
    ):
        """Create a bank authorization URL. Returns ``(url, state)``."""
        valid_until = (
            dt.datetime.now(dt.timezone.utc) + dt.timedelta(days=valid_days)
        ).replace(microsecond=0).isoformat()
        state = str(uuid.uuid4())
        body = {
            "access": {"valid_until": valid_until},
            "aspsp": {"name": aspsp_name, "country": aspsp_country},
            "state": state,
            "redirect_url": redirect_url,
            "psu_type": psu_type,
        }
        auth = self._request("POST", "/auth", body=body)
        return auth["url"], state

    def create_session(self, code: str) -> dict:
        """Exchange the redirect ``code`` for a session (+ its accounts)."""
        return self._request("POST", "/sessions", body={"code": code})

    def balances(self, account_uid: str) -> list:
        """Current balances for an account (list of balance objects).

        Each item carries ``balance_amount`` ({amount, currency}) and a
        ``balance_type`` (e.g. CLBD closing-booked, XPCD, ITAV interim-available).
        Returns [] on any error so a missing-balances endpoint never blocks the
        transaction scan.
        """
        try:
            data = self._request("GET", f"/accounts/{account_uid}/balances")
            return data.get("balances", [])
        except EnableBankingError:
            return []

    def _fetch_window(self, account_uid, *, date_from, date_to, page_budget):
        """Page through ONE [date_from, date_to] window (default strategy).

        Returns ``(txns, pages_used, rate_limited, hit_budget)``. Raises
        EnableBankingError on a non-2xx that isn't a rate limit (the caller
        decides whether that ends the whole scan or just the backward walk).
        """
        txns: list = []
        cont = None
        pages = 0
        rate_limited = False
        while pages < page_budget:
            params = {"date_from": date_from, "date_to": date_to}
            if cont:
                params["continuation_key"] = cont
            resp = None
            for attempt in range(3):  # retry the SAME page on 429 with backoff
                resp = requests.get(
                    f"{BASE_URL}/accounts/{account_uid}/transactions",
                    headers=self._headers(), params=params, timeout=_TIMEOUT,
                )
                if resp.status_code != 429:
                    break
                rate_limited = True
                time.sleep(1.5 * (attempt + 1))
            if resp.status_code == 429:
                # Still limited after the retries. This is a FAILURE, not a
                # result: returning the pages fetched so far would be
                # indistinguishable from "this window is fully fetched", and the
                # caller would publish a window with a hole in it.
                raise EnableBankingError(
                    429, f"/accounts/{account_uid}/transactions",
                    "rate limited — retries exhausted")
            if not resp.ok:
                raise EnableBankingError(
                    resp.status_code, f"/accounts/{account_uid}/transactions",
                    resp.text)
            data = resp.json() if resp.text else {}
            txns.extend(data.get("transactions", []))
            pages += 1
            cont = data.get("continuation_key")
            if not cont:
                return txns, pages, rate_limited, False  # window fully fetched
            time.sleep(0.1)
        return txns, pages, rate_limited, True  # hit the page budget

    def transactions(self, account_uid: str, *, months_back: int = 12,
                     page_budget: int = 90, window_days: int = 30, today=None):
        """Fetch up to ``months_back`` months of transactions, NEWEST WINDOW FIRST.

        Oldest-first banks (SEB) return a long ``date_from``-only window starting
        at the earliest month, so the page budget gets spent on old data and the
        fresh months are never reached. Instead we walk backward in
        ``window_days`` windows using BOTH ``date_from`` and ``date_to`` — the
        freshest window is fetched first, so recent data is always retrieved
        regardless of the bank's page order, and we only go deeper (for salary /
        annual-subscription detection) until the overall ``page_budget`` is spent
        or the bank reports no more history.

        Returns ``(transactions, diag)``. Already-fetched recent windows are never
        discarded because an older window failed.
        """
        today = today or dt.date.today()
        all_txns: list = []
        pages_used = 0
        windows_fetched = 0
        rate_limited = False
        truncated = False
        history_exhausted = False
        n_windows = max(1, (months_back * 30) // window_days)
        for i in range(n_windows):
            if pages_used >= page_budget:
                truncated = True
                break
            d_to = today - dt.timedelta(days=window_days * i)
            d_from = today - dt.timedelta(days=window_days * (i + 1))
            try:
                txns, pages, rl, hit_budget = self._fetch_window(
                    account_uid,
                    date_from=d_from.isoformat(), date_to=d_to.isoformat(),
                    page_budget=page_budget - pages_used,
                )
            except EnableBankingError as e:
                # The freshest window is the one the whole dashboard is built on.
                # If it fails for ANY reason — rate limit, expired consent, the
                # bank refusing the period — we have nothing trustworthy for this
                # account, and an empty list here is indistinguishable from "this
                # account had no activity": the caller would publish the bank's
                # BALANCE with none of its PAYMENTS. Surface it so the caller can
                # keep the last-known data instead.
                if windows_fetched == 0:
                    raise
                # An OLDER window failing just ends the backward walk — the fresh
                # windows already fetched are real and are kept.
                if _is_period_error(e):
                    history_exhausted = True  # bank has no data that far back
                else:
                    truncated = True  # history is short of what we asked for
                    logging.warning(
                        "transactions: window %d (%s..%s) failed, keeping the %d "
                        "txns already fetched: %s",
                        i, d_from, d_to, len(all_txns), e)
                break
            all_txns.extend(txns)
            pages_used += pages
            rate_limited = rate_limited or rl
            windows_fetched += 1
            if hit_budget:
                truncated = True
                break
        dates = [t.get("booking_date") for t in all_txns if t.get("booking_date")]
        diag = {
            "pages": pages_used,
            "windows": windows_fetched,
            "months_back": months_back,
            "rate_limited": rate_limited,
            "truncated": truncated,            # page budget spent before done
            "history_exhausted": history_exhausted,  # bank had no older data
            "count": len(all_txns),
            "from": min(dates) if dates else None,
            "to": max(dates) if dates else None,
        }
        return all_txns, diag
