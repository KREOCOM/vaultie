"""Regression tests for the evidence-preserving entity resolver.

Covers the five real SEB descriptors that broke naive first-match resolution,
plus abstention. No network/Firestore — the flat DB cache is emptied so only the
curated KB (kb_entities.json) + resolver logic are exercised.

Run:  python3 functions/test_resolver.py
"""

import os
import sys

sys.path.insert(0, os.path.dirname(__file__))

import kb  # noqa: E402
import merchant_db  # noqa: E402
import resolver  # noqa: E402
from resolver import NEEDS_EXTERNAL, RESOLVED, UNKNOWN  # noqa: E402

merchant_db._cache = []       # no flat-DB entries; curated KB only
kb.reset_cache()


def _txn(creditor, remittance=None):
    return {
        "credit_debit_indicator": "DBIT",
        "transaction_amount": {"amount": "10.00", "currency": "EUR"},
        "creditor": {"name": creditor} if creditor else None,
        "remittance_information": ([remittance] if remittance else []),
    }


def _resolve(creditor, remittance=None):
    return resolver.resolve(_txn(creditor, remittance), corpus=None)


CASES = []


def _line(tag, r):
    top = r["candidates"][0] if r["candidates"] else None
    CASES.append((tag, r))
    return (f"{tag:<26} {r['status']:<26} "
            f"top={r['top_score']:.2f} second={r['second_score']:.2f} "
            f"margin={r['margin']:.2f} cov={r['explanation_coverage']:.2f} "
            f"-> {r['canonical_name']}")


def main() -> int:
    fails = []

    def check(cond, msg):
        if not cond:
            fails.append(msg)

    print("REGRESSION WALKTHROUGH")
    print("-" * 96)

    # 1. EUROVAISTINE, UAB Fil. -> Eurovaistinė (UAB/Fil residual, not identity).
    r = _resolve("EUROVAISTINE, UAB Fil.")
    print(_line("EUROVAISTINE, UAB Fil.", r))
    check(r["status"] == RESOLVED, "EUROVAISTINE not RESOLVED")
    check(r["canonical_name"] == "Eurovaistinė", "EUROVAISTINE wrong entity")
    check("EUROVAISTINE" in [t.upper() for t in r["matched_tokens"]],
          "EUROVAISTINE not the matched brand")
    resid = [t.upper() for t in r["residual_tokens"]]
    check("UAB" in resid and "FIL" in resid, "UAB/Fil not kept as residual")

    # 2. YX GRAMYRA 0836 -> YX (Gramyra=location, 0836=store), NOT Gramyra.
    r = _resolve("YX GRAMYRA 0836")
    print(_line("YX GRAMYRA 0836", r))
    check(r["status"] == RESOLVED, "YX not RESOLVED")
    check(r["canonical_name"] == "YX", "YX wrong entity (Gramyra leak?)")
    check("GRAMYRA" in [t.upper() for t in r["residual_tokens"]],
          "Gramyra not residual location")

    # 3. ST1 BALLANGEN -> ST1, NOT Ballangen Municipality.
    r = _resolve("ST1 BALLANGEN")
    print(_line("ST1 BALLANGEN", r))
    check(r["status"] == RESOLVED, "ST1 not RESOLVED")
    check(r["canonical_name"] == "ST1", "ST1 wrong entity (Ballangen leak?)")
    check("BALLANGEN" in [t.upper() for t in r["residual_tokens"]],
          "Ballangen not residual location")

    # 4. Stena Scandica -> Stena Line (related-alias / entity relationship).
    r = _resolve("Stena Scandica")
    print(_line("Stena Scandica", r))
    check(r["status"] == RESOLVED, "Stena not RESOLVED")
    check(r["canonical_name"] == "Stena Line",
          "Stena Scandica not linked to Stena Line")

    # 5a. UAB OPAY SOLUTIONS + gymplius.lt -> gymplius.lt (unwrap), NOT OPAY.
    r = _resolve("UAB OPAY SOLUTIONS", "Mokėjimas tinklalapyje gymplius.lt")
    print(_line("OPAY + gymplius.lt", r))
    check(r["status"] == RESOLVED, "OPAY+domain not RESOLVED")
    check("opay" not in (r["canonical_name"] or "").lower(),
          "processor OPAY became the merchant")
    check("gymplius" in (r["canonical_name"] or "").lower(),
          "real merchant gymplius.lt not resolved")

    # 5b. UAB OPAY SOLUTIONS with NO merchant evidence -> NEEDS_EXTERNAL, not OPAY.
    r = _resolve("UAB OPAY SOLUTIONS")
    print(_line("OPAY (no domain)", r))
    check(r["status"] == NEEDS_EXTERNAL, "OPAY-only should need external")
    check(r["canonical_name"] is None, "OPAY-only wrongly resolved")

    # 6. Abstention: unknown local business, no KB -> UNKNOWN (false-merge > unresolved).
    r = _resolve("MB Artusgrupė")
    print(_line("MB Artusgrupė (unknown)", r))
    check(r["status"] in (UNKNOWN, NEEDS_EXTERNAL), "unknown should abstain")
    check(r["entity"] is None, "unknown wrongly bound to an entity")

    print("-" * 96)
    if fails:
        print("\nFAILURES:")
        for f in fails:
            print(f"  ✗ {f}")
        return 1
    print("All resolver regression assertions passed ✓")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
