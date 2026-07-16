"""Second pass: fill the domains the main fetch missed, and replace any logo
that came back too small to look sharp, using Google's favicon service at build
time (see fetch_logos.py for why that's leak-free here)."""
import glob, json, os, re, struct, subprocess

ROOT = os.path.dirname(os.path.dirname(os.path.dirname(os.path.abspath(__file__))))
OUT = os.path.join(ROOT, "assets", "logos")
DART = os.path.join(ROOT, "lib", "services", "logo_service.dart")
SRC = os.path.join(OUT, "sources.json")

def dims(p):
    try:
        h = open(p, "rb").read(24)
    except Exception:
        return (0, 0)
    if h[:4] == b"\x89PNG":
        return struct.unpack(">II", h[16:24])
    return (999, 999)  # svg = vector, always sharp

body = open(DART).read().split("_serviceDomains = {")[1].split("};")[0]
dom = {}
for k, d in re.findall(r"'([^']+)':\s*'([^']+)'", body):
    dom.setdefault(d, k)
sources = json.load(open(SRC)) if os.path.exists(SRC) else {}

def have_good(key):
    for ext in ("png", "svg"):
        p = os.path.join(OUT, f"{key}.{ext}")
        if os.path.exists(p) and dims(p)[0] >= 48:
            return True
    return False

fixed = 0
for d, key in sorted(dom.items()):
    if have_good(key):
        continue
    for sz in (256, 128):
        u = f"https://www.google.com/s2/favicons?domain={d}&sz={sz}"
        r = subprocess.run(["curl", "-sL", "--max-time", "20", u],
                           capture_output=True)
        data = r.stdout
        if data[:4] == b"\x89PNG" and len(data) > 900:
            w, _ = struct.unpack(">II", data[16:24])
            if w >= 48:
                for old in glob.glob(os.path.join(OUT, f"{key}.*")):
                    if not old.endswith("sources.json"):
                        os.remove(old)
                open(os.path.join(OUT, f"{key}.png"), "wb").write(data)
                sources[key] = {"domain": d, "url": u, "file": f"{key}.png",
                                "bytes": len(data)}
                fixed += 1
                print(f"OK  {key}  {w}px")
                break
    else:
        print(f"--  {key} ({d}) still missing/small")

json.dump(sources, open(SRC, "w"), indent=1, sort_keys=True)
print(f"\nfixed {fixed}; total files {len(glob.glob(os.path.join(OUT,'*.png')))+len(glob.glob(os.path.join(OUT,'*.svg')))}")
