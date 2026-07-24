import 'package:flutter_test/flutter_test.dart';
import 'package:vaultie/services/dashboard_store.dart';

/// H1: local per-transaction edits (recategorise / rename / mark-transfer / star)
/// and deletions must survive a background sync, which rebuilds the feed from the
/// bank's data. DashboardStore records them keyed by a stable identity and
/// re-layers them onto every fresh feed via applyTxOverrides — exercised here as
/// pure functions (no Hive).

Map<String, dynamic> _row(String mkey, String d, num a,
        {String cat = 'Kita', bool star = false}) =>
    {'mkey': mkey, 'd': d, 'a': a, 'cat': cat, 'star': star, 'nm': mkey};

void main() {
  group('DashboardStore.txIdentity', () {
    test('is mkey|date|amount with 2-decimal amount', () {
      expect(DashboardStore.txIdentity(_row('lidl', '2026-07-10', -25)),
          'lidl|2026-07-10|-25.00');
      // int vs double amount produce the same identity.
      expect(DashboardStore.txIdentity({'mkey': 'x', 'd': '2026-01-01', 'a': -5}),
          DashboardStore.txIdentity({'mkey': 'x', 'd': '2026-01-01', 'a': -5.0}));
    });
  });

  group('DashboardStore.applyTxOverrides', () {
    test('recategorise re-applies to the matching fresh row', () {
      final rows = [_row('lidl', '2026-07-10', -25), _row('bolt', '2026-07-11', -8)];
      final id = DashboardStore.txIdentity(rows[0]);
      DashboardStore.applyTxOverrides(rows, {
        id: {'cat': 'Maistas', 'col': 'green', 'sec': 'Maistas'}
      }, {});
      expect(rows[0]['cat'], 'Maistas');
      expect(rows[0]['sec'], 'Maistas');
      expect(rows[1]['cat'], 'Kita', reason: 'unrelated row untouched');
    });

    test('star override survives', () {
      final rows = [_row('netflix', '2026-07-01', -12.99)];
      DashboardStore.applyTxOverrides(
          rows, {DashboardStore.txIdentity(rows[0]): {'star': true}}, {});
      expect(rows[0]['star'], true);
    });

    test('deletion removes the transaction from the fresh feed', () {
      final rows = [_row('lidl', '2026-07-10', -25), _row('bolt', '2026-07-11', -8)];
      final del = {DashboardStore.txIdentity(rows[0])};
      DashboardStore.applyTxOverrides(rows, {}, del);
      expect(rows.map((r) => r['mkey']), ['bolt']);
    });

    test('same merchant + day, different amounts are edited independently', () {
      final rows = [
        _row('coffee', '2026-07-10', -3.50),
        _row('coffee', '2026-07-10', -9.00),
      ];
      DashboardStore.applyTxOverrides(rows, {
        DashboardStore.txIdentity(rows[1]): {'cat': 'Pramogos'}
      }, {});
      expect(rows[0]['cat'], 'Kita', reason: 'the €3.50 one is left alone');
      expect(rows[1]['cat'], 'Pramogos');
    });

    test('a single-row amount edit keyed by ORIGINAL identity applies on resync', () {
      // User corrected the amount; the override is stored under the original
      // identity (what the bank re-presents next scan) with the new value.
      final freshFromBank = [_row('atm', '2026-07-05', -100)];
      final originalId = DashboardStore.txIdentity(freshFromBank[0]);
      DashboardStore.applyTxOverrides(freshFromBank, {
        originalId: {'a': -120, 'nm': 'Cash withdrawal'}
      }, {});
      expect(freshFromBank[0]['a'], -120);
      expect(freshFromBank[0]['nm'], 'Cash withdrawal');
    });

    test('a row both deleted and edited is removed (delete wins)', () {
      final rows = [_row('lidl', '2026-07-10', -25)];
      final id = DashboardStore.txIdentity(rows[0]);
      DashboardStore.applyTxOverrides(rows, {
        id: {'cat': 'Maistas'}
      }, {
        id
      });
      expect(rows, isEmpty);
    });

    test('no overrides → feed is untouched', () {
      final rows = [_row('lidl', '2026-07-10', -25)];
      DashboardStore.applyTxOverrides(rows, {}, {});
      expect(rows.single['cat'], 'Kita');
    });
  });
}
