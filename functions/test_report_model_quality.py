"""The monthly report must be written by a model that can actually write
Lithuanian, not one chosen for being fast and cheap.

A real report generated on Haiku 4.5 came back "Birželis buvo gan šalatanas
mėnuo" ("šalatanas" is not a Lithuanian word — nothing close to one exists)
and "Gaukos 2816 eurų" (not a real conjugation of "gauti"; should be "Gavai").
Found by the person actually using the app, in production, not in testing —
the report had been running on the smaller model since it was built, on the
reasoning that it's "just a summariser" (Q&A over a few numbers). That
reasoning was about REASONING difficulty; a monthly narrative is free-form
generative prose with nothing to copy from, which is a HARDER target for
fluent Lithuanian than the chat's shorter, more constrained answers — the
report needed the strong model more than chat did, not less.

This can't test generation quality itself without hitting the network (and
even Sonnet 5 isn't provably perfect on any single run) — what it CAN pin,
cheaply and deterministically, is that the report is no longer configured to
run on the tier that produced the actual observed failure, and that the
prompt explicitly forbids inventing words as a second line of defence.

Run:  ./venv/bin/python test_report_model_quality.py
"""
import os
import sys

sys.path.insert(0, os.path.dirname(__file__))
from finance_chat import _MODEL, _CHAT_MODEL, _report_system  # noqa: E402


def _run():
    # The exact regression: the report ran on Haiku while chat ran on Sonnet.
    assert _MODEL != "claude-haiku-4-5-20251001", \
        "month_report is back on the tier that produced 'šalatanas' / 'Gaukos'"
    assert _MODEL == _CHAT_MODEL, \
        "report and chat should use the same (strong) model for LT fluency"
    assert "sonnet" in _MODEL.lower(), f"expected a Sonnet-tier model, got {_MODEL!r}"

    # Belt-and-braces: the prompt itself forbids inventing words, in both
    # language variants (the rule is phrased in Lithuanian — it's an
    # instruction TO the model — but applies regardless of the target
    # language, since {lang_rule} only swaps which language it writes in).
    for lang in ("lt", "en"):
        sys_prompt = _report_system(lang)
        assert "neišgalvok žodž" in sys_prompt, \
            f"({lang}) missing the no-invented-words rule"
        assert "{lang_rule}" not in sys_prompt, \
            f"({lang}) lang rule placeholder not substituted"

    print("test_report_model_quality: PASS")


if __name__ == "__main__":
    _run()
