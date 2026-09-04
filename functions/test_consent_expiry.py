"""The bank consent expiry the app warns against.

PSD2 access is granted for a fixed window and then the bank simply stops
answering — the figures quietly stop moving and nothing on screen says why.
The app can only warn before that if the server hands it a date, so this
function must always produce one, and must never produce a wrong one silently.

Run:  ./venv/bin/python test_consent_expiry.py
"""
import datetime as dt
import os
import sys

sys.path.insert(0, os.path.dirname(__file__))
from main import _consent_valid_until  # noqa: E402

NOW = dt.datetime(2026, 7, 31, 12, 0, 0, tzinfo=dt.timezone.utc)

failures = []


def check(label, got, want):
    if got != want:
        failures.append(f"{label}\n     got: {got!r}\n    want: {want!r}")


def check_true(label, cond):
    if not cond:
        failures.append(label)


# The bank's own answer wins — it decides what it granted, and some ASPSPs
# grant less than the 90 days we ask for. Taking our own number instead would
# warn AFTER access had already died.
check(
    "the bank's valid_until is used verbatim",
    _consent_valid_until({"access": {"valid_until": "2026-09-15T10:00:00+00:00"}},
                         now=NOW),
    "2026-09-15T10:00:00+00:00",
)

check(
    "a Z-suffixed date is accepted, not rewritten",
    _consent_valid_until({"access": {"valid_until": "2026-09-15T10:00:00Z"}},
                         now=NOW),
    "2026-09-15T10:00:00Z",
)

check(
    "surrounding whitespace is trimmed",
    _consent_valid_until({"access": {"valid_until": "  2026-09-15T10:00:00Z  "}},
                         now=NOW),
    "2026-09-15T10:00:00Z",
)

# Every shape of "no usable date" must still yield one. Returning nothing here
# would produce silence in exactly the case the warning exists to prevent.
fallback = (NOW + dt.timedelta(days=90)).replace(microsecond=0).isoformat()
for label, session in [
    ("no access block", {"session_id": "s1"}),
    ("access present but empty", {"access": {}}),
    ("valid_until is null", {"access": {"valid_until": None}}),
    ("valid_until is blank", {"access": {"valid_until": "   "}}),
    ("valid_until is not a string", {"access": {"valid_until": 1789}}),
    ("valid_until is unparseable", {"access": {"valid_until": "next tuesday"}}),
    ("access is not a dict", {"access": "nope"}),
    ("session is empty", {}),
    ("session is None", None),
]:
    check(f"falls back to 90 days — {label}", _consent_valid_until(session, now=NOW),
          fallback)

# The fallback must be a real date the client can parse, not a formatted string
# that only looks like one.
parsed = dt.datetime.fromisoformat(_consent_valid_until({}, now=NOW))
check_true("the fallback parses back to a tz-aware datetime",
           parsed.tzinfo is not None)
check_true("the fallback is 90 days out", (parsed - NOW).days == 90)

# Called without `now` it must still work — production passes no clock.
check_true("works with the real clock",
           dt.datetime.fromisoformat(_consent_valid_until({})) > dt.datetime.now(
               dt.timezone.utc))

if failures:
    print("FAILED:")
    for f in failures:
        print("  ✗ " + f)
    sys.exit(1)
print("ok — consent expiry: bank's date honoured, always a usable fallback")
