import 'package:flutter_test/flutter_test.dart';
import 'package:vaultie/models/subscription.dart';

Subscription _sub(DateTime next, BillingCycle cycle) => Subscription(
      id: 'test',
      name: 'Test',
      cost: 9.99,
      billingCycle: cycle,
      category: 'other',
      nextBillingDate: next,
    );

void main() {
  group('rolledForwardBillingDate — anchor is measured from the original day', () {
    test('monthly charge on the 31st keeps the 31st (regression: drifted to 28)',
        () {
      final sub = _sub(DateTime(2026, 1, 31), BillingCycle.monthly);
      // Opened mid-March: Jan 31 → (Feb clamp) → the correct next is Mar 31,
      // NOT the Mar 28 the old iterative clamp produced.
      final rolled = sub.rolledForwardBillingDate(DateTime(2026, 3, 15));
      expect(rolled, DateTime(2026, 3, 31));
    });

    test('the day never permanently drifts across many months', () {
      final sub = _sub(DateTime(2026, 1, 31), BillingCycle.monthly);
      // A full year later still lands on the 31st.
      final rolled = sub.rolledForwardBillingDate(DateTime(2027, 1, 1));
      expect(rolled, DateTime(2027, 1, 31));
    });

    test('short target month clamps for that month only', () {
      final sub = _sub(DateTime(2026, 1, 31), BillingCycle.monthly);
      final rolled = sub.rolledForwardBillingDate(DateTime(2026, 2, 15));
      expect(rolled, DateTime(2026, 2, 28)); // Feb has no 31st
    });

    test('leap-year February clamps to the 29th, then restores the 31st', () {
      final sub = _sub(DateTime(2024, 1, 31), BillingCycle.monthly);
      expect(sub.rolledForwardBillingDate(DateTime(2024, 2, 10)),
          DateTime(2024, 2, 29));
      expect(sub.rolledForwardBillingDate(DateTime(2024, 3, 10)),
          DateTime(2024, 3, 31));
    });

    test('a still-future date is returned unchanged', () {
      final sub = _sub(DateTime(2026, 6, 30), BillingCycle.monthly);
      expect(sub.rolledForwardBillingDate(DateTime(2026, 3, 15)),
          DateTime(2026, 6, 30));
    });

    test('yearly on Feb 29 clamps to Feb 28 in non-leap years', () {
      final sub = _sub(DateTime(2024, 2, 29), BillingCycle.yearly);
      expect(sub.rolledForwardBillingDate(DateTime(2025, 1, 1)),
          DateTime(2025, 2, 28));
    });

    test('quarterly advances three months from the anchor', () {
      final sub = _sub(DateTime(2026, 1, 31), BillingCycle.quarterly);
      // Jan 31 + 3 months = Apr 30 (April has no 31st).
      expect(sub.rolledForwardBillingDate(DateTime(2026, 3, 1)),
          DateTime(2026, 4, 30));
    });

    test('weekly rolls forward in whole calendar weeks', () {
      final sub = _sub(DateTime(2026, 1, 1), BillingCycle.weekly);
      expect(sub.rolledForwardBillingDate(DateTime(2026, 1, 20)),
          DateTime(2026, 1, 22)); // +3 weeks
    });
  });
}
