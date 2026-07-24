"""Static FX → EUR (approximate rates; NOT live).

Single source of truth shared by the dashboard aggregation (dashboard.py) and
the recurring engine (recurring.py) so mixed-currency, multi-bank amounts (a
Revolut NOK account + a SEB EUR account) are normalized to the user's base
currency BEFORE anything is summed. Without this, raw NOK and EUR numbers get
added together and every total is wrong.

Base currency is EUR for now (Eurozone users). When per-user base currency
lands, this becomes a lookup keyed on the user's chosen base.
"""

import logging

# Approximate rates → EUR. Kept deliberately small and static (no network call
# in the hot path); refined when a live FX source is added. Being approximate is
# fine — they are used to make mixed-currency totals roughly comparable, not to
# quote prices. Being ABSENT is not fine: see to_eur.
_FX_TO_EUR = {
    "EUR": 1.0, "NOK": 0.086, "SEK": 0.088, "DKK": 0.134, "PLN": 0.235,
    "USD": 0.92, "GBP": 1.17, "CHF": 1.07, "CZK": 0.040, "ISK": 0.0066,
    # Added after an audit found unknown currencies passing through at 1.0.
    # These are the ones a Lithuanian traveller or a Revolut account realistically
    # produces; all approximate, all better than treating them as euros.
    "JPY": 0.0060, "HUF": 0.0025, "RON": 0.20, "BGN": 0.511, "UAH": 0.022,
    "CAD": 0.66, "AUD": 0.60, "TRY": 0.026, "CNY": 0.13,
    # 'XXX' = ISO "no currency": some banks (Swedbank) tag an account/amount with
    # it though the money is real euros. Treat as EUR rather than zeroing it. The
    # normalize layer already prefers a real currency where one exists.
    "XXX": 1.0,
}

# Currencies already reported once this process lifetime — keeps a busy scan
# from writing the same warning hundreds of times.
_warned: set = set()


def to_eur(value, currency):
    """Convert ``value`` in ``currency`` to EUR.

    An unrecognised currency contributes **0**, not its face value. This used to
    pass through at a rate of 1.0, so a ¥50 000 charge was added to the totals
    as €50 000 — silently, with nothing in the logs. A missing row is a visible,
    contained error; a number wrong by two orders of magnitude quietly corrupts
    every total, budget and savings figure on the dashboard.

    The warning names the currency so it can be added to the table above.
    """
    code = (currency or "EUR").upper()
    rate = _FX_TO_EUR.get(code)
    if rate is None:
        if code not in _warned:
            _warned.add(code)
            logging.warning(
                "fx: no rate for %r — amounts in it are counted as 0. "
                "Add it to _FX_TO_EUR in fx.py.", code)
        return 0.0
    return value * rate
