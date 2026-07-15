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
  /// and merged later, WITHOUT another login. Keyed by bank name — reconnecting
  /// the same bank replaces its record (fresh session id) rather than
  /// duplicating it. [accounts] items carry {uid, iban, name, currency}.
  static Future<void> addConnection({
    required String bank,
    String? sessionId,
    required List<Map<String, dynamic>> accounts,
  }) async {
    // Spread into a fresh GROWABLE list — connections() can return an empty
    // const list on the first connect, and add()/removeWhere() on a const list
    // throws (silently aborting the very first bank, so the list never grows).
    final list = [...connections()]
      ..removeWhere((c) => (c['bank'] as String?) == bank);
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
    for (final c in connections()) {
      final bank = c['bank'];
      for (final a in ((c['accounts'] as List?) ?? const [])) {
        out.add({...(a as Map).cast<String, dynamic>(), 'bank': bank});
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
