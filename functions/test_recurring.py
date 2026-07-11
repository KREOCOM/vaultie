"""Unit tests for recurring detection — no network/Firestore, runs anywhere.

New model: EVERY outgoing merchant is returned (even seen once), tagged
autoDetected when the merchant DB knows it. Income and frequent-spending
merchants are never candidates. Variants collapse (processor prefixes stripped,
known merchants grouped by canonical name).

Run:  python3 functions/test_recurring.py
"""

import os
import sys

sys.path.insert(0, os.path.dirname(__file__))

import kb  # noqa: E402
import merchant_db  # noqa: E402
from recurring import detect_recurring  # noqa: E402

# Hermetic unit test: this file exercises recurring-detection LOGIC against a
# controlled merchant set, so pin the KB to empty (no compiled artifact) — every
# lookup then falls through to the merchant_db seed below. Otherwise the real
# 1541-entity Wikidata artifact would supply richer canonical names (e.g.
# "Maxima LT") and couple this logic test to live open data.
kb._entities = []
kb._alias_index = kb._related_index = kb._norm_index = kb._prefix_index = {}
kb._loaded_source = "test-empty"

merchant_db._cache = [
    {"_key": "spotify", "displayName": "Spotify", "type": "subscription",
     "category": "entertainment", "logoDomain": "spotify.com",
     "aliases": ["spotify"], "status": "active"},
    {"_key": "dribbble", "displayName": "Dribbble", "type": "subscription",
     "category": "entertainment", "logoDomain": "dribbble.com",
     "aliases": ["dribbble"], "status": "active"},
    {"_key": "telia", "displayName": "Telia", "type": "bill",
     "category": "connectivity", "logoDomain": None,
     "aliases": ["telia"], "status": "active"},
    {"_key": "maxima", "displayName": "Maxima", "type": "frequent",
     "category": "other", "logoDomain": None,
     "aliases": ["maxima"], "status": "active"},
    {"_key": "applecombill", "displayName": "Apple", "type": "possible",
     "category": "entertainment", "logoDomain": "apple.com",
     "aliases": ["apple.com", "apple"], "status": "active"},
]


def _txn(date, amount, name, indicator="DBIT"):
    return {
        "booking_date": date,
        "credit_debit_indicator": indicator,
        "transaction_amount": {"amount": f"{amount:.2f}", "currency": "EUR"},
        "creditor": {"name": name} if indicator == "DBIT" else None,
        "debtor": {"name": name} if indicator == "CRDT" else None,
        "remittance_information": [name],
    }


DEMO = [
    _txn("2026-05-05", 9.99, "Spotify AB"),
    _txn("2026-06-05", 9.99, "Spotify AB"),
    # Dribbble variants — must collapse into ONE auto-detected candidate.
    _txn("2026-05-28", 14.62, "DRIBBBLE PRO STANDARD"),
    _txn("2026-06-29", 9.04, "DRIBBBLE*"),
    # apple.com variants (possible) → one auto candidate, needs review.
    _txn("2026-05-20", 22.99, "APPLE.COM/BILL"),
    _txn("2026-06-25", 117.46, "APPLE.COM/US"),
    _txn("2026-06-08", 11.99, "UAB Telia 8842"),
    # Fuel single charge — filtered out ("kuro" hint).
    _txn("2026-06-22", 45.00, "Kuro Pavilnys UAB"),
    # One-off travel / fuel — filtered out.
    _txn("2026-06-02", 120.00, "Ferryscanner"),
    _txn("2026-06-14", 55.00, "ORLEN DEGALINE"),
    # Card-processor prefix, seen twice → kept as APPMYWEB.
    _txn("2026-05-11", 61.88, "PAYPAL*APPMYWEB"),
    _txn("2026-06-11", 60.00, "PAYPAL*APPMYWEB"),
    # Single small digital service → kept.
    _txn("2026-06-18", 12.00, "SOMECLOUD.IO"),
    # Rent (unknown, large) — a manual candidate.
    _txn("2026-05-03", 1203.00, "MB Artusgrupė"),
    _txn("2026-05-31", 1043.00, "MB Artusgrupe"),
    # Frequent + income — never candidates.
    _txn("2026-06-03", 43.17, "Maxima LT"),
    _txn("2026-06-09", 21.80, "Maxima LT"),
    _txn("2026-06-01", 2100.00, "Employer UAB", indicator="CRDT"),
]


def main() -> int:
    result = detect_recurring(DEMO)
    cands = result["candidates"]
    by_name = {c["name"]: c for c in cands}
    freq_names = {f["name"] for f in result["frequent"]}
    failures = []

    def check(cond, msg):
        if not cond:
            failures.append(msg)

    # Auto-detected known merchants.
    check(by_name.get("Spotify", {}).get("autoDetected") is True, "Spotify not auto")
    check(by_name.get("Spotify", {}).get("needsReview") is False, "Spotify needsReview")
    check(by_name.get("Telia", {}).get("type") == "bill", "Telia not bill")

    # Dribbble variants collapse into one.
    dribbble = [c for c in cands if c["name"] == "Dribbble"]
    check(len(dribbble) == 1, f"Dribbble not collapsed (got {len(dribbble)})")
    check(dribbble and dribbble[0]["autoDetected"] is True, "Dribbble not auto")
    check(dribbble and dribbble[0]["occurrences"] == 2, "Dribbble occ != 2")

    # apple.com variants collapse; possible → auto + review.
    apple = [c for c in cands if c["name"] == "Apple"]
    check(len(apple) == 1, f"Apple not collapsed (got {len(apple)})")
    check(apple and apple[0]["autoDetected"] is True, "Apple not auto")
    check(apple and apple[0]["needsReview"] is True, "Apple (possible) not review")

    # Repeated unknown → kept as a MANUAL candidate.
    check("MB Artusgrupė" in by_name, "MB Artusgrupė not returned")
    check(by_name.get("MB Artusgrupė", {}).get("autoDetected") is False,
          "MB should be manual")

    # Card-processor prefix stripped → APPMYWEB (seen 2×), not PayPal.
    check(any("appmyweb" in c["name"].lower() for c in cands), "APPMYWEB not kept")
    check(all("paypal" not in c["name"].lower() for c in cands),
          "processor prefix leaked")

    # Single small digital service is kept.
    check(any("somecloud" in c["name"].lower() for c in cands),
          "SomeCloud.io dropped")

    # One-off / physical / fuel merchants are filtered OUT.
    for nm in ("kuro", "ferryscanner", "orlen"):
        check(not any(nm in c["name"].lower() for c in cands),
              f"{nm} wrongly shown")

    # Never candidates: frequent + income.
    check("Maxima" in freq_names, "Maxima not frequent")
    check("Maxima" not in by_name, "Maxima wrongly a candidate")
    check("Employer UAB" not in by_name, "Income wrongly a candidate")

    # Every candidate carries the autoDetected flag.
    check(all("autoDetected" in c for c in cands), "candidate missing autoDetected")

    auto = sum(1 for c in cands if c["autoDetected"])
    print(f"{len(cands)} candidates ({auto} auto, {len(cands) - auto} manual), "
          f"{len(result['frequent'])} frequent:")
    for c in cands:
        tag = "AUTO" if c["autoDetected"] else "manual"
        print(f"  • [{tag:6}] {c['name']:<20} {c['type']:<12} {c['cost']:>7.2f} "
              f"{c['category']:<13} ×{c['occurrences']}")

    if failures:
        print("\nFAILURES:")
        for f in failures:
            print(f"  ✗ {f}")
        return 1
    print("\nAll assertions passed ✓")
    return 0


def test_classifier() -> int:
    """The classify_unknown hook is treated exactly like a DB hit (no network)."""
    calls = []

    def fake(name, amount):
        calls.append(name)
        low = name.lower()
        if "ferry" in low or "orlen" in low or "kuro" in low:
            return ("One-off", "one_time", "travel", None)      # hidden
        if "somecloud" in low:
            return ("SomeCloud", "subscription", "cloud", None)  # high → auto
        if "artusgrup" in low:
            return ("MB Artusgrupė", "possible", "housing", None)  # → review
        return None  # unknown to the model → heuristic fallback

    result = detect_recurring(DEMO, classify_unknown=fake)
    cands = {c["name"]: c for c in result["candidates"]}
    failures = []

    def check(cond, msg):
        if not cond:
            failures.append(msg)

    # one_time answers are hidden, even though heuristic would also drop them.
    for nm in ("ferryscanner", "orlen", "kuro"):
        check(not any(nm in n.lower() for n in cands), f"{nm} not hidden by AI")
    check(result["debug"]["aiHidden"] >= 3, "aiHidden not counted")

    # Known subscription but seen only ONCE → auto-detected yet flagged for
    # review and not "confident": a single charge isn't proof of recurrence, so
    # it must not be auto-counted until the user confirms it.
    sc = cands.get("SomeCloud")
    check(sc is not None, "SomeCloud not classified")
    check(sc and sc["autoDetected"] is True, "SomeCloud not auto")
    check(sc and sc["needsReview"] is True, "single-charge SomeCloud should need review")
    check(sc and sc["confident"] is False, "single-charge SomeCloud should not be confident")
    check(sc and sc["type"] == "subscription", "SomeCloud type wrong")

    # "possible" (medium/low) → auto-detected but flagged for review.
    ar = cands.get("MB Artusgrupė")
    check(ar is not None, "Artusgrupė not classified")
    check(ar and ar["autoDetected"] is True, "Artusgrupė not auto (possible)")
    check(ar and ar["needsReview"] is True, "Artusgrupė not flagged for review")

    # DB hits never reach the classifier (Spotify/Telia/Maxima are known).
    check(all("spotify" not in n.lower() for n in calls), "DB hit sent to AI")

    if failures:
        print("\nclassifier FAILURES:")
        for f in failures:
            print(f"  ✗ {f}")
        return 1
    print("Classifier hook assertions passed ✓")
    return 0


if __name__ == "__main__":
    raise SystemExit(main() or test_classifier())
