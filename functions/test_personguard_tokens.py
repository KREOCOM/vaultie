"""Regression: legal-form markers in _looks_person are matched as WHOLE TOKENS,
not substrings — so a person whose name merely CONTAINS the letters as/ab/ou is
still guarded, while a real legal form (a standalone AS/UAB/OU token) is not.
Pure-local, no API."""
import os
import sys

sys.path.insert(0, os.path.dirname(__file__))
from ai_enrichment import _looks_person  # noqa: E402

# People whose names naturally contain a marker substring — MUST read as person
# (guarded). These are exactly the names that leaked through the old substring check.
PEOPLE = [
    "Jonas Petraitis",       # "as" inside "Jonas"
    "Fabijonas Kazlauskas",  # "ab" in "Fabijonas", "as" in both tokens
    "Silvija Roubaite",      # "ou" inside "Roubaite"
    "Tomas Balčiūnas",       # "as" inside both
    "Gabriele Ablonskyte",   # "ab" inside "Ablonskyte"
    "Rasa Noumea",           # "as" and "ou"
]

# Real legal forms present as standalone tokens — MUST NOT read as person (company).
COMPANIES = [
    "Firma AS",              # Norwegian AS
    "Senukai UAB",           # Lithuanian UAB
    "Baltic OU",             # Estonian OÜ (ascii'd)
    "Mefo AB",               # Swedish AB
]


def test_people_with_marker_substrings_are_guarded():
    bad = [n for n in PEOPLE if not _looks_person(n)]
    assert not bad, f"these PEOPLE bypassed the person-guard (should be blocked): {bad}"


def test_real_legal_forms_are_not_people():
    bad = [n for n in COMPANIES if _looks_person(n)]
    assert not bad, f"these COMPANIES were mistaken for people: {bad}"


if __name__ == "__main__":
    test_people_with_marker_substrings_are_guarded()
    test_real_legal_forms_are_not_people()
    for n in PEOPLE:
        print(f"  person   {n!r:26} -> guarded={_looks_person(n)}")
    for n in COMPANIES:
        print(f"  company  {n!r:26} -> guarded={_looks_person(n)}")
    print("\nToken-boundary legal-marker guard: all assertions passed ✓")
