"""Balance-card dedup must collapse a reconnected no-IBAN account (fresh session
UID, same physical account) to ONE card — otherwise its balance is summed twice
into net worth. Regression for the double-counted-net-worth bug.
"""
from main import _dedupe_summaries


def _s(name, ccy, bank, iban, amount=1000.0):
    return {"name": name, "amount": amount, "sub": None, "icon": "bank",
            "currency": ccy, "bank": bank, "iban": iban}


def _run():
    # Same no-IBAN account, reconnected → same bank/name/currency, different session.
    out = _dedupe_summaries([_s("Current", "EUR", "FooBank", None),
                             _s("Current", "EUR", "FooBank", None)])
    assert len(out) == 1, f"no-IBAN reconnect not deduped (double-counts): {len(out)}"

    # Two currencies at the same no-IBAN bank are DIFFERENT accounts → kept.
    out = _dedupe_summaries([_s("Wallet", "EUR", "Bar", None),
                             _s("Wallet", "NOK", "Bar", None)])
    assert len(out) == 2, "distinct no-IBAN currencies wrongly collapsed"

    # IBAN accounts unaffected: a Revolut EUR + NOK wallet SHARE one IBAN → kept.
    out = _dedupe_summaries([_s("Revolut", "EUR", "Revolut", "LT120000"),
                             _s("Revolut", "NOK", "Revolut", "LT120000")])
    assert len(out) == 2, "Revolut EUR+NOK wallets wrongly collapsed"

    # Same IBAN + currency (reconnect of a real bank) → collapsed.
    out = _dedupe_summaries([_s("SEB", "EUR", "SEB", "LT700440"),
                             _s("SEB", "EUR", "SEB", "LT700440")])
    assert len(out) == 1, "IBAN reconnect not deduped"

    print("test_dedupe_summaries: PASS")


if __name__ == "__main__":
    _run()
