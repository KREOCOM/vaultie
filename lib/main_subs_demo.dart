// STANDALONE — 2026-08-12. Boots straight into the Prenumeratos sort-screen
// demo (screens/preview/subs_sort_demo.dart) with local fake data — no
// Firebase, no Hive, no real backend touched at all.
//
// Run with:
//   flutter run -t lib/main_subs_demo.dart
//
// To remove: delete this file and lib/screens/preview/subs_sort_demo.dart.
import 'package:flutter/material.dart';

import 'screens/preview/subs_sort_demo.dart';

void main() {
  runApp(const _SubsDemoApp());
}

class _SubsDemoApp extends StatelessWidget {
  const _SubsDemoApp();

  @override
  Widget build(BuildContext context) {
    return const MaterialApp(
      debugShowCheckedModeBanner: false,
      home: SubsDemoScreen(),
    );
  }
}
