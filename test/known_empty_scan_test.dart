import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:hive/hive.dart';
import 'package:vaultie/main.dart';
import 'package:vaultie/services/dashboard_store.dart';

/// A scan that comes back with accounts but NO transactions must not empty the
/// phone's cached history.
///
/// That cache is the only copy of the user's transactions — the backend stores
/// none — and it exists so a bad scan cannot make their rent disappear. A
/// provider hiccup answering "here are your accounts, and nothing else" looks
/// exactly like a real answer, and replacing on it destroyed the very thing the
/// cache is for. Banks do not spontaneously forget a year of transactions.
void main() {
  setUp(() async {
    Hive.init('.dart_tool/test_hive_${DateTime.now().microsecondsSinceEpoch}');
    await Hive.openBox<dynamic>(HiveBoxes.dashboard);
  });

  tearDown(() async => Hive.deleteFromDisk());

  Map<String, dynamic> t(String bank, String ref) =>
      {'_bank': bank, 'entry_reference': ref};
  Map<String, dynamic> a(String bank) => {'_bank': bank, 'iban': 'LT$bank'};

  Future<List> cachedTxns() async =>
      (DashboardStore.knownScan()['txns'] as List?) ?? const [];

  test('a bank returning no transactions keeps the ones already cached',
      () async {
    await DashboardStore.mergeKnown({
      'txns': [t('Revolut', 'r1'), t('Revolut', 'r2')],
      'accounts': [a('Revolut')],
    });
    // The hiccup: accounts come back, transactions do not.
    await DashboardStore.mergeKnown({
      'txns': <Map<String, dynamic>>[],
      'accounts': [a('Revolut')],
    });
    expect((await cachedTxns()).length, 2,
        reason: 'an empty scan wiped the only copy of the history');
  });

  test('a bank that DOES return transactions replaces its own', () async {
    await DashboardStore.mergeKnown({
      'txns': [t('Revolut', 'old1'), t('Revolut', 'old2')],
      'accounts': [a('Revolut')],
    });
    await DashboardStore.mergeKnown({
      'txns': [t('Revolut', 'new1')],
      'accounts': [a('Revolut')],
    });
    final refs = (await cachedTxns())
        .map((e) => (e as Map)['entry_reference'])
        .toList();
    expect(refs, ['new1'],
        reason: 'a real scan must supersede what it replaces, not accumulate');
  });

  test('one bank scanning does not touch another bank', () async {
    await DashboardStore.mergeKnown({
      'txns': [t('SEB', 's1'), t('Revolut', 'r1')],
      'accounts': [a('SEB'), a('Revolut')],
    });
    // A connect scan only ever covers the bank being connected.
    await DashboardStore.mergeKnown({
      'txns': [t('Revolut', 'r2')],
      'accounts': [a('Revolut')],
    });
    final refs = (await cachedTxns())
        .map((e) => (e as Map)['entry_reference'])
        .toSet();
    expect(refs.contains('s1'), isTrue,
        reason: "scanning one bank dropped another bank's cache");
    expect(refs.contains('r2'), isTrue);
    expect(refs.contains('r1'), isFalse);
  });

  test('an entirely empty payload changes nothing', () async {
    await DashboardStore.mergeKnown({
      'txns': [t('SEB', 's1')],
      'accounts': [a('SEB')],
    });
    await DashboardStore.mergeKnown(
        {'txns': <dynamic>[], 'accounts': <dynamic>[]});
    expect((await cachedTxns()).length, 1);
  });

  test('a malformed cache does not take the merge down', () async {
    Hive.box<dynamic>(HiveBoxes.dashboard).put('knownScan', jsonEncode('nope'));
    await DashboardStore.mergeKnown({
      'txns': [t('SEB', 's1')],
      'accounts': [a('SEB')],
    });
    expect((await cachedTxns()).length, 1);
  });
}
