"""Download each brand's OWN published app icon into assets/logos/.

Why bundle at all: fetching logos at runtime from a logo service tells that
service every merchant our users pay — their pharmacy, their lender, where they
eat — alongside the user's IP. For a finance app that is spending data, and no
free tier is worth leaking it. Bundling also means no network on render: the icon
is simply there, offline, instantly, with nothing to flash or fail.

Why the brand's own site: these are the assets each brand publishes for exactly
this purpose (the icon you get when you save their site to a phone's home
screen). Displaying them next to a transaction the user actually made is
referential use — it identifies the merchant, it doesn't claim to be them.
Bundling does NOT make them ours; each mark stays its owner's, and `sources.json`
records where every file came from so any of them can be removed on request.

Run:  python3 tools/logos/fetch_logos.py
"""
import json
import os
import re
import subprocess
import sys

ROOT = os.path.dirname(os.path.dirname(os.path.dirname(os.path.abspath(__file__))))
OUT = os.path.join(ROOT, "assets", "logos")
DART = os.path.join(ROOT, "lib", "services", "logo_service.dart")
UA = ("Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/537.36 "
      "(KHTML, like Gecko) Chrome/124.0 Safari/537.36")


def curl(url, binary=False, timeout=20):
    try:
        r = subprocess.run(
            ["curl", "-sL", "--max-time", str(timeout), "-A", UA, url],
            capture_output=True, timeout=timeout + 5)
        if r.returncode != 0 or not r.stdout:
            return None
        return r.stdout if binary else r.stdout.decode("utf-8", "ignore")
    except Exception:
        return None


def brands():
    """(key, domain) pairs straight from the app's own table — one source of
    truth, so a brand added there can never be silently missing its icon."""
    body = open(DART).read().split("const Map<String, String> _serviceDomains = {")[1]
    body = body.split("};")[0]
    seen = {}
    for key, domain in re.findall(r"'([^']+)':\s*'([^']+)'", body):
        seen.setdefault(domain, key)   # one icon per domain, not per alias
    return [(k, d) for d, k in seen.items()]


def icon_urls(domain):
    """Candidate icon URLs for a domain, best-quality first."""
    html = curl(f"https://{domain}") or ""
    out = []
    for m in re.finditer(
            r'<link[^>]+rel=["\']([^"\']*icon[^"\']*)["\'][^>]*>', html, re.I):
        tag = m.group(0)
        href = re.search(r'href=["\']([^"\']+)["\']', tag)
        if not href:
            continue
        u = href.group(1)
        if u.startswith("//"):
            u = "https:" + u
        elif u.startswith("/"):
            u = f"https://{domain}{u}"
        elif not u.startswith("http"):
            u = f"https://{domain}/{u}"
        size = 0
        s = re.search(r'sizes=["\'](\d+)x\d+', tag)
        if s:
            size = int(s.group(1))
        rel = m.group(1).lower()
        # apple-touch-icon is the one brands actually art-direct; it is square,
        # opaque and sized for a phone — exactly our use.
        score = (2 if "apple" in rel else 0, size)
        out.append((score, u))
    out.sort(reverse=True)
    urls = [u for _, u in out]
    urls.append(f"https://{domain}/apple-touch-icon.png")
    # Last resort: Google's favicon service, which serves the brand's own icon as
    # a PNG. It's used HERE, at build time, from a developer's machine — the one
    # place it costs nothing: no user exists yet, so nothing about anyone's
    # spending is disclosed. Calling it from the app instead is what we're
    # avoiding. It also rescues the sites that block scripted requests or only
    # publish a .ico.
    urls.append(f"https://www.google.com/s2/favicons?domain={domain}&sz=256")
    return urls


def main():
    os.makedirs(OUT, exist_ok=True)
    sources, ok, fail = {}, [], []
    items = brands()
    for i, (key, domain) in enumerate(sorted(items), 1):
        got = False
        for u in icon_urls(domain)[:8]:
            data = curl(u, binary=True)
            # Anything tiny is a spacer or an error page, not a logo.
            if not data or len(data) < 900:
                continue
            if data[:4] not in (b"\x89PNG", b"\x00\x00\x01\x00") and b"<svg" not in data[:400]:
                continue
            ext = "png" if data[:4] == b"\x89PNG" else ("svg" if b"<svg" in data[:400] else "ico")
            if ext == "ico":
                continue  # .ico needs conversion; PNG/SVG only
            path = os.path.join(OUT, f"{key}.{ext}")
            open(path, "wb").write(data)
            sources[key] = {"domain": domain, "url": u, "file": f"{key}.{ext}",
                            "bytes": len(data)}
            ok.append(key)
            got = True
            break
        if not got:
            fail.append(f"{key} ({domain})")
        print(f"[{i}/{len(items)}] {'OK ' if got else '-- '} {key}", flush=True)
    json.dump(sources, open(os.path.join(OUT, "sources.json"), "w"),
              indent=1, sort_keys=True)
    print(f"\nDONE  got={len(ok)}  missing={len(fail)}")
    if fail:
        print("MISSING: " + ", ".join(sorted(fail)))


if __name__ == "__main__":
    sys.exit(main())
