// STANDALONE — 2026-08-13. Boots straight into the Sąskaitos sort-screen
// demo (screens/preview/bills_sort_demo.dart) with local fake data — no
// Firebase, no Hive, no real backend touched at all.
//
// Run with:
//   flutter run -t lib/main_bills_demo.dart
//
// To remove: delete this file and lib/screens/preview/bills_sort_demo.dart.
import 'package:flutter/material.dart';

import 'screens/preview/bills_sort_demo.dart';

void main() {
  runApp(const _BillsDemoApp());
}

class _BillsDemoApp extends StatelessWidget {
  const _BillsDemoApp();

  @override
  Widget build(BuildContext context) {
    return const MaterialApp(
      debugShowCheckedModeBanner: false,
      home: BillsDemoScreen(),
    );
  }
}
