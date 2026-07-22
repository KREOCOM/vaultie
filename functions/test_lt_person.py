"""Lithuanian person-name detection by distinctive surname endings.

Guards `recurring._lt_person`: a first-name + surname counterparty must be caught
as a PERSON (so it never lands in subscriptions/bills), while brands and places —
many of which also end in -a/-ė (Maxima, Norfa, Litena, Camelia, Aibė) — must NOT.
The discriminator is the DISTINCTIVE surname suffix (-ienė/-aitė/-evičius/-evas…),
never the bare -a/-ė. Folding diacritics makes ALLCAPS / no-diacritic bank forms
match ("GABRIELE MAZEIKAITE", "Rasa Konciute").

Run: python3 functions/test_lt_person.py
"""
import os
import sys

sys.path.insert(0, os.path.dirname(__file__))
from recurring import _lt_person  # noqa: E402

# Real people seen on the user's statements (must be detected).
PERSONS = [
    "Gabrielė Mažeikaitė", "Lina Gliožerienė", "Neringa Malinauskienė",
    "Deimantė Pukinskė", "Rasa Končiūtė", "Mantas Rimkevičius",
    "Osvaldas Sulajevas", "Živilė Šulajeva", "Šulajevas Osvaldas",
    "Rasa Konciute", "GABRIELE MAZEIKAITE", "LINA GLIOZERIENE",
    "Tomas Kazlauskas",
]
# Real brands / places / merchants (must NOT be detected as a person), incl. many
# ending in -a / -ė that a naive rule would wrongly flag.
NONPERSONS = [
    "Maxima", "Maxima Lt X587", "Norfa", "Litena", "Camelia", "Aibė",
    "Royal Smoke", "Vinted", "Vinted Pay UAB", "Skoniai", "Tiltu", "Overvisual",
    "Pildyk", "Mogo", "Tele2", "Netflix", "Delfi", "Anthropic", "Paysera LT",
    "Bolt", "Meal Box", "Evelina", "Vero Cafe", "Skani Mesa",
    "Circle K Sendvaris", "Circle K Miskas", "Circle K Jonusai Klaipedos",
    "Rimi Siaures", "Lidl Klaipeda", "Lidl Klaipeda Slengiu", "Prezo Kepyklele",
    "Iki Universitetas", "Kika Arenos Parduotuve", "Tallinn",
    "Uab Litena Parduotuve",
]


def main() -> int:
    fails = []
    for n in PERSONS:
        if not _lt_person(n):
            fails.append(f"MISSED person: {n!r}")
    for n in NONPERSONS:
        if _lt_person(n):
            fails.append(f"WRONGLY flagged as person: {n!r}")
    if fails:
        print(f"FAILURES ({len(fails)}):")
        for f in fails:
            print("  x", f)
        return 1
    print(f"All LT person-detection assertions passed OK "
          f"({len(PERSONS)} people caught, {len(NONPERSONS)} brands safe)")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
