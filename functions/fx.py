"""Static FX → EUR (approximate rates; NOT live).

Single source of truth shared by the dashboard aggregation (dashboard.py) and
the recurring engine (recurring.py) so mixed-currency, multi-bank amounts (a
Revolut NOK account + a SEB EUR account) are normalized to the user's base
currency BEFORE anything is summed. Without this, raw NOK and EUR numbers get
added together and every total is wrong.

Base currency is EUR for now (Eurozone users). When per-user base currency
lands, this becomes a lookup keyed on the user's chosen base.
"""

# Approximate rates → EUR. Kept deliberately small and static (no network call
# in the hot path); refined when a live FX source is added.
_FX_TO_EUR = {
    "EUR": 1.0, "NOK": 0.086, "SEK": 0.088, "DKK": 0.134, "PLN": 0.235,
    "USD": 0.92, "GBP": 1.17, "CHF": 1.07, "CZK": 0.040, "ISK": 0.0066,
}


def to_eur(value, currency):
    """Convert ``value`` in ``currency`` to EUR. Unknown currency → passthrough."""
    return value * _FX_TO_EUR.get((currency or "EUR").upper(), 1.0)
