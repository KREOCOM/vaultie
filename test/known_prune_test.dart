import 'package:flutter_test/flutter_test.dart';
import 'package:vaultie/services/dashboard_store.dart';

/// M2: the `known` cache (last-known raw scan) is handed back to the backend on
/// every scan and re-served for any bank that didn't answer — including a bank
/// the user just removed, which isn't scanned at all and so counts as "quiet",
/// resurrecting its transactions on the dashboard. prunedKnown drops cached data
/// for banks that are no longer connected. Pure — exercised without Hive.
Map<String, dynamic> _known() => {
      'txns': [
        {'_bank': 'SEB', 'entry_reference': 's1'},
        {'_bank': 'Revolut', 'entry_reference': 'r1'},
      ],
      'accounts': [
        {'bank': 'SEB', 'iban': 'LT9'},
        {'bank': 'Revolut', 'iban': 'LT1'},
      ],
    };

void main() {
  group('DashboardStore.prunedKnown', () {
    test('drops a removed bank, keeps the connected one', () {
      final out = DashboardStore.prunedKnown(_known(), {'Revolut'});
      expect((out['txns'] as List).map((t) => t['_bank']), ['Revolut']);
      expect((out['accounts'] as List).map((a) => a['bank']), ['Revolut']);
    });

    test('all connected → nothing dropped', () {
      final out = DashboardStore.prunedKnown(_known(), {'SEB', 'Revolut'});
      expect((out['txns'] as List).length, 2);
      expect((out['accounts'] as List).length, 2);
    });

    test('none connected → everything dropped', () {
      final out = DashboardStore.prunedKnown(_known(), <String>{});
      expect(out['txns'], isEmpty);
      expect(out['accounts'], isEmpty);
    });

    test('accounts use `bank`, txns use `_bank` — both honoured', () {
      final out = DashboardStore.prunedKnown(_known(), {'SEB'});
      expect((out['txns'] as List).single['entry_reference'], 's1');
      expect((out['accounts'] as List).single['iban'], 'LT9');
    });

    test('empty/malformed known never crashes', () {
      expect(DashboardStore.prunedKnown({}, {'SEB'}),
          {'txns': [], 'accounts': []});
    });
  });
}
