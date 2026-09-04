"""Stock/crypto price + symbol search + logo lookup for the Investavimas
tab's manually-tracked holdings.

PROTOTYPE (2026-08-27, provider swapped 2026-08-28 twice) — isolated on
purpose so it can be deleted cleanly if it doesn't work out: this module,
its registration in main.py, and lib/screens/preview/investing_tab.dart are
the entire surface. Nothing else in the app reads from or writes to this
data.

History: Stooq (originally planned) blocks datacenter IPs with a JS
challenge — verified directly, unusable server-side. Yahoo Finance's
unofficial endpoint worked but is explicitly the kind of thing that gets
rate-limited/blocked without notice (real shipped apps don't rely on it
long-term). Settled on Finnhub — an official provider with a real free tier
(60 req/min), verified directly against the live API with a real key:
- /quote and /search and /stock/profile2 all work on the free tier.
- /stock/candle and /crypto/candle (historical OHLC, needed for a price
  chart) return "You don't have access to this resource" on the free tier —
  that's a paid-plan feature. So there is NO price history chart right now;
  only a current price + day change. A chart could come back later either
  by paying for candle access, or (free) by having the app itself record a
  daily price snapshot locally once a symbol is tracked — building its own
  history over time instead of buying someone else's.

Cost: free tier is a request-rate limit (60/min), not a monthly cap — see
the cost estimate given to the user (2026-08-28): even 120 active holders
with 5-minute server-side caching stays far under that ceiling.
"""
import logging
import time

import requests

_BASE = "https://finnhub.io/api/v1"
_TIMEOUT = 8

# Tiny in-memory cache: many users checking the same popular ticker (TSLA,
# AAPL...) within the same few minutes shouldn't each trigger a fresh
# upstream hit. A Cloud Functions instance is short-lived and scaled out, so
# this is a best-effort dampener, not a real cache — still meaningfully cuts
# calls under normal traffic since a warm instance serves many requests.
_quote_cache: dict = {}
_CACHE_TTL = 300  # 5 minutes


def quote(symbol: str, api_key: str):
    """Returns {"price","prevClose","open","high","low": float} or None on
    any failure (unknown symbol, upstream unreachable/rejecting) — caller
    shows a "couldn't fetch price" state, this never raises.

    open/high/low are TODAY's real values (Finnhub's free /quote gives them
    for free, no extra call) — 2026-08-28: added back so the portfolio hero
    can draw a genuine (not fabricated) "since market open" area chart. No
    "history" key — see module doc for why there's no multi-day chart.
    """
    sym = (symbol or "").strip().upper()
    if not sym or not api_key:
        return None
    cached = _quote_cache.get(sym)
    if cached and time.time() - cached[0] < _CACHE_TTL:
        return cached[1]
    try:
        r = requests.get(f"{_BASE}/quote", params={"symbol": sym, "token": api_key},
                          timeout=_TIMEOUT)
        r.raise_for_status()
        data = r.json()
        price = data.get("c")
        prev = data.get("pc")
        # Finnhub returns 200 with all-zero fields for a symbol it doesn't
        # recognise, rather than a 404 — a real quote is never exactly 0.
        if not price:
            return None
        result = {
            "price": float(price),
            "prevClose": float(prev or price),
            "open": float(data.get("o") or price),
            "high": float(data.get("h") or price),
            "low": float(data.get("l") or price),
        }
        _quote_cache[sym] = (time.time(), result)
        return result
    except Exception:  # noqa: BLE001
        logging.warning("stock_quote: quote failed for %s", sym)
        return None


def search(query: str, api_key: str):
    """Returns a list of {"symbol", "name"} (US common stocks only, capped
    at 15), or [] on any failure/empty query. Never raises.
    """
    q = (query or "").strip()
    if not q or not api_key:
        return []
    try:
        r = requests.get(f"{_BASE}/search", params={"q": q, "token": api_key},
                          timeout=_TIMEOUT)
        r.raise_for_status()
        data = r.json()
        out = []
        for item in data.get("result") or []:
            sym = item.get("symbol")
            desc = item.get("description")
            typ = item.get("type") or ""
            # Foreign-exchange-suffixed duplicates of the same US company
            # (TES.MC, SLS.TO, SLS.AX...) flood a name search with noise a
            # user typing "Tesla" or "SLS" almost never means. A bare symbol
            # (no dot) is the primary US listing in practice for this
            # search's purpose (manually tracking a personal holding).
            if not sym or not desc or "." in sym:
                continue
            if "Common Stock" not in typ and "ADR" not in typ:
                continue
            out.append({"symbol": sym, "name": desc.title()})
            if len(out) >= 15:
                break
        return out
    except Exception:  # noqa: BLE001
        logging.warning("stock_search: failed for query=%r", q)
        return []


def profile(symbol: str, api_key: str):
    """Returns {"domain": str} (bare hostname, e.g. "apple.com") for the
    existing merchant-logo proxy to resolve a real brand logo from, or None.
    Called ONCE per symbol, when the user picks it from search results —
    not for every row in a search result list.
    """
    sym = (symbol or "").strip().upper()
    if not sym or not api_key:
        return None
    try:
        r = requests.get(f"{_BASE}/stock/profile2", params={"symbol": sym, "token": api_key},
                          timeout=_TIMEOUT)
        r.raise_for_status()
        data = r.json()
        url = data.get("weburl") or ""
        domain = url.split("//")[-1].split("/")[0].removeprefix("www.")
        return {"domain": domain} if domain else None
    except Exception:  # noqa: BLE001
        logging.warning("stock_profile: failed for %s", sym)
        return None
