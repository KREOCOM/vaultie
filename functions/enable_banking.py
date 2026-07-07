"""Thin Enable Banking API client — ported from the proven ``banksync.py`` PoC.

Every request is authorized with a short-lived RS256 JWT signed by the
application's RSA private key. That key is injected at call time from a Firebase
Secret and never lives in source or on the device.
"""

import datetime as dt
import json
import time
import uuid

import jwt
import requests

# Public identifier — it is the ``.pem`` filename and the JWT ``kid`` header, so
# it is NOT a secret. Only the private key itself is sensitive. This app is
# registered with the https redirect https://vaultie-1a2c4.web.app/banking/callback.
APP_ID = "c070330a-2b2d-4cc8-843b-cde49c3dd881"
BASE_URL = "https://api.enablebanking.com"
DEFAULT_COUNTRY = "LT"

_TIMEOUT = 30  # seconds


class EnableBankingError(RuntimeError):
    """Raised when the Enable Banking API returns a non-2xx response."""

    def __init__(self, status: int, path: str, body: str):
        super().__init__(f"[HTTP {status}] {path}: {body[:300]}")
        self.status = status


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
        valid_days: int = 10,
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

    def transactions(self, account_uid: str, *, date_from: str, max_pages: int = 10) -> list:
        """Page through an account's transactions since ``date_from`` (ISO date)."""
        all_txns: list = []
        cont = None
        for _ in range(max_pages):
            params = {"date_from": date_from}
            if cont:
                params["continuation_key"] = cont
            resp = requests.get(
                f"{BASE_URL}/accounts/{account_uid}/transactions",
                headers=self._headers(),
                params=params,
                timeout=_TIMEOUT,
            )
            # ASPSP consent-frequency rate limit — stop paging, keep what we have.
            if resp.status_code == 429:
                break
            if not resp.ok:
                raise EnableBankingError(
                    resp.status_code, f"/accounts/{account_uid}/transactions", resp.text
                )
            data = resp.json() if resp.text else {}
            all_txns.extend(data.get("transactions", []))
            cont = data.get("continuation_key")
            if not cont:
                break
        return all_txns
