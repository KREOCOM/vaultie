"""Direction comes from the credit/debit indicator, not the sign the bank wrote
on the amount (M-M2); and every currency the client can pick has a backend rate
so it isn't silently counted as 0 (M-M3)."""
import fx
from dashboard import _amt


def _txn(indicator, amount, ccy="EUR"):
    return {"credit_debit_indicator": indicator,
            "transaction_amount": {"amount": str(amount), "currency": ccy}}


def _run():
    # A DBIT whose amount the bank already signed negative must stay an expense
    # (negative), not flip to a positive income/refund.
    assert _amt(_txn("DBIT", "-5.00")) == -5.0, _amt(_txn("DBIT", "-5.00"))
    assert _amt(_txn("DBIT", "5.00")) == -5.0
    assert _amt(_txn("CRDT", "5.00")) == 5.0
    assert _amt(_txn("CRDT", "-5.00")) == 5.0

    # Every currency the client currency picker offers must convert (non-zero rate)
    # so an account/transaction in it is never silently dropped to 0.
    client_currencies = ["AUD", "BGN", "CAD", "CHF", "CNY", "CZK", "DKK", "EUR",
                         "GBP", "HUF", "ISK", "JPY", "NOK", "PLN", "RON", "SEK",
                         "TRY", "USD"]
    for c in client_currencies:
        assert fx.to_eur(100, c) > 0, f"currency {c} has no backend rate (counts as 0)"

    print("test_money_signs: PASS")


if __name__ == "__main__":
    _run()
