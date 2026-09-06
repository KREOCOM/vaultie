"""Stage 1 — Canonical transaction identity.

Derives a STABLE counterparty identity from the strongest structured signal the
provider already gives us, BEFORE any merchant/brand resolution. Recurring
detection groups by ``identity_key``, so a repeated payment is detectable even
when the merchant is unknown to the KB — the cold-start / unseen-country case.

Deterministic priority:
  1. counterparty IBAN  (creditor_account for DBIT / debtor_account for CRDT)  EXACT
  2. counterparty scheme id  (SEPA CID / mandate — only if the provider gives it) HIGH
  3. counterparty name  (creditor.name / debtor.name — structured, verbatim)      HIGH
  4. remittance evidence  (parsed acceptor / domain)                              MEDIUM
  else                                                                            NONE

The user's OWN account IBAN is never used as counterparty identity. Mapping an
identity to a canonical merchant/brand is a SEPARATE stage (resolver/kb); this
module never touches the KB and never merges name with remittance.
"""

import re
import unicodedata

from entity import (BANK_FEE, PURCHASE, TRANSFER_IN, TRANSFER_OUT, UNKNOWN_TYPE,
                    _amount, _creditor, _date, _debtor, _looks_like_person,
                    classify_type,
                    parse_remittance)

# transaction types (structured, code-gated)
CARD = "CARD"
TYPE_TRANSFER_OUT = "TRANSFER_OUT"
TYPE_TRANSFER_IN = "TRANSFER_IN"
FEE = "FEE"
UNKNOWN_T = "UNKNOWN"

# identity sources / confidences
S_IBAN = "IBAN"
S_SCHEME = "SCHEME_ID"
S_NAME = "NAME"
S_REMIT = "REMITTANCE"
S_NONE = "NONE"
C_EXACT = "EXACT"
C_HIGH = "HIGH"
C_MEDIUM = "MEDIUM"
C_NONE = "NONE"

_TYPE_MAP = {PURCHASE: CARD, TRANSFER_OUT: TYPE_TRANSFER_OUT,
             TRANSFER_IN: TYPE_TRANSFER_IN, BANK_FEE: FEE, UNKNOWN_TYPE: UNKNOWN_T}

_SPECIAL = {"ø": "o", "œ": "oe", "æ": "ae", "ß": "ss", "đ": "d", "ł": "l",
            "þ": "th", "ð": "d"}


def _norm(s):
    s = (s or "").lower()
    for k, v in _SPECIAL.items():
        s = s.replace(k, v)
    s = unicodedata.normalize("NFKD", s)
    s = "".join(c for c in s if not unicodedata.combining(c))
    return re.sub(r"[^a-z0-9]+", "", s)


def _acct_iban(t, key):
    a = t.get(key)
    return a.get("iban") if isinstance(a, dict) and a.get("iban") else None


def _scheme_id(party):
    """SEPA creditor scheme identifier / organisation id — supported if the
    provider supplies it. Enable Banking/SEB currently does not; never fabricated."""
    if not isinstance(party, dict):
        return None
    org = party.get("organisation_id") or party.get("organization_id")
    if isinstance(org, dict):
        return org.get("scheme_identification") or org.get("identification")
    return party.get("scheme_identification") or None


# A registrable web domain anywhere in a merchant signal — the STABLE identity of
# an online / processor-routed payment (Plaid-style Named Entity Linking anchor).
_DOMAIN_TOK = re.compile(
    r"\b((?:[a-z0-9][a-z0-9-]*\.)+"
    r"(?:com|lt|net|io|app|eu|co|org|shop|store|de|fr|es|it|pl|lv|ee|fi|se|no|dk|nl|ie|uk))\b",
    re.I)


def _strip_star(name):
    """The real merchant behind a card-processor '*' prefix. The convention is
    PROCESSOR*MERCHANT ("SumUp *Cafe Sol", "Pronas*Skani Mesa", "PTL*Vr.fi",
    "Delfiplius* Uab Delfi") — the merchant is everything after the first '*'. So
    two different processors fronting one merchant collapse to the same identity,
    for any processor, any country. Returns the name unchanged when there is no '*'
    or nothing usable after it."""
    if name and "*" in name:
        after = name.split("*", 1)[1].strip()
        if len(after) >= 2:
            return after
    return name


def _domain_of(pr, *extra):
    """A clean registrable domain from ANY merchant signal — the website line
    ("Mokėjimas tinklalapyje gymplius.lt"), a leading domain ("APPLE.COM/BILL"),
    a card acceptor ("www.savasld.lt/ VILNIUS/LTU"), or any ``extra`` text passed
    (counterparty name, raw remittance) — else None. Strips 'www.'.

    This is the GLOBAL identity rule: the domain names the real merchant regardless
    of which processor (OPAY, Paysera…) or which display-name variant the bank
    happened to send, so every descriptor form of one merchant collapses to one
    identity — for any merchant, any country."""
    for cand in (pr.get("web_merchant"), pr.get("domain_merchant"),
                 pr.get("card_merchant"), *extra):
        if not cand:
            continue
        m = _DOMAIN_TOK.search(str(cand))
        if m:
            d = m.group(1).lower()
            return d[4:] if d.startswith("www.") else d
    return None


def build_canonical(t):
    """Return the canonical identity model for one raw provider transaction."""
    direction = t.get("credit_debit_indicator")
    ttype, ttype_ev = classify_type(t)          # code-gated; text only if no code
    txn_type = _TYPE_MAP.get(ttype, UNKNOWN_T)

    if direction == "CRDT":                     # incoming: counterparty is the debtor
        cp_party = t.get("debtor")
        cp_name = _debtor(t)
        cp_iban = _acct_iban(t, "debtor_account")
        own_iban = _acct_iban(t, "creditor_account")
    else:                                       # DBIT: counterparty is the creditor
        cp_party = t.get("creditor")
        cp_name = _creditor(t)
        cp_iban = _acct_iban(t, "creditor_account")
        own_iban = _acct_iban(t, "debtor_account")
    if cp_iban and cp_iban == own_iban:         # never identify by our own account
        cp_iban = None
    cp_scheme = _scheme_id(cp_party)

    pr = parse_remittance(t)
    lines = t.get("remittance_information") or []
    acceptor = pr.get("card_merchant")
    domain = pr.get("domain_merchant") or pr.get("web_merchant")
    cp_name = _strip_star(cp_name)   # "SumUp *Cafe Sol" → "Cafe Sol"
    # clean registrable domain from any signal — incl. the star-stripped name and
    # the raw remittance (so "PTL*Vr.fi korttimaksu" → vr.fi).
    _rmt_text = " ".join(str(x) for x in lines)
    web_domain = _domain_of(pr, cp_name, _rmt_text)

    # GLOBAL RULE — Named Entity Linking anchor: a website domain in the descriptor
    # IS the merchant, ahead of a processor's IBAN and ahead of a variant name. This
    # is what collapses "gymplius.lt via OPAY" (whose counterparty is OPAY's IBAN)
    # and every display-name variant to ONE merchant. A DIRECT SEPA payment with no
    # domain in the memo (rent to a real recipient) carries no web_domain, so it
    # keeps its IBAN identity untouched.
    if web_domain:
        key, src, conf = "dom:" + web_domain, S_REMIT, C_HIGH
    elif cp_iban:
        key, src, conf = "iban:" + _norm(cp_iban), S_IBAN, C_EXACT
    elif cp_scheme:
        key, src, conf = "cid:" + _norm(cp_scheme), S_SCHEME, C_HIGH
    elif cp_name and _norm(cp_name):
        key, src, conf = "name:" + _norm(cp_name), S_NAME, C_HIGH
    elif domain or acceptor:
        key, src, conf = "rmt:" + _norm(domain or acceptor), S_REMIT, C_MEDIUM
    else:
        key, src, conf = None, S_NONE, C_NONE

    return {
        "direction": direction,
        "transaction_type": txn_type,
        "type_evidence": ttype_ev,
        "counterparty": {
            "iban": cp_iban, "name": cp_name, "scheme_id": cp_scheme,
            # WEAK structural hint (NOT ground truth — the heuristic over-triggers
            # on some institutions, e.g. VMI). Used only to keep an unknown-brand
            # counterparty out of subscription/bill purely from a stable IBAN +
            # recurrence; never to assert a person identity.
            "party_kind_hint": ("person_like"
                                if cp_name and _looks_like_person(cp_name) else None),
        },
        "remittance": {
            "lines": list(lines), "acceptor": acceptor,
            "city": pr.get("city_hint"), "country": pr.get("country_hint"),
            "domain": domain, "processor": None,
        },
        "amount": _amount(t),
        "currency": (t.get("transaction_amount") or {}).get("currency"),
        "booking_date": _date(t),
        "references": {"entry_reference": t.get("entry_reference"),
                       "reference_number": t.get("reference_number")},
        "identity_key": key,
        "identity_source": src,
        "identity_confidence": conf,
    }
