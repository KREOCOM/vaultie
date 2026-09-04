"""Fetch the Lithuanian Legal Entities Register (JAR) via the data.gov.lt Spinta API.

This is the FREE legal-entity backbone for the merchant DB: company code + name +
legal form + address + registration/dereg dates. It is NOT a merchant map — JAR
holds no IBAN, no brand/trade name, no card descriptor (those come from OSM +
real transactions). Use this to (a) validate that an AI-proposed merchant is a
real registered entity, (b) pull its company code, (c) later join NACE activity
(a SEPARATE data.gov.lt dataset) for a category prior.

Source model : datasets/gov/rc/jar/iregistruoti/JuridinisAsmuo
Fields       : ja_kodas, ja_pavadinimas, pilnas_adresas, reg_data, isreg_data,
               stat_data, forma._id (ref), statusas._id (ref)
Active        : isreg_data is null  (not deregistered)
Paging        : response._page.next cursor → &page('<cursor>')
Rate limit    : ~5000 req/h; be polite. stdlib only (urllib) — no deps.

Usage:
  python3 functions/rc_jar_fetch.py --limit 20                # print a sample
  python3 functions/rc_jar_fetch.py --active --max 5000 -o jar.ndjson
  python3 functions/rc_jar_fetch.py --name maxima             # search by name
"""
import argparse
import json
import re
import sys
import time
import urllib.parse
import urllib.request

BASE = "https://get.data.gov.lt/datasets/gov/rc/jar/iregistruoti/JuridinisAsmuo"
FIELDS = ("ja_kodas", "ja_pavadinimas", "pilnas_adresas",
          "reg_data", "isreg_data", "stat_data")
# Legal form sits at the START of the name ("UAB Maxima LT", "MB Motera",
# "VšĮ Drugelio efektas") — cheap to read without resolving the forma._id ref.
_FORM_RE = re.compile(r"^(UAB|AB|MB|VšĮ|VsI|IĮ|II|KŪB|TŪB|ŽŪB|VĮ|SĮ|BĮ|AsB)\b",
                      re.IGNORECASE)


def _legal_form(name: str) -> str:
    m = _FORM_RE.match((name or "").strip())
    return m.group(1).upper() if m else ""


def _brand_guess(name: str) -> str:
    """Strip the legal-form prefix and quotes to approximate the brand the way it
    might read on a statement. NOT authoritative — a real descriptor is confirmed
    from transactions; this is only a candidate alias."""
    n = _FORM_RE.sub("", (name or "").strip()).strip()
    return n.strip('"“”„ ').strip()


def _get(url: str, retries: int = 4):
    req = urllib.request.Request(url, headers={
        "Accept": "application/json",
        "User-Agent": "vaultie-jar-fetch/1.0 (open-data backbone)",
    })
    for attempt in range(retries):
        try:
            with urllib.request.urlopen(req, timeout=30) as r:
                return json.loads(r.read().decode("utf-8"))
        except Exception as e:  # noqa: BLE001 — network flake / 429: back off
            if attempt == retries - 1:
                raise
            time.sleep(1.5 * (attempt + 1))
    return {}


def _query(select, sort=None, name=None, limit=1000, cursor=None) -> str:
    # RQL query string. Spinta wants the operators unencoded; only the values are
    # escaped. select()/sort()/filter()/limit()/page() are comma-free segments.
    parts = [f"select({','.join(select)})", f"limit({limit})"]
    if sort:
        parts.append(f"sort({sort})")
    if name:
        # case-insensitive substring match on the name
        parts.append(f'ja_pavadinimas.contains("{name}")')
    if cursor:
        parts.append(f'page("{cursor}")')
    return BASE + "?" + "&".join(parts)


def fetch(active=False, name=None, max_rows=20, page_size=1000, sort="-reg_data"):
    """Yield normalised company records, transparently paging through the cursor."""
    cursor = None
    seen = 0
    while seen < max_rows:
        want = min(page_size, max_rows - seen)
        url = _query(FIELDS, sort=sort, name=name, limit=want, cursor=cursor)
        data = _get(url)
        rows = data.get("_data") or []
        if not rows:
            return
        for r in rows:
            if active and r.get("isreg_data") is not None:
                continue
            name_full = r.get("ja_pavadinimas") or ""
            yield {
                "code": r.get("ja_kodas"),
                "name": name_full,
                "legal_form": _legal_form(name_full),
                "brand_guess": _brand_guess(name_full),
                "address": r.get("pilnas_adresas"),
                "reg_date": r.get("reg_data"),
                "dereg_date": r.get("isreg_data"),
                "active": r.get("isreg_data") is None,
            }
            seen += 1
            if seen >= max_rows:
                return
        cursor = (data.get("_page") or {}).get("next")
        if not cursor:
            return


def main() -> int:
    ap = argparse.ArgumentParser(description="Fetch RC JAR (LT legal entities).")
    ap.add_argument("--limit", type=int, default=10, help="rows to print as a sample")
    ap.add_argument("--max", type=int, dest="max_rows", default=None,
                    help="total rows to write (defaults to --limit)")
    ap.add_argument("--active", action="store_true", help="only currently registered")
    ap.add_argument("--name", default=None,
                    help="substring name search (CASE-SENSITIVE; JAR names are "
                         "usually upper-case, e.g. --name MAXIMA)")
    ap.add_argument("-o", "--out", default=None, help="write NDJSON to this file")
    args = ap.parse_args()

    max_rows = args.max_rows or args.limit
    out = open(args.out, "w", encoding="utf-8") if args.out else None
    n = 0
    try:
        for rec in fetch(active=args.active, name=args.name, max_rows=max_rows):
            n += 1
            if out:
                out.write(json.dumps(rec, ensure_ascii=False) + "\n")
            if not out or n <= args.limit:
                print(f"  {str(rec['code']):<10} {rec['legal_form']:<4} "
                      f"{(rec['brand_guess'] or rec['name'])[:44]:<44} "
                      f"{'aktyvi' if rec['active'] else 'išreg.'} {rec['reg_date']}")
    finally:
        if out:
            out.close()
            print(f"\nWrote {n} records to {args.out}")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
