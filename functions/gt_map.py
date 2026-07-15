"""Fixed, a-priori mapping from independent OSM tags -> Vaultie category buckets.

Defined BEFORE running the test; not tuned to results. Keys are OSM
shop=/amenity= values; the value is the Vaultie section (as CAT_MAP returns in
slot [3]) we consider CORRECT for that merchant kind. `None` = intentionally
AMBIGUOUS (excluded from the accuracy denominator) because the tag maps to no
single Vaultie category or is inherently fuzzy.
"""

# Vaultie sections (CAT_MAP slot 3): "Maistas, gėrimai", "Transportas",
# "Apsipirkimas", "Sveikata, sportas", "Būstas, sąskaitos", "Finansai",
# "Pramogos", "Švietimas", "Kita".

OSM_TO_SECTION = {
    # food & drink
    "supermarket": "Maistas, gėrimai", "convenience": "Maistas, gėrimai",
    "grocery": "Maistas, gėrimai", "greengrocer": "Maistas, gėrimai",
    "butcher": "Maistas, gėrimai", "bakery": "Maistas, gėrimai",
    "pastry": "Maistas, gėrimai", "confectionery": "Maistas, gėrimai",
    "restaurant": "Maistas, gėrimai", "fast_food": "Maistas, gėrimai",
    "cafe": "Maistas, gėrimai", "bar": "Maistas, gėrimai", "pub": "Maistas, gėrimai",
    "food_court": "Maistas, gėrimai", "ice_cream": "Maistas, gėrimai",
    "alcohol": "Maistas, gėrimai", "wine": "Maistas, gėrimai",
    "beverages": "Maistas, gėrimai", "tobacco": "Maistas, gėrimai",
    # transport / auto / fuel
    "fuel": "Transportas", "car_repair": "Transportas", "car": "Transportas",
    "car_parts": "Transportas", "tyres": "Transportas", "car_wash": "Transportas",
    "parking": "Transportas", "motorcycle": "Transportas",
    # shopping (retail)
    "clothes": "Apsipirkimas", "shoes": "Apsipirkimas", "jewelry": "Apsipirkimas",
    "electronics": "Apsipirkimas", "mobile_phone": "Apsipirkimas",
    "computer": "Apsipirkimas", "furniture": "Apsipirkimas",
    "doityourself": "Apsipirkimas", "hardware": "Apsipirkimas",
    "florist": "Apsipirkimas", "books": "Apsipirkimas", "toys": "Apsipirkimas",
    "sports": "Apsipirkimas", "bicycle": "Apsipirkimas", "gift": "Apsipirkimas",
    "stationery": "Apsipirkimas", "cosmetics": "Apsipirkimas",
    "perfumery": "Apsipirkimas", "boutique": "Apsipirkimas",
    "department_store": "Apsipirkimas", "kiosk": "Apsipirkimas",
    "variety_store": "Apsipirkimas", "pet": "Apsipirkimas",
    # health & sport
    "pharmacy": "Sveikata, sportas", "chemist": "Sveikata, sportas",
    "optician": "Sveikata, sportas", "hairdresser": "Sveikata, sportas",
    "beauty": "Sveikata, sportas", "dentist": "Sveikata, sportas",
    "doctors": "Sveikata, sportas", "clinic": "Sveikata, sportas",
    "hospital": "Sveikata, sportas", "fitness_centre": "Sveikata, sportas",
    "gym": "Sveikata, sportas", "massage": "Sveikata, sportas",
    # housing / utilities
    "bank": "Finansai", "atm": "Finansai", "bureau_de_change": "Finansai",
    # entertainment
    "cinema": "Pramogos", "theatre": "Pramogos", "nightclub": "Pramogos",
    # education
    "school": "Švietimas", "university": "Švietimas", "college": "Švietimas",
    "kindergarten": "Švietimas", "language_school": "Švietimas",
    # intentionally AMBIGUOUS (no clean single Vaultie bucket) -> excluded
    "yes": None, "vending_machine": None, "post_office": None, "hotel": None,
    "hostel": None, "travel_agency": None, "laundry": None, "copyshop": None,
    "storage_rental": None, "estate_agent": None, "insurance": None,
    "money_lender": None, "charity": None, "second_hand": None, "trade": None,
    "wholesale": None, "art": None, "photo": None, "funeral_directors": None,
}


def ground_truth(osm_value):
    """Return (section_or_None, is_ambiguous). Unknown tags -> ambiguous."""
    if osm_value in OSM_TO_SECTION:
        sec = OSM_TO_SECTION[osm_value]
        return sec, (sec is None)
    return None, True  # tag not in our a-priori map -> ambiguous, excluded
