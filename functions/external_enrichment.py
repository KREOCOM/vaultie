"""P9 — External enrichment fallback interface (NO provider wired).

This is the single, explicit place a future external merchant-enrichment
provider would be called — and ONLY for transactions the deterministic resolver
could not confidently resolve (status == NEEDS_EXTERNAL_ENRICHMENT, or UNKNOWN
if a caller opts in). No paid/remote provider is integrated. The default
provider is a no-op that always abstains, so behaviour is unchanged until a real
provider is deliberately registered.

Privacy note (enforced later, not here): a provider must receive only a minimal,
sanitized merchant descriptor — never raw transactions, amounts, IBANs, names or
user identifiers. The `minimal_descriptor` built below already excludes all of
that; the actual minimization/consent policy is a separate, deliberate step.
"""

from resolver import NEEDS_EXTERNAL, UNKNOWN


class ExternalEnrichmentProvider:
    """Interface a concrete provider implements. `resolve` returns either a
    resolver-style hit tuple (canonical, recurring_type, category, logo) or None
    to abstain."""

    def resolve(self, minimal_descriptor: dict):  # noqa: D401
        raise NotImplementedError


class NullExternalProvider(ExternalEnrichmentProvider):
    """Default: always abstains. Keeps the call-site live but inert."""

    def resolve(self, minimal_descriptor: dict):
        return None


# The single active provider. Swapping this for a real implementation is the
# only wiring change needed later — nothing else in the pipeline moves.
_provider: ExternalEnrichmentProvider = NullExternalProvider()


def set_provider(provider: ExternalEnrichmentProvider) -> None:
    global _provider
    _provider = provider


def _minimal_descriptor(resolution: dict) -> dict:
    """Only merchant-descriptor signal — no amount, IBAN, names, user id, or raw
    transaction. This is the ONLY payload a provider may ever receive."""
    return {
        "surface": resolution.get("surface"),
        "matched_tokens": resolution.get("matched_tokens"),
        "residual_tokens": resolution.get("residual_tokens"),
        "top_score": resolution.get("top_score"),
        "margin": resolution.get("margin"),
    }


def maybe_enrich(resolution: dict, *, include_unknown: bool = False):
    """Call-site (inert by default). Returns a hit tuple if a provider resolves
    the unresolved descriptor, else None. Only fires for NEEDS_EXTERNAL_
    ENRICHMENT (and UNKNOWN when include_unknown)."""
    status = resolution.get("status")
    if status == NEEDS_EXTERNAL or (include_unknown and status == UNKNOWN):
        return _provider.resolve(_minimal_descriptor(resolution))
    return None
