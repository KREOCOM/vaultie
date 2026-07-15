"""Honest generalization / stress test for Vaultie's merchant categorization.

Population  : real EU merchant names from OpenStreetMap (Overpass) — an INDEPENDENT
              public source, NOT functions/kb/merchant_index.sqlite.
Ground truth: the merchant's OSM shop=/amenity= tag mapped a-priori to a Vaultie
              section (gt_map.py, written before the run). Tags with no clean
              single Vaultie bucket are AMBIGUOUS and excluded from accuracy.
Known filter: names our deterministic resolver already resolves STRONGLY (on the
              clean name) are removed — we test UNKNOWN / NEW merchant
              generalization only.
Pipeline    : the SAME production path — resolver.resolve_hit (KB → offline
              global index) → AI fallback (ai_enrichment.classify, Haiku) for the
              unresolved / weak tail → CAT_MAP → Vaultie section. Nothing tuned to
              the test; no case's answer is fed back.

Two forms are graded on the SAME unknown-merchant set:
  * CLEAN  — the raw OSM name (least synthetic, most independent).
  * DESCRIPTOR — a realistic bank-statement variant (uppercase / city / store no /
    acquirer prefix). Category-neutral noise only; never leaks the answer.

Run: DYLD_LIBRARY_PATH=... ANTHROPIC_API_KEY=... venv/bin/python3 \
        functions/run_generalization_test.py <osm.json> [ai_workers] [descr_sample]
"""
import json
import os
import re
import sys
import threading
import unicodedata
from concurrent.futures import ThreadPoolExecutor

sys.path.insert(0, os.path.dirname(__file__))

import resolver          # noqa: E402
import ai_enrichment     # noqa: E402
import gt_map            # noqa: E402
from dashboard import CAT_MAP, OTHER  # noqa: E402

SRC = sys.argv[1]
WORKERS = int(sys.argv[2]) if len(sys.argv) > 2 else 10
DESCR_SAMPLE = int(sys.argv[3]) if len(sys.argv) > 3 else 2500
AI_KEY = os.environ.get("ANTHROPIC_API_KEY")
if not AI_KEY:
    print("!! ANTHROPIC_API_KEY not set — AI layer would be silently skipped. Aborting.")
    sys.exit(1)

OTHER_SEC = OTHER[3]
CACHE_PATH = os.path.join(os.path.dirname(SRC), "ai_cache.json")
_ai_lock = threading.Lock()
_ai_disk = {}
if os.path.exists(CACHE_PATH):
    try:
        _ai_disk = json.load(open(CACHE_PATH))
    except Exception:
        _ai_disk = {}


def flush_cache():
    """Atomic snapshot write under lock — safe to call from worker threads."""
    with _ai_lock:
        snapshot = dict(_ai_disk)
    tmp = CACHE_PATH + ".tmp"
    with open(tmp, "w") as f:
        json.dump(snapshot, f, ensure_ascii=False)
    os.replace(tmp, CACHE_PATH)

CITY = {"DE": "BERLIN", "FR": "PARIS", "NO": "OSLO", "PL": "WARSZAWA",
        "SE": "STOCKHOLM", "FI": "HELSINKI", "IT": "ROMA", "ES": "MADRID",
        "NL": "AMSTERDAM", "LT": "VILNIUS", "EE": "TALLINN", "LV": "RIGA",
        "DK": "KOBENHAVN", "CZ": "PRAHA", "AT": "WIEN", "PT": "LISBOA"}


def norm(s):
    s = unicodedata.normalize("NFKD", s or "")
    s = "".join(c for c in s if not unicodedata.combining(c))
    return re.sub(r"[^a-z0-9]+", "", s.lower())


def section_of(cat):
    return CAT_MAP.get((cat or "other").lower(), OTHER)[3]


def tx(name):
    return {
        "booking_date": "2026-05-01", "credit_debit_indicator": "DBIT",
        "transaction_amount": {"amount": "17.40", "currency": "EUR"},
        "creditor": {"name": name}, "remittance_information": [name],
        "bank_transaction_code": {"code": "CCRD", "sub_code": "OTHR"},
    }


def descriptor(name, cc, i):
    """Realistic, category-NEUTRAL bank-statement variant of a merchant name."""
    city = CITY.get(cc, "")
    compact = re.sub(r"\s+", "", name)
    variants = [
        name.upper(),
        f"{name.upper()} {city}".strip(),
        f"SumUp *{name}",
        f"{name.upper()} {100 + (i * 7) % 899}",
        f"iZ *{name} {city}".strip(),
        f"PAYPAL *{compact[:18]}",
        f"{name} {city}".strip(),
        f"{name.upper()}*{cc}",
    ]
    return variants[i % len(variants)]


def ai_classify(surface):
    """AI classify with a persistent disk cache (keyed by normalized surface)."""
    k = norm(surface)
    if not k:
        return None
    with _ai_lock:
        if k in _ai_disk:
            v = _ai_disk[k]
            return tuple(v) if v else None
    v = ai_enrichment.classify(surface, AI_KEY)
    with _ai_lock:
        _ai_disk[k] = list(v) if v else None
    return v


def resolve_one(surface, corpus):
    """Deterministic resolver → (cat_or_None, weak_bool)."""
    try:
        _, hit, res = resolver.resolve_hit(tx(surface), corpus)
    except Exception:
        return None, False
    if not hit:
        return None, False
    weak = float((res or {}).get("explanation_coverage") or 1.0) < 0.5
    return hit[2], weak


def run_pipeline(items, surface_fn, corpus, workers):
    """Mirror production resolve_cat for each item; record final_sec + layer.
    surface_fn(item, index) -> the surface string actually fed to the pipeline."""
    # Stage A: deterministic resolver (single-threaded; sqlite/CPU).
    for i, r in enumerate(items):
        r["_surface"] = surface_fn(r, i)
        r["_res_cat"], r["_weak"] = resolve_one(r["_surface"], corpus)
    # Stage B: AI fallback for the unresolved / weak tail (concurrent).
    need = [r for r in items if r["_res_cat"] is None or r["_weak"]]
    todo = [r for r in need if norm(r["_surface"]) not in _ai_disk]
    if todo:
        print(f"    AI calls needed: {len(todo)} (of {len(need)} tail; "
              f"{len(need) - len(todo)} cached)")
        done = [0]

        def work(r):
            ai_classify(r["_surface"])
            with _ai_lock:
                done[0] += 1
                d = done[0]
            if d % 1000 == 0:
                print(f"      …{d}/{len(todo)}")
                flush_cache()  # atomic periodic flush

        with ThreadPoolExecutor(max_workers=workers) as ex:
            list(ex.map(work, todo))
        flush_cache()
    # Stage C: compose exactly like production (AI overrides weak resolver guess).
    for r in items:
        if r["_res_cat"] is not None and not r["_weak"]:
            r["_layer"], cat = "resolver", r["_res_cat"]
        else:
            ai = ai_classify(r["_surface"]) if (r["_res_cat"] is None or r["_weak"]) else None
            if ai:
                r["_layer"], cat = "ai", ai[1]
            elif r["_res_cat"] is not None:
                r["_layer"], cat = "resolver_weak", r["_res_cat"]
            else:
                r["_layer"], cat = "none", "other"
        r["_cat"] = cat
        r["_sec"] = section_of(cat)


def grade(items):
    correct = wrong = kita = 0
    wrong_cases, by_country, by_section, by_layer = [], {}, {}, {}
    for r in items:
        gt, got = r["gt"], r["_sec"]
        by_layer[r["_layer"]] = by_layer.get(r["_layer"], 0) + 1
        bc = by_country.setdefault(r["country"], [0, 0])
        bs = by_section.setdefault(gt, [0, 0])
        bc[1] += 1
        bs[1] += 1
        if got == OTHER_SEC:
            kita += 1
        elif got == gt:
            correct += 1
            bc[0] += 1
            bs[0] += 1
        else:
            wrong += 1
            if len(wrong_cases) < 100:
                wrong_cases.append(r)
    return dict(correct=correct, wrong=wrong, kita=kita, n=len(items),
                wrong_cases=wrong_cases, by_country=by_country,
                by_section=by_section, by_layer=by_layer)


def pct(a, b):
    return f"{100.0 * a / b:.1f}%" if b else "n/a"


def report(label, g, extra=""):
    n = g["n"]
    print("\n" + "=" * 64)
    print(f"RESULTS — {label}  (n={n}) {extra}")
    print("=" * 64)
    print(f"  Correct section:           {g['correct']:>5}  ({pct(g['correct'], n)})")
    print(f"  Wrong section:             {g['wrong']:>5}  ({pct(g['wrong'], n)})")
    print(f"  'Kita' (system abstained): {g['kita']:>5}  ({pct(g['kita'], n)})")
    print(f"  End-to-end accuracy (correct/all):          {pct(g['correct'], n)}")
    print(f"  Committed accuracy (correct/(correct+wrong)):{pct(g['correct'], g['correct'] + g['wrong'])}")
    print("  -- by country --")
    for cc in sorted(g["by_country"], key=lambda c: -g["by_country"][c][1]):
        c, t = g["by_country"][cc]
        print(f"     {cc}: {c:>4}/{t:<4} {pct(c, t)}")
    print("  -- by ground-truth section --")
    for sec in sorted(g["by_section"], key=lambda s: -g["by_section"][s][1]):
        c, t = g["by_section"][sec]
        print(f"     {sec:<20} {c:>4}/{t:<4} {pct(c, t)}")
    print("  -- deciding pipeline layer --")
    for lyr in sorted(g["by_layer"], key=lambda x: -g["by_layer"][x]):
        print(f"     {lyr:<14} {g['by_layer'][lyr]:>5}  {pct(g['by_layer'][lyr], n)}")


def main():
    raw = json.load(open(SRC))
    print(f"Loaded {len(raw)} raw OSM POIs from {os.path.basename(SRC)}")

    seen, items = set(), []
    for r in raw:
        k = norm(r["name"])
        if not k or k in seen:
            continue
        seen.add(k)
        items.append({"name": r["name"], "osm": r["osm"], "country": r["country"]})
    print(f"Deduped to {len(items)} distinct merchant names")
    countries = sorted({r["country"] for r in items})
    print(f"Countries ({len(countries)}): {', '.join(countries)}")

    for r in items:
        r["gt"], r["amb"] = gt_map.ground_truth(r["osm"])

    corpus = None
    try:
        corpus = resolver.build_corpus([tx(r["name"]) for r in items])
    except Exception:
        corpus = None

    # KNOWN filter on the CLEAN canonical name (definition of "new merchant").
    known = 0
    for r in items:
        cat, weak = resolve_one(r["name"], corpus)
        r["known"] = bool(cat is not None and not weak)
        if r["known"]:
            known += 1
    unknown = [r for r in items if not r["known"]]
    gradeable = [r for r in unknown if not r["amb"]]
    ambiguous = len(unknown) - len(gradeable)
    print(f"\nKNOWN to Vaultie (strong resolver hit, EXCLUDED): {known}")
    print(f"UNKNOWN / weak (test population):                 {len(unknown)}")
    print(f"  AMBIGUOUS ground truth (EXCLUDED from accuracy):{ambiguous}")
    print(f"  GRADEABLE test cases:                           {len(gradeable)}")

    # ---- PASS 1: CLEAN name ----
    print("\n[PASS 1] CLEAN real name — full pipeline incl. AI")
    run_pipeline(gradeable, lambda r, i: r["name"], corpus, WORKERS)
    g_clean = grade(gradeable)
    report("CLEAN name — UNKNOWN merchant generalization", g_clean)

    print("\n  -- Top wrong cases (name | cc | expected -> actual | layer/cat | osm) --")
    for r in g_clean["wrong_cases"]:
        print(f"     {r['name'][:30]:30} [{r['country']}] {r['gt']:<18} -> "
              f"{r['_sec']:<18} [{r['_layer']}/{r['_cat']}] osm={r['osm']}")

    # ---- PASS 2: realistic DESCRIPTOR form, on a subset of the SAME set ----
    sub = sorted(gradeable, key=lambda r: norm(r["name"]))[:DESCR_SAMPLE]
    print(f"\n[PASS 2] Realistic bank-DESCRIPTOR form — sensitivity on n={len(sub)}")
    run_pipeline(sub, lambda r, i: descriptor(r["name"], r["country"], i), corpus, WORKERS)
    g_desc = grade(sub)
    report("DESCRIPTOR form — sensitivity sample", g_desc,
           extra="(realistic uppercase/city/store-no/acquirer noise)")

    out = {
        "raw": len(raw), "deduped": len(items), "countries": countries,
        "known_excluded": known, "unknown": len(unknown), "ambiguous_excluded": ambiguous,
        "clean": {k: v for k, v in g_clean.items() if k != "wrong_cases"},
        "descriptor": {k: v for k, v in g_desc.items() if k != "wrong_cases"},
        "clean_wrong_top100": [
            {"name": r["name"], "country": r["country"], "osm": r["osm"],
             "expected": r["gt"], "actual": r["_sec"], "layer": r["_layer"],
             "cat": r["_cat"]} for r in g_clean["wrong_cases"]],
    }
    dst = os.path.join(os.path.dirname(SRC), "generalization_result.json")
    json.dump(out, open(dst, "w"), ensure_ascii=False, indent=1)
    print(f"\nFull machine-readable result written to {dst}")
    print(f"AI cache ({len(_ai_disk)} entries) at {CACHE_PATH}")


if __name__ == "__main__":
    main()
