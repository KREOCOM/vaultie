import json, re, sys, unicodedata
sys.path.insert(0, '.')
import resolver, ai_enrichment as ai, gt_map


def norm(s):
    s = unicodedata.normalize("NFKD", s or "")
    s = "".join(c for c in s if not unicodedata.combining(c))
    return re.sub(r"[^a-z0-9]+", "", s.lower())


def tx(n):
    return {"booking_date": "2026-05-01", "credit_debit_indicator": "DBIT",
            "transaction_amount": {"amount": "17.40", "currency": "EUR"},
            "creditor": {"name": n}, "remittance_information": [n],
            "bank_transaction_code": {"code": "CCRD", "sub_code": "OTHR"}}


raw = json.load(open(sys.argv[1]))
seen, items = set(), []
for r in raw:
    k = norm(r['name'])
    if k and k not in seen:
        seen.add(k)
        items.append(r)
corpus = None
try:
    corpus = resolver.build_corpus([tx(r['name']) for r in items])
except Exception:
    pass
grad = []
for r in items:
    try:
        _, hit, res = resolver.resolve_hit(tx(r['name']), corpus)
    except Exception:
        hit, res = None, {}
    weak = hit and float((res or {}).get("explanation_coverage") or 1.0) < 0.5
    known = bool(hit and not weak)
    sec, amb = gt_map.ground_truth(r['osm'])
    if not known and not amb:
        grad.append(r['name'])
pg = [n for n in grad if ai._looks_person(n)]


def shape(n):
    p = n.split()
    return len(p) in (2, 3) and all(re.sub(r"[-']", '', x).isalpha() for x in p)


defusable = [n for n in pg if shape(n)]
print(f"gradeable: {len(grad)}")
print(f"person-guard blocks (clean name): {len(pg)}  = {100*len(pg)/len(grad):.1f}%")
print(f"  of those, pure 2-3 alpha-word shape (a real bank descriptor with a store#/")
print(f"  city token/processor '*' would DEFUSE the guard): {len(defusable)}  "
      f"({100*len(defusable)/max(1,len(pg)):.0f}% of blocked)")
