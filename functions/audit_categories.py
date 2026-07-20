"""One-off categorisation audit — NOT a unit test.

Feeds a spread of real, common Lithuanian + EU/global merchant descriptors (in
the shapes banks actually send) through the FULL production classifier
(build_dashboard) and prints the category + section each lands in. The point is
to see, with evidence rather than assurances, where categorisation is right and
where it isn't — for a general user, not one specific account.

Run: functions/venv/bin/python functions/audit_categories.py
"""
import os
import sys

sys.path.insert(0, os.path.dirname(__file__))

from dashboard import build_dashboard

# (descriptor as a bank sends it, what a human expects). One transaction each.
CASES = [
    # ── fuel ──
    ("CIRCLE K MISKAS", "fuel"),
    ("VIADA LT VILNIUS", "fuel"),
    ("NESTE LIETUVA", "fuel"),
    ("ORLEN KAUNAS", "fuel"),
    ("EMSI AZS", "fuel"),
    # ── groceries ──
    ("MAXIMA LT X587", "groceries"),
    ("LIDL/50216 LIDL KLAIPEDA", "groceries"),
    ("IKI UNIVERSITETAS", "groceries"),
    ("RIMI SIAURES", "groceries"),
    ("AIBE", "groceries"),
    ("NORFA", "groceries"),
    # ── restaurants / cafes ──
    ("MCDONALDS LIEPU", "restaurants"),
    ("CAIFF COFFEE", "restaurants"),
    ("BARAS BARDAKAS", "restaurants"),
    ("WOLT", "restaurants"),
    ("HESBURGER VILNIUS", "restaurants"),
    # ── transport ──
    ("BOLT.EU/O/2606", "transport"),
    ("UBER TRIP", "transport"),
    ("TRAFI VILNIUS", "transport"),
    ("LTG LINK", "transport"),
    # ── subscriptions / digital ──
    ("APPLE.COM/BILL", "digital"),
    ("GOOGLE *YOUTUBEPREMIUM", "digital"),
    ("NETFLIX.COM", "digital"),
    ("SPOTIFY P0A1B2", "digital"),
    ("OPENAI *CHATGPT SUBSCR", "digital"),
    ("DELFIPLIUS* UAB DELFI", "digital"),
    ("AMAZON PRIME", "digital"),
    ("MICROSOFT*365", "digital"),
    # ── telecom / utilities ──
    ("TELIA LIETUVA", "utilities/telecom"),
    ("BITE LIETUVA", "utilities/telecom"),
    ("TELE2", "utilities/telecom"),
    ("IGNITIS", "utilities"),
    ("VILNIAUS VANDENYS", "utilities"),
    # ── health / pharmacy ──
    ("EUROVAISTINE UAB", "pharmacy/health"),
    ("BENU VAISTINE", "pharmacy/health"),
    ("GYMPLUS", "health/sport"),
    ("LEMON GYM", "health/sport"),
    # ── shopping / retail ──
    ("UAB KESKO SENUKAI", "home/retail"),
    ("IKEA VILNIUS", "home/retail"),
    ("ZARA LIETUVA", "clothing"),
    ("H&M VILNIUS", "clothing"),
    ("PEGASAS KNYGYNAS", "retail"),
    ("APOTEKA VET", "retail"),
    # ── finance ──
    ("UAB MOGO LT", "finance/loan"),
    ("NYA*UAB DELCA INVEST", "finance"),
    ("SWEDBANK P2P PALUKANOS", "finance"),
    # ── alcohol / tobacco ──
    ("ROYAL SMOKE", "alcohol/tobacco"),
    # ── entertainment ──
    ("FORUM CINEMAS", "entertainment"),
    ("STEAMGAMES.COM", "entertainment/digital"),
    # ── the tricky ones (should NOT be a normal category) ──
    ("EVP*EPASLAUGOS", "government/tax?"),
]


# Realistic MCC per case, as a Revolut-style feed would carry. None = the bank
# sent no MCC (older bank), so the name resolver must carry it alone.
MCC = {
    "WOLT": "5812", "LTG LINK": "4112", "AMAZON PRIME": "5999",
    "MICROSOFT*365": "5734", "IKEA VILNIUS": "5712", "ZARA LIETUVA": "5651",
    "H&M VILNIUS": "5651", "UAB KESKO SENUKAI": "5211", "PEGASAS KNYGYNAS": "5942",
    "APOTEKA VET": "0742", "IGNITIS": "4900", "VILNIAUS VANDENYS": "4900",
    "SWEDBANK P2P PALUKANOS": "6012",
}


def _tx(descriptor, i, mcc=None):
    t = {
        "booking_date": f"2026-07-{(i % 27) + 1:02d}",
        "transaction_amount": {"amount": "12.34", "currency": "EUR"},
        "credit_debit_indicator": "DBIT",
        "status": "BOOK",
        "entry_reference": f"ref{i}",
        "creditor": {"name": descriptor},
        "bank_transaction_code": {"code": "CCRD"},
    }
    if mcc:
        t["merchant_category_code"] = mcc
    return t


def main():
    txns = [_tx(d, i) for i, (d, _) in enumerate(CASES)]
    accounts = [{"name": "Sąskaita", "amount": 100.0, "currency": "EUR",
                 "bank": "SEB", "iban": "LT121000011101001000"}]
    dash = build_dashboard(txns, accounts)
    by_ref = {}
    for r in dash["all"]:
        by_ref.setdefault(r.get("nm", ""), r)
    rows = dash["all"]
    print(f"{'DESCRIPTOR':<34}{'→ CATEGORY':<26}{'SECTION':<22}EXPECTED")
    print("-" * 110)
    # dash['all'] is sorted by date desc; match back by index order isn't stable,
    # so re-derive per descriptor from the feed by name proximity.
    # Simplest: rebuild one-by-one so each maps cleanly.
    for descriptor, expected in CASES:
        d1 = build_dashboard([_tx(descriptor, 0, MCC.get(descriptor))], accounts)
        row = d1["all"][0] if d1["all"] else {}
        cat = row.get("cat", "—")
        sec = row.get("sec", "—")
        tag = " (MCC)" if MCC.get(descriptor) else ""
        print(f"{descriptor[:32]:<34}{(cat + tag)[:24]:<26}{sec[:20]:<22}{expected}")


if __name__ == "__main__":
    main()
