import 'package:flutter_test/flutter_test.dart';
import 'package:vaultie/services/dashboard_store.dart';

/// B-H2: a bank whose data the backend served from cache this scan (its label in
/// `balance.staleBanks`) must NOT let the dashboard read as freshly synced. The
/// "last synced" clock advances only when at least one bank came back fresh —
/// [DashboardStore.isFullyStale] is that decision, exercised here without Hive.
Map<String, dynamic> _dash(List<String> bankTags, List<String> stale) => {
      'balance': {
        'accounts': [
          for (final b in bankTags) {'name': '$b acct', 'bank': b, 'amount': 1.0},
        ],
        'staleBanks': stale,
      },
    };

void main() {
  group('DashboardStore.isFullyStale', () {
    test('no stale banks → fresh (advance clock)', () {
      expect(DashboardStore.isFullyStale(_dash(['SEB', 'Revolut'], [])), isFalse);
    });

    test('every bank stale → fully stale (do NOT advance clock)', () {
      expect(DashboardStore.isFullyStale(_dash(['SEB'], ['SEB'])), isTrue);
      expect(
          DashboardStore.isFullyStale(_dash(['SEB', 'Revolut'], ['SEB', 'Revolut'])),
          isTrue);
    });

    test('some fresh, some stale → NOT fully stale (the sync was real)', () {
      // Revolut answered; SEB came from cache. The dashboard genuinely refreshed.
      expect(DashboardStore.isFullyStale(_dash(['SEB', 'Revolut'], ['SEB'])),
          isFalse);
    });

    test('bank-label matching is case-insensitive', () {
      expect(DashboardStore.isFullyStale(_dash(['SEB'], ['seb'])), isTrue);
    });

    test('malformed / empty payloads never crash and read as fresh', () {
      expect(DashboardStore.isFullyStale({}), isFalse);
      expect(DashboardStore.isFullyStale({'balance': 'not a map'}), isFalse);
      expect(DashboardStore.isFullyStale(_dash([], ['SEB'])), isFalse);
    });
  });
}
