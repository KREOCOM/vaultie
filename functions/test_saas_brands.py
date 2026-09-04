"""Card payments to AI/dev/creator SaaS brands (Base44, Replit, Lovable, CapCut,
Canva…) can only be a software service — they must categorise as software /
subscriptions, never fall through to "Kita". Regression for the brand KB.
"""
from dashboard import NAME_OVERRIDES, _SUBS


def _run():
    subs_tokens = set()
    for kws, mapped in NAME_OVERRIDES:
        if mapped is _SUBS:
            subs_tokens.update(kws)

    for brand in ("base44", "replit", "lovable", "loveable", "capcut", "cursor",
                  "canva", "vercel", "supabase", "elevenlabs", "perplexity",
                  "framer", "webflow", "grammarly", "anthropic", "openai"):
        assert brand in subs_tokens, \
            f"{brand!r} is not mapped to the software/subscriptions category"

    print("test_saas_brands: PASS")


if __name__ == "__main__":
    _run()
