"""LOCAL, no-AI validation of the fingerprint cache-key change (Feature A).

Measures, on real merchant names with realistic bank-descriptor variants:
  1. cache-cardinality reduction  (OLD raw-norm key vs NEW fingerprint key)
  2. per-merchant variant collapse (do a business's variants share one key?)
  3. collision risk (does one fingerprint merge DISTINCT businesses?)
No external calls.
"""
import json
import re
import sys

sys.path.insert(0, ".")
import entity
import resolver
import ai_enrichment as ai

CITY = {"DE": "BERLIN", "FR": "PARIS", "NO": "OSLO", "PL": "WARSZAWA",
        "SE": "STOCKHOLM", "FI": "HELSINKI", "IT": "ROMA", "ES": "MADRID",
        "NL": "AMSTERDAM", "LT": "VILNIUS", "EE": "TALLINN", "LV": "RIGA",
        "DK": "KOBENHAVN", "CZ": "PRAHA", "AT": "WIEN", "PT": "LISBOA"}


def variants(name, cc):
    """Realistic bank-descriptor forms. Processor prefix is PROCESSOR*MERCHANT
    (merchant AFTER the *), matching how acquirers actually format the line."""
    return [
        name, name.upper(),
        f"SumUp *{name}", f"iZ *{name}", f"PAYPAL *{name}",
        f"{name.upper()} 02", f"{name.upper()} 4471",
        f"UAB {name}", f"{name} OY",
    ]


def new_key(surface):
    """Production path (CONSERVATIVE): clean surface -> identity_key, >=4 else raw-norm."""
    clean = resolver._clean_surface(surface)
    k = entity.identity_key(clean)
    return k if len(k) >= 4 else ai._norm(clean)


def fp_key(surface):
    """The REJECTED aggressive option, for comparison only."""
    clean = resolver._clean_surface(surface)
    fp = re.sub(r"[^a-z0-9]", "", (entity.normalize(clean)["matching_fingerprint"] or "").lower())
    return fp if len(fp) >= 4 else ai._norm(clean)


def main():
    raw = json.load(open(sys.argv[1]))
    seen, items = set(), []
    for r in raw:
        k = ai._norm(r["name"])
        if k and k not in seen:
            seen.add(k)
            items.append(r)
    print(f"distinct base merchants: {len(items):,}")

    old_keys, new_keys, agg_keys = set(), set(), set()
    total = 0
    collapsed = 0                       # merchants whose ALL variants share 1 new key
    new_to_base, agg_to_base = {}, {}   # key -> set of base merchant names
    nvar = len(variants("x", "DE"))
    for r in items:
        nkeys = set()
        for v in variants(r["name"], r["country"]):
            total += 1
            old_keys.add(ai._norm(v))
            nk = new_key(v)
            ak = fp_key(v)
            new_keys.add(nk)
            agg_keys.add(ak)
            nkeys.add(nk)
            new_to_base.setdefault(nk, set()).add(r["name"])
            agg_to_base.setdefault(ak, set()).add(r["name"])
        if len(nkeys) == 1:
            collapsed += 1

    print(f"variant instances ({nvar} per merchant):  {total:,}")
    print(f"DISTINCT keys — OLD raw-norm (current):     {len(old_keys):,}")
    print(f"DISTINCT keys — NEW identity_key (chosen):  {len(new_keys):,}")
    print(f"DISTINCT keys — matching_fingerprint (rej): {len(agg_keys):,}")
    print(f"  cold-cache paid AI calls (1 per distinct key):")
    print(f"    OLD {len(old_keys):,}  ->  NEW {len(new_keys):,}   "
          f"reduction {100*(1-len(new_keys)/len(old_keys)):.1f}%")
    print(f"merchants whose {nvar} variants collapse to ONE new key: "
          f"{collapsed:,}/{len(items):,} ({100*collapsed/len(items):.1f}%)")

    def collisions(m, label):
        collide = {k: v for k, v in m.items() if len(v) > 1}
        extra = sum(len(v) - 1 for v in collide.values())
        print(f"\nCOLLISION — {label}")
        print(f"  keys merging >1 distinct business: {len(collide):,}")
        print(f"  extra businesses wrongly merged:   {extra:,} "
              f"({100*extra/len(items):.2f}% of merchants)")
        for k, names in sorted(collide.items(), key=lambda x: -len(x[1]))[:8]:
            print(f"    {k!r:26} <- {sorted(names)[:5]}")
        return extra

    collisions(agg_to_base, "matching_fingerprint (REJECTED)")
    collisions(new_to_base, "identity_key (CHOSEN)")


if __name__ == "__main__":
    main()
