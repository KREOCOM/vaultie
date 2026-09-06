"""Synthetic Enable Banking responses across regions — for the schema-compat test.

These are NOT real bank data. Each entry deliberately exercises a DIFFERENT way a
bank fills (or fails to fill) the unified Berlin Group schema, so the test proves
the code handles the SCHEMA STATES, not a specific bank. Every quirk below was
seen or is plausible on Enable Banking:

  * creditor.name empty, merchant packed into remittance (Swedbank);
  * merchant in a `note` field;
  * non-EUR account currency (SEK/NOK/DKK) needing conversion;
  * 'XXX' ("no currency") account tag though the balance is real;
  * balance list with types other than CLBD (ITAV/CLAV/FWAV/ITBD), or NONE matching;
  * no MCC anywhere;
  * no bank_transaction_code;
  * pending + booked duplicate of the same charge;
  * P2P to a person, a refund (CRDT), a cash withdrawal;
  * payment intermediaries (apple.com, PAYPAL*, SumUp*, Zettle_*);
  * a minimal bank returning only date + amount (no name / code / MCC).

The bank NAME on each fixture is only a label — the code under test must never
branch on it.
"""


def _tx(dind, amount, currency="EUR", *, creditor=None, debtor=None, rmt=None,
        note=None, mcc=None, btc=None, sub=None, date="2026-06-10",
        ref=None, status="BOOK"):
    t = {
        "credit_debit_indicator": dind,
        "transaction_amount": {"amount": f"{amount:.2f}", "currency": currency},
        "booking_date": date,
        "value_date": date,
        "status": status,
        "remittance_information": ([rmt] if isinstance(rmt, str) else (rmt or [])),
        "entry_reference": ref,
    }
    if creditor is not None:
        t["creditor"] = {"name": creditor}
    if debtor is not None:
        t["debtor"] = {"name": debtor}
    if note is not None:
        t["note"] = note
    if mcc is not None:
        t["merchant_category_code"] = mcc
    if btc is not None:
        t["bank_transaction_code"] = {"code": btc, "sub_code": sub, "description": None}
    return t


def _bal(amount, currency="EUR", btype="CLBD"):
    return {"balance_amount": {"amount": f"{amount:.2f}", "currency": currency},
            "balance_type": btype}


# region, label, accounts[{name,currency,iban,balances}], transactions[]
FIXTURES = [
    # ── BALTIC ───────────────────────────────────────────────────────────────
    {
        "region": "Baltic", "bank": "Swedbank-like (LT)",
        # account currency 'XXX', balance is EUR under ITAV/ITBD (no CLBD).
        "accounts": [{"name": "ZIVILE", "currency": "XXX", "iban": "LT037300010116375655",
                      "balances": [_bal(982.22, "EUR", "ITAV"), _bal(1063.68, "EUR", "ITBD")]}],
        "transactions": [
            # creditor.name empty → merchant in remittance; no MCC; no BTC.
            _tx("DBIT", 35.22, creditor=None,
                rmt="PIRKINYS 516793******6331 21.06.26 19:00 35.22 EUR (465736) MAXIMA/XX-587 MAXIMA 92138 KLAIPEDA 000LT",
                date="2026-06-05", ref="6a5e3f88-1"),
            _tx("DBIT", 12.99, creditor=None,
                rmt="PIRKINYS 516793******6331 05.06.26 09:00 12.99 EUR (112233) NETFLIX.COM 000NL",
                date="2026-06-06", ref="6a5e3f88-2"),
            _tx("DBIT", 12.99, creditor=None,
                rmt="PIRKINYS 516793******6331 05.05.26 09:00 12.99 EUR (112999) NETFLIX.COM 000NL",
                date="2026-05-06", ref="6a5e3f88-3"),
        ],
    },
    {
        "region": "Baltic", "bank": "SEB-like (LT)",
        "accounts": [{"name": "OSVALDAS", "currency": "EUR", "iban": "LT707044012345678901",
                      "balances": [_bal(495.10, "EUR", "CLBD")]}],
        "transactions": [
            _tx("DBIT", 18.49, creditor="pildyk.lt", btc="CCRD", sub="OTHR", date="2026-06-04"),
            _tx("CRDT", 200.00, debtor="Zivile Pavarde", btc="RCDT", sub="ESCT", date="2026-06-03"),  # P2P in
            _tx("DBIT", 2.00, creditor="SEB", btc="MDOP", sub="FEES", date="2026-06-02"),  # bank fee
        ],
    },
    # ── SCANDINAVIAN ─────────────────────────────────────────────────────────
    {
        "region": "Scandinavian", "bank": "Nordea-like (SE)",
        # non-EUR: SEK. Balance under CLAV. Merchant in creditor.name.
        "accounts": [{"name": "SVEN", "currency": "SEK", "iban": "SE4550000000058398257466",
                      "balances": [_bal(15000.00, "SEK", "CLAV")]}],
        "transactions": [
            _tx("DBIT", 149.00, "SEK", creditor="Spotify AB", date="2026-06-07"),
            _tx("DBIT", 149.00, "SEK", creditor="Spotify AB", date="2026-05-07"),  # recurring
            _tx("DBIT", 500.00, "SEK", creditor="ICA Supermarket", date="2026-06-08"),
        ],
    },
    {
        "region": "Scandinavian", "bank": "DNB-like (NO)",
        # NOK; balance ONLY under FWAV (forward available) — no CLBD/ITAV.
        # Merchant lives in `note`, remittance empty.
        "accounts": [{"name": "KARI", "currency": "NOK", "iban": "NO9386011117947",
                      "balances": [_bal(24000.00, "NOK", "FWAV")]}],
        "transactions": [
            _tx("DBIT", 320.00, "NOK", creditor=None, note="REMA 1000 OSLO", date="2026-06-09"),
            _tx("DBIT", 99.00, "NOK", creditor=None, note="NETFLIX", date="2026-06-01"),
        ],
    },
    # ── WESTERN ──────────────────────────────────────────────────────────────
    {
        "region": "Western", "bank": "N26-like (DE)",
        # EUR; MCC PRESENT (some Western banks pass it); merchant in creditor.name.
        "accounts": [{"name": "MAX", "currency": "EUR", "iban": "DE89370400440532013000",
                      "balances": [_bal(1200.55, "EUR", "CLBD")]}],
        "transactions": [
            _tx("DBIT", 4.50, creditor="REWE SAGT DANKE", mcc="5411", date="2026-06-10"),
            _tx("DBIT", 9.99, creditor="Spotify", mcc="5815", date="2026-06-02"),
        ],
    },
    # ── SOUTHERN ─────────────────────────────────────────────────────────────
    {
        "region": "Southern", "bank": "Santander-like (ES)",
        # EUR; merchant in remittance, DIFFERENT format (no "PIRKINYS", uses "COMPRA
        # EN <merchant> <city>"); balance under ITAV; intermediaries present.
        "accounts": [{"name": "MARIA", "currency": "EUR", "iban": "ES9121000418450200051332",
                      "balances": [_bal(742.00, "EUR", "ITAV")]}],
        "transactions": [
            _tx("DBIT", 23.40, creditor=None,
                rmt="COMPRA EN MERCADONA MADRID (901234) 000ES", date="2026-06-11"),
            _tx("DBIT", 20.00, creditor="PAYPAL *OPENAI", date="2026-06-03"),  # intermediary
            _tx("DBIT", 8.00, creditor="SumUp *Cafe Sol", date="2026-06-04"),  # intermediary
        ],
    },
    # ── EDGE: minimal / insufficient data ────────────────────────────────────
    {
        "region": "Edge", "bank": "Minimal bank (only date+amount)",
        # No name anywhere, no code, no MCC, no remittance. Balance has NO matching
        # type (only a made-up 'OTHR'), currency present.
        "accounts": [{"name": "ACCT", "currency": "EUR", "iban": "LT111111111111111111",
                      "balances": [_bal(50.00, "EUR", "OTHR")]}],
        "transactions": [
            _tx("DBIT", 5.00, creditor=None, date="2026-06-12"),
        ],
    },
    {
        "region": "Edge", "bank": "Broken fields (missing/empty)",
        # Account missing currency entirely; balance_amount missing amount; a txn
        # missing credit_debit_indicator and transaction_amount. Must NOT crash.
        "accounts": [{"name": "BROKEN", "iban": "LT222222222222222222",
                      "balances": [{"balance_amount": {"currency": "EUR"}, "balance_type": "CLBD"}]}],
        "transactions": [
            {"booking_date": "2026-06-13", "remittance_information": ["APPLE.COM/BILL CORK"]},
            {"credit_debit_indicator": "DBIT", "booking_date": "2026-06-13",
             "transaction_amount": {"amount": "1.99"}},  # no currency on the txn
        ],
    },
    # ── CLASSIFICATION: everyday spending must NOT look like a subscription ─────
    {
        "region": "Classification", "bank": "Local shops (card, unknown to DB)",
        # Repeated card purchases at UNRECOGNISED local merchants whose names carry
        # no category word: "Skani mėsa" (a butcher stall in a supermarket), "Tiltų"
        # (a café). By SHAPE these are indistinguishable from a subscription except
        # that they bill VARYING amounts on an IRREGULAR cadence. They MUST land in
        # `frequent` (everyday spending), never the subscription list. `expect` is
        # the ground truth this fixture guards.
        "accounts": [{"name": "ZIVILE", "currency": "EUR", "iban": "LT121000011101001000",
                      "balances": [_bal(300.00, "EUR", "CLBD")]}],
        "transactions": [
            _tx("DBIT", 8.40, rmt="PIRKINYS 516793******6331 03.06.26 18:00 8.40 EUR (111) SKANI MESA 12 VILNIUS 000LT", date="2026-06-03", ref="sm-1"),
            _tx("DBIT", 12.60, rmt="PIRKINYS 516793******6331 11.06.26 18:00 12.60 EUR (112) SKANI MESA 12 VILNIUS 000LT", date="2026-06-11", ref="sm-2"),
            _tx("DBIT", 6.20, rmt="PIRKINYS 516793******6331 19.06.26 18:00 6.20 EUR (113) SKANI MESA 12 VILNIUS 000LT", date="2026-06-19", ref="sm-3"),
            _tx("DBIT", 3.20, rmt="PIRKINYS 516793******6331 04.06.26 09:00 3.20 EUR (121) TILTU VILNIUS 000LT", date="2026-06-04", ref="tl-1"),
            _tx("DBIT", 4.80, rmt="PIRKINYS 516793******6331 06.06.26 09:00 4.80 EUR (122) TILTU VILNIUS 000LT", date="2026-06-06", ref="tl-2"),
            _tx("DBIT", 2.90, rmt="PIRKINYS 516793******6331 13.06.26 09:00 2.90 EUR (123) TILTU VILNIUS 000LT", date="2026-06-13", ref="tl-3"),
            _tx("DBIT", 5.40, rmt="PIRKINYS 516793******6331 22.06.26 09:00 5.40 EUR (124) TILTU VILNIUS 000LT", date="2026-06-22", ref="tl-4"),
        ],
        "expect": {"frequent": ["skani", "tiltu"], "not_candidate": ["skani", "tiltu"]},
    },
    {
        "region": "Classification", "bank": "P2P to a person + a real subscription",
        # A SEPA transfer whose counterparty descriptor is only a SURNAME ("Sulajeva")
        # — no card acceptor, no domain. A person is never a subscription, even a
        # regular monthly €4 (`_looks_like_person` needs two tokens; the bare surname
        # is exactly what slipped through and was offered as a "€4 subscription").
        # Netflix (constant amount, monthly, has a domain) is the positive control:
        # it MUST stay a candidate so the person guard didn't over-correct.
        "accounts": [{"name": "ZIVILE", "currency": "EUR", "iban": "LT131000011101001001",
                      "balances": [_bal(510.00, "EUR", "CLBD")]}],
        "transactions": [
            _tx("DBIT", 4.00, creditor="Sulajeva", btc="PMNT", sub="ICDT",
                rmt="Pervedimas", date="2026-05-05", ref="p2p-1"),
            _tx("DBIT", 4.00, creditor="Sulajeva", btc="PMNT", sub="ICDT",
                rmt="Pervedimas", date="2026-06-05", ref="p2p-2"),
            _tx("DBIT", 12.99, creditor=None,
                rmt="PIRKINYS 516793******6331 06.05.26 09:00 12.99 EUR (131) NETFLIX.COM 000NL", date="2026-05-06", ref="nf-1"),
            _tx("DBIT", 12.99, creditor=None,
                rmt="PIRKINYS 516793******6331 06.06.26 09:00 12.99 EUR (132) NETFLIX.COM 000NL", date="2026-06-06", ref="nf-2"),
        ],
        "expect": {"not_subscription": ["sulajeva"], "candidate": ["netflix"]},
    },
]
