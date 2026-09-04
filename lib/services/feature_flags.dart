import 'package:firebase_remote_config/firebase_remote_config.dart';
import 'package:flutter/foundation.dart';
import 'package:hive_flutter/hive_flutter.dart';

import '../main.dart';

/// Remotely-controllable feature flags, backed by Firebase Remote Config.
///
/// The only flag today is [bankingEnabled], a kill-switch for the Vaultie 2.0
/// bank-connection feature. It lets us flip banking on (or off, e.g. during an
/// Enable Banking outage) from the Firebase console without shipping an app
/// update. Set the `banking_enabled` boolean parameter in Remote Config.
class FeatureFlags {
  FeatureFlags._();
  static final FeatureFlags instance = FeatureFlags._();

  /// Remote Config parameter key — must match the key in the Firebase console.
  static const bankingKey = 'banking_enabled';

  /// Whether the "Connect your bank" feature is available. Backed by Remote
  /// Config; defaults to `false` so the feature stays hidden if config never
  /// loads (offline first launch, fetch failure). Listeners rebuild when a
  /// fresh config activates, so the card appears the moment the flag arrives.
  final ValueNotifier<bool> bankingEnabled = ValueNotifier<bool>(false);

  /// Hive key holding the last value Remote Config actually returned.
  static const _cacheKey = 'flag_$bankingKey';

  /// Seeds [bankingEnabled] from the last known value before any network call.
  ///
  /// Without this, "config hasn't loaded yet" and "the kill-switch is on" look
  /// identical, so every offline launch hid banking — the entire product —
  /// with no explanation. A cached answer is a better guess than a default,
  /// and the real value overwrites it moments later.
  void loadCached() {
    try {
      final box = Hive.box(HiveBoxes.settings);
      bankingEnabled.value = box.get(_cacheKey, defaultValue: true) as bool;
    } catch (_) {
      bankingEnabled.value = true;
    }
  }

  void _publish(bool value) {
    bankingEnabled.value = value;
    try {
      Hive.box(HiveBoxes.settings).put(_cacheKey, value);
    } catch (_) {
      // Cache is an optimisation; the live value still applies this session.
    }
  }

  /// Fetches and activates Remote Config, then publishes the flags. Fire this
  /// once at startup WITHOUT awaiting — it never throws and never blocks the
  /// first frame; any failure leaves the safe in-code defaults in place.
  Future<void> init() async {
    // TEST OVERRIDE (debug + profile, never release): exercise the real
    // bank-connect flow without flipping production Remote Config. Remove
    // before release.
    if (!kReleaseMode) {
      bankingEnabled.value = true;
      return;
    }
    try {
      final rc = FirebaseRemoteConfig.instance;
      await rc.setDefaults(const {bankingKey: false});
      await rc.setConfigSettings(
        RemoteConfigSettings(
          fetchTimeout: const Duration(seconds: 8),
          // Low interval so a console flip (especially a kill-switch) reaches
          // users on their next launch instead of hours later.
          minimumFetchInterval: const Duration(hours: 1),
        ),
      );
      await rc.fetchAndActivate();
      _publish(rc.getBool(bankingKey));

      // Pick up config the SDK pushes later in the same session (realtime),
      // so a kill-switch can take effect without an app restart.
      rc.onConfigUpdated.listen((_) async {
        try {
          await rc.activate();
          _publish(rc.getBool(bankingKey));
        } catch (_) {
          // Ignore — keep the last activated value.
        }
      });
    } catch (_) {
      // Keep the safe in-code defaults (banking hidden) on any failure.
    }
  }
}
