"""Merchant Category Code → Vaultie category.

MCC (ISO 18245) is the four-digit code the card networks attach to every card
purchase. It says what KIND of merchant was paid — grocery, fuel, restaurant —
independent of the merchant's NAME, so it categorises the entire long tail
(every shop in Europe) without a merchant list. The bank passes it through as
``merchant_category_code`` when it has it; not every bank does, and it only
comes on card purchases (never transfers or direct debits), so it is a strong
FIRST signal, not the only one — the name resolver stays the fallback.

Codes map to the category KEYS in dashboard.CAT_MAP. Ranges cover the common
groupings; specific codes override where a range would be wrong. Anything not
listed returns None so the caller falls back to the name resolver.
"""

# Specific codes first (checked before ranges).
_MCC_EXACT = {
    # food & grocery
    "5411": "groceries",       # supermarkets / grocery
    "5412": "groceries",       # convenience
    "5422": "groceries",       # meat/freezer
    "5451": "groceries",       # dairy
    "5462": "restaurant",      # bakeries → prepared food
    "5499": "groceries",       # misc food stores
    "5811": "restaurant",      # caterers
    "5812": "restaurant",      # restaurants
    "5813": "alcohol",         # bars / lounges
    "5814": "restaurant",      # fast food
    "5921": "alcohol",         # liquor stores
    "5993": "alcohol",         # tobacco
    # fuel & vehicle
    "5541": "fuel",
    "5542": "fuel",            # automated fuel dispensers
    "5983": "fuel",            # fuel dealers
    "7511": "fuel",            # truck stop
    "5511": "automotive",      # car dealers
    "5533": "automotive",      # auto parts
    "7538": "automotive",      # service stations
    "7542": "car_wash",
    "7523": "parking",
    # transport
    "4121": "taxi",            # taxi / limo
    "4111": "transport",       # local/commuter transport
    "4112": "transport",       # railways
    "4131": "transport",       # bus
    "4789": "transport",       # transport services
    "4511": "travel",          # airlines
    "4411": "travel",          # cruise
    "4722": "travel",          # travel agencies
    "7011": "travel",          # hotels
    "7512": "travel",          # car rental
    # health
    "5912": "pharmacy",        # drug stores / pharmacies
    "8011": "health",          # doctors
    "8021": "health",          # dentists
    "8031": "health",          # osteopaths
    "8041": "health",          # chiropractors
    "8042": "health",          # optometrists
    "8049": "health",
    "8062": "health",          # hospitals
    "8099": "health",
    "5975": "health",          # hearing aids
    "5976": "health",
    # fitness / personal
    "7997": "fitness",         # clubs / gyms
    "7941": "fitness",         # sports / recreation
    "7298": "health",          # health & beauty spas
    "7230": "retail",          # beauty / barber
    # clothing / apparel
    "5611": "clothing", "5621": "clothing", "5631": "clothing",
    "5641": "clothing", "5651": "clothing", "5655": "clothing",
    "5661": "clothing",        # shoes
    "5691": "clothing", "5697": "clothing", "5698": "clothing", "5699": "clothing",
    "5137": "clothing", "5139": "clothing",
    "7296": "clothing",        # clothing rental
    # electronics / software / digital
    "5732": "electronics",
    "5734": "software",        # computer software
    "5045": "electronics",     # computers / peripherals
    "5815": "software", "5816": "software", "5817": "software", "5818": "software",  # digital goods
    "4816": "software",        # computer network / info services
    # home / hardware / furniture
    "5200": "hardware",        # home supply warehouse
    "5211": "hardware",        # lumber / building
    "5231": "hardware",        # glass / paint
    "5251": "hardware",        # hardware stores
    "5261": "hardware",        # nurseries / garden
    "5712": "hardware",        # furniture
    "5713": "hardware", "5714": "hardware", "5718": "hardware", "5719": "hardware",
    "5722": "hardware",        # household appliances
    "5021": "hardware",        # office/commercial furniture
    # retail / shopping
    "5311": "shopping",        # department stores
    "5300": "shopping",        # wholesale clubs
    "5310": "shopping",        # discount stores
    "5331": "shopping",        # variety stores
    "5399": "shopping",        # general merchandise
    "5942": "retail",          # bookstores
    "5943": "retail",          # stationery / office
    "5945": "retail",          # toys / games
    "5947": "retail",          # gift / novelty
    "5977": "retail",          # cosmetics
    "5992": "retail",          # florists
    "5999": "retail",          # misc specialty retail
    "5931": "retail",          # used / second-hand
    "5948": "retail",          # luggage / leather
    "5970": "retail",          # art / craft
    "5192": "retail",          # books / periodicals
    # pets
    "5995": "retail",          # pet shops / vet supplies
    "0742": "health",          # veterinary services
    # entertainment / leisure
    "7832": "entertainment",   # cinemas
    "7833": "entertainment",
    "7922": "entertainment",   # theatrical / ticket agencies
    "7929": "entertainment",
    "7991": "entertainment",   # tourist attractions
    "7996": "entertainment",   # amusement parks
    "7998": "entertainment",   # aquariums / zoos
    "7999": "entertainment",   # recreation services
    "5735": "entertainment",   # record stores
    "5733": "entertainment",   # music instruments
    "7994": "entertainment",   # video game arcades
    # telecom / utilities
    "4814": "connectivity",    # telecom
    "4815": "connectivity",
    "4821": "connectivity",    # telegraph
    "4899": "connectivity",    # cable / satellite
    "4900": "utilities",       # electric / gas / water / sanitary
    # finance / insurance / tax
    "6300": "insurance",
    "5960": "insurance",       # direct marketing insurance
    "9311": "taxes",           # tax payments
    "9399": "taxes",           # government services
    "9222": "taxes",           # fines
    "9402": "taxes",           # postal (government)
    "6012": "finance",         # financial institutions
    "6051": "finance",         # quasi-cash / crypto
    "6011": "finance",         # ATM / cash
    "6540": "finance",         # non-fin institutions (funding)
    # education / childcare
    "8220": "education",       # colleges / universities
    "8211": "education",       # elementary / secondary
    "8241": "education",       # correspondence schools
    "8244": "education",       # business / secretarial
    "8249": "education",       # trade / vocational
    "8299": "education",       # educational services
    "8351": "childcare",       # child care
}

# Range fallbacks for whole families (checked only if no exact match).
_MCC_RANGES = [
    (3000, 3299, "travel"),        # airlines (branded)
    (3300, 3499, "travel"),        # car rental (branded)
    (3500, 3999, "travel"),        # hotels (branded)
    (5811, 5814, "restaurant"),
    (5600, 5699, "clothing"),
    (5200, 5271, "hardware"),
    (5300, 5399, "shopping"),
    (7990, 7999, "entertainment"),
    (8000, 8099, "health"),
    (8200, 8299, "education"),
    (4100, 4199, "transport"),
]


def category_for_mcc(mcc) -> str | None:
    """Vaultie category KEY for an MCC, or None to defer to the name resolver."""
    if mcc is None:
        return None
    code = str(mcc).strip()
    if not code or not code.isdigit():
        return None
    code = code.zfill(4)
    hit = _MCC_EXACT.get(code)
    if hit:
        return hit
    n = int(code)
    for lo, hi, cat in _MCC_RANGES:
        if lo <= n <= hi:
            return cat
    return None
