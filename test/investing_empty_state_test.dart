// Regression test for a real bug, found in a 2026-09-04 audit: the
// Investing tab's empty-state welcome content (trust rows + the "Pridėti
// pirmą investiciją" CTA + the disclaimer line) used to sit in a Positioned
// with a loose (unbounded) height — on a short device like iPhone SE, that
// risked the CTA running past the screen's own bottom edge. Stack's default
// clip blocks hit-testing past its bounds, not just painting, so the ONE
// button that starts a first investment could become fully unreachable.
//
// Fixed by giving that Positioned a `bottom: 0` and wrapping its content in
// a SingleChildScrollView — this test pins the viewport to iPhone SE's exact
// logical size and asserts the CTA is still reachable (scrolled into view,
// fully inside the viewport) rather than clipped off with no way to tap it.
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:vaultie/screens/preview/investing_tab.dart';

void main() {
  testWidgets(
      'Investing tab empty state: CTA stays reachable on iPhone SE',
      (tester) async {
    // iPhone SE (2nd/3rd gen) logical size — the shortest common iOS device
    // this app still supports.
    tester.view.physicalSize = const Size(375, 667);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    await tester.pumpWidget(MaterialApp(
      home: InvestingTab(onExit: () {}),
    ));
    await tester.pumpAndSettle();

    // The test harness's default locale resolves tr() to English, not the
    // app's own Lithuanian source strings — the button's rendered text is
    // 'Add your first investment' here regardless of what a real device
    // would show. Layout/hit-testing don't depend on which string it is.
    final cta = find.text('Add your first investment');
    expect(cta, findsOneWidget,
        reason: 'the empty-state CTA must exist in the tree at all');

    // Scroll any ancestor Scrollable until the CTA is on-screen — if the
    // fix regressed (no Scrollable ancestor, or the content isn't actually
    // wrapped by one), this throws instead of silently passing.
    await tester.ensureVisible(cta);
    await tester.pumpAndSettle();

    // Fully inside the viewport, not just partially — a clipped/half-shown
    // button is still effectively untappable at its cut edge.
    final ctaRect = tester.getRect(cta);
    final viewport = Offset.zero & const Size(375, 667);
    expect(viewport.contains(ctaRect.topLeft), isTrue,
        reason: 'CTA top-left must be inside the SE viewport, got $ctaRect');
    expect(viewport.contains(ctaRect.bottomRight), isTrue,
        reason:
            'CTA bottom-right must be inside the SE viewport, got $ctaRect');
  });
}
