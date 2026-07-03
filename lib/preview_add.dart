// Debug-only preview entrypoint for the category-first Add-expense screen.
// Run with: flutter run -t lib/preview_add.dart
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:hive_flutter/hive_flutter.dart';

import 'app_prefs.dart';
import 'l10n/app_localizations.dart';
import 'main.dart';
import 'models/subscription.dart';
import 'screens/add_subscription_screen.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await Hive.initFlutter();
  if (!Hive.isAdapterRegistered(SubscriptionAdapter().typeId)) {
    Hive.registerAdapter(SubscriptionAdapter());
  }
  await Hive.openBox(HiveBoxes.settings);
  await Hive.openBox<Subscription>(HiveBoxes.subscriptions);
  AppPrefs.load();
  final base = ThemeData(useMaterial3: true);
  runApp(MaterialApp(
    debugShowCheckedModeBanner: false,
    locale: const Locale('en'),
    localizationsDelegates: AppLocalizations.localizationsDelegates,
    supportedLocales: AppLocalizations.supportedLocales,
    theme: base.copyWith(
      scaffoldBackgroundColor: Colors.white,
      textTheme: GoogleFonts.interTextTheme(base.textTheme),
    ),
    home: const AddSubscriptionScreen(),
  ));
}
