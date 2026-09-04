"""Same real purchase, two banks, two different raw merchant strings — the
_classify display name must converge on one, so it merges into one row in
the feed and one entry in the client's top-merchants grouping (which keys
off this exact string via _merchantKey).

Real-world trigger: a Lithuanian dev reported (via a technical audit,
2026-08-16) that SEB and Revolut can return different fields/formats for
the SAME merchant through Enable Banking. Verified: category assignment was
already robust (substring match on the raw name), but the DISPLAY name
only converged for Bolt/Uber (_BRAND_CANON) — anything else (Maxima
included) kept whatever string the connecting bank happened to send.
_classify now falls back to normalize.clean_merchant_display for every
NAME_OVERRIDES match, not just the two hard-coded brands.

Run:  python3 functions/test_merchant_canon_cross_bank.py
"""
import os
import sys

sys.path.insert(0, os.path.dirname(__file__))

import kb  # noqa: E402
import dashboard  # noqa: E402

# No network / KB needed — a NAME_OVERRIDES match returns before the resolver.
kb._entities = []
kb._alias_index = kb._related_index = kb._norm_index = kb._prefix_index = {}
kb._loaded_source = "test-empty"


def _tx(name):
    return {
        "creditor": {"name": name},
        "credit_debit_indicator": "DBIT",
        "transaction_amount": {"amount": "25.00", "currency": "EUR"},
        "bank_transaction_code": {"code": "CARD_PAYMENT"},
        "remittance_information": [name],
    }


def _classify(name):
    return dashboard._classify(_tx(name), lambda t: (None, "other", None), set(), set())


def main() -> int:
    fails = []

    def check(cond, msg):
        if not cond:
            fails.append(msg)

    # The exact cross-bank pair from the report: one bank sends a clean
    # name, another bakes a store/terminal id into it.
    seb = _classify("Maxima Lt X587")
    revolut = _classify("Maxima")
    check(seb[0] == "Maxima", f"SEB-style name -> {seb[0]!r}, expected 'Maxima'")
    check(revolut[0] == "Maxima", f"Revolut-style name -> {revolut[0]!r}, expected 'Maxima'")
    check(seb[0] == revolut[0],
          f"same merchant, two banks, did not converge: {seb[0]!r} vs {revolut[0]!r}")
    check(seb[1] == "Maisto prekės" == revolut[1], "category diverged across banks")

    # An all-caps bank feed shouldn't produce an all-caps display name once
    # cleaned — both ends land on the same Title Case string.
    check(_classify("MAXIMA LT X603")[0] == "Maxima",
          "all-caps SEB-style name not normalised")

    # A brand with digits as part of its actual identity must not lose them
    # — only a bank-specific SUFFIX id is meant to go, not the name itself.
    check(_classify("7-Eleven")[0] == "7-Eleven", "'7-Eleven' wrongly stripped of its digit")

    # Regression guard: a merchant NAME_OVERRIDES doesn't canonicalise at
    # all (no drop-worthy tokens) must still pass through unchanged — this
    # is the same assertion test_bolt_merge.py already locks in, repeated
    # here because it's the exact safety property this change relies on.
    check(_classify("Vilniaus Taksi UAB")[0] == "Vilniaus Taksi UAB",
          "generic merchant wrongly renamed")

    if fails:
        print("FAILURES:")
        for f in fails:
            print("  ✗", f)
        return 1
    print("All cross-bank merchant-canonicalisation assertions passed ✓")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
