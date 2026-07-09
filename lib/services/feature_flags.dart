import 'package:firebase_remote_config/firebase_remote_config.dart';
import 'package:flutter/foundation.dart';

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

  /// Fetches and activates Remote Config, then publishes the flags. Fire this
  /// once at startup WITHOUT awaiting — it never throws and never blocks the
  /// first frame; any failure leaves the safe in-code defaults in place.
  Future<void> init() async {
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
      bankingEnabled.value = rc.getBool(bankingKey);

      // Pick up config the SDK pushes later in the same session (realtime),
      // so a kill-switch can take effect without an app restart.
      rc.onConfigUpdated.listen((_) async {
        try {
          await rc.activate();
          bankingEnabled.value = rc.getBool(bankingKey);
        } catch (_) {
          // Ignore — keep the last activated value.
        }
      });
    } catch (_) {
      // Keep the safe in-code defaults (banking hidden) on any failure.
    }
  }
}
