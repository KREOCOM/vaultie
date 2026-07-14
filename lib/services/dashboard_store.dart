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

  static Box get _box => Hive.box(HiveBoxes.dashboard);

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

  static Future<void> clear() => _box.clear();
}
