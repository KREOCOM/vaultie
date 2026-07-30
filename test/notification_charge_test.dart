import 'package:flutter_test/flutter_test.dart';
import 'package:vaultie/services/notification_service.dart';

/// A reminder about money must state the amount that actually moves.
///
/// The recurring engine normalises every stream to a MONTHLY equivalent so the
/// figures can be added up. The reminder then announced that normalised number:
/// a 120 €/year subscription produced "10 € – due in 2 days" two days before
/// 120 € left the account. The number was off by the length of the cycle, and
/// silently — it looks like a perfectly reasonable amount.
void main() {
  group('chargeFor turns a monthly equivalent back into one real charge', () {
    test('a yearly subscription charges twelve months at once', () {
      // The bug: this used to be reported as 10.
      expect(NotificationService.chargeFor(10, 'yearly'), 120);
    });

    test('twice a year', () {
      expect(NotificationService.chargeFor(10, 'semiannual'), 60);
    });

    test('quarterly', () {
      expect(NotificationService.chargeFor(10, 'quarterly'), 30);
    });

    test('monthly is already one charge', () {
      expect(NotificationService.chargeFor(10, 'monthly'), 10);
    });

    test('an unknown cadence is left alone rather than guessed at', () {
      // Inventing a multiplier for a cadence we do not recognise would overstate
      // the charge; showing the monthly figure is at worst conservative.
      expect(NotificationService.chargeFor(10, 'irregular'), 10);
      expect(NotificationService.chargeFor(10, ''), 10);
    });

    test('a weekly charge is SMALLER than its monthly equivalent', () {
      // The one direction that goes down. Getting the sign of this wrong would
      // announce a month's worth of a weekly payment.
      final weekly = NotificationService.chargeFor(43.33, 'weekly');
      expect(weekly, lessThan(43.33));
      expect(weekly, closeTo(10, 0.05));
    });

    test('a fortnightly charge is about half a month', () {
      expect(NotificationService.chargeFor(43.48, 'biweekly'), closeTo(20, 0.1));
    });

    test('the 40 € early-warning threshold is crossed by the real charge, '
        'not the monthly figure', () {
      // Why the conversion matters beyond the wording: a 60 €/year subscription
      // carries monthly = 5. Tested against the monthly figure it would never
      // earn the 7-day warning — which is the whole point of that warning,
      // because a yearly renewal is exactly what you need time to cancel.
      const monthlyEquivalent = 5.0;
      expect(monthlyEquivalent, lessThan(40));
      expect(NotificationService.chargeFor(monthlyEquivalent, 'yearly'),
          greaterThan(40));
    });
  });
}
