import 'package:flutter_test/flutter_test.dart';
import 'package:vaultie/services/dashboard_store.dart';

/// SB-M3: Planning stores budgets keyed by SECTION as `{sec, limit, auto}`
/// records; the dashboard/month-review/tx-detail consume a `section → limit`
/// map. budgetMapFrom is the bridge — it must produce section-keyed limits (so a
/// consumer looking up by a transaction's section finds the budget) and ignore
/// malformed rows. Exercised as a pure function (no Hive).
void main() {
  group('DashboardStore.budgetMapFrom', () {
    test('produces a section → limit map', () {
      final m = DashboardStore.budgetMapFrom([
        {'sec': 'Maistas, gėrimai', 'limit': 400, 'auto': false},
        {'sec': 'Transportas', 'limit': 150.5, 'auto': true},
      ]);
      expect(m['Maistas, gėrimai'], 400.0);
      expect(m['Transportas'], 150.5);
      expect(m.length, 2);
    });

    test('limits are doubles regardless of int/double input', () {
      final m = DashboardStore.budgetMapFrom([
        {'sec': 'Pramogos', 'limit': 60}
      ]);
      expect(m['Pramogos'], isA<double>());
      expect(m['Pramogos'], 60.0);
    });

    test('malformed rows are skipped, not crash', () {
      final m = DashboardStore.budgetMapFrom([
        {'sec': 'Būstas, sąskaitos', 'limit': 1000},
        {'sec': 'NoLimit'}, // missing limit
        {'limit': 50}, // missing sec
        {'sec': 42, 'limit': 10}, // sec not a string
      ]);
      expect(m.keys.toList(), ['Būstas, sąskaitos']);
    });

    test('empty input → empty map', () {
      expect(DashboardStore.budgetMapFrom([]), isEmpty);
    });
  });
}
