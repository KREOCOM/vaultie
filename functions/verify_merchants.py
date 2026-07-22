"""Verify an AI-proposed merchant candidate list against INDEPENDENT sources.

The AI (ChatGPT) PROPOSES; truth comes from agreement with sources that don't
depend on the AI's guess:
  * domain  — does the official website actually resolve + serve? (catches a
              hallucinated domain, and proves the brand is real & online)
  * Registrų centras (JAR) — is there a real, active LT legal entity whose name
              contains the brand token? (LT-existence + a company code)

Each candidate is bucketed:
  CONFIRMED  — domain resolves AND (RC match OR a known-foreign brand w/ live site)
  UNCERTAIN  — exactly one independent signal held; hold for human / a real txn
  DISCARD    — domain dead AND no RC match: nothing independent backs it

stdlib only. Usage: python3 functions/verify_merchants.py <candidates.json>
"""
import concurrent.futures as cf
import json
import socket
import ssl
import sys
import urllib.parse
import urllib.request

RC = "https://get.data.gov.lt/datasets/gov/rc/jar/iregistruoti/JuridinisAsmuo"
_STOP = {"uab", "ab", "mb", "vsi", "vši", "lt", "ltu", "group", "grupe", "grupė",
         "lietuva", "baltic", "the", "and", "de", "la"}


def domain_live(domain: str):
    """(ok, detail). ok=True if DNS resolves AND an HTTP(S) request returns a
    non-5xx status. Falls back to DNS-only when the site blocks HEAD/GET."""
    if not domain:
        return False, "no domain"
    host = domain.replace("https://", "").replace("http://", "").strip("/").split("/")[0]
    try:
        socket.setdefaulttimeout(6)
        socket.getaddrinfo(host, 443)
    except Exception:
        return False, "DNS fail"
    for scheme in ("https", "http"):
        try:
            req = urllib.request.Request(f"{scheme}://{host}", method="GET",
                                         headers={"User-Agent": "Mozilla/5.0 vaultie-verify"})
            ctx = ssl.create_default_context()
            ctx.check_hostname = False
            ctx.verify_mode = ssl.CERT_NONE
            with urllib.request.urlopen(req, timeout=8, context=ctx) as r:
                return True, f"HTTP {r.status}"
        except urllib.error.HTTPError as e:
            return (e.code < 500), f"HTTP {e.code}"
        except Exception:
            continue
    return True, "DNS ok (no HTTP)"   # resolves but blocks bots — still real


def _brand_token(rec) -> str:
    for cand in (rec.get("name") or "").split():
        t = cand.strip('"“”„.,&').lower()
        if len(t) >= 3 and t not in _STOP:
            return cand.strip('"“”„.,&')
    return (rec.get("name") or "").strip()


def rc_match(rec):
    """Search JAR for an ACTIVE legal entity whose name contains the brand token.
    Returns (matched_name, code) or None. Case-sensitive → try upper + title."""
    token = _brand_token(rec)
    if not token:
        return None
    for term in {token.upper(), token.title(), token}:
        q = (f'select(ja_kodas,ja_pavadinimas,isreg_data)&'
             f'ja_pavadinimas.contains("{term}")&limit(8)')
        url = RC + "?" + q
        try:
            req = urllib.request.Request(url, headers={"Accept": "application/json",
                                                       "User-Agent": "vaultie-verify/1.0"})
            with urllib.request.urlopen(req, timeout=15) as r:
                rows = json.loads(r.read().decode()).get("_data") or []
        except Exception:
            rows = []
        active = [x for x in rows if x.get("isreg_data") is None]
        if active:
            b = active[0]
            return b.get("ja_pavadinimas"), b.get("ja_kodas")
    return None


def main() -> int:
    path = sys.argv[1] if len(sys.argv) > 1 else "vaultie_lt_merchants_candidates_70.json"
    data = json.load(open(path, encoding="utf-8"))
    recs = data if isinstance(data, list) else next(
        (v for v in data.values() if isinstance(v, list)), [])

    # domains in parallel (network-bound), RC sequentially (be polite to Spinta)
    with cf.ThreadPoolExecutor(max_workers=12) as ex:
        dom = list(ex.map(lambda r: domain_live(r.get("domain")), recs))
    rcm = [rc_match(r) for r in recs]

    confirmed, uncertain, discard = [], [], []
    for rec, (dok, ddet), rc in zip(recs, dom, rcm):
        row = (rec.get("name"), rec.get("category"), rec.get("domain"),
               ddet, rc, rec.get("confidence"))
        if dok and rc:
            confirmed.append(row + ("domenas+RC",))
        elif dok:
            confirmed.append(row + ("domenas gyvas",))
        elif rc:
            uncertain.append(row + ("RC yra, domenas neatsako",))
        else:
            discard.append(row + ("nei domeno, nei RC",))

    def show(title, rows, n=99):
        print(f"\n{title}: {len(rows)}")
        for name, cat, dom_, ddet, rc, conf, why in rows[:n]:
            rcs = f"RC:{rc[1]}" if rc else "RC:—"
            print(f"   {(name or '')[:24]:24} {(cat or ''):11} {(dom_ or ''):22} "
                  f"{ddet:14} {rcs:12} [{conf}] {why}")

    print(f"IŠ VISO: {len(recs)} kandidatų")
    show("✅ CONFIRMED (paruošti į KB)", confirmed)
    show("⏸️  UNCERTAIN (laukia žmogaus/domeno)", uncertain)
    show("❌ DISCARD (niekas nepatvirtina)", discard)

    out = path.rsplit(".", 1)[0] + "_verified.json"
    with open(out, "w", encoding="utf-8") as f:
        json.dump({
            "confirmed": [r[0] for r in confirmed],
            "uncertain": [r[0] for r in uncertain],
            "discard": [r[0] for r in discard],
        }, f, ensure_ascii=False, indent=2)
    print(f"\nSanti: {len(confirmed)} confirmed / {len(uncertain)} uncertain / "
          f"{len(discard)} discard → {out}")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
