// STANDALONE — 2026-08-12. Boots the REAL DashboardPreview widget (same one
// every user gets) on its baked-in sample data (the same account App Review
// uses — see review_account.dart), with the "premium blue" palette
// experiment switched on via designPreviewPalette. Bootstrap below is a
// trimmed copy of main.dart's — only what DashboardPreview actually touches
// (Hive boxes, AppPrefs, FxRates, Firebase for the services that expect it to
// exist) — no bank sync, no notifications, no purchases.
//
// Run with:
//   flutter run -t lib/main_design_preview.dart
//
// To remove the experiment entirely: delete this file. dashboard_preview.dart
// keeps a few inert "PREVIEW-ONLY (2026-08-12)" additions gated on
// designPreviewPalette, which defaults to false and nothing else sets —
// remove those too if you want the file back to exactly as it was.
import 'dart:typed_data';

import 'package:firebase_core/firebase_core.dart';
import 'package:flutter/material.dart';
import 'package:hive_flutter/hive_flutter.dart';

import 'app_prefs.dart';
import 'firebase_options.dart';
import 'main.dart' show HiveBoxes;
import 'models/subscription.dart';
import 'services/fx_rates.dart';
import 'services/local_crypto.dart';
import 'screens/preview/dashboard_preview.dart';

Future<Box<T>> _openBox<T>(String name) async {
  try {
    return await Hive.openBox<T>(name, encryptionCipher: LocalCrypto.cipher);
  } catch (_) {
    return Hive.openBox<T>('${name}_fallback', bytes: Uint8List(0));
  }
}

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  try {
    await Firebase.initializeApp(options: DefaultFirebaseOptions.currentPlatform);
  } catch (_) {}
  try {
    await Hive.initFlutter();
  } catch (_) {}
  try {
    if (!Hive.isAdapterRegistered(SubscriptionAdapter().typeId)) {
      Hive.registerAdapter(SubscriptionAdapter());
    }
  } catch (_) {}
  await LocalCrypto.init();
  await _openBox<Subscription>(HiveBoxes.subscriptions);
  await _openBox<dynamic>(HiveBoxes.settings);
  await _openBox<dynamic>(HiveBoxes.cancellations);
  await _openBox<dynamic>(HiveBoxes.monthlyStats);
  await _openBox<dynamic>(HiveBoxes.dashboard);
  try {
    await FxRates.instance.init();
  } catch (_) {}
  try {
    AppPrefs.load();
  } catch (_) {}

  designPreviewPalette = true;
  // This sandbox has no real synced bank data of its own (no bank sync, see
  // header comment) — only it should get the canned demo recurring
  // catalogue; main.dart must never set this. See the flag's own doc
  // comment in dashboard_preview.dart.
  designPreviewFakeRecurring = true;
  runApp(const _PreviewApp());
}

class _PreviewApp extends StatelessWidget {
  const _PreviewApp();

  @override
  Widget build(BuildContext context) {
    return const MaterialApp(
      debugShowCheckedModeBanner: false,
      home: DashboardPreview(),
    );
  }
}
