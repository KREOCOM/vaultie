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

  /// The last-known raw scan to hand back to the backend ({txns, accounts}).
  static Map<String, dynamic> knownScan() {
    final raw = _box.get(_kKnown) as String?;
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
        e is Map ? (e['_bank'] ?? e['bank']) as String? : null;
    final fresh = {...txns.map(bankOf), ...accounts.map(bankOf)}..remove(null);
    final old = knownScan();
    final keptTxns = ((old['txns'] as List?) ?? const [])
        .where((t) => !fresh.contains(bankOf(t)));
    final keptAccounts = ((old['accounts'] as List?) ?? const [])
        .where((a) => !fresh.contains(bankOf(a)));
    await _box.put(
        _kKnown,
        jsonEncode({
          'txns': [...txns, ...keptTxns],
          'accounts': [...accounts, ...keptAccounts],
        }));
  }

  /// Save the dashboard payload from a successful scan (overwrites the previous).
  static Future<void> save(Map<String, dynamic> dash, {String? bank}) async {
    await _box.put(_kDash, jsonEncode(dash));
    await _box.put(_kSyncedAt, DateTime.now().toIso8601String());
    if (bank != null && bank.isNotEmpty) await _box.put(_kBank, bank);
  }

  /// The saved dashboard payload, or null if there isn't one (or it's corrupt).
  static Map<String, dynamic>? load() {
    final raw = _box.get(_kDash) as String?;
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
    final s = _box.get(_kSyncedAt) as String?;
    return s == null ? null : DateTime.tryParse(s);
  }

  static String? get bank => _box.get(_kBank) as String?;

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
    Set<String> ibansOf(List? accts) => ((accts ?? const [])
            .map((a) =>
                ((a as Map)['iban'] as String?)?.replaceAll(' ', '').toUpperCase())
            .whereType<String>()
            .where((s) => s.isNotEmpty)
            .toSet());
    final newIbans = ibansOf(accounts);
    // Spread into a fresh GROWABLE list — connections() can return an empty
    // const list on the first connect, and add()/removeWhere() on a const list
    // throws (silently aborting the very first bank, so the list never grows).
    final list = [...connections()]
      ..removeWhere((c) {
        final old = ibansOf(c['accounts'] as List?);
        // Replace only when this is the SAME account (IBANs overlap). When
        // neither side exposes an IBAN there is nothing to tell them apart, so
        // fall back to the old bank-name replacement to avoid duplicate records.
        if (old.isEmpty && newIbans.isEmpty) {
          return (c['bank'] as String?) == bank;
        }
        return old.intersection(newIbans).isNotEmpty;
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
    for (final c in connections().reversed) {
      final bank = c['bank'];
      for (final a in ((c['accounts'] as List?) ?? const [])) {
        final m = (a as Map).cast<String, dynamic>();
        final iban = (m['iban'] as String?)?.replaceAll(' ', '').toUpperCase();
        if (iban != null && iban.isNotEmpty && !seenIban.add(iban)) continue;
        out.add({...m, 'bank': bank});
      }
    }
    return out;
  }

  static Future<void> removeConnection(String bank) async {
    final list = [...connections()]
      ..removeWhere((c) => (c['bank'] as String?) == bank);
    await _box.put(_kBanks, jsonEncode(list));
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

  /// Names the user marked "not recurring / ended" — dropped from the total.
  static Set<String> recurringExcluded() => _loadSet(_kRecExcluded);

  /// Names the user marked "still active" — kept in the total even if the
  /// heuristic thinks the stream ended.
  static Set<String> recurringIncluded() => _loadSet(_kRecIncluded);

  /// Set the user's verdict for a stream. [counted] true → force-include;
  /// false → force-exclude; null → clear the override (back to the heuristic).
  static Future<void> setRecurringOverride(String name, bool? counted) async {
    final key = name.trim().toLowerCase();
    final excl = recurringExcluded()..remove(key);
    final incl = recurringIncluded()..remove(key);
    if (counted == false) excl.add(key);
    if (counted == true) incl.add(key);
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

  static Future<void> setPendingConnect(String? bank) async {
    try {
      if (bank == null) {
        await _box.delete(_kPendingBank);
      } else {
        await _box.put(_kPendingBank, bank);
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

  static Future<void> clear() => _box.clear();
}
