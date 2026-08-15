"""receipt_scan._parse_response — pure parse/validate step, tested without a
network mock (same convention as test_chat_lang.py: test the pure part, skip
the actual API call).
"""
from receipt_scan import _CATEGORIES, _parse_response, scan


def _run():
    # Happy path: well-formed JSON, real category names.
    r = _parse_response(
        '{"items":[{"name":"Duona","price":1.5,"category":"Maisto prekės"},'
        '{"name":"Alus","price":4.2,"category":"Alkoholis, tabakas"}],'
        '"total":5.7}')
    assert r is not None
    assert len(r["items"]) == 2
    assert r["total"] == 5.7
    assert r["items"][0]["category"] == "Maisto prekės"

    # A category the model invented (not in our taxonomy) falls back to
    # "Kita" rather than being dropped or shipped as an unrecognised string
    # the client's picker/_catMetaFor can't resolve.
    r = _parse_response(
        '{"items":[{"name":"X","price":3,"category":"Something made up"}],'
        '"total":3}')
    assert r["items"][0]["category"] == "Kita"

    # A missing/garbage total is recomputed from the item prices, not left
    # as whatever the model happened to say (or crashed on).
    r = _parse_response(
        '{"items":[{"name":"A","price":2,"category":"Kita"},'
        '{"name":"B","price":3,"category":"Kita"}]}')
    assert r["total"] == 5.0

    # A zero/negative price line is dropped, not passed through as a
    # negative split amount.
    r = _parse_response(
        '{"items":[{"name":"A","price":0,"category":"Kita"},'
        '{"name":"B","price":-1,"category":"Kita"},'
        '{"name":"C","price":2,"category":"Kita"}],"total":2}')
    assert len(r["items"]) == 1 and r["items"][0]["name"] == "C"

    # No items at all → None, not an empty-but-truthy result the client
    # would render as a valid (if pointless) split.
    assert _parse_response('{"items":[],"total":0}') is None
    assert _parse_response('not json at all') is None
    assert _parse_response('') is None

    # Prose wrapped around the JSON (the model ignoring the "JSON only"
    # instruction) is still recovered — same regex-extraction pattern
    # ai_enrichment.classify already relies on.
    r = _parse_response(
        'Here you go:\n{"items":[{"name":"X","price":1,"category":"Kita"}],'
        '"total":1}\nHope that helps!')
    assert r is not None and r["total"] == 1

    # No API key / no image → scan() short-circuits without a network call.
    assert scan("", "image/jpeg", "key") is None
    assert scan("abc", "image/jpeg", "") is None

    assert "Kita" in _CATEGORIES, "'Kita' must be a valid fallback category"

    print("test_receipt_scan: PASS")


if __name__ == "__main__":
    _run()
