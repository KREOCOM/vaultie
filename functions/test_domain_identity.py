"""Domain-canonical merchant identity (Plaid-style Named Entity Linking).

RULE (global, not per-merchant): when a payment carries a website DOMAIN in its
descriptor — via a processor ("Mokėjimas tinklalapyje gymplius.lt"), a card-web
line ("kortelė ... www.savasld.lt/ VILNIUS/LTU"), or a leading domain
("APPLE.COM/BILL") — the DOMAIN is the merchant's stable identity, NOT the
processor's IBAN and NOT an inconsistent display name. So two descriptor variants
of the same domain collapse to ONE merchant, for ANY merchant in ANY country.

A DIRECT SEPA payment to a real recipient (rent to "MB Artusgrupe", a real IBAN,
no domain in the memo) keeps its IBAN identity — the domain rule must not touch it.

Fixtures are REAL descriptors from the user's banks; the rule they validate is
universal. Run: python3 functions/test_domain_identity.py
"""
import os
import sys

sys.path.insert(0, os.path.dirname(__file__))
import canonical  # noqa: E402
from recurring import detect_recurring  # noqa: E402
import normalize  # noqa: E402


def _tx(amount, rmt, *, creditor=None, cred_iban=None, date="2026-06-10", ref=None):
    t = {
        "credit_debit_indicator": "DBIT",
        "transaction_amount": {"amount": f"{amount:.2f}", "currency": "EUR"},
        "booking_date": date, "value_date": date, "status": "BOOK",
        "remittance_information": [rmt] if isinstance(rmt, str) else rmt,
        "entry_reference": ref,
    }
    if creditor is not None:
        t["creditor"] = {"name": creditor}
    if cred_iban is not None:
        t["creditor_account"] = {"iban": cred_iban}
    return t


# region label, txn, expected identity substring (what the identity_key must contain)
CASES = [
    ("gymplius via OPAY #1",
     _tx(35.90, "8TGTX8YMN4 Mokėjimas tinklalapyje gymplius.lt, užsakymo nr. 279069382",
         creditor="UAB OPAY SOLUTIONS", cred_iban="LT137044060007869474", ref="g1"),
     "gymplius.lt"),
    ("gymplius via OPAY #2",
     _tx(49.80, "8TJY389XCB Mokėjimas tinklalapyje gymplius.lt, užsakymo nr. 77497005",
         creditor="UAB OPAY SOLUTIONS", cred_iban="LT137044060007869474", ref="g2"),
     "gymplius.lt"),
    ("savasld via card",
     _tx(14.91, "01/06/2026 11:30 kortele...124261 www.savasld.lt/ VILNIUS/LTU #141417",
         ref="s1"),
     "savasld.lt"),
    ("apple leading domain",
     _tx(22.99, "31/05/2026 00:00 kortele...124261 APPLE.COM/BILL/CORK/IRL #575572",
         ref="a1"),
     "apple.com"),
    ("MB Artusgrupe direct SEPA (rent, real IBAN, NO domain)",
     _tx(1043.00, "Uz nuoma + komunaliniai",
         creditor="MB Artusgrupe", cred_iban="LT301010012345678901", ref="r1"),
     "iban:"),   # must stay IBAN-identified, NOT a domain
    # processor '*' prefix — the merchant is after the star (any processor)
    ("Pronas* processor prefix",
     _tx(4.80, "Pronas*Skani Mesa", creditor="Pronas*Skani Mesa", ref="p2"),
     "skanimesa"),
    ("SumUp * processor prefix",
     _tx(8.00, "SumUp *Cafe Sol", creditor="SumUp *Cafe Sol", ref="p3"),
     "cafesol"),
    ("PTL* prefix hiding a domain",
     _tx(2.29, "PTL*Vr.fi korttimaksu", creditor="PTL*Vr.fi korttimaksu", ref="p4"),
     "vr.fi"),
]


def main() -> int:
    fails = []
    print("IDENTITY per case (dabartinis kodas):")
    for label, t, expect in CASES:
        canon = canonical.build_canonical(t)
        key = canon.get("identity_key")
        src = canon.get("identity_source")
        ok = bool(key) and expect in key
        print(f"   {'OK ' if ok else 'XX '} {label:44} → {key!r}  (want ~{expect!r}, src={src})")
        if not ok:
            fails.append(f"{label}: identity {key!r} does not contain {expect!r}")

    # Dedup: the SAME monthly charge, three DIFFERENT descriptor variants (each a
    # different OPAY order-ref, so the old entry_reference dedup can't help), must
    # collapse to ONE recurring candidate via the shared domain identity — the real
    # win, since the bank sends a fresh ref every month.
    gym = [
        _tx(35.90, "8TGTX8YMN4 Mokėjimas tinklalapyje gymplius.lt, užsakymo nr. 279069382",
            creditor="UAB OPAY SOLUTIONS", cred_iban="LT137044060007869474",
            date="2026-04-17", ref="g1"),
        _tx(35.90, "8TJY389XCB Mokėjimas tinklalapyje gymplius.lt, užsakymo nr. 77497005",
            creditor="UAB OPAY SOLUTIONS", cred_iban="LT137044060007869474",
            date="2026-05-17", ref="g2"),
        _tx(35.90, "8TDME8S435 Mokėjimas tinklalapyje gymplius.lt, užsakymo nr. 999",
            creditor="UAB OPAY SOLUTIONS", cred_iban="LT137044060007869474",
            date="2026-06-17", ref="g3"),
    ]
    norm = [dict(x) for x in gym]
    normalize.normalize_transactions(norm)
    det = detect_recurring(norm, own_ibans=set())
    gym_cands = [c for c in det["candidates"]
                 if "gym" in c["name"].lower() or "opay" in c["name"].lower()]
    print(f"\nDEDUP: gymplius kandidatų: {len(gym_cands)} "
          f"(want 1) → {[c['name'] for c in gym_cands]}")
    if len(gym_cands) != 1:
        fails.append(f"gymplius NOT deduped: {len(gym_cands)} candidates")

    if fails:
        print(f"\nFAILURES ({len(fails)}):")
        for f in fails:
            print("  x", f)
        return 1
    print("\nAll domain-identity assertions passed OK")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
