"""Regression: dashboard._is_person_name matches company markers as WHOLE TOKENS,
not substrings — people whose names contain as/ab/ou are labelled personal
transfers, real company tokens are not. Pure-local, no API."""
import os
import sys

sys.path.insert(0, os.path.dirname(__file__))
from dashboard import _is_person_name  # noqa: E402

PEOPLE = [
    "Fabijonas Kazlauskas",  # "ab"/"as" inside tokens
    "Silvija Roubaite",      # "ou" inside "Roubaite"
    "Milda Dirsiene",
    "Ingrida Čeledinė",
    "Rasa Noumea",
]

COMPANIES = [
    "Senukai UAB",
    "Firma AS",
    "Baltic OU",
    "Mefo AB",
    "Artus Grupe",           # business (rent payee) — must stay a company
]


def test_people_with_marker_substrings_are_personal():
    bad = [n for n in PEOPLE if not _is_person_name(n)]
    assert not bad, f"these PEOPLE were not recognised as personal transfers: {bad}"


def test_company_tokens_are_not_people():
    bad = [n for n in COMPANIES if _is_person_name(n)]
    assert not bad, f"these COMPANIES were mistaken for people: {bad}"


if __name__ == "__main__":
    test_people_with_marker_substrings_are_personal()
    test_company_tokens_are_not_people()
    for n in PEOPLE:
        print(f"  person   {n!r:24} -> is_person={_is_person_name(n)}")
    for n in COMPANIES:
        print(f"  company  {n!r:24} -> is_person={_is_person_name(n)}")
    print("\ndashboard._is_person_name token-boundary: all assertions passed ✓")
