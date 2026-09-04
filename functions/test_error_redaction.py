"""Bank error messages must not carry account identifiers or raw bank bodies.

`EnableBankingError`'s message travels further than it looks: into Cloud Logging
through `scan_diag`, and back to the phone as `HttpsError.details`. It used to
include the request path — which addresses a specific account — plus 300 raw
characters of the bank's response.

The second test is the one that matters: the window-walk termination marker used
to be read out of that body via `str(e)`, so redacting the message without moving
that check would silently turn "no more history" into a failed scan.
"""
import os
import sys

sys.path.insert(0, os.path.dirname(__file__))

from enable_banking import EnableBankingError, _is_period_error

PATH = "/accounts/9f3c1e77-aaaa-bbbb-cccc-2b8d10f4e001/transactions"
BODY = '{"message":"WRONG_TRANSACTIONS_PERIOD","iban":"LT121000011101001000"}'


def test_message_hides_the_account_uid():
    msg = str(EnableBankingError(400, PATH, BODY))
    assert "9f3c1e77" not in msg, msg
    assert "/accounts/…" in msg, msg


def test_message_hides_the_raw_bank_body():
    msg = str(EnableBankingError(400, PATH, BODY))
    assert "LT121000011101001000" not in msg, msg
    assert "iban" not in msg.lower(), msg


def test_status_is_still_available_for_rate_limit_handling():
    assert EnableBankingError(429, PATH, "slow down").status == 429


def test_period_marker_is_still_detected_after_redaction():
    # Regression guard: the marker lives in the body, which the message no
    # longer repeats. Miss this and the backward window walk stops degrading
    # gracefully and starts reporting hard failures instead.
    assert _is_period_error(EnableBankingError(400, PATH, BODY)) is True


def test_unrelated_error_is_not_mistaken_for_a_period_error():
    assert _is_period_error(EnableBankingError(500, PATH, "boom")) is False


def test_body_is_kept_on_the_instance_for_debugging():
    assert EnableBankingError(400, PATH, BODY).body == BODY


def main_():
    for name, fn in sorted(globals().items()):
        if name.startswith("test_") and callable(fn):
            fn()
            print(f"  ✓ {name}")
    print("\nBank errors stay quiet about accounts ✓")


if __name__ == "__main__":
    main_()
