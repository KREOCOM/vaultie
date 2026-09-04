"""Filling in the banks a scan couldn't read, from the phone's last-known copy.

A bank can go quiet at any moment — a rate limit, a timeout, a consent that
expired. The dashboard is rebuilt from whatever a scan managed to fetch, so
without a last-known copy a quiet bank doesn't degrade: it CEASES TO EXIST. Rent
and a loan drop out of the feed and out of the monthly commitment, and the person
looking at the screen is quietly told they don't have those payments. That is the
one outcome this module exists to make impossible.

The phone keeps the raw ``known`` block from each scan and hands it back with the
next one. Here it is used for exactly the banks that did NOT answer; the banks
that did answer are authoritative and are never touched, so the two sets are
disjoint by bank and there is nothing to reconcile.

Lives outside main.py so it can be tested without the Firebase runtime.
"""
import datetime as dt
import logging


def norm_iban(iban) -> str | None:
    """Uppercase, strip spaces — so own-account IBANs compare regardless of
    formatting."""
    if not iban:
        return None
    return str(iban).replace(" ", "").upper()


def bank_of(entry) -> str | None:
    """The bank an entry belongs to. Transactions are tagged ``_bank`` by the
    scan; account summaries carry ``bank``."""
    if not isinstance(entry, dict):
        return None
    return entry.get("_bank") or entry.get("bank")


def merge_known(all_txns: list, summaries: list, own_ibans: set, scan_diag: list,
                known: dict, months_back: int, *, today=None, fresh_from=None):
    """Return ``(txns, summaries, own_ibans, stale_banks)`` with history filled
    in from [known].

    Two jobs, and they used to be one:

    * **Quiet banks.** A bank that failed or wasn't asked is served entirely from
      the phone's copy, so rent doesn't vanish from the dashboard because one
      provider rate-limited us.
    * **Incremental sync** (when [fresh_from] is given). A bank that DID answer
      was asked only for the days since [fresh_from]; everything older comes from
      the phone. Re-downloading six months every half hour is the reason a
      refresh took most of a minute — a booked transaction is final and cannot
      change, so fetching it again buys nothing.

    Only BOOKED entries are reused: they are final at the bank, so they can't
    resurrect something that was later cancelled. Anything still pending comes
    from the fresh scan alone. Reused history is clipped to the window the caller
    asked for, so the cache can't quietly grow the dashboard's date range.
    """
    # The `known` block comes straight from the client; a malformed one (a string
    # or list instead of a dict) must be ignored, not crash the whole paid scan to
    # INTERNAL. Every other client field is already type-guarded; this closes the gap.
    if not isinstance(known, dict):
        known = {}
    k_txns = known.get("txns") or []
    k_accts = known.get("accounts") or []
    if not k_txns and not k_accts:
        return all_txns, summaries, own_ibans, []
    # A bank counts as having answered only if its scan carried no error. Banks
    # that weren't asked at all (not in scan_diag) are quiet too — that's what
    # lets a caller deliberately skip a bank and still show its data.
    answered = {d.get("bank") for d in scan_diag if not d.get("error")}
    # A bank that REFUSED us is not a quiet bank. When a consent expires or the
    # user withdraws it in their own bank, re-serving that bank from cache means
    # the app keeps showing data for an account the user has revoked access to —
    # which is the one thing withdrawing consent is supposed to stop. Treated
    # like an answer so nothing of theirs is reused.
    revoked = {d.get("bank") for d in scan_diag if d.get("revoked")}
    excluded = answered | revoked
    cutoff = ((today or dt.date.today())
              - dt.timedelta(days=months_back * 31)).isoformat()
    # An account that was just scanned fresh must NOT also be re-served from the
    # cache under an old, differently-labelled record — that is what left the
    # same physical account showing twice (once fresh "Revolut", once cached
    # "Bankas") after reconnect churn. Identity is the IBAN, not the label, so a
    # cached account whose IBAN was freshly scanned is dropped, and any cached
    # bank label that has no surviving account with it is dropped wholesale.
    fresh_ibans = {norm_iban(a.get("iban")) for a in summaries
                   if norm_iban(a.get("iban"))}
    kept_accts = [a for a in k_accts
                  if bank_of(a) not in excluded
                  and norm_iban(a.get("iban")) not in fresh_ibans]
    kept_banks = {bank_of(a) for a in kept_accts}
    kept_txns = [t for t in k_txns
                 if bank_of(t) not in excluded
                 and bank_of(t) in kept_banks
                 and t.get("status") == "BOOK"
                 and (t.get("booking_date") or "") >= cutoff]
    stale = sorted({b for b in (bank_of(a) for a in kept_accts) if b})

    # ── Incremental history for the banks that DID answer ────────────────────
    #
    # These are not stale: their recent data is fresh, only their older data was
    # not requested. So they are added to `kept_txns` but NOT to `stale`, or the
    # UI would mark a bank that just synced as "not updated".
    #
    # Revoked banks stay excluded. Serving their history from cache after the
    # user withdrew consent is exactly what withdrawing consent must stop.
    if fresh_from:
        seen = {t.get("entry_reference") for t in all_txns
                if t.get("entry_reference")}
        incremental = [
            t for t in k_txns
            if bank_of(t) in answered
            and bank_of(t) not in revoked
            and t.get("status") == "BOOK"
            # Strictly OLDER than the window we just fetched. Anything inside it
            # came from the bank a moment ago and is authoritative — reusing a
            # cached copy of the same day is how a transaction gets counted twice
            # when it was still pending in the cache and is booked now.
            and (t.get("booking_date") or "") < fresh_from
            and (t.get("booking_date") or "") >= cutoff
            # Belt and braces on top of the date rule: never re-add a reference
            # the fresh scan already returned.
            and (not t.get("entry_reference")
                 or t.get("entry_reference") not in seen)
        ]
        if incremental:
            logging.info("known: reusing %d older txns for answered banks %s",
                         len(incremental), sorted(answered))
            kept_txns = kept_txns + incremental
    if kept_txns or kept_accts:
        logging.info("known: reusing %d txns / %d accounts for quiet banks %s",
                     len(kept_txns), len(kept_accts), stale)
    # A quiet bank's IBANs are still the user's own — drop them and its transfers
    # to the other bank stop being recognised as own-account moves, which would
    # book them as real spending.
    ibans = set(own_ibans) | {norm_iban(a.get("iban")) for a in kept_accts
                              if norm_iban(a.get("iban"))}
    return all_txns + kept_txns, summaries + kept_accts, ibans, stale
