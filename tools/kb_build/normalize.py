"""Alias normalization + sanitization for the offline KB build.

This is the primary defence for the zero-false-merge invariant (G1): a broad
open-data pull contains short, generic and ambiguous surface forms that would
substring-match unrelated descriptors. Sanitization is GENERIC — a stoplist of
descriptor-noise / structural words + length and shape rules — never a per-brand
rule. Anything too weak to be a safe identity is dropped; the brand simply won't
resolve rather than mis-resolve.
"""

import re
import unicodedata

# Letters that do NOT NFKD-decompose to base+combining (so NFKD alone misses
# them). NFKD handles the rest (LT diacritics, å ä ö, etc.).
_SPECIAL = {"ø": "o", "œ": "oe", "æ": "ae", "ß": "ss", "đ": "d", "ł": "l",
            "þ": "th", "ð": "d"}

# Structural / generic / ambiguous tokens that must never stand alone as an
# alias (they collide across unrelated merchants). Legal forms, geo words,
# category words, filler. NOT brand names.
_STOP = {
    "uab", "ab", "mb", "as", "asa", "oy", "oyj", "ii", "ij", "ou", "oü", "sia",
    "sa", "bv", "gmbh", "ltd", "inc", "llc", "plc", "norge", "sverige", "suomi",
    "danmark", "eesti", "latvija", "lietuva", "norway", "sweden", "finland",
    "denmark", "estonia", "latvia", "lithuania", "group", "holding", "company",
    "co", "concern", "stores", "store", "shop", "shops", "market", "marked",
    "marketing", "retail", "brand", "chain", "express", "center", "centre",
    "centra", "central", "city", "point", "plus", "extra", "power", "feel",
    "mani", "vic", "one", "the", "and", "for", "energy", "energi", "energia",
    "oil", "fuel", "gas", "petrol", "station", "kiosk", "food", "foods", "auto",
    "home", "online", "digital", "media", "service", "services", "systems",
    "nord", "syd", "vest", "north", "south", "east", "west", "international",
    "global", "trading", "prekyba", "parduotuve", "aptieka", "apteka",
}

_LEGAL_GEO_SUFFIX = {
    "uab", "ab", "asa", "as", "oy", "oyj", "ou", "sia", "sa", "gmbh", "ltd",
    "inc", "llc", "plc", "norge", "sverige", "suomi", "danmark", "eesti",
    "latvija", "lietuva", "a", "s",
    # trailing country codes — so "Maxima LT" also yields the brand core "maxima"
    # and merges with a "Maxima" record from another market (union-find on shared
    # alias_norm). Additive: the full form is kept too.
    "lt", "lv", "ee", "no", "se", "dk", "fi",
}


def fold(s):
    s = (s or "").lower()
    for k, v in _SPECIAL.items():
        s = s.replace(k, v)
    s = unicodedata.normalize("NFKD", s)
    return "".join(c for c in s if not unicodedata.combining(c))


def norm(s):
    """Folded, alnum-only key used for the alias_norm / prefix indices."""
    return re.sub(r"[^a-z0-9]+", "", fold(s))


def _tokens(s):
    return [t for t in re.split(r"[^a-z0-9]+", fold(s)) if t]


def alias_variants(label):
    """From one raw label produce candidate alias display-strings: the full
    surface and a legal/geo-suffix-stripped core."""
    out = set()
    lab = (label or "").strip()
    if "http" in lab.lower() or "/" in lab or "@" in lab:
        return out                    # URL-ish altLabel -> not an identity
    disp = re.sub(r"\s+", " ", lab.lower())
    if disp:
        out.add(disp)
    toks = _tokens(label)
    # Strip trailing legal/geo tokens to expose the brand core.
    core = list(toks)
    while core and core[-1] in _LEGAL_GEO_SUFFIX:
        core.pop()
    if core and core != toks:
        out.add(" ".join(core))
    return out


def sanitize_aliases(labels):
    """Return (aliases_display, alias_norms) after dropping unsafe surfaces."""
    disp, norms = [], []
    seen = set()
    for lab in labels:
        for a in alias_variants(lab):
            n = norm(a)
            if len(n) < 3:            # too short -> collides
                continue
            if n.isdigit():           # pure number -> store id, not identity
                continue
            if a in _STOP or n in _STOP:
                continue
            # A single generic stop-token core is unsafe even if >=3 chars.
            toks = _tokens(a)
            if len(toks) == 1 and toks[0] in _STOP:
                continue
            if n in seen:
                continue
            seen.add(n)
            disp.append(a)
            norms.append(n)
    return disp, norms


def slug(label):
    n = norm(label)
    return n or "entity"
