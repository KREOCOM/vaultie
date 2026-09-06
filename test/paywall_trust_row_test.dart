// Regression check for lib/screens/onb_paywall.dart's _trustRow() — three
// icon+label facts ("Šifruota · 2 700+ bankų · Atšauk bet kada").
//
// 2026-09-04: a widget-test audit on a small-phone check found this row was
// originally a plain Row with no Flexible/Expanded around any child — at
// iPhone SE's available width it threw a real RenderFlex overflow, not a
// silent clip. Fixed by switching to Wrap (each icon+label pair as one
// unit), which reads as a single line wherever it already fit and drops to
// two lines instead of erroring wherever it doesn't. This test reproduces
// the row's exact widget tree at iPhone SE's available width (375 logical
// pt minus the paywall's own 20pt/side horizontal padding — see
// onb_paywall.dart's _bottom() call site) rather than booting the whole
// paywall screen, which needs PurchaseService/live store pricing wired up
// to build at all.
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

const _trustText = Color(0xFFDCE4F7);

Widget _fact(IconData icon, String label) => Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(icon, size: 12, color: _trustText),
        const SizedBox(width: 5),
        Text(label,
            style: const TextStyle(
                fontSize: 11, fontWeight: FontWeight.w700, color: _trustText)),
      ],
    );

Widget _trustRow() => Container(
      padding: const EdgeInsets.symmetric(vertical: 9, horizontal: 10),
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.09),
        borderRadius: BorderRadius.circular(11),
        border: Border.all(color: Colors.white.withValues(alpha: 0.18)),
      ),
      child: Wrap(
        alignment: WrapAlignment.center,
        crossAxisAlignment: WrapCrossAlignment.center,
        spacing: 10,
        runSpacing: 4,
        children: [
          _fact(Icons.lock_outline_rounded, 'Šifruota'),
          _fact(Icons.account_balance_rounded, '2 700+ bankų'),
          _fact(Icons.event_busy_rounded, 'Atšauk bet kada'),
        ],
      ),
    );

void main() {
  testWidgets('Paywall trust row: no overflow at iPhone SE width',
      (tester) async {
    const seWidth = 375.0;
    const paywallHorizontalPadding = 20.0 * 2;
    await tester.pumpWidget(MaterialApp(
      home: Scaffold(
        backgroundColor: Colors.black,
        body: Center(
          child: SizedBox(
            width: seWidth - paywallHorizontalPadding,
            child: _trustRow(),
          ),
        ),
      ),
    ));
    await tester.pumpAndSettle();

    expect(tester.takeException(), isNull,
        reason:
            'the trust row must not overflow at iPhone SE\'s available width');
  });
}
