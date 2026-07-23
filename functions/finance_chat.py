"""AI finance chat — answers the user's questions about their OWN money.

Privacy-first, App-Store-shaped (like Bilancė's agent, which Apple/Google
approved): the phone sends a compact SUMMARY of the user's finances — category
totals, subscriptions, balances — never raw transactions, IBANs, or the names of
people they paid. Nothing is persisted server-side; the summary lives only in
the request. The Anthropic API does not train on API traffic, which is the point
to disclose to the user and to App Review.

Model: Haiku 4.5 (fast + cheap; this is Q&A over a short summary, not reasoning
over a corpus). Prompt caching keeps follow-up questions ~10× cheaper by reusing
the summary across a conversation.

Called over plain HTTPS (requests) — no new pip dependency, same as
ai_enrichment.
"""
import json
import logging
import time

import requests

_URL = "https://api.anthropic.com/v1/messages"
_MODEL = "claude-haiku-4-5-20251001"  # monthly-report summariser: fast + cheap
# The chat talks TO the user in Lithuanian, a heavily-inflected language where the
# smallest tier makes visible declension/agreement errors. Sonnet 5 writes fluent
# LT; thinking is disabled below to keep this Q&A snappy and cheap (no reasoning
# tokens). Prompt caching still applies to the summary.
_CHAT_MODEL = "claude-sonnet-5"
_TIMEOUT = 30

# Hard caps so a malformed or hostile client can't run up a bill or a huge call.
_MAX_SUMMARY_CHARS = 20_000
_MAX_TURNS = 24
_MAX_TURN_CHARS = 2_000
_MAX_REPLY_TOKENS = 700

# Static persona — cached across every user and conversation (identical bytes).
_SYSTEM = (
    "Tu esi „Vaultie“ asistentas — draugiškas, konkretus pagalbininkas, "
    "atsakantis į vartotojo klausimus apie JO PATIES asmeninius finansus. "
    "ATSAKYK TA PAČIA KALBA, KURIA PARAŠYTAS VARTOTOJO KLAUSIMAS — jei jis rašo "
    "angliškai, atsakyk angliškai; jei lietuviškai — lietuviškai. Niekada "
    "neperjunk kalbos savo nuožiūra. Rašyk TAISYKLINGA, sklandžia kalba — "
    "lietuviškai naudok teisingus linksnius, gimines ir derinimą, be vertalų. "
    "Rašyk trumpai ir aiškiai (2–5 sakiniai; sąrašai tik kai "
    "tikrai padeda). Sumas rašyk eurais.\n\n"
    "GRIEŽTOS TAISYKLĖS:\n"
    "1. Remkis TIK žemiau pateikta vartotojo finansų santrauka. Jei santraukoje "
    "duomenų nėra, sąžiningai pasakyk, kad tų duomenų nematai — NIEKADA "
    "neišgalvok skaičių, kategorijų ar sandorių.\n"
    "2. Tu NETEIKI investicinių ar teisinių patarimų. Gali paaiškinti vartotojo "
    "įpročius ir pasiūlyti bendrų taupymo idėjų, bet aiškiai pažymėk, kad tai "
    "nėra finansinė konsultacija, jei vartotojas prašo rekomendacijų.\n"
    "3. Nemoralizuok ir nesmerk išlaidų. Būk neutralus ir naudingas.\n"
    "4. Jei klausimas nesusijęs su vartotojo finansais, mandagiai grąžink prie "
    "temos.\n"
    "5. Rašyk paprastu tekstu. NENAUDOK Markdown formatavimo — jokių „**“, "
    "„#“ ar kitų simbolių paryškinimui."
)


# Summary-writing persona for the monthly review card. Same privacy contract as
# the chat: it only ever sees pre-aggregated figures the phone computed, never
# raw transactions or names.
_REPORT_SYSTEM = (
    "Tu esi „Vaultie“ asistentas. Parašyk TRUMPĄ, draugišką vieno mėnesio "
    "finansų santrauką pagal žemiau pateiktus skaičius. "
    "{lang_rule} "
    "3–5 sakiniai, šiltas bet neutralus tonas. Natūraliai paminėk pajamas, "
    "išlaidas, grynąjį rezultatą, didžiausią išlaidų kategoriją ir santaupų "
    "normą, jei tie skaičiai pateikti. Gali trumpai palyginti su praėjusiu "
    "mėnesiu, jei duomenų yra.\n\n"
    "GRIEŽTOS TAISYKLĖS:\n"
    "1. Remkis TIK pateiktais skaičiais — nieko neišgalvok (nei sumų, nei "
    "kategorijų, nei sandorių).\n"
    "2. Nemoralizuok ir nesmerk išlaidų — būk neutralus ir palaikantis.\n"
    "3. Neteik investicinių ar teisinių patarimų.\n"
    "4. Rašyk paprastu tekstu. NENAUDOK Markdown (jokių „**“, „#“ ar kitų "
    "formatavimo simbolių)."
)

# The one line that differs per language. Two variants means two cached system
# prompts, which is fine — far better than one that is always Lithuanian.
_REPORT_LANG_RULE = {
    "lt": "Rašyk lietuviškai.",
    "en": "Write the summary in English.",
}


def _report_system(lang: str) -> str:
    rule = _REPORT_LANG_RULE.get((lang or "lt").lower(), _REPORT_LANG_RULE["lt"])
    return _REPORT_SYSTEM.replace("{lang_rule}", rule)


def month_report(stats: str, api_key: str, lang: str = "lt") -> str:
    """Write a short narrative for a month's figures, in the app's language.

    Unlike the chat — where the reply can simply follow the language the
    question was asked in — nothing here is written by the user, so the UI
    locale has to be passed in. It used to be hard-coded Lithuanian, so an
    English user's monthly summary arrived in Lithuanian.

    ``stats`` is a compact, PII-free block of pre-computed numbers. Returns the
    narrative text, or "" on any failure so the client can fall back to its own
    templated summary (never raises)."""
    stats = (stats or "").strip()[:_MAX_SUMMARY_CHARS]
    if not stats:
        return ""
    payload = json.dumps({
        "model": _MODEL,
        "max_tokens": 400,
        "system": [{"type": "text", "text": _report_system(lang)}],
        "messages": [{"role": "user", "content": "Mėnesio skaičiai:\n\n" + stats}],
    })
    headers = {"x-api-key": api_key, "anthropic-version": "2023-06-01",
               "content-type": "application/json"}
    for attempt in range(3):
        try:
            r = requests.post(_URL, timeout=_TIMEOUT, headers=headers, data=payload)
        except Exception as e:  # noqa: BLE001
            logging.warning("month_report request failed: %s", e)
            time.sleep(0.8 * (attempt + 1))
            continue
        if r.status_code == 429:
            time.sleep(1.5 * (attempt + 1))
            continue
        if not r.ok:
            logging.warning("month_report http %s: %s", r.status_code, r.text[:200])
            break
        try:
            data = r.json()
            parts = [b.get("text", "") for b in data.get("content", [])
                     if b.get("type") == "text"]
            reply = "".join(parts).strip()
            if data.get("usage"):
                logging.info("month_report usage=%s", data["usage"])
            if reply:
                return reply
        except Exception as e:  # noqa: BLE001
            logging.warning("month_report parse failed: %s", e)
        break
    return ""


def _sanitize_history(raw):
    """Coerce the client's message list into a clean, bounded alternating chat."""
    out = []
    if not isinstance(raw, list):
        return out
    for m in raw[-_MAX_TURNS:]:
        if not isinstance(m, dict):
            continue
        role = m.get("role")
        text = m.get("text")
        if role not in ("user", "assistant") or not isinstance(text, str):
            continue
        text = text.strip()[:_MAX_TURN_CHARS]
        if not text:
            continue
        out.append({"role": role, "content": text})
    # The API needs the conversation to start with a user turn and end with one.
    while out and out[0]["role"] != "user":
        out.pop(0)
    if not out or out[-1]["role"] != "user":
        return []  # nothing to answer — caller returns a gentle prompt
    return out


def chat(summary: str, history, api_key: str) -> str:
    """Answer the latest user question given a finance summary + conversation.

    Returns the assistant's reply text, or a short Lithuanian fallback string on
    any failure (never raises — a chat hiccup must not crash the client)."""
    summary = (summary or "").strip()[:_MAX_SUMMARY_CHARS]
    turns = _sanitize_history(history)
    if not turns:
        return "Užduok klausimą apie savo finansus — pavyzdžiui „Kiek išleidau maistui?“"

    system = [
        {"type": "text", "text": _SYSTEM},
        # The summary is stable for the whole conversation, so cache it: the
        # first question pays for it once, every follow-up reads it ~10× cheaper.
        {"type": "text",
         "text": "VARTOTOJO FINANSŲ SANTRAUKA (tik skaitymui):\n\n" + summary,
         "cache_control": {"type": "ephemeral"}},
    ]
    payload = json.dumps({
        "model": _CHAT_MODEL,
        "max_tokens": _MAX_REPLY_TOKENS,
        # Simple Q&A over a short summary — no thinking needed. Sonnet 5 runs
        # adaptive thinking by default when omitted, so disable it explicitly to
        # keep replies fast and avoid billing reasoning tokens.
        "thinking": {"type": "disabled"},
        "system": system,
        "messages": turns,
    })
    headers = {"x-api-key": api_key, "anthropic-version": "2023-06-01",
               "content-type": "application/json"}

    for attempt in range(3):
        try:
            r = requests.post(_URL, timeout=_TIMEOUT, headers=headers, data=payload)
        except Exception as e:  # noqa: BLE001 — network/timeout, brief backoff
            logging.warning("finance_chat request failed: %s", e)
            time.sleep(0.8 * (attempt + 1))
            continue
        if r.status_code == 429:
            time.sleep(1.5 * (attempt + 1))
            continue
        if not r.ok:
            logging.warning("finance_chat http %s: %s", r.status_code, r.text[:200])
            break
        try:
            data = r.json()
            parts = [b.get("text", "") for b in data.get("content", [])
                     if b.get("type") == "text"]
            reply = "".join(parts).strip()
            if data.get("usage"):
                logging.info("finance_chat usage=%s", data["usage"])
            if reply:
                return reply
        except Exception as e:  # noqa: BLE001
            logging.warning("finance_chat parse failed: %s", e)
        break

    return "Atsiprašau, nepavyko atsakyti. Pabandyk dar kartą po akimirkos."
