// STANDALONE — 2026-08-27. Boots straight into InvestingTab (see its own
// doc for why the whole feature is a deletable prototype) so it can be
// screenshotted/tested without navigating the full app first. Bootstrap
// copied from main_design_preview.dart — only what InvestingTab actually
// touches (Hive boxes for DashboardStore, AppPrefs for dark mode, FxRates
// for USD conversion).
//
// Run with:
//   flutter run -t lib/main_investing_preview.dart
//
// To remove: delete this file — nothing else references it.
import 'dart:typed_data';

import 'package:firebase_core/firebase_core.dart';
import 'package:flutter/material.dart';
import 'package:hive_flutter/hive_flutter.dart';

import 'app_prefs.dart';
import 'firebase_options.dart';
import 'main.dart' show HiveBoxes;
import 'models/subscription.dart';
import 'services/dashboard_store.dart';
import 'services/fx_rates.dart';
import 'services/local_crypto.dart';
import 'screens/preview/investing_tab.dart';

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
    await FxRates.instance.refresh(); // force a live rate for this one-shot test
  } catch (_) {}
  try {
    AppPrefs.load();
  } catch (_) {}

  // DEBUG SEED (2026-08-28) — for screenshotting the populated state without
  // needing to tap through the add-flow. Remove before shipping; harmless if
  // left (only affects THIS standalone preview's own Hive data).
  await DashboardStore.setInvestments([
    {
      'symbol': 'TSLA',
      'name': 'Tesla',
      'domain': 'tesla.com',
      'shares': 2.0,
      'addedAt': DateTime.now().toIso8601String(),
    },
    {
      'symbol': 'BINANCE:BTCUSDT',
      'name': 'Bitcoin',
      'domain': 'bitcoin.org',
      'shares': 0.05,
      'addedAt': DateTime.now().toIso8601String(),
    },
  ]);

  runApp(const _PreviewApp());
}

class _PreviewApp extends StatelessWidget {
  const _PreviewApp();

  @override
  Widget build(BuildContext context) {
    return const MaterialApp(
      debugShowCheckedModeBanner: false,
      home: InvestingTab(),
    );
  }
}
