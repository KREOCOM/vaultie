"""Local, NO-API validation of the fail-closed person-guard relaxation (Feature D)
and the merchant_context wiring. Monkeypatches the network so nothing is spent."""
import datetime as dt
import os
import sys

sys.path.insert(0, os.path.dirname(__file__))

import ai_enrichment
import dashboard

# ── 1. classify() guard branch: network reached only when allowed ──────────
reached = {"n": 0}


class _Sentinel(Exception):
    pass


def _fake_post(*a, **k):
    reached["n"] += 1
    raise _Sentinel()          # blow up the moment the API path is entered


ai_enrichment.requests.post = _fake_post


def _try(name, **kw):
    reached["n"] = 0
    try:
        ai_enrichment.classify(name, "fake-key", **kw)
    except _Sentinel:
        pass
    return reached["n"] > 0     # True => network path entered (guard did NOT block)


# pick person names the EXISTING guard actually catches (precondition-checked, so
# the test validates the merchant_context toggle, not _looks_person's own quirks)
PERSON = "Egle Vaitkute"
assert ai_enrichment._looks_person(PERSON), f"precondition: {PERSON} must read as person"
# person-shaped name, no proof it's a merchant -> guard blocks, no network
assert _try(PERSON) is False, "person must be blocked by default (fail-closed)"
assert _try(PERSON, merchant_context=False) is False, "explicit False stays closed"
# same name but proven card-merchant context -> guard skipped, network attempted
assert _try(PERSON, merchant_context=True) is True, "card ctx skips guard (card != P2P)"
assert _try("Trattoria da Enzo", merchant_context=True) is True, "merchant ctx must skip guard"
# an obvious business name is never blocked either way
assert _try("Cafe Vero") is True, "business word name reaches API"
print("classify() fail-closed guard: OK")

# ── 2. dashboard wiring: merchant_context True only for card (CCRD) ─────────
seen = []


def _spy(surface, api_key, cache_key=None, merchant_context=False):
    seen.append((surface, cache_key, merchant_context))
    return None                # force fall-through to "other"; we only inspect calls


ai_enrichment.classify = _spy


def tx(name, code):
    return {"entry_reference": name + code, "booking_date": "2026-05-10",
            "credit_debit_indicator": "DBIT",
            "transaction_amount": {"amount": "9.90", "currency": "EUR"},
            "creditor": {"name": name}, "remittance_information": [name],
            "bank_transaction_code": {"code": code, "sub_code": "OTHR"}}


# gibberish so the resolver is guaranteed to abstain -> AI IS consulted; it is
# also person-shaped (3 alpha words), so the card path also proves the guard skip
txns = [
    tx("Zxqv Blorptax Qwzzle", "CCRD"),           # card merchant -> reach AI w/ ctx=True
    tx("Egle Vaitkute", "ICDT"),                  # P2P transfer -> must NEVER reach AI
    tx("Ruta Butkute", "MSCT"),                   # P2P transfer -> must NEVER reach AI
]
dashboard.build_dashboard(
    txns, [{"name": "SEB", "balance": 0, "sub": "", "icon": "bank", "currency": "EUR"}],
    today=dt.date(2026, 5, 15), ai_key="fake-key")

names_sent = [s for s, _, _ in seen]
assert any("Zxqv" in s for s in names_sent), "card merchant should reach AI"
assert all("Vaitkute" not in s and "Butkute" not in s for s in names_sent), \
    "P2P transfers must never reach the AI classifier"
card_calls = [m for s, _, m in seen if "Zxqv" in s]
assert card_calls and all(card_calls), "card merchant must carry merchant_context=True"
print(f"dashboard wiring: OK  (AI reached for {len(seen)} merchant call(s), "
      f"0 P2P leaked, card ctx={card_calls[0]})")
print("\nAll fail-closed person-guard assertions passed ✓")
