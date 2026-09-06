"""A subscription price change (e.g. 9.99 -> 10.99) is ONE subscription at the new
price, not two concurrent ones. Two genuinely concurrent subs at the same merchant
(Apple 9.99 + 2.99) must stay separate. Regression for the double-counted-on-price-
change bug.
"""
from dashboard import _collapse_recurring


def _cand(name, amount, status, occ, last):
    return {"name": name, "cost": amount, "monthlyAmount": amount,
            "billingCycle": "monthly", "cadenceLabel": "monthly",
            "status": status, "occurrences": occ, "lastChargeDate": last,
            "type": "subscription", "category": None}


def _run():
    # Price change: old 9.99 ended, new 10.99 active → ONE item at 10.99.
    out = _collapse_recurring([
        _cand("Streamly", 9.99, "ended", 3, "2026-03-05"),
        _cand("Streamly", 10.99, "active", 2, "2026-05-05"),
    ])
    assert len(out) == 1, f"price change not merged: {[(o['name'], o['monthly']) for o in out]}"
    assert abs(out[0]["monthly"] - 10.99) < 0.01, f"kept wrong price: {out[0]['monthly']}"
    assert out[0]["active"] is True

    # Price DECREASE: old 12.99 ended, new 9.99 active → ONE item at 9.99.
    out = _collapse_recurring([
        _cand("Streamly", 12.99, "ended", 3, "2026-03-05"),
        _cand("Streamly", 9.99, "active", 2, "2026-05-05"),
    ])
    assert len(out) == 1 and abs(out[0]["monthly"] - 9.99) < 0.01, \
        f"price decrease wrong: {[(o['name'], o['monthly']) for o in out]}"

    # Two CONCURRENT subs at one merchant (both active, not a multiple) → SEPARATE.
    out = _collapse_recurring([
        _cand("Apple", 2.99, "active", 3, "2026-05-05"),
        _cand("Apple", 19.95, "active", 3, "2026-05-05"),
    ])
    assert len(out) == 2, f"concurrent subs wrongly merged: {[(o['name'], o['monthly']) for o in out]}"

    print("test_price_change: PASS")


if __name__ == "__main__":
    _run()
