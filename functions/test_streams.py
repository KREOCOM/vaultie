"""Payment-stream segmentation regression tests.

Same merchant identity != same payment stream. These assert that independent
payment patterns under one merchant do not contaminate each other, and that a
transaction never becomes recurring merely because another stream under the same
merchant is recurring. Hermetic (KB emptied; merchant_db seeded so every test
merchant resolves to a known brand -> a candidate).

Run:  python3 functions/test_streams.py
"""
import os
import sys

sys.path.insert(0, os.path.dirname(__file__))

import kb            # noqa: E402
import merchant_db   # noqa: E402
from recurring import detect_recurring  # noqa: E402

kb._entities = []
kb._alias_index = kb._related_index = kb._norm_index = kb._prefix_index = {}
kb._loaded_source = "test"
_BRANDS = ["apple", "google", "paypal", "netflix", "utilco", "landlord",
           "pildyk", "base44", "oneoff", "sameamt", "weekco", "annualco", "duostream"]
merchant_db._cache = [
    {"_key": b, "displayName": b.capitalize(), "type": "subscription",
     "category": "other", "logoDomain": None, "aliases": [b], "status": "active"}
    for b in _BRANDS]


def _txn(date, amt, name, ind="DBIT", code=("CCRD", "OTHR")):
    return {
        "booking_date": date, "credit_debit_indicator": ind,
        "transaction_amount": {"amount": f"{amt:.2f}", "currency": "EUR"},
        "creditor": {"name": name} if ind == "DBIT" else None,
        "debtor": {"name": name} if ind == "CRDT" else None,
        "remittance_information": [name],
        "bank_transaction_code": {"code": code[0], "sub_code": code[1]},
    }


def _run(txns):
    out = detect_recurring(txns)
    return out["candidates"]


def _confident(cands, name=None):
    return [c for c in cands if c["confident"] and (name is None or c["name"] == name)]


def main() -> int:
    fails = []

    def check(cond, msg):
        if not cond:
            fails.append(msg)

    # 1 + 14. Apple: two monthly subs (diff days) + one-off + irregular buys.
    apple = _run([
        _txn("2025-01-05", 9.99, "apple"), _txn("2025-02-05", 9.99, "apple"),
        _txn("2025-03-05", 9.99, "apple"),
        _txn("2025-01-14", 2.99, "apple"), _txn("2025-02-14", 2.99, "apple"),
        _txn("2025-03-14", 2.99, "apple"),
        _txn("2025-02-20", 137.99, "apple"),
        _txn("2025-01-09", 6.99, "apple"), _txn("2025-01-23", 14.99, "apple"),
        _txn("2025-02-11", 3.49, "apple")])
    conf = _confident(apple)
    check(len(conf) == 2, f"Apple: expected 2 recurring streams, got {len(conf)}")
    check({round(c["cost"], 2) for c in conf} == {9.99, 2.99},
          "Apple streams not 9.99 + 2.99")
    check(all(c["billingCycle"] == "monthly" for c in conf), "Apple streams not monthly")
    # CRITICAL: no transaction becomes recurring merely because another stream
    # under the same merchant is recurring. Every CONFIDENT candidate must be one
    # of the two real subscriptions; the 137.99 one-off + irregular buys land in
    # the not-confident residual.
    check(all(round(c["cost"], 2) in (9.99, 2.99) for c in conf),
          "CRITICAL: a non-subscription Apple amount became recurring")
    residual = [c for c in apple if not c["confident"]]
    check(residual and any(137.99 in (c["stream"]["amounts"] or []) for c in residual),
          "Apple 137.99 one-off missing from not-confident residual")

    # 2. Google: two fixed monthly amounts -> two streams.
    g = _confident(_run([
        _txn("2025-01-03", 9.99, "google"), _txn("2025-02-03", 9.99, "google"),
        _txn("2025-03-03", 9.99, "google"),
        _txn("2025-01-20", 49.99, "google"), _txn("2025-02-20", 49.99, "google"),
        _txn("2025-03-20", 49.99, "google")]))
    check(len(g) == 2, f"Google: expected 2 streams, got {len(g)}")

    # 3. PayPal collapsed by name into two unrelated cadences/amounts.
    pp = _confident(_run([
        _txn("2025-01-01", 5.00, "paypal"), _txn("2025-01-08", 5.00, "paypal"),
        _txn("2025-01-15", 5.00, "paypal"), _txn("2025-01-22", 5.00, "paypal"),
        _txn("2025-01-10", 20.00, "paypal"), _txn("2025-02-10", 20.00, "paypal"),
        _txn("2025-03-10", 20.00, "paypal")]))
    check(len(pp) == 2, f"PayPal: expected 2 streams (weekly+monthly), got {len(pp)}")

    # 4. Fixed monthly subscription.
    nf = _confident(_run([_txn(f"2025-0{m}-10", 12.99, "netflix") for m in (1, 2, 3, 4)]))
    check(len(nf) == 1 and nf[0]["billingCycle"] == "monthly", "Netflix fixed monthly failed")

    # 5. Variable monthly utility (amounts drift, cadence stable) -> one stream.
    ut = _confident(_run([
        _txn("2025-01-15", 43.79, "utilco"), _txn("2025-02-15", 45.10, "utilco"),
        _txn("2025-03-15", 41.20, "utilco"), _txn("2025-04-15", 44.00, "utilco")]))
    check(len(ut) == 1, f"Utility variable-recurring: expected 1 stream, got {len(ut)}")

    # 6. Salary (income) is never a candidate.
    sal = _run([_txn(f"2025-0{m}-25", 2000.0, "employer", ind="CRDT",
                     code=("RCDT", "ESCT")) for m in (1, 2, 3)])
    check(all("employer" not in c["name"].lower() for c in sal), "Salary surfaced as candidate")

    # 7. Rent with small adjustments -> one variable stream.
    rent = _confident(_run([
        _txn("2025-01-03", 1043.0, "landlord"), _txn("2025-02-03", 1203.0, "landlord"),
        _txn("2025-03-03", 1100.0, "landlord")]))
    check(len(rent) == 1, f"Rent: expected 1 stream, got {len(rent)}")

    # 8. Pildyk-like: fixed 9.99 top-ups recurring; ad-hoc top-ups not.
    pil = _run([
        _txn("2025-01-05", 9.99, "pildyk"), _txn("2025-02-05", 9.99, "pildyk"),
        _txn("2025-03-05", 9.99, "pildyk"),
        _txn("2025-01-18", 5.00, "pildyk"), _txn("2025-02-22", 1.49, "pildyk")])
    check(len(_confident(pil)) == 1 and _confident(pil)[0]["cost"] == 9.99,
          "Pildyk: 9.99 stream not the sole recurring one")

    # 9. Base44-like burst of varied purchases -> no recurring stream.
    b44 = _confident(_run([
        _txn("2025-05-13", 43.79, "base44"), _txn("2025-05-19", 70.29, "base44"),
        _txn("2025-05-25", 53.79, "base44"), _txn("2025-06-03", 27.84, "base44")]))
    check(len(b44) == 0, f"Base44 burst wrongly recurring: {len(b44)} streams")

    # 10. One-off purchase.
    oo = _run([_txn("2025-02-02", 59.0, "oneoff")])
    check(len(_confident(oo)) == 0, "One-off purchase wrongly recurring")

    # 11. Same amount repeated at irregular intervals -> not recurring.
    sa = _confident(_run([
        _txn("2025-01-01", 15.0, "sameamt"), _txn("2025-01-03", 15.0, "sameamt"),
        _txn("2025-02-20", 15.0, "sameamt"), _txn("2025-03-15", 15.0, "sameamt")]))
    check(len(sa) == 0, f"Same-amount-irregular wrongly recurring: {len(sa)}")

    # 12. Weekly recurring.
    wk = _confident(_run([_txn(d, 5.0, "weekco") for d in
                          ("2025-01-06", "2025-01-13", "2025-01-20", "2025-01-27")]))
    check(len(wk) == 1 and wk[0]["billingCycle"] == "weekly", "Weekly recurring failed")

    # 13. Annual payment with sufficient history.
    an = _confident(_run([_txn("2024-03-01", 99.0, "annualco"),
                          _txn("2025-03-01", 99.0, "annualco")]))
    check(len(an) == 1, "Annual recurring failed")

    print(f"stream regression: {len(fails)} failure(s)")
    for f in fails:
        print("  ✗", f)
    if fails:
        return 1
    print("All payment-stream regression assertions passed ✓")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
