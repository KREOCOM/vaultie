"""Merchant recovery + cleaning from a card-purchase remittance (now in normalize).
Run: python3 functions/test_merchant_remittance.py"""
import os, sys
sys.path.insert(0, os.path.dirname(__file__))
from normalize import merchant_from_remittance as _m  # noqa: E402

def main():
    fails = []
    def check(c, msg):
        if not c: fails.append(msg)
    cases = [
        ("PIRKINYS 516793******6331 21.06.26 19:04 5.09 EUR (474352) DROGAS 064 Klaipeda 000LT", "drogas"),
        ("PIRKINYS 516793******6331 21.06.26 19:00 35.22 EUR (465736) MAXIMA/XX-587 MAXIMA 92138 KLAIPEDA 000LT", "maxima"),
        ("PIRKINYS 516793******6331 20.06.26 11:23 37.78 EUR (691700) UAB EUROVAISTINE V0364Klaipeda 000LT", "eurovaistine"),
        ("PIRKINYS 516793******6331 20.06.26 09:00 12.99 EUR (112233) NETFLIX.COM 000NL", "netflix"),
        ("COMPRA EN MERCADONA MADRID (901234) 000ES", "mercadona"),
    ]
    for txt, kw in cases:
        got = _m(txt)
        check(got is not None and kw in got.lower(), f"{kw!r} not in {got!r}")
        if got:
            check("pirkinys" not in got.lower() and "516793" not in got, f"prefix leaked {got!r}")
            check(not any(c.isdigit() for c in got), f"digits leaked {got!r}")
    check(_m("Saskaitos papildymas") is None, "non-card wrongly parsed")
    check(_m("") is None, "empty not None")
    if fails:
        print("FAILURES:"); [print("  x", f) for f in fails]; return 1
    for txt, kw in cases: print(f"  {kw:12} <- {_m(txt)!r}")
    print("All remittance-merchant assertions passed OK")
    return 0

if __name__ == "__main__":
    raise SystemExit(main())
