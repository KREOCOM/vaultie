"""receipt_scan — pure parse/validate steps, tested without a network mock
(same convention as test_chat_lang.py: test the pure part, skip the actual
API call). _validate operates on an already-parsed dict (what a forced tool
call's `input` looks like) rather than a JSON string, since tool_choice
forcing means the API itself guarantees valid JSON before this module ever
sees it — there's no text-parsing step left to test.
"""
from receipt_scan import (_CATEGORIES, _TOOL_NAME, _tool_input, _validate,
                           scan)


def _run():
    # Happy path: well-formed input, real category names, a legible merchant.
    r = _validate(
        {"items": [{"name": "Duona", "price": 1.5, "category": "Maisto prekės"},
                    {"name": "Alus", "price": 4.2, "category": "Alkoholis, tabakas"}],
         "total": 5.7, "merchant": "Maxima"})
    assert r is not None
    assert len(r["items"]) == 2
    assert r["total"] == 5.7
    assert r["items"][0]["category"] == "Maisto prekės"
    assert r["merchant"] == "Maxima"

    # No merchant, or a genuinely blank one, is None — never an empty string
    # the UI would render as a blank-but-present header.
    r = _validate({"items": [{"name": "X", "price": 1, "category": "Kita"}],
                    "total": 1})
    assert r["merchant"] is None
    r = _validate({"items": [{"name": "X", "price": 1, "category": "Kita"}],
                    "total": 1, "merchant": "  "})
    assert r["merchant"] is None
    r = _validate({"items": [{"name": "X", "price": 1, "category": "Kita"}],
                    "total": 1, "merchant": 42})
    assert r["merchant"] is None

    # A category the model invented (not in our taxonomy) falls back to
    # "Kita" rather than being dropped or shipped as an unrecognised string
    # the client's picker/_catMetaFor can't resolve. Defence in depth — the
    # tool's JSON Schema `enum` should already rule this out at the API
    # level, but a stale/mismatched _CATEGORIES list must still degrade
    # safely rather than propagate an unknown string.
    r = _validate(
        {"items": [{"name": "X", "price": 3, "category": "Something made up"}],
         "total": 3})
    assert r["items"][0]["category"] == "Kita"

    # A missing/garbage total is recomputed from the item prices, not left
    # as whatever the model happened to say (or crashed on).
    r = _validate({"items": [{"name": "A", "price": 2, "category": "Kita"},
                              {"name": "B", "price": 3, "category": "Kita"}]})
    assert r["total"] == 5.0

    # A zero/negative price line is dropped, not passed through as a
    # negative split amount.
    r = _validate(
        {"items": [{"name": "A", "price": 0, "category": "Kita"},
                    {"name": "B", "price": -1, "category": "Kita"},
                    {"name": "C", "price": 2, "category": "Kita"}],
         "total": 2})
    assert len(r["items"]) == 1 and r["items"][0]["name"] == "C"

    # An empty name (the schema marks it required, but a defence-in-depth
    # check still exists) falls back to the category rather than shipping a
    # blank string the split screen would render as nothing at all.
    r = _validate({"items": [{"name": "", "price": 1, "category": "Kita"}],
                    "total": 1})
    assert r["items"][0]["name"] == "Kita"

    # No items at all -> None, not an empty-but-truthy result the client
    # would render as a valid (if pointless) split.
    assert _validate({"items": [], "total": 0}) is None
    assert _validate({}) is None
    assert _validate(None) is None
    assert _validate("not a dict") is None

    # _tool_input: only a matching tool_use block counts; plain text content,
    # a differently-named tool call, or a missing content list all yield
    # None rather than crashing scan()'s caller.
    good = {"content": [{"type": "tool_use", "name": _TOOL_NAME,
                          "input": {"items": [], "total": 0}}]}
    assert _tool_input(good) == {"items": [], "total": 0}
    text_only = {"content": [{"type": "text", "text": "sorry, I can't"}]}
    assert _tool_input(text_only) is None
    wrong_tool = {"content": [{"type": "tool_use", "name": "other_tool",
                               "input": {}}]}
    assert _tool_input(wrong_tool) is None
    assert _tool_input({}) is None

    # No API key / no image -> scan() short-circuits without a network call.
    assert scan("", "image/jpeg", "key") is None
    assert scan("abc", "image/jpeg", "") is None

    assert "Kita" in _CATEGORIES, "'Kita' must be a valid fallback category"

    print("test_receipt_scan: PASS")


if __name__ == "__main__":
    _run()
