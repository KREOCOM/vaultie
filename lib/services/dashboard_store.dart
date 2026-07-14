import 'dart:convert';

import 'package:hive_flutter/hive_flutter.dart';

import '../main.dart';

/// Persists the latest bank-scan dashboard payload on-device (Hive) so the app
/// opens straight into the dashboard instead of forcing a re-connect every time.
///
/// Local only — the payload never leaves the phone, same privacy model as the
/// scan itself. Scoped per account via [ensureLocalDataForCurrentUser] (the box
/// is wiped when a different user signs in).
class DashboardStore {
  static const _kDash = 'dash';
  static const _kSyncedAt = 'syncedAt';
  static const _kBank = 'bank';

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

  static bool get hasData => _box.get(_kDash) != null;

  /// When the saved dashboard was last synced (for a "last updated" label).
  static DateTime? get syncedAt {
    final s = _box.get(_kSyncedAt) as String?;
    return s == null ? null : DateTime.tryParse(s);
  }

  static String? get bank => _box.get(_kBank) as String?;

  static Future<void> clear() => _box.clear();
}
