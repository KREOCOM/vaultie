"""Receipt scanning — turns a photo of a paper receipt into categorised line
items, to PRE-FILL the client's manual split editor (see
dashboard_preview.dart's _SplitTransactionScreen, Phase 1). Reuses the exact
same Anthropic call shape as finance_chat/ai_enrichment — no new provider, no
new secret, just an image content block added to the message.

2026-08-16: rewritten to use FORCED TOOL USE (tool_choice) instead of asking
the model to write JSON into a text reply. Researched first (see chat/commit
history) — the earlier text-JSON approach silently lost every item whenever
the reply didn't parse cleanly (truncation mid-object, prose wrapped around
the JSON, an item missing a required field). tool_choice forcing makes the
API itself validate the reply against input_schema before ever returning it
— a malformed or incomplete tool call is a documented API-level error
instead of unparseable text this module had to guess at. This is also the
standard mitigation this whole class of "vision LLM extraction" work
converges on (schema-constrained decoding for guaranteed type-safe, complete
output) rather than something specific to this codebase.

Privacy: the photo is sent to Anthropic for this ONE request and is never
persisted server-side — same "nothing stored" contract as finance_chat.

Called over plain HTTPS (requests), same as finance_chat/ai_enrichment.
"""
import json
import logging
import time

import requests

_URL = "https://api.anthropic.com/v1/messages"
_MODEL = "claude-sonnet-5"
# Per-request timeout to Anthropic. A vision call generating up to 6000
# tokens legitimately runs longer than a text-only chat reply — 30s (and 3
# retries on top of it) could itself exceed the callable's own timeout,
# which is exactly backwards: the RETRY LOOP became the thing timing out
# the user's request. 2 attempts instead of 3, so worst case (both attempts
# time out) stays comfortably under scan_receipt's timeout_sec=110 in
# main.py — keep the two numbers in sync if either changes.
_TIMEOUT = 45
# A real Lithuanian grocery receipt easily runs 15-25 line items. 1200 was
# tuned against a short example and silently truncated the reply mid-object
# on a real 19-item Maxima receipt; 4000 was still short on a receipt with
# many items once every field (name + price + category per item) is spelled
# out. 6000 gives real receipts comfortable headroom — still cheap for a
# single-request feature, and tool_choice means a truncated call now surfaces
# as a clean "incomplete tool call" rather than unparseable partial JSON.
_MAX_TOKENS = 6000

# Mirrors dashboard_preview.dart's _taxonomy subs exactly. The model must pick
# FROM this list (enforced via the tool's JSON Schema `enum`, not just asked
# nicely in prose), not invent categories the client's picker/_catMetaFor
# won't recognise. 'Higiena' added 2026-08-16 per request — shampoo/
# toothpaste/toilet paper were falling into the generic 'Namų prekės'
# (household GOODS — more furniture/appliances than toiletries), which read
# as too coarse next to a receipt where every other line got its own
# precise category.
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

_TOOL_NAME = "record_receipt_items"
_TOOL = {
    "name": _TOOL_NAME,
    "description": (
        "Record every line item read from the receipt photo, exactly as "
        "printed on it — a single call covering the WHOLE receipt, every "
        "line, none skipped or merged."
    ),
    "input_schema": {
        "type": "object",
        "properties": {
            "items": {
                "type": "array",
                "minItems": 1,
                "items": {
                    "type": "object",
                    "properties": {
                        "name": {
                            "type": "string",
                            "description": (
                                "The product name EXACTLY as printed on the "
                                "receipt, in Lithuanian. Never empty. NEVER "
                                "the category name — a real product name "
                                "even when the category is obvious."
                            ),
                        },
                        "price": {
                            "type": "number",
                            "description": (
                                "The final price actually paid for THIS "
                                "line (after any per-line discount), read "
                                "digit by digit from the receipt — never "
                                "rounded, never approximated."
                            ),
                        },
                        "category": {
                            "type": "string",
                            "enum": _CATEGORIES,
                            "description": (
                                "The single most SPECIFIC fitting category "
                                "for this exact product — not the broadest "
                                "one that technically applies."
                            ),
                        },
                    },
                    "required": ["name", "price", "category"],
                },
            },
            "total": {
                "type": "number",
                "description": "The receipt's own printed grand total.",
            },
            "merchant": {
                "type": ["string", "null"],
                "description": (
                    "The store/restaurant name printed at the top of the "
                    "receipt (e.g. \"Maxima\", \"IKI\"), in Lithuanian as "
                    "printed. null if genuinely not legible — never guess."
                ),
            },
        },
        "required": ["items", "total", "merchant"],
    },
}

_SYSTEM = (
    "Skaitai nuotrauką kasos kvito ir užpildai record_receipt_items įrankį. "
    "Grąžink KIEKVIENĄ kvite atskirai atspausdintą eilutę kaip ATSKIRĄ "
    "prekę — NIEKADA nesugrupuok kelių skirtingų kvito eilučių į vieną, net "
    "jeigu jos panašios (pvz. \"Agurkai\" ir \"Pomidorai\" lieka DVI "
    "atskiros eilutės, ne viena \"Daržovės\"). Vienoje kvito eilutėje "
    "nurodytas kiekis (pvz. \"2x Burger\") lieka viena eilute su bendra tos "
    "eilutės suma — to skaidyti papildomai nereikia. "
    "PRIEŠ atsakydamas, perskaityk kvitą nuo viršaus iki apačios ir "
    "suskaičiuok, kiek eilučių jame atspausdinta — tiek eilučių ir grąžink, "
    "nė vienos nepraleisdamas. Po to patikrink: ar visų grąžintų eilučių "
    "kainų suma maždaug (per PVM/apvalinimo paklaidą) sutampa su kvite "
    "atspausdinta bendra suma? Jei tavo suma gerokai mažesnė — tai ženklas, "
    "kad kažkurią eilutę praleidai; peržiūrėk nuotrauką dar kartą ir "
    "papildyk trūkstamas eilutes PRIEŠ kviesdamas įrankį. "
    "Kategorija turi būti KUO TIKSLESNĖ pačiai konkrečiai prekei, ne "
    "bendriausia įmanoma — pvz. vištiena/duona/pienas → \"Maisto prekės\", "
    "šampūnas/dantų pasta/tualetinis popierius/indų ploviklis → \"Higiena\", "
    "sportinis kamuolys/sportinė apranga → \"Sportas\", alkoholis/tabakas → "
    "\"Alkoholis, tabakas\", vaistai → \"Vaistinė\". Jei tikrai neaišku — "
    "\"Kita\"."
)


def scan(image_b64: str, media_type: str, api_key: str):
    """Parse a receipt photo into line items.

    Returns {"items": [{"name","price","category"}], "total": float}, or None
    on any failure (network, rate limit, an incomplete/missing tool call) —
    the caller falls back to the empty manual-split editor, this never
    raises.
    """
    if not image_b64 or not api_key:
        return None
    payload = _payload(image_b64, media_type)
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
        except Exception as e:  # noqa: BLE001
            logging.warning("receipt_scan response wasn't JSON: %s", e)
            break
        if data.get("usage"):
            logging.info("receipt_scan usage=%s", data["usage"])
        if data.get("stop_reason") == "max_tokens":
            # Cut off mid-generation — with tool_choice forcing this means
            # an INCOMPLETE tool call (missing required fields / truncated
            # array), not invalid JSON syntax, but it's still an unusable
            # reply. Logged distinctly so a truncation regression (a
            # receipt with even more items than 6000 tokens covers) is
            # visible in Cloud Logging instead of looking like a random
            # scan failure.
            logging.warning(
                "receipt_scan truncated at max_tokens (%d)", _MAX_TOKENS)
        tool_input = _tool_input(data)
        if tool_input is None:
            logging.warning("receipt_scan: no %s tool_use block in reply "
                             "(stop_reason=%s)", _TOOL_NAME,
                             data.get("stop_reason"))
            break
        result = _validate(tool_input)
        if result is not None:
            return result
        break
    return None


def _payload(image_b64: str, media_type: str) -> str:
    return json.dumps({
        "model": _MODEL,
        "max_tokens": _MAX_TOKENS,
        "system": [{"type": "text", "text": _SYSTEM}],
        "tools": [_TOOL],
        # Forces this exact tool call every time — the model can't reply
        # with plain prose instead, and the API validates the call against
        # input_schema before this ever sees it.
        "tool_choice": {"type": "tool", "name": _TOOL_NAME},
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


def _tool_input(data: dict):
    """The record_receipt_items tool call's `input` (already a parsed dict —
    the API guarantees valid JSON conforming to input_schema for a forced
    tool call), or None if the reply has no such block (a truncated call, or
    the model refusing for some reason)."""
    for block in data.get("content") or []:
        if (isinstance(block, dict) and block.get("type") == "tool_use"
                and block.get("name") == _TOOL_NAME):
            inp = block.get("input")
            return inp if isinstance(inp, dict) else None
    return None


def _validate(obj: dict):
    """Sanitise the model's (already schema-valid) structured output against
    the app's own rules the JSON Schema can't express — a positive price, a
    category that's still in _CATSET (defence in depth against a stale
    enum), a name that isn't blank. Factored out from scan() so it's testable
    without a network mock (same convention as _chat_system in
    finance_chat/test_chat_lang.py — test the pure part, skip the network).
    Returns {"items": [...], "total": float} or None if nothing usable
    survived."""
    if not isinstance(obj, dict):
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
        name = str(it.get("name") or "").strip()[:60]
        if not name:
            # The schema marks this required — a genuinely empty string
            # despite that is worth knowing about, not just silently
            # patched over (the old text-JSON path used to fall back to
            # the category itself here, which LOOKED like a name but
            # wasn't one — that's exactly the bug this replaces).
            logging.warning("receipt_scan: item with empty name (category=%s)",
                             cat)
            name = cat
        out.append({"name": name, "price": price, "category": cat})
    if not out:
        return None
    try:
        total = round(float(obj.get("total")), 2)
    except (TypeError, ValueError):
        total = round(sum(i["price"] for i in out), 2)
    merchant = obj.get("merchant")
    merchant = str(merchant).strip()[:60] if isinstance(merchant, str) else None
    merchant = merchant or None  # an empty string is the same as "not legible"
    return {"items": out, "total": total, "merchant": merchant}
