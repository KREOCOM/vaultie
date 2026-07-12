import 'package:flutter/material.dart';

import 'screens/preview/dashboard_preview.dart';
import 'theme/vaultie_theme.dart';

/// Phase-1 preview entrypoint — runs the onboarding flow standalone (no Firebase)
/// so screens can be built and screenshotted quickly on the simulator.
///
///   flutter run -t lib/main_preview.dart -d <simulator-id>
void main() {
  runApp(const _PreviewApp());
}

class _PreviewApp extends StatelessWidget {
  const _PreviewApp();

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      debugShowCheckedModeBanner: false,
      title: 'Vaultie Preview',
      theme: ThemeData(
        useMaterial3: true,
        scaffoldBackgroundColor: VT.canvas,
        fontFamily: 'Inter',
        colorScheme: ColorScheme.fromSeed(
          seedColor: VT.brand,
          primary: VT.brand,
        ),
      ),
      home: const DashboardPreview(),
    );
  }
}
