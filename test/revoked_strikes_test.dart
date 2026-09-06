import 'package:flutter_test/flutter_test.dart';
import 'package:hive/hive.dart';
import 'package:vaultie/main.dart';
import 'package:vaultie/services/dashboard_store.dart';

/// A bank must refuse TWICE IN A ROW before the app removes it.
///
/// SEB scanned 150 transactions at midday and answered one 401 four hours later,
/// and the app deleted the connection on the spot. Any 401/403 was read as "the
/// user withdrew access" — which it usually is, but a token refresh mid-flight,
/// a bank-side hiccup, or an ASPSP wanting a header on that one call all arrive
/// the same way.
///
/// This is the rule that stops a blip from costing someone their bank, so it is
/// pinned here rather than left to a comment.
void main() {
  setUp(() async {
    Hive.init('.dart_tool/test_hive_${DateTime.now().microsecondsSinceEpoch}');
    await Hive.openBox<dynamic>(HiveBoxes.dashboard);
  });

  tearDown(() async => Hive.deleteFromDisk());

  test('one refusal is not enough to remove a bank', () async {
    expect(await DashboardStore.bumpRevokedStrike('SEB'), 1);
  });

  test('two in a row is', () async {
    expect(await DashboardStore.bumpRevokedStrike('SEB'), 1);
    expect(await DashboardStore.bumpRevokedStrike('SEB'), 2);
  });

  test('a successful scan clears the count, so strikes must be consecutive',
      () async {
    await DashboardStore.bumpRevokedStrike('SEB');
    await DashboardStore.clearRevokedStrike('SEB');
    // A bank that failed, worked, then failed again is not withdrawing access —
    // it is flaky, and flaky must never reach the removal path.
    expect(await DashboardStore.bumpRevokedStrike('SEB'), 1);
  });

  test('banks are counted separately', () async {
    await DashboardStore.bumpRevokedStrike('SEB');
    await DashboardStore.bumpRevokedStrike('SEB');
    expect(await DashboardStore.bumpRevokedStrike('Revolut'), 1,
        reason: 'one bank failing must not spend another bank\'s tolerance');
  });

  test('the name is matched regardless of case or padding', () async {
    await DashboardStore.bumpRevokedStrike('SEB');
    expect(await DashboardStore.bumpRevokedStrike('  seb '), 2,
        reason: 'the same bank arriving differently cased would otherwise get '
            'unlimited retries and never be cleaned up');
  });

  test('an empty bank name records nothing', () async {
    expect(await DashboardStore.bumpRevokedStrike('  '), 0);
  });

  test('clearing a bank that never failed is harmless', () async {
    await DashboardStore.clearRevokedStrike('Luminor');
    expect(await DashboardStore.bumpRevokedStrike('Luminor'), 1);
  });
}
