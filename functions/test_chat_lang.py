"""The AI finance chat must answer in the APP's language, not one it guesses.

Regression for the on-device bug: app in English, question asked in English, but
the reply came back in Lithuanian because the finance summary (merchant names,
categories) is Lithuanian and the model inferred LT. The fix threads the app's
`lang` into chat() and states the reply language explicitly in the system prompt
(mirroring month_report/_report_system). This test locks that wiring in without
hitting the network.
"""
from finance_chat import _chat_system, _FALLBACK_ASK, chat


def _run():
    # The system prompt must carry an explicit, per-language reply instruction —
    # NOT the old "detect from the question" wording that let LT data win.
    en_sys = _chat_system("en")
    assert "respond in english" in en_sys.lower(), \
        "English system prompt missing an explicit English reply rule"
    assert "{lang_rule}" not in en_sys, "lang rule placeholder not substituted"

    lt_sys = _chat_system("lt")
    assert "lietuvi" in lt_sys.lower(), "Lithuanian system prompt missing LT rule"

    # The two variants must actually differ (otherwise language isn't threaded).
    assert en_sys != lt_sys, "system prompt identical across languages"

    # Unknown / missing language falls back to Lithuanian, never crashes.
    assert _chat_system("") == lt_sys
    assert _chat_system("de") == lt_sys  # unsupported → LT default
    assert _chat_system(None) == lt_sys

    # The empty-question fallback is localised (no API call on empty history).
    assert chat("some summary", [], api_key="", lang="en") == _FALLBACK_ASK["en"]
    assert chat("some summary", [], api_key="", lang="lt") == _FALLBACK_ASK["lt"]
    assert "food" in _FALLBACK_ASK["en"].lower(), "EN fallback not in English"

    print("test_chat_lang: PASS")


if __name__ == "__main__":
    _run()
