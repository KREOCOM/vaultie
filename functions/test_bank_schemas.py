"""Schema-compatibility test: run the ingestion pipeline over synthetic banks.

Each fixture in ``bank_fixtures`` fills the unified Berlin Group schema a DIFFERENT
(often broken) way. This test drives the real normalisation + balance + dedup +
recurring pipeline over every one and asserts INVARIANTS DERIVED FROM THE SCHEMA
STATE — never from the bank label. The bank name is only printed; no assertion
branches on it. If a rule here needed "if bank == X", it would be the wrong rule.

Invariants checked per bank:
  * direction  — every txn ends DBIT|CRDT; an original CRDT (income) is never flipped
  * remittance — always a list afterwards (never a char-sliceable string)
  * merchant   — resolves to a real name IFF the raw row carried any merchant source;
                 rows with NO source (minimal/broken banks) are allowed to stay "—"
  * balance    — pick_balance honours the type-priority; the displayed currency comes
                 from the balance object and is a REAL currency (never 'XXX'/None),
                 even when the account is tagged 'XXX' or missing a currency
  * subscriptions — a merchant recurring across >=2 distinct months surfaces as a
                 detect_recurring candidate (cores computed from the data, not typed)
  * no crash   — normalise, dedup, detect_recurring and build_dashboard all survive
                 every fixture, including the deliberately-broken one

Run: python3 functions/test_bank_schemas.py
"""
import copy
import os
import re
import sys

sys.path.insert(0, os.path.dirname(__file__))

import normalize  # noqa: E402
from recurring import detect_recurring  # noqa: E402
from dashboard import build_dashboard  # noqa: E402
from bank_fixtures import FIXTURES  # noqa: E402

_ALPHA = re.compile(r"[A-Za-zÀ-ž]+")


def _has_merchant_source(t) -> bool:
    """Did the RAW row carry anything a merchant name could come from?"""
    for key in ("creditor", "debtor"):
        p = t.get(key)
        if isinstance(p, dict) and (p.get("name") or "").strip():
            return True
    m = t.get("merchant")
    if isinstance(m, dict) and (m.get("name") or "").strip():
        return True
    if isinstance(m, str) and m.strip():
        return True
    if isinstance(t.get("note"), str) and t["note"].strip():
        return True
    r = t.get("remittance_information")
    if isinstance(r, str) and r.strip():
        return True
    if isinstance(r, list) and any(str(x).strip() for x in r):
        return True
    return False


def _month(t) -> str:
    return str(t.get("booking_date") or "")[:7]


def _core(name: str) -> str:
    """Longest alphabetic token of a merchant name — the brand core, data-derived."""
    toks = _ALPHA.findall(name or "")
    return max(toks, key=len).lower() if toks else ""


def main() -> int:
    fails = []
    rows = []
    all_norm = []          # every normalised txn, for the combined checks
    all_summaries = []

    def check(cond, bank, msg):
        if not cond:
            fails.append(f"[{bank}] {msg}")

    for fx in FIXTURES:
        bank = fx["bank"]
        region = fx["region"]
        crash = None
        n_merch_ok = n_merch_expected = 0
        bal_str = ccy_disp = "?"

        try:
            # ── balance (one account per fixture) ──────────────────────────
            acc = fx["accounts"][0]
            bals = acc.get("balances") or []
            picked_amt, picked_ccy = normalize.pick_balance(bals)
            ccy_disp = normalize.real_currency(picked_ccy, acc.get("currency"))
            bal_str = f"{picked_amt:.2f}"

            # displayed currency is always real, never the 'XXX'/absent account tag
            check(ccy_disp and str(ccy_disp).upper() != "XXX", bank,
                  f"displayed currency not real: {ccy_disp!r}")
            if bals:
                bal_ccys = {(b.get("balance_amount") or {}).get("currency") for b in bals}
                check(picked_ccy in bal_ccys, bank,
                      f"balance ccy {picked_ccy!r} not from a balance object {bal_ccys}")
                # if any balance holds a real positive figure, we must not fall to 0
                real_amts = []
                for b in bals:
                    try:
                        real_amts.append(float((b.get("balance_amount") or {}).get("amount") or 0))
                    except (TypeError, ValueError):
                        pass
                if any(a > 0 for a in real_amts):
                    check(picked_amt > 0, bank,
                          f"picked 0 though a real balance exists ({real_amts})")

            summ = {"name": acc.get("name", "?"), "amount": picked_amt,
                    "currency": ccy_disp, "bank": bank, "iban": acc.get("iban")}
            all_summaries.append(summ)

            # ── normalise transactions (mutates copies) ────────────────────
            raw_txns = copy.deepcopy(fx["transactions"])
            sources = [_has_merchant_source(t) for t in raw_txns]
            orig_crdt = [t.get("credit_debit_indicator") == "CRDT" for t in raw_txns]

            normalize.normalize_transactions(raw_txns)
            txns = normalize.dedupe(raw_txns)

            for t in txns:
                # direction is always one of the two valid states afterwards
                check(t.get("credit_debit_indicator") in ("DBIT", "CRDT"), bank,
                      f"bad indicator {t.get('credit_debit_indicator')!r}")
                # remittance is always a list (never a string to be char-sliced)
                check(isinstance(t.get("remittance_information"), list), bank,
                      "remittance not a list after normalise")

            # an original income row is never silently flipped to an expense
            for t, was_crdt in zip(raw_txns, orig_crdt):
                if was_crdt:
                    check(t.get("credit_debit_indicator") == "CRDT", bank,
                          "CRDT income flipped to DBIT")

            # merchant resolves IFF the row had any source to resolve from
            for t, had_src in zip(raw_txns, sources):
                name = normalize.merchant_name(t)
                if had_src:
                    n_merch_expected += 1
                    if name and name != "—":
                        n_merch_ok += 1
                    else:
                        check(False, bank, f"source present but merchant unresolved: {t!r}")
                else:
                    check(name == "—", bank,
                          f"no source yet resolved a merchant {name!r} from {t!r}")

            # ── subscriptions: recurring across >=2 months must be candidates ──
            months = {}
            for t in txns:
                if t.get("credit_debit_indicator") == "DBIT":
                    c = _core(normalize.merchant_name(t))
                    if c:
                        months.setdefault(c, set()).add(_month(t))
            multi_month = {c for c, ms in months.items() if len(ms) >= 2}

            det = detect_recurring(txns, own_ibans=set())
            cand_names = [c.get("name", "").lower() for c in det["candidates"]]
            sub_names = [c.get("name", "").lower() for c in det["candidates"]
                         if c.get("type") == "subscription"]
            freq_names = [f.get("name", "").lower() for f in det["frequent"]]
            surfaced = " ".join(cand_names + freq_names)
            # A merchant charged across >=2 months must not silently VANISH — it may
            # be a subscription (candidate) or everyday spending (frequent), but it
            # has to land somewhere.
            for core in multi_month:
                check(core in surfaced, bank,
                      f"multi-month merchant {core!r} vanished (not in candidates or frequent)")

            # Ground-truth classification for the fixtures that declare `expect`.
            exp = fx.get("expect") or {}
            for core in exp.get("frequent", []):
                check(any(core in n for n in freq_names), bank,
                      f"{core!r} expected in frequent, got {freq_names}")
            for core in exp.get("not_candidate", []):
                check(not any(core in n for n in cand_names), bank,
                      f"{core!r} must NOT be a candidate (everyday spending), got {cand_names}")
            for core in exp.get("not_subscription", []):
                check(not any(core in n for n in sub_names), bank,
                      f"{core!r} must NOT be a subscription, got subs={sub_names}")
            for core in exp.get("candidate", []):
                check(any(core in n for n in cand_names), bank,
                      f"{core!r} expected as a candidate, got {cand_names}")

            all_norm.extend(txns)
            n_subs = len(det["candidates"])

        except Exception as e:  # noqa: BLE001 — a crash IS the failure here
            crash = f"{type(e).__name__}: {e}"
            check(False, bank, f"pipeline CRASHED: {crash}")
            n_subs = 0

        rows.append((region, bank, len(fx["accounts"]), bal_str, ccy_disp,
                     f"{n_merch_ok}/{n_merch_expected}",
                     n_subs, "—" if crash else "ok"))

    # ── combined: whole multi-bank scan must dedup + detect + render, no crash ──
    combined_subs = combined_dash = "?"
    try:
        merged = normalize.dedupe(copy.deepcopy(all_norm))
        det = detect_recurring(merged, own_ibans=set())
        combined_subs = str(len(det["candidates"]))
        dash = build_dashboard(merged, all_summaries, own_ibans=set(), ai_key=None)
        combined_dash = "ok" if dash is not None else "None"
        check(dash is not None, "ALL", "build_dashboard returned None")
    except Exception as e:  # noqa: BLE001
        check(False, "ALL", f"combined pipeline CRASHED: {type(e).__name__}: {e}")
        combined_dash = "CRASH"

    # ── results table ──────────────────────────────────────────────────────
    print()
    hdr = ("REGION", "BANK", "ACC", "BALANCE", "CCY", "MERCH", "SUBS", "CRASH")
    w = (11, 32, 3, 10, 4, 6, 4, 5)
    line = "  ".join(h.ljust(width) for h, width in zip(hdr, w))
    print(line)
    print("-" * len(line))
    for r in rows:
        print("  ".join(str(c).ljust(width) for c, width in zip(r, w)))
    print("-" * len(line))
    print(f"combined: {len(all_norm)} txns -> {len(normalize.dedupe(copy.deepcopy(all_norm)))} "
          f"deduped, {combined_subs} candidates, dashboard={combined_dash}")
    print()

    if fails:
        print(f"FAILURES ({len(fails)}):")
        for f in fails:
            print("  x", f)
        return 1
    print(f"All schema-compat assertions passed OK ({len(rows)} banks, "
          f"{len(all_norm)} transactions)")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
