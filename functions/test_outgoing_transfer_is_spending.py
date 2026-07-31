"""Paying a company by bank transfer is spending, not a "transfer".

Found from a real day in the app: the feed showed "Penktadienis, 31 d. −11,48 €"
with a payment to "PAYSERA LT, UAB" underneath it, and that day's bar in the
week chart was empty. The money had left the account and left the totals.

Every outgoing credit transfer that was not a person, a loan or a housing
keyword fell through to a generic "Pervedimas" with is_transfer=True, which
removes it from spending everywhere — week bars, month total, categories,
budget. In this market a large share of ordinary spending is settled exactly
that way: invoices, utilities, and gateways like Paysera or OPAY.

What must NOT change is the set of things that are genuinely not spending:
money between the user's own accounts, currency conversions, cash withdrawals,
and transfers to and from people.

Run:  ./venv/bin/python test_outgoing_transfer_is_spending.py
"""
import os
import sys

sys.path.insert(0, os.path.dirname(__file__))
from dashboard import build_dashboard  # noqa: E402

MINE = "LT111111111111111111"
OTHER_MINE = "LT222222222222222222"
THEIRS = "LT999999999999999999"

failures = []


def check(label, cond, detail=""):
    if not cond:
        failures.append(f"{label}{(' — ' + detail) if detail else ''}")


def tx(date, direction, amount, *, cp_name, cp_iban=THEIRS, code="ICDT"):
    acct = "debtor_account" if direction == "CRDT" else "creditor_account"
    own_acct = "creditor_account" if direction == "CRDT" else "debtor_account"
    party = "debtor" if direction == "CRDT" else "creditor"
    return {
        "booking_date": date,
        "credit_debit_indicator": direction,
        "transaction_amount": {"amount": f"{amount:.2f}", "currency": "EUR"},
        "bank_transaction_code": {"code": code},
        acct: {"iban": cp_iban},
        own_acct: {"iban": MINE},
        party: {"name": cp_name},
        "entry_reference": f"{date}-{direction}-{amount}-{cp_name}",
    }


ACCOUNTS = [{"name": "SEB", "amount": 1000.0, "iban": MINE,
             "currency": "EUR", "icon": "bank"}]


def only_row(dash):
    """The single classified row. Rows carry no `name` of their own — the payee
    is folded into the display name upstream — so identity here is the amount."""
    rows = dash["all"]
    return rows[0] if len(rows) == 1 else None


# ── The case that started it ────────────────────────────────────────────────
d = build_dashboard([tx("2026-07-31", "DBIT", 11.48, cp_name='"PAYSERA LT", UAB')],
                    ACCOUNTS)
r = only_row(d)
check("the Paysera payment survives into the feed", r is not None)
if r:
    check("it is no longer filed as a transfer", r["sec"] != "Pervedimai",
          f"sec={r['sec']}")
    check("the amount is untouched", r["a"] == -11.48, f"a={r['a']}")
check("it counts as spending", d["totals"]["all"]["expenses"] == 11.48,
      f"expenses={d['totals']['all']['expenses']}")
check("it is not counted as income", d["totals"]["all"]["income"] == 0.0)

# The week chart is the view that was empty. It must now draw the day.
week_total = sum(day["total"] for day in (d["week"] or {"days": []})["days"])
check("the week chart is no longer empty for that day", week_total > 0,
      f"week total={week_total}")

# ── What must still NOT be spending ─────────────────────────────────────────
own = build_dashboard(
    [tx("2026-07-10", "DBIT", 500.0, cp_name="Vardas Pavarde", cp_iban=OTHER_MINE)],
    ACCOUNTS, own_ibans={MINE, OTHER_MINE})
check("moving money to my own account is still not spending",
      own["totals"]["all"]["expenses"] == 0.0,
      f"expenses={own['totals']['all']['expenses']}")

person = build_dashboard(
    [tx("2026-07-11", "DBIT", 40.0, cp_name="Milda Dirsiene")], ACCOUNTS)
check("sending money to a person is still not spending",
      person["totals"]["all"]["expenses"] == 0.0,
      f"expenses={person['totals']['all']['expenses']}")

cash = build_dashboard(
    [tx("2026-07-12", "DBIT", 100.0, cp_name="ATM Klaipeda", code="CWDL")], ACCOUNTS)
check("a cash withdrawal is still not spending",
      cash["totals"]["all"]["expenses"] == 0.0,
      f"expenses={cash['totals']['all']['expenses']}")

# ── The incoming leg is deliberately left alone ─────────────────────────────
# It may be the user's own money arriving from a bank we have no IBAN for.
incoming = build_dashboard(
    [tx("2026-07-13", "CRDT", 250.0, cp_name="UAB Kazkas")], ACCOUNTS)
check("an unattributable incoming transfer is not counted as income",
      incoming["totals"]["all"]["income"] == 0.0,
      f"income={incoming['totals']['all']['income']}")
check("and it does not become a negative expense either",
      incoming["totals"]["all"]["expenses"] == 0.0,
      f"expenses={incoming['totals']['all']['expenses']}")

# ── A company payment must not be mistaken for a person ─────────────────────
for company in ['"PAYSERA LT", UAB', "UAB Ignitis", "Artus Grupe", "MB Statyba"]:
    c = build_dashboard([tx("2026-07-14", "DBIT", 60.0, cp_name=company)], ACCOUNTS)
    check(f"paying {company} counts as spending",
          c["totals"]["all"]["expenses"] == 60.0,
          f"expenses={c['totals']['all']['expenses']}")

if failures:
    print("FAILED:")
    for f in failures:
        print("  ✗ " + f)
    sys.exit(1)
print("ok — outgoing company transfers count as spending; own, person, cash and "
      "incoming legs unchanged")
