"""Taxonomy source-of-truth invariant (Feature B).

CAT_MAP (dashboard) is the single source of truth for how a category maps to a
Vaultie product section. Every category that any UPSTREAM layer can emit — the
AI enricher's fixed vocabulary, and the deterministic resolver/global-index —
MUST be a CAT_MAP key, otherwise a correctly-resolved merchant silently falls
through to 'Kita'. This test locks that alignment so a future taxonomy edit
cannot reintroduce a silent section leak. Pure-local, no API.
"""
import os
import sys

sys.path.insert(0, os.path.dirname(__file__))

from dashboard import CAT_MAP            # noqa: E402
from ai_enrichment import _CATEGORIES    # noqa: E402

CATSET = set(CAT_MAP.keys())


def test_ai_vocabulary_subset_of_catmap():
    """The AI enricher may only emit categories CAT_MAP can place. 'other' is the
    sanctioned abstention (maps to OTHER/Kita by design)."""
    orphan = [c for c in _CATEGORIES if c != "other" and c not in CATSET]
    assert not orphan, (
        f"AI can emit categories CAT_MAP does not map (→ silent Kita): {orphan}. "
        f"Add them to CAT_MAP or remove from ai_enrichment._CATEGORIES.")


def test_resolver_emitted_categories_subset_of_catmap():
    """Every category the KB / global index attaches to an entity must be a
    CAT_MAP key. Scans the shipped KB so the check needs no network."""
    import kb
    emitted = set()
    for e in (getattr(kb, "_entities", None) or []):
        for c in (e.get("categories") or []):
            emitted.add((c or "").lower())
    orphan = sorted(c for c in emitted if c and c != "other" and c not in CATSET)
    assert not orphan, (
        f"Resolver/KB can emit categories CAT_MAP does not map (→ silent Kita): "
        f"{orphan}. Extend CAT_MAP to cover them.")


if __name__ == "__main__":
    test_ai_vocabulary_subset_of_catmap()
    test_resolver_emitted_categories_subset_of_catmap()
    print(f"CAT_MAP keys: {len(CATSET)}   AI vocab: {len(_CATEGORIES)}")
    print("Taxonomy invariant holds ✓  (AI vocab ⊆ CAT_MAP, KB categories ⊆ CAT_MAP)")
