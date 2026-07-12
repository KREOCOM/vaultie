"""READ-ONLY build validation: flag brand-vs-parent pollution in the compiled
merchant KB — a parent/legal/holding entity that absorbs DISTINCT consumer-facing
subsidiary brands as its own identity aliases (the ICA AB -> {rimi, cura} case).

It NEVER edits or merges anything and is NOT part of the runtime resolver. Run
it after a KB rebuild (and especially after any future Overture/Wikidata
expansion) to catch new pollution before it ships.

    python3 tools/kb_build/lint_pollution.py            # report
    python3 tools/kb_build/lint_pollution.py --strict   # exit 1 if any found
"""
import json
import os
import re
import sys

_ROOT = os.path.dirname(os.path.dirname(os.path.dirname(os.path.abspath(__file__))))
_ARTIFACT = os.path.join(_ROOT, "functions", "kb", "merchant_kb.v2.json")

# canonical tokens that mark a legal/company/holding entity (not a brand name)
_LEGAL = {
    "ab", "asa", "as", "oyj", "oy", "sa", "group", "holding", "holdings", "inc",
    "ltd", "llc", "corporation", "corp", "plc", "se", "nv", "gmbh", "company",
    "co", "international", "enterprises", "spa", "srl", "bv", "aps", "kb", "ag",
    "oao", "pao", "sarl", "sas", "gruppen", "koncernen", "aktiebolag",
}


def _toks(s):
    return [t for t in re.split(r"[^a-z0-9]+", (s or "").lower()) if t]


def _canon_core(name):
    return [t for t in _toks(name) if t not in _LEGAL and len(t) >= 3]


def lint(entities):
    findings = []
    for e in entities:
        name = e["canonical_name"]
        ntoks = _toks(name)
        is_legalish = any(t in _LEGAL for t in ntoks)
        if not is_legalish:
            continue
        core = _canon_core(name)
        core_str = "".join(core)
        # an alias is "unrelated" if it shares no core token / substring link and
        # is not an obvious extension of the canonical core
        suspicious = []
        for a in e.get("alias_norms", []):
            if len(a) < 4:
                continue
            if any(c in a or a in c for c in core):      # lexical link to canonical
                continue
            if core_str and (core_str in a or a in core_str):
                continue
            suspicious.append(a)
        # distinct-brand signal: at least 2 unrelated aliases, and at least one is
        # SHORT (a distinct brand name, not a long legal expansion)
        short_brandy = [a for a in suspicious if len(a) <= 14]
        if len(suspicious) >= 2 and short_brandy:
            findings.append({
                "canonical": name,
                "type": e.get("merchant_type"),
                "suspicious": suspicious,
                "short_brand_like": short_brandy,
                "reason": "legal/holding canonical absorbs unrelated alias families",
                "source": e.get("_source", "wikidata"),
            })
    findings.sort(key=lambda f: -len(f["short_brand_like"]))
    return findings


def main():
    ents = json.load(open(_ARTIFACT, encoding="utf-8"))["entities"]
    findings = lint(ents)
    print(f"POLLUTION LINT — {len(findings)} suspicious entity(ies) / {len(ents)} total\n")
    print(f"{'CANONICAL':<26}{'TYPE':<13}{'SHORT-BRAND-LIKE ALIASES':<34}SOURCE")
    for f in findings:
        print(f"{f['canonical'][:25]:<26}{str(f['type']):<13}"
              f"{', '.join(f['short_brand_like'])[:33]:<34}{f['source']}")
        print(f"    reason: {f['reason']}")
        print(f"    all suspicious: {f['suspicious']}")
    if "--strict" in sys.argv and findings:
        sys.exit(1)


if __name__ == "__main__":
    main()
