// Debug-only preview entrypoint. Launches straight into the paywall so the
// screen can be reviewed without signing in. Not shipped — run with:
//   flutter run -t lib/preview_paywall.dart
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:hive_flutter/hive_flutter.dart';

import 'l10n/app_localizations.dart';
import 'main.dart';
import 'screens/paywall_screen.dart';
import 'services/purchase_service.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await Hive.initFlutter();
  await Hive.openBox(HiveBoxes.settings);
  // Use the offline mock here so the paywall can be previewed without a live
  // RevenueCat/StoreKit connection. Prices fall back to the static plan prices.
  PurchaseService.instance = MockPurchaseService();
  await PurchaseService.instance.init();
  runApp(const _PreviewApp());
}

class _PreviewApp extends StatelessWidget {
  const _PreviewApp();

  @override
  Widget build(BuildContext context) {
    final base = ThemeData(useMaterial3: true);
    return MaterialApp(
      debugShowCheckedModeBanner: false,
      localizationsDelegates: AppLocalizations.localizationsDelegates,
      supportedLocales: AppLocalizations.supportedLocales,
      // Force English so the preview shows the EN copy; change to
      // Locale('lt') to preview Lithuanian.
      locale: const Locale('en'),
      theme: base.copyWith(
        textTheme: GoogleFonts.interTextTheme(base.textTheme),
      ),
      home: const PaywallScreen(),
    );
  }
}
