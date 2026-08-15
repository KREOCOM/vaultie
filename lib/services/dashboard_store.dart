import 'dart:convert';

import 'package:hive_flutter/hive_flutter.dart';

import '../main.dart';

/// Persists the latest bank-scan dashboard payload on-device (Hive) so the app
/// opens straight into the dashboard instead of forcing a re-connect every time.
///
/// Multi-bank: [_kBanks] holds one record per connected bank (its Enable Banking
/// session id + account uids/IBANs), so all banks can be re-fetched and merged
/// into ONE combined dashboard (see refresh_dashboard). [_kDash] holds that
/// combined payload for instant open.
///
/// Local only — nothing leaves the phone, same privacy model as the scan itself.
/// Scoped per account via [ensureLocalDataForCurrentUser] (the box is wiped when
/// a different user signs in).
class DashboardStore {
  static const _kDash = 'dash';
  static const _kSyncedAt = 'syncedAt';
  static const _kBank = 'bank';
  static const _kBanks = 'banks';
  static const _kKnown = 'knownScan';

  static Box get _box => Hive.box(HiveBoxes.dashboard);

  // ── Last-known raw scan (the safety net) ────────────────────────────────
  // A bank can go quiet at any moment — a rate limit, a timeout, a consent that
  // expired. The backend rebuilds the whole dashboard from whatever it managed
  // to fetch, so without a copy of the last good raw data, a quiet bank means
  // its rent and its loan simply cease to exist on screen. This is that copy:
  // the phone hands it back with every scan, and the backend uses it ONLY for
  // banks that didn't answer. It's what makes a bank's payments disappearing
  // impossible rather than merely unlikely.
  //
  // Kept raw (not the built dashboard) because only the backend's engine can
  // turn transactions into a dashboard — and keeping the merge logic in exactly
  // one place is what stops the two from ever disagreeing.

  /// Same tolerance for values read out of a decoded payload rather than the box.
  /// The bank decides these shapes, not us, so a field arriving as a number
  /// instead of a string must not take a screen down.
  static String? _asStr(Object? v) => v is String ? v : null;

  /// Reads [key] as a String, tolerating a value of any other type.
  ///
  /// These reads were plain `as String?` casts sitting OUTSIDE the try blocks
  /// that follow them, so the guard never saw them: a value written by an older
  /// build, or half-written by a crash, threw on the cast itself. `load()` runs
  /// on the launch path, which turned a stale record into a crash with nothing
  /// on screen behind it.
  static String? _str(dynamic key) {
    final v = _box.get(key);
    return v is String ? v : null;
  }

  /// The last-known raw scan to hand back to the backend ({txns, accounts}).
  static Map<String, dynamic> knownScan() {
    final raw = _str(_kKnown);
    if (raw == null) return const {};
    try {
      return (jsonDecode(raw) as Map).cast<String, dynamic>();
    } catch (_) {
      return const {};
    }
  }

  /// Merge a scan's `known` block into the cache, PER BANK.
  ///
  /// A connect scan only ever covers the bank being connected, so replacing the
  /// cache wholesale would drop every other bank out of it — and the next time
  /// one of those went quiet there would be nothing to fall back on. Only the
  /// banks present in [known] are replaced; the rest are left exactly as they
  /// were.
  static Future<void> mergeKnown(Map<String, dynamic>? known) async {
    if (known == null) return;
    final txns = (known['txns'] as List?) ?? const [];
    final accounts = (known['accounts'] as List?) ?? const [];
    if (txns.isEmpty && accounts.isEmpty) return;
    String? bankOf(dynamic e) =>
        e is Map ? _asStr(e['_bank'] ?? e['bank']) : null;
    final fresh = {...txns.map(bankOf), ...accounts.map(bankOf)}..remove(null);
    // A bank replaces its cached TRANSACTIONS only if it actually returned some.
    //
    // A provider hiccup that answers "here are your accounts, and no
    // transactions" is indistinguishable from a real answer, and replacing on
    // that emptied the phone's only copy of the user's history — the copy that
    // exists precisely so a bad scan cannot make their rent disappear. Banks do
    // not spontaneously forget a year of transactions; a scan that returns none
    // for a bank that had hundreds is a failure wearing a success's clothes.
    final freshTxnBanks = {...txns.map(bankOf)}..remove(null);
    final old = knownScan();
    final keptTxns = ((old['txns'] as List?) ?? const [])
        .where((t) => !freshTxnBanks.contains(bankOf(t)));
    final keptAccounts = ((old['accounts'] as List?) ?? const [])
        .where((a) => !fresh.contains(bankOf(a)));
    await _box.put(
        _kKnown,
        jsonEncode({
          'txns': [...txns, ...keptTxns],
          'accounts': [...accounts, ...keptAccounts],
        }));
  }

  /// Save the dashboard payload from a scan (overwrites the previous).
  ///
  /// The "last synced" clock is advanced only when at least one bank returned
  /// FRESH data. When every bank in the payload was served from the last-known
  /// cache (a total rate-limit or Enable Banking outage — see `staleBanks`),
  /// nothing actually synced: bumping the clock would make frozen data read as
  /// "just updated" and would stall the retry throttle on data that never
  /// refreshed. The dashboard blob is still saved (it may differ after the merge)
  /// so the cached-through banks and any per-bank "not updated" flag persist.
  static Future<void> save(Map<String, dynamic> dash, {String? bank}) async {
    await _box.put(_kDash, jsonEncode(dash));
    if (!isFullyStale(dash)) {
      await _box.put(_kSyncedAt, DateTime.now().toIso8601String());
    }
    if (bank != null && bank.isNotEmpty) await _box.put(_kBank, bank);
  }

  /// True when every bank represented in [dash] was served from cache this scan
  /// (its label is in `balance.staleBanks`) — i.e. not one bank came back fresh.
  /// False when there are no stale banks, or at least one bank answered. Pure
  /// (no Hive) so [save]'s "advance the sync clock?" decision is unit-testable.
  static bool isFullyStale(Map<String, dynamic> dash) {
    final bal = dash['balance'];
    if (bal is! Map) return false;
    final stale = ((bal['staleBanks'] as List?) ?? const [])
        .map((e) => e.toString().toLowerCase().trim())
        .where((s) => s.isNotEmpty)
        .toSet();
    if (stale.isEmpty) return false;
    final banks = ((bal['accounts'] as List?) ?? const [])
        .whereType<Map>()
        .map((a) => _asStr(a['bank'])?.toLowerCase().trim())
        .whereType<String>()
        .where((s) => s.isNotEmpty)
        .toSet();
    if (banks.isEmpty) return false;
    return banks.difference(stale).isEmpty;
  }

  /// The saved dashboard payload, or null if there isn't one (or it's corrupt).
  static Map<String, dynamic>? load() {
    final raw = _str(_kDash);
    if (raw == null) return null;
    try {
      return jsonDecode(raw) as Map<String, dynamic>;
    } catch (_) {
      return null;
    }
  }

  /// Overwrite just the dashboard payload, keeping the existing sync time/bank
  /// label (used when the user edits data locally, e.g. a manual transaction —
  /// the bank wasn't re-synced, so [syncedAt] must not move).
  static Future<void> persist(Map<String, dynamic> dash) =>
      _box.put(_kDash, jsonEncode(dash));

  static bool get hasData => _box.get(_kDash) != null;

  /// When the saved dashboard was last synced (for a "last updated" label).
  static DateTime? get syncedAt {
    final s = _str(_kSyncedAt);
    return s == null ? null : DateTime.tryParse(s);
  }

  /// When a FULL (non-incremental) scan last ran.
  ///
  /// Refreshes normally ask the bank only for recent days and reuse the phone's
  /// history, which is right for everyday use and blind to one thing: a bank
  /// posting a transaction dated weeks back. A periodic full scan is what
  /// notices that. Null means "never" — the next refresh runs full.
  static const _kFullScanAt = 'fullScanAt';
  static DateTime? get fullScanAt {
    final s = _str(_kFullScanAt);
    return s == null ? null : DateTime.tryParse(s);
  }

  static Future<void> markFullScan() async {
    try {
      await _box.put(_kFullScanAt, DateTime.now().toIso8601String());
    } catch (_) {/* a missed stamp only means one extra full scan */}
  }

  // ── Bank consent lifetime ────────────────────────────────────────────────
  // PSD2 access is granted for 90 days (enable_banking.py: valid_days=90) and
  // then the bank simply stops answering: the figures quietly stop moving and
  // nothing says why. The user is warned before that happens.
  //
  // The date comes from the BANK, relayed by finish_bank_auth as
  // `connection.validUntil` (see _consent_valid_until) — some banks grant less
  // than the 90 days we ask for, and assuming 90 would warn after access had
  // already died. Kept per bank, because they expire on their own schedules.
  static const _kConsentAt = 'consentUntilByBank';

  static Future<void> markConsentGranted(String bank, String? validUntil) async {
    if (validUntil == null || validUntil.isEmpty) return;
    try {
      final raw = _box.get(_kConsentAt) as String?;
      final m = raw == null
          ? <String, dynamic>{}
          : (jsonDecode(raw) as Map).cast<String, dynamic>();
      m[bank] = validUntil;
      await _box.put(_kConsentAt, jsonEncode(m));
    } catch (_) {/* only costs the expiry warning */}
  }

  /// When the FIRST live bank consent lapses, or null if none is known.
  ///
  /// The earliest, not the latest: that is the one that fails first, and the
  /// user needs telling before their data stops moving — not after two of three
  /// banks have already gone quiet. Banks no longer connected are ignored, so a
  /// disconnected bank cannot keep raising an alarm about access nobody has.
  static DateTime? get consentExpiry {
    try {
      final live = connections()
          .map((c) => (c['bank'] as String?) ?? '')
          .where((b) => b.isNotEmpty)
          .toSet();
      if (live.isEmpty) return null;
      final raw = _box.get(_kConsentAt) as String?;
      if (raw == null) return null;
      final m = (jsonDecode(raw) as Map).cast<String, dynamic>();
      final dates = m.entries
          .where((e) => live.contains(e.key))
          .map((e) => DateTime.tryParse('${e.value}'))
          .whereType<DateTime>()
          .toList()
        ..sort();
      return dates.isEmpty ? null : dates.first;
    } catch (_) {
      return null;
    }
  }

  // ── Revoked strikes ──────────────────────────────────────────────────────
  // A bank answering 401/403 usually means the consent is gone — but not always.
  // A token refresh mid-flight, a bank-side hiccup, a header the ASPSP wanted on
  // that one call: all arrive as 401. Removing the connection on the first one
  // destroys a working setup over a blip, and the user has to walk the whole
  // consent flow again to undo it.
  //
  // So a bank has to refuse us TWICE in a row. One strike shows a warning and
  // changes nothing; a successful scan clears it.
  static const _kRevokedStrikes = 'revokedStrikes';

  static Map<String, int> _strikes() {
    final raw = _str(_kRevokedStrikes);
    if (raw == null) return {};
    try {
      return (jsonDecode(raw) as Map)
          .map((k, v) => MapEntry(k.toString(), (v as num).toInt()));
    } catch (_) {
      return {};
    }
  }

  static Future<void> _putStrikes(Map<String, int> m) async {
    try {
      await _box.put(_kRevokedStrikes, jsonEncode(m));
    } catch (_) {/* a lost strike only costs one extra warning */}
  }

  /// Records a refusal and returns how many in a row this bank has now had.
  static Future<int> bumpRevokedStrike(String bank) async {
    final k = bank.trim().toLowerCase();
    if (k.isEmpty) return 0;
    final m = _strikes();
    final n = (m[k] ?? 0) + 1;
    m[k] = n;
    await _putStrikes(m);
    return n;
  }

  /// Called for every bank that answered — a good scan wipes its history of
  /// refusals, so two strikes must be CONSECUTIVE.
  static Future<void> clearRevokedStrike(String bank) async {
    final k = bank.trim().toLowerCase();
    final m = _strikes();
    if (m.remove(k) != null) await _putStrikes(m);
  }

  static String? get bank => _str(_kBank);

  // ── Multi-bank connections ──────────────────────────────────────────────

  /// Record (or replace) a connected bank's accounts so they can be re-fetched
  /// and merged later, WITHOUT another login. Keyed by the connection's ACCOUNT
  /// IBANs — reconnecting the SAME account (fresh session id, same IBANs)
  /// replaces its record, while a DIFFERENT account at the same bank (e.g. a
  /// spouse's Revolut) has disjoint IBANs and is KEPT, so two "Revolut" records
  /// can coexist. [accounts] items carry {uid, iban, name, currency}.
  static Future<void> addConnection({
    required String bank,
    String? sessionId,
    required List<Map<String, dynamic>> accounts,
  }) async {
    // Account identity = IBAN + CURRENCY. Revolut multi-currency wallets (EUR +
    // NOK) SHARE one IBAN but are different accounts — keying on IBAN alone made
    // connecting the NOK wallet REPLACE and wipe the EUR wallet (and its balance).
    Set<String> keysOf(List? accts) => ((accts ?? const [])
            .map((a) {
              final m = a as Map;
              final iban =
                  _asStr(m['iban'])?.replaceAll(' ', '').toUpperCase() ?? '';
              if (iban.isEmpty) return '';
              final cur = (m['currency'] as String?)?.toUpperCase() ?? '';
              return '$iban|$cur';
            })
            .where((s) => s.isNotEmpty)
            .toSet());
    final newKeys = keysOf(accounts);
    // Spread into a fresh GROWABLE list — connections() can return an empty
    // const list on the first connect, and add()/removeWhere() on a const list
    // throws (silently aborting the very first bank, so the list never grows).
    final list = [...connections()]
      ..removeWhere((c) {
        final old = keysOf(c['accounts'] as List?);
        // Replace only when this is the SAME account (IBAN+currency overlap).
        // When neither side exposes an IBAN there is nothing to tell them apart,
        // so fall back to the old bank-name replacement to avoid duplicates.
        if (old.isEmpty && newKeys.isEmpty) {
          return _asStr(c['bank']) == bank;
        }
        return old.intersection(newKeys).isNotEmpty;
      });
    list.add({
      'bank': bank,
      'sessionId': sessionId,
      'accounts': accounts,
      'connectedAt': DateTime.now().toIso8601String(),
    });
    await _box.put(_kBanks, jsonEncode(list));
  }

  /// Every connected bank's stored record. Always a growable list.
  static List<Map<String, dynamic>> connections() {
    final raw = _box.get(_kBanks) as String?;
    if (raw == null) return <Map<String, dynamic>>[];
    try {
      return (jsonDecode(raw) as List)
          .map((e) => (e as Map).cast<String, dynamic>())
          .toList();
    } catch (_) {
      return <Map<String, dynamic>>[];
    }
  }

  /// Flat list of every connected account across all banks, shaped for
  /// refresh_dashboard: {uid, bank, iban, name, currency}.
  static List<Map<String, dynamic>> accountRefs() {
    final out = <Map<String, dynamic>>[];
    // One ref per physical account (by IBAN). Reconnecting a bank mints a new
    // Enable Banking session with new account UIDs for the SAME accounts, so a
    // few reconnects leave several sessions all pointing at one account — each
    // would otherwise be scanned and shown as a separate balance. The IBAN is
    // the stable identity; the newest connection's UID for it wins (connections
    // are appended, so the last one is freshest). Refs without an IBAN are all
    // kept — nothing to dedupe them by.
    final seenIban = <String>{};
    final seenNoIban = <String>{};
    for (final c in connections().reversed) {
      final bank = c['bank'];
      for (final a in ((c['accounts'] as List?) ?? const [])) {
        final m = (a as Map).cast<String, dynamic>();
        final iban = (m['iban'] as String?)?.replaceAll(' ', '').toUpperCase();
        if (iban != null && iban.isNotEmpty) {
          // IBAN + CURRENCY: Revolut EUR and NOK wallets share one IBAN but are
          // distinct accounts — dedupe on IBAN alone would drop one wallet.
          final cur = (m['currency'] as String?)?.toUpperCase() ?? '';
          if (!seenIban.add('$iban|$cur')) continue;
        } else {
          // No IBAN to dedupe by (some banks send none). A reconnect mints a
          // fresh session UID for the same physical account, so keying on UID
          // lets it accumulate and DOUBLE-COUNT its balance. Fall back to a
          // stable identity: bank + account name + currency.
          final key =
              '$bank|${m['name'] ?? ''}|${m['currency'] ?? ''}'.toUpperCase();
          if (!seenNoIban.add(key)) continue;
        }
        out.add({...m, 'bank': bank});
      }
    }
    return out;
  }

  static Future<void> removeConnection(String bank) async {
    final list = [...connections()]
      ..removeWhere((c) => (c['bank'] as String?) == bank);
    await _box.put(_kBanks, jsonEncode(list));
    await reconcileKnown();
  }

  /// Drop cached (`known`) data for banks that no longer have a connection.
  /// The known cache is handed back to the backend on every scan and re-served
  /// for any bank that didn't answer — including one the user just removed, which
  /// isn't scanned at all, so it counts as "quiet" and its rent/loan would
  /// resurrect on the dashboard. Pruning it to the still-connected banks closes
  /// that (M2). Called after every connection removal.
  static Future<void> reconcileKnown() async {
    final known = knownScan();
    if (known.isEmpty) return;
    final connected = connections()
        .map((c) => c['bank'] as String?)
        .whereType<String>()
        .toSet();
    try {
      await _box.put(_kKnown, jsonEncode(prunedKnown(known, connected)));
    } catch (_) {/* no box (preview) */}
  }

  /// Pure: keep only the cached txns/accounts whose bank is still [connected].
  /// Separated from Hive so the resurrection guard is unit-testable.
  static Map<String, dynamic> prunedKnown(
      Map<String, dynamic> known, Set<String> connected) {
    String? bankOf(dynamic e) =>
        e is Map ? _asStr(e['_bank'] ?? e['bank']) : null;
    return {
      'txns': ((known['txns'] as List?) ?? const [])
          .where((t) => connected.contains(bankOf(t)))
          .toList(),
      'accounts': ((known['accounts'] as List?) ?? const [])
          .where((a) => connected.contains(bankOf(a)))
          .toList(),
    };
  }

  /// Remove ONLY the specified revoked accounts (keys of `IBAN|CURRENCY`), not
  /// every same-named bank. A connection keeps its surviving accounts; a
  /// connection whose accounts are all revoked is dropped. This preserves a
  /// still-valid Revolut EUR wallet when its NOK sibling's consent is revoked
  /// (they share one IBAN, so removing by bank name would wipe both).
  static Future<void> removeRevokedAccounts(Set<String> revokedKeys) async {
    String keyOf(Map a) {
      final iban = (a['iban'] as String?)?.replaceAll(' ', '').toUpperCase() ?? '';
      if (iban.isEmpty) return '';
      final cur = (a['currency'] as String?)?.toUpperCase() ?? '';
      return '$iban|$cur';
    }

    final out = <Map<String, dynamic>>[];
    for (final c in connections()) {
      final accts = (((c['accounts'] as List?) ?? const [])
          .map((e) => (e as Map).cast<String, dynamic>())
          .toList());
      final kept =
          accts.where((a) => !revokedKeys.contains(keyOf(a))).toList();
      if (kept.isEmpty) continue; // every account revoked → drop the connection
      out.add({...c, 'accounts': kept});
    }
    await _box.put(_kBanks, jsonEncode(out));
    await reconcileKnown();
  }

  /// Number of connected banks (0 before any connection).
  static int get bankCount => connections().length;

  /// Forgets every bank connection and the data derived from it, so the user can
  /// reconnect from a clean slate. Leaves manual assets, settings and the
  /// account itself untouched — this is a bank reset, not a wipe.
  static Future<void> disconnectAllBanks() async {
    try {
      await _box.delete(_kBanks);
      await _box.delete(_kBank);
      await _box.delete(_kDash);
      await _box.delete(_kKnown);
      await _box.delete(_kSyncedAt);
      await _box.delete(_kPendingBank);
    } catch (_) {/* no box (preview) */}
  }

  // ── Recurring lifecycle overrides (Monarch/Copilot-style) ────────────────
  // The backend classifies each recurring stream active/ended, but the user is
  // the final authority. These sets (keyed by the stream's lowercased name) let
  // them force a stream OUT of the monthly commitment ("not recurring" / "I
  // stopped paying") or back IN ("still active"), overriding the heuristic.
  static const _kRecExcluded = 'recExcluded';
  static const _kRecIncluded = 'recIncluded';

  static Set<String> _loadSet(String key) {
    try {
      final raw = _box.get(key) as String?;
      if (raw == null) return <String>{};
      return (jsonDecode(raw) as List).map((e) => e as String).toSet();
    } catch (_) {
      // No Hive box (e.g. the standalone preview) → no overrides.
      return <String>{};
    }
  }

  /// Stream ids (sid) the user marked "not recurring / ended" — dropped from the
  /// total. Keyed by sid, NOT name: two streams of the same merchant at different
  /// prices (iCloud €2.99 + Apple One €19.95) share a name but have distinct sids,
  /// so a name key toggled BOTH off at once.
  static Set<String> recurringExcluded() => _loadSet(_kRecExcluded);

  /// Stream ids (sid) the user marked "still active" — kept in the total even if
  /// the heuristic thinks the stream ended.
  static Set<String> recurringIncluded() => _loadSet(_kRecIncluded);

  /// Set the user's verdict for ONE stream. [counted] true → force-include;
  /// false → force-exclude; null → clear (back to the heuristic).
  ///
  /// [alsoClear] must list every OTHER key the same stream may already be stored
  /// under — its old positional sid, its bare lowercase name. Readers accept all
  /// of those forms, so clearing only [key] left a stale "excluded" entry that
  /// won every lookup: the SEB row could not be switched back on, because each
  /// tap wrote include under the new key while the old sid kept excluding it, and
  /// the toggle simply appeared dead.
  static Future<void> setRecurringOverride(String key, bool? counted,
      {Iterable<String> alsoClear = const []}) async {
    final k = key.trim();
    final stale = [k, ...alsoClear.map((s) => s.trim())].where((s) => s.isNotEmpty);
    final excl = recurringExcluded()..removeAll(stale);
    final incl = recurringIncluded()..removeAll(stale);
    if (counted == false) excl.add(k);
    if (counted == true) incl.add(k);
    try {
      await _box.put(_kRecExcluded, jsonEncode(excl.toList()));
      await _box.put(_kRecIncluded, jsonEncode(incl.toList()));
    } catch (_) {
      // No Hive box (standalone preview) → override is in-memory only.
    }
  }

  // ── Recurring review queue (uncertain streams the user has acted on) ──────
  // A stream the backend flagged needsReview (unknown merchant / KB 'possible')
  // shows in the Planning "review" inbox until the user acts. Acknowledging it —
  // keep OR remove — records its sid here so it leaves the inbox and never nags
  // again. The keep/remove effect on the monthly total goes through
  // setRecurringOverride; this set only tracks "seen and decided".
  static const _kRecReviewed = 'recReviewed';

  /// Series ids (sid) the user has already confirmed or removed from the queue.
  static Set<String> recurringReviewed() => _loadSet(_kRecReviewed);

  static Future<void> markRecurringReviewed(String sid) async {
    if (sid.isEmpty) return;
    final seen = recurringReviewed()..add(sid);
    try {
      await _box.put(_kRecReviewed, jsonEncode(seen.toList()));
    } catch (_) {
      // No Hive box (standalone preview) → in-memory only.
    }
  }

  // ── Recurring hidden (deleted from the list entirely) ─────────────────────
  // Turning a stream OFF (setRecurringOverride) keeps it in the manager so it can
  // be turned back on. DELETING it (trash icon) hides it from the list AND the
  // totals for good — for streams the user never wants to see again. Keyed by
  // sid, re-applied on every sync.
  static const _kRecHidden = 'recHidden';

  static Set<String> recurringHidden() => _loadSet(_kRecHidden);

  static Future<void> setRecurringHidden(String sid, bool hidden) async {
    if (sid.isEmpty) return;
    final set = recurringHidden();
    if (hidden) {
      set.add(sid);
    } else {
      set.remove(sid);
    }
    try {
      await _box.put(_kRecHidden, jsonEncode(set.toList()));
    } catch (_) {
      // No Hive box (standalone preview) → in-memory only.
    }
  }

  // ── Recurring TYPE overrides (subscription <-> bill), by sid ──────────────
  // The engine guesses whether a stream is a subscription or a bill; the user can
  // reclassify (e.g. a gym billed via a payment processor → subscription). Keyed
  // by sid, re-applied on every sync.
  static const _kRecType = 'recType';

  static Map<String, String> recurringTypes() {
    try {
      final raw = _box.get(_kRecType) as String?;
      if (raw == null) return {};
      return (jsonDecode(raw) as Map).map((k, v) => MapEntry(k as String, v as String));
    } catch (_) {
      return {};
    }
  }

  static Future<void> setRecurringType(String sid, String? type) async {
    if (sid.isEmpty) return;
    final m = recurringTypes();
    if (type == null) {
      m.remove(sid);
    } else {
      m[sid] = type;
    }
    try {
      await _box.put(_kRecType, jsonEncode(m));
    } catch (_) {
      // No Hive box (standalone preview) → in-memory only.
    }
  }

  // ── Manual recurring entries (bills/subscriptions the user adds by hand) ───
  // Streams the bank data didn't surface (cash rent, a card the app isn't linked
  // to). Same shape as a backend `subs.item`, plus manual:true. Counted like any
  // other. Keyed/removed by sid.
  static const _kRecManual = 'recManual';

  static List<Map<String, dynamic>> manualRecurring() {
    try {
      final raw = _box.get(_kRecManual) as String?;
      if (raw == null) return [];
      return (jsonDecode(raw) as List)
          .map((e) => Map<String, dynamic>.from(e as Map))
          .toList();
    } catch (_) {
      return [];
    }
  }

  static Future<void> addManualRecurring(Map<String, dynamic> item) async {
    final list = manualRecurring()
      ..removeWhere((e) => e['sid'] == item['sid'])
      ..add(item);
    try {
      await _box.put(_kRecManual, jsonEncode(list));
    } catch (_) {
      // No Hive box (standalone preview) → in-memory only.
    }
  }

  static Future<void> removeManualRecurring(String sid) async {
    final list = manualRecurring()..removeWhere((e) => e['sid'] == sid);
    try {
      await _box.put(_kRecManual, jsonEncode(list));
    } catch (_) {
      // No Hive box (standalone preview) → in-memory only.
    }
  }

  // ── Manual assets (cash / savings the bank can't see) ────────────────────
  // These count toward NET WORTH only — never the live bank balance or spending
  // analytics. Each entry: {id, label, amount}. Kept on-device.
  static const _kAssets = 'manualAssets';

  static List<Map<String, dynamic>> manualAssets() {
    try {
      final raw = _box.get(_kAssets) as String?;
      if (raw == null) return [];
      return (jsonDecode(raw) as List)
          .map((e) => Map<String, dynamic>.from(e as Map))
          .toList();
    } catch (_) {
      return [];
    }
  }

  static Future<void> setManualAssets(List<Map<String, dynamic>> assets) async {
    try {
      await _box.put(_kAssets, jsonEncode(assets));
    } catch (_) {
      // No Hive box (standalone preview) → in-memory only.
    }
  }

  // ── Pending bank connection ─────────────────────────────────────────────────
  // The bank whose consent flow is in progress, stored before the bank's page
  // opens. If the bank hands off to its own app and the return cold-launches
  // Vaultie via a universal link, the callback carries only a `code` — not which
  // bank it was — so this is how the resumed connection recovers the label it
  // needs to store the connection under. Cleared on completion, cancel or error.
  static const _kPendingBank = 'pendingConnectBank';

  /// The bank's own mark, kept beside the name for the same reason: the return
  /// from a universal link carries only a `code`, so without this the screen
  /// confirming the connection cannot show whose connection it is.
  static const _kPendingLogo = 'pendingConnectLogo';

  static Future<void> setPendingConnect(String? bank, {String? logo}) async {
    try {
      if (bank == null) {
        await _box.delete(_kPendingBank);
        await _box.delete(_kPendingLogo);
      } else {
        await _box.put(_kPendingBank, bank);
        if (logo != null && logo.isNotEmpty) {
          await _box.put(_kPendingLogo, logo);
        } else {
          await _box.delete(_kPendingLogo);
        }
      }
    } catch (_) {/* no box (preview) → nothing to resume anyway */}
  }

  static String? pendingConnect() {
    try {
      return _box.get(_kPendingBank) as String?;
    } catch (_) {
      return null;
    }
  }

  static String? pendingConnectLogo() {
    try {
      return _box.get(_kPendingLogo) as String?;
    } catch (_) {
      return null;
    }
  }

  // ── Per-category budgets ────────────────────────────────────────────────────
  // The user's spending limits, one per section. Each entry:
  // {sec, limit, auto} where `auto` records whether the limit was our suggestion
  // or their own number.
  //
  // These lived only in a State field, reset to [] on every initState, and were
  // never written anywhere: a budget survived until the user navigated away and
  // then silently ceased to exist. Local, like the rest of the vault.
  static const _kBudgets = 'budgets';

  static List<Map<String, dynamic>> budgets() {
    try {
      final raw = _box.get(_kBudgets) as String?;
      if (raw == null) return [];
      return (jsonDecode(raw) as List)
          .map((e) => Map<String, dynamic>.from(e as Map))
          .toList();
    } catch (_) {
      return [];
    }
  }

  static Future<void> setBudgets(List<Map<String, dynamic>> items) async {
    try {
      await _box.put(_kBudgets, jsonEncode(items));
    } catch (_) {
      // No Hive box (standalone preview) → in-memory only.
    }
  }

  /// Budgets as a `section → limit` map, the shape the dashboard/month-review/
  /// tx-detail consume. Budgets are keyed by SECTION (`sec`), so consumers must
  /// look them up by a transaction's section, not its category. Previously the
  /// dashboard payload carried an always-empty `budgets: {}`, so Planning budgets
  /// never reached those screens at all — this is the bridge (SB-M3).
  static Map<String, dynamic> budgetMap() => budgetMapFrom(budgets());

  /// Pure transform of budget records → `section → limit` (malformed rows
  /// skipped). Separated from Hive so it is unit-testable.
  static Map<String, dynamic> budgetMapFrom(List<Map<String, dynamic>> records) {
    final out = <String, dynamic>{};
    for (final b in records) {
      if (b['sec'] is String && b['limit'] is num) {
        out[b['sec'] as String] = (b['limit'] as num).toDouble();
      }
    }
    return out;
  }

  // ── Subscription aliases (user-given names for anonymous recurring series) ──
  // Maps a recurring series id (sid, from the dashboard payload) → a display
  // name, e.g. an unnameable "APPLE.COM/BILL" stream → "ChatGPT". Attached to the
  // SERIES, not a merchant+amount, so it only renames that stream's charges.
  static const _kSubAlias = 'subAliases';

  static Map<String, String> subscriptionAliases() {
    try {
      final raw = _box.get(_kSubAlias) as String?;
      if (raw == null) return {};
      return (jsonDecode(raw) as Map)
          .map((k, v) => MapEntry(k as String, v as String));
    } catch (_) {
      return {};
    }
  }

  static Future<void> setSubscriptionAlias(String sid, String? name) async {
    final m = subscriptionAliases();
    if (name == null || name.trim().isEmpty) {
      m.remove(sid);
    } else {
      m[sid] = name.trim();
    }
    try {
      await _box.put(_kSubAlias, jsonEncode(m));
    } catch (_) {
      // No Hive box (standalone preview) → in-memory only.
    }
  }

  // ── Per-transaction local edits & deletions (survive a background sync) ─────
  // Editing a bank transaction (recategorise, rename, mark a transfer, star) or
  // deleting it mutates the on-device dashboard blob — but the next background
  // sync rebuilds that blob from the bank's data and would wipe the change. So
  // the change is ALSO recorded here, keyed by a stable transaction identity, and
  // re-applied to every freshly synced feed (see applyTxOverrides). Same pattern
  // as the recurring overrides: local intent is the source of truth, re-layered
  // on top of the server truth after each sync.
  //
  // Identity = merge-key | date | amount. None of these is changed by a
  // recategorise/rename/star, and all three are reproduced identically by the
  // backend for the same physical transaction on the next scan, so the override
  // re-attaches to the same row. (A single-row amount/date edit stores its NEW
  // values under the ORIGINAL identity, which is what the next scan presents.)
  static const _kTxEdits = 'txEdits';
  static const _kTxDeleted = 'txDeleted';

  /// Stable identity of a feed row for override matching: `mkey|date|amount`.
  static String txIdentity(Map row) {
    final mkey = (row['mkey'] ?? '').toString();
    final d = (row['d'] ?? '').toString();
    final a = ((row['a'] ?? 0) as num).toStringAsFixed(2);
    return '$mkey|$d|$a';
  }

  /// identity → overridden fields (e.g. {cat, col, ic, sec, secc, pos, nm, star}).
  static Map<String, Map<String, dynamic>> txEdits() {
    try {
      final raw = _box.get(_kTxEdits) as String?;
      if (raw == null) return {};
      return (jsonDecode(raw) as Map).map((k, v) =>
          MapEntry(k as String, Map<String, dynamic>.from(v as Map)));
    } catch (_) {
      return {};
    }
  }

  /// Record (merge) an override for [id]. Later keys win over earlier ones.
  static Future<void> setTxEdit(String id, Map<String, dynamic> fields) async {
    if (id.isEmpty) return;
    final m = txEdits();
    m[id] = {...?m[id], ...fields};
    try {
      await _box.put(_kTxEdits, jsonEncode(m));
    } catch (_) {
      // No Hive box (standalone preview) → in-memory only.
    }
  }

  /// Identities the user deleted — dropped from every future synced feed.
  static Set<String> txDeleted() => _loadSet(_kTxDeleted);

  static const _kSalaryRefs = 'salaryRefs';

  /// Merchant keys (see dashboard_preview.dart's _merchantKey) the user has
  /// confirmed pay them like an employer, by picking "Atlyginimas" once from
  /// a transaction's category sheet. Re-applied to every synced feed (see
  /// _applySalaryRefs) so a source the bank keeps coding as a plain top-up
  /// or transfer counts as income from then on — not just the one row that
  /// was tapped.
  static Set<String> salaryRefs() => _loadSet(_kSalaryRefs);

  static Future<void> addSalaryRef(String key) async {
    if (key.isEmpty) return;
    final s = salaryRefs()..add(key);
    try {
      await _box.put(_kSalaryRefs, jsonEncode(s.toList()));
    } catch (_) {
      // No Hive box (standalone preview) → in-memory only.
    }
  }

  /// Mark [id] deleted (and drop any field override for it — a gone row needs none).
  static Future<void> addTxDeleted(String id) async {
    if (id.isEmpty) return;
    final del = txDeleted()..add(id);
    final edits = txEdits()..remove(id);
    try {
      await _box.put(_kTxDeleted, jsonEncode(del.toList()));
      await _box.put(_kTxEdits, jsonEncode(edits));
    } catch (_) {
      // No Hive box (standalone preview) → in-memory only.
    }
  }

  /// Re-apply the user's local edits and deletions onto a freshly-synced `all`
  /// feed [rows]: drop deleted transactions, merge field overrides onto matching
  /// rows. Mutates and returns [rows]. Pure (no Hive) so it is unit-testable —
  /// pass [edits]/[deleted] from [txEdits]/[txDeleted].
  static List<Map<String, dynamic>> applyTxOverrides(
      List<Map<String, dynamic>> rows,
      Map<String, Map<String, dynamic>> edits,
      Set<String> deleted) {
    if (edits.isEmpty && deleted.isEmpty) return rows;
    if (deleted.isNotEmpty) {
      rows.removeWhere((r) => deleted.contains(txIdentity(r)));
    }
    if (edits.isNotEmpty) {
      for (final r in rows) {
        final ov = edits[txIdentity(r)];
        if (ov != null) r.addAll(ov);
      }
    }
    return rows;
  }

  static Future<void> clear() => _box.clear();
}
