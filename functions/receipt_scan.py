"""Receipt scanning — turns a photo of a paper receipt into categorised line
items, to PRE-FILL the client's manual split editor (see
dashboard_preview.dart's _SplitTransactionScreen, Phase 1). Reuses the exact
same Anthropic call shape as finance_chat/ai_enrichment — no new provider, no
new secret, just an image content block added to the message.

Privacy: the photo is sent to Anthropic for this ONE request and is never
persisted server-side — same "nothing stored" contract as finance_chat.

Called over plain HTTPS (requests), same as finance_chat/ai_enrichment.
"""
import json
import logging
import re
import time

import requests

_URL = "https://api.anthropic.com/v1/messages"
_MODEL = "claude-sonnet-5"
# Per-request timeout to Anthropic. A vision call generating up to 4000
# tokens legitimately runs longer than a text-only chat reply — 30s (and 3
# retries on top of it) could itself exceed the callable's own timeout,
# which is exactly backwards: the RETRY LOOP became the thing timing out
# the user's request. 2 attempts instead of 3, so worst case (both attempts
# time out) stays comfortably under scan_receipt's timeout_sec=110 in
# main.py — keep the two numbers in sync if either changes.
_TIMEOUT = 45
# A real Lithuanian grocery receipt easily runs 15-25 line items — 1200 was
# tuned against a short example and silently truncated the JSON mid-object on
# a real 19-item Maxima receipt (max_tokens cuts generation off mid-stream,
# HTTP still 200, the partial text just fails json.loads → every item lost).
# 4000 gives real receipts headroom; still cheap for a single-request feature.
_MAX_TOKENS = 4000

# Mirrors dashboard_preview.dart's _taxonomy subs exactly. The model must pick
# FROM this list, not invent categories the client's picker/_catMetaFor won't
# recognise — an unrecognised string would silently fall back to "Kita"
# client-side anyway, so it's cheaper to constrain the model up front and
# never ship a category name the two sides disagree on. 'Higiena' added
# 2026-08-16 per request — shampoo/toothpaste/toilet paper were falling into
# the generic 'Namų prekės' (household GOODS — more furniture/appliances
# than toiletries), which read as too coarse next to a receipt where every
# other line got its own precise category.
_CATEGORIES = [
    "Maisto prekės", "Kavinės, restoranai", "Alkoholis, tabakas",
    "Kuras", "Taksi", "Automobilis", "Viešasis transportas",
    "Paspirtukai, dalinimasis", "Parkavimas",
    "Drabužiai", "Elektronika, prekės", "Namų prekės", "Higiena",
    "Nuoma", "Būstas, nuoma", "Būsto paskola", "Komunaliniai",
    "Ryšys, internetas", "Draudimas",
    "Sveikata", "Sportas", "Vaistinė",
    "Pramogos", "Prenumeratos", "Kelionės",
    "Mokesčiai", "Bankas, komisiniai", "Investicijos", "Paskola, lizingas",
    "Mokslas", "Kursai, knygos", "Vaikai, ugdymas",
    "Kita",
]
_CATSET = set(_CATEGORIES)

_SYSTEM = (
    "Skaitai nuotrauką kasos kvito. Grąžink KIEKVIENĄ kvite atskirai "
    "atspausdintą eilutę kaip ATSKIRĄ prekę — NIEKADA nesugrupuok kelių "
    "skirtingų kvito eilučių į vieną, net jeigu jos panašios (pvz. "
    "\"Agurkai\" ir \"Pomidorai\" lieka DVI atskiros eilutės, ne viena "
    "\"Daržovės\"). Vienoje kvito eilutėje nurodytas kiekis (pvz. \"2x "
    "Burger\") lieka viena eilute su bendra ta eilutės suma — to nereikia "
    "skaidyti papildomai. Naudok GALUTINĘ sumokėtą kainą (po nuolaidos, jei "
    "ji nurodyta prie prekės). "
    "Kategorija turi būti KUO TIKSLESNĖ pačiai konkrečiai prekei, ne "
    "bendriausia įmanoma — pvz. vištiena/duona/pienas → \"Maisto prekės\", "
    "šampūnas/dantų pasta/tualetinis popierius/indų ploviklis → \"Higiena\", "
    "sportinis kamuolys/sportinė apranga → \"Sportas\", alkoholis/tabakas → "
    "\"Alkoholis, tabakas\", vaistai → \"Vaistinė\". "
    f"Kategorija kiekvienai eilutei PRIVALO būti TIKSLIAI viena iš šio "
    f"sąrašo, be jokių naujų ar pakeistų: {', '.join(_CATEGORIES)}. Jei "
    'tikrai neaišku — "Kita". '
    "Grąžink TIK kompaktišką JSON, be jokio kito teksto ar paaiškinimų: "
    '{"items":[{"name":"<prekės pavadinimas lietuviškai, kaip kvite>",'
    '"price":<skaičius>,"category":"<kategorija iš sąrašo>"}],'
    '"total":<visa kvito suma>}.'
)


def scan(image_b64: str, media_type: str, api_key: str):
    """Parse a receipt photo into line items.

    Returns {"items": [{"name","price","category"}], "total": float}, or None
    on any failure (network, rate limit, malformed/empty reply) — the caller
    falls back to the empty manual-split editor, this never raises.
    """
    if not image_b64 or not api_key:
        return None
    payload = json.dumps({
        "model": _MODEL,
        "max_tokens": _MAX_TOKENS,
        "system": [{"type": "text", "text": _SYSTEM}],
        "messages": [{
            "role": "user",
            "content": [
                {"type": "image", "source": {"type": "base64",
                                              "media_type": media_type,
                                              "data": image_b64}},
                {"type": "text", "text": "Nuskaityk šį kvitą."},
            ],
        }],
    })
    headers = {"x-api-key": api_key, "anthropic-version": "2023-06-01",
               "content-type": "application/json"}
    for attempt in range(2):
        try:
            r = requests.post(_URL, timeout=_TIMEOUT, headers=headers, data=payload)
        except Exception as e:  # noqa: BLE001
            logging.warning("receipt_scan request failed: %s", e)
            time.sleep(0.6 * (attempt + 1))
            continue
        if r.status_code == 429:
            time.sleep(1.0 * (attempt + 1))
            continue
        if not r.ok:
            logging.warning("receipt_scan http %s: %s", r.status_code, r.text[:200])
            break
        try:
            data = r.json()
            txt = "".join(b.get("text", "") for b in data.get("content", [])
                          if b.get("type") == "text")
            if data.get("usage"):
                logging.info("receipt_scan usage=%s", data["usage"])
            if data.get("stop_reason") == "max_tokens":
                # The reply was cut off mid-generation — likely mid-JSON, so
                # _parse_response is about to fail. Logged distinctly from a
                # genuine parse failure so a truncation regression (receipt
                # with even more items than 4000 tokens covers) is visible in
                # Cloud Logging instead of looking like a random bad scan.
                logging.warning(
                    "receipt_scan truncated at max_tokens (%d) — reply likely "
                    "incomplete JSON", _MAX_TOKENS)
        except Exception as e:  # noqa: BLE001
            logging.warning("receipt_scan parse failed: %s", e)
            break
        result = _parse_response(txt)
        if result is not None:
            return result
        break
    return None


def _parse_response(txt: str):
    """Pure parse/validate step, factored out so it's testable without a
    network mock (same convention as _chat_system in finance_chat/
    test_chat_lang.py — test the pure part, skip the network). Returns
    {"items": [...], "total": float} or None if the model's reply had no
    usable items."""
    try:
        m = re.search(r"\{.*\}", txt or "", re.S)
        if not m:
            return None
        obj = json.loads(m.group(0))
    except Exception as e:  # noqa: BLE001
        logging.warning("receipt_scan parse failed: %s", e)
        return None
    items = obj.get("items")
    if not isinstance(items, list) or not items:
        return None
    out = []
    for it in items:
        if not isinstance(it, dict):
            continue
        try:
            price = round(float(it.get("price")), 2)
        except (TypeError, ValueError):
            continue
        if price <= 0:
            continue
        cat = str(it.get("category") or "").strip()
        if cat not in _CATSET:
            cat = "Kita"
        name = str(it.get("name") or "").strip()[:60] or cat
        out.append({"name": name, "price": price, "category": cat})
    if not out:
        return None
    try:
        total = round(float(obj.get("total")), 2)
    except (TypeError, ValueError):
        total = round(sum(i["price"] for i in out), 2)
    return {"items": out, "total": total}
