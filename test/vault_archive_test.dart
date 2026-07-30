import 'package:flutter_test/flutter_test.dart';
import 'package:hive/hive.dart';
import 'package:vaultie/main.dart';
import 'package:vaultie/models/subscription.dart';
import 'package:vaultie/user_session.dart';

/// Switching accounts on one phone must never cost anybody their vault.
///
/// Vaultie's data is local-only — there is no server copy — so when a second
/// account signs in on the same device, the outgoing account's data is set
/// aside under uid-tagged boxes rather than deleted, and moved back when they
/// return. That archive/restore path had NO test at all, which made it the one
/// piece of untested code standing between a user and the irreversible loss of
/// every connected bank and imported transaction (it has already eaten one real
/// vault; see the sign-in wipe that prompted this).
///
/// The sequence pinned here is the real one: account A holds a vault → B signs
/// in → A signs back in. Anything less than a full round trip would not have
/// caught the failure that matters.
void main() {
  const uidA = 'FAjXA0jhAaaaaaaaaaaaaaaaf042';
  const uidB = 'ZZbbbbbbbbbbbbbbbbbbbbbb1234';

  /// Every box the archive is responsible for, opened the way the app opens
  /// them (subscriptions is typed; the rest are dynamic).
  Future<void> openAll() async {
    await Hive.openBox<Subscription>(HiveBoxes.subscriptions);
    await Hive.openBox<dynamic>(HiveBoxes.settings);
    await Hive.openBox<dynamic>(HiveBoxes.cancellations);
    await Hive.openBox<dynamic>(HiveBoxes.monthlyStats);
    await Hive.openBox<dynamic>(HiveBoxes.dashboard);
  }

  Subscription sub(String id, String name, double cost) => Subscription(
        id: id,
        name: name,
        cost: cost,
        billingCycle: BillingCycle.monthly,
        category: 'Other',
        nextBillingDate: DateTime(2026, 8, 15),
      );

  /// What [_wipeLocalData] clears, minus the notification cancel (a platform
  /// channel that cannot run under flutter_test). The data effects are
  /// identical, which is what this test is about.
  Future<void> wipeLive() async {
    await Hive.box<Subscription>(HiveBoxes.subscriptions).clear();
    await Hive.box<dynamic>(HiveBoxes.cancellations).clear();
    await Hive.box<dynamic>(HiveBoxes.monthlyStats).clear();
    await Hive.box<dynamic>(HiveBoxes.dashboard).clear();
    final settings = Hive.box<dynamic>(HiveBoxes.settings);
    for (final key in const [
      'premium',
      'monthlyBudget',
      'lockPinHash',
      'lockPinSalt',
      'lockFaceId',
      'aiChatConsent',
      'userName',
    ]) {
      await settings.delete(key);
    }
  }

  /// Gives the live boxes a vault that looks like a real one: two banks' worth
  /// of dashboard payload, a subscription, history, and the per-account
  /// settings — alongside device-level prefs that must NOT move between users.
  Future<void> seedVaultA() async {
    await Hive.box<Subscription>(HiveBoxes.subscriptions)
        .put('s1', sub('s1', 'Netflix', 12.99));
    await Hive.box<dynamic>(HiveBoxes.dashboard)
        .put('payload', '{"banks":["revolut","seb"],"txns":412}');
    await Hive.box<dynamic>(HiveBoxes.dashboard).put('knownScan', 'A-known');
    await Hive.box<dynamic>(HiveBoxes.cancellations)
        .put('c1', {'name': 'Spotify', 'monthly': 9.99});
    await Hive.box<dynamic>(HiveBoxes.monthlyStats).put('2026-07', 1840.55);
    final settings = Hive.box<dynamic>(HiveBoxes.settings);
    await settings.put('premium', true);
    await settings.put('monthlyBudget', 2000.0);
    await settings.put('lockPinHash', 'hash-A');
    await settings.put('userName', 'Osvaldas');
    await settings.put('aiChatConsent', true);
    // Device-level: belongs to the phone, not the account.
    await settings.put('onboarded', true);
    await settings.put('language', 'lt');
  }

  setUp(() async {
    Hive.init('.dart_tool/test_hive_${DateTime.now().microsecondsSinceEpoch}');
    if (!Hive.isAdapterRegistered(SubscriptionAdapter().typeId)) {
      Hive.registerAdapter(SubscriptionAdapter());
    }
    await openAll();
  });

  tearDown(() async => Hive.deleteFromDisk());

  group('account switch A → B → A', () {
    test('A gets every part of the vault back, B never sees any of it',
        () async {
      await seedVaultA();

      // ── B signs in: archive A, then wipe. ──
      expect(await archiveVault(uidA), isTrue,
          reason: 'a vault that archives cleanly must report success');
      await wipeLive();
      await restoreVault(uidB); // B has no archive — nothing to bring back

      // B must start from zero. Anything surviving here is one user seeing
      // another's finances.
      expect(Hive.box<Subscription>(HiveBoxes.subscriptions).length, 0);
      expect(Hive.box<dynamic>(HiveBoxes.dashboard).length, 0);
      expect(Hive.box<dynamic>(HiveBoxes.cancellations).length, 0);
      expect(Hive.box<dynamic>(HiveBoxes.monthlyStats).length, 0);
      final asB = Hive.box<dynamic>(HiveBoxes.settings);
      expect(asB.get('premium'), isNull, reason: "A's entitlement must not carry");
      expect(asB.get('lockPinHash'), isNull,
          reason: "A's PIN must not lock B out of the app");
      expect(asB.get('userName'), isNull,
          reason: 'B must not be greeted by A\'s name');
      expect(asB.get('aiChatConsent'), isNull,
          reason: "A's consent must never be applied to B's data");
      // …but the phone's own prefs stay.
      expect(asB.get('onboarded'), isTrue);
      expect(asB.get('language'), 'lt');

      // ── B builds their own vault, then A signs back in. ──
      await Hive.box<Subscription>(HiveBoxes.subscriptions)
          .put('s9', sub('s9', 'Bolt', 4.50));
      await Hive.box<dynamic>(HiveBoxes.dashboard).put('payload', 'B-payload');
      await asB.put('userName', 'Someone Else');

      expect(await archiveVault(uidB), isTrue);
      await wipeLive();
      await restoreVault(uidA);

      // Everything A had, exactly as A left it.
      final subs = Hive.box<Subscription>(HiveBoxes.subscriptions);
      expect(subs.length, 1);
      expect(subs.get('s1')?.name, 'Netflix');
      expect(subs.get('s1')?.cost, 12.99);
      expect(subs.get('s9'), isNull, reason: "B's subscription must not leak to A");
      final dash = Hive.box<dynamic>(HiveBoxes.dashboard);
      expect(dash.get('payload'), '{"banks":["revolut","seb"],"txns":412}',
          reason: 'the connected banks and imported transactions are in here — '
              'this is the value that cannot be recreated');
      expect(dash.get('knownScan'), 'A-known');
      expect(Hive.box<dynamic>(HiveBoxes.cancellations).get('c1'),
          {'name': 'Spotify', 'monthly': 9.99});
      expect(Hive.box<dynamic>(HiveBoxes.monthlyStats).get('2026-07'), 1840.55);
      final asA = Hive.box<dynamic>(HiveBoxes.settings);
      expect(asA.get('premium'), isTrue);
      expect(asA.get('monthlyBudget'), 2000.0);
      expect(asA.get('lockPinHash'), 'hash-A');
      expect(asA.get('userName'), 'Osvaldas');
      expect(asA.get('onboarded'), isTrue);
    });

    test('B can sign back in after A reclaims the phone', () async {
      // The second half of the round trip is not symmetric by accident — B's
      // archive must survive A restoring, or the phone only ever works for one
      // of them.
      await seedVaultA();
      await archiveVault(uidA);
      await wipeLive();
      await restoreVault(uidB);

      await Hive.box<dynamic>(HiveBoxes.dashboard).put('payload', 'B-payload');
      await archiveVault(uidB);
      await wipeLive();
      await restoreVault(uidA);
      expect(Hive.box<dynamic>(HiveBoxes.dashboard).get('payload'),
          '{"banks":["revolut","seb"],"txns":412}');

      await archiveVault(uidA);
      await wipeLive();
      await restoreVault(uidB);
      expect(Hive.box<dynamic>(HiveBoxes.dashboard).get('payload'), 'B-payload');
    });
  });

  test('restoring an account with no archive leaves the live boxes alone',
      () async {
    // A brand-new account must not be able to blank a vault just by signing in
    // before anything was ever archived for them.
    await seedVaultA();
    await restoreVault('never-seen-this-uid');
    expect(Hive.box<Subscription>(HiveBoxes.subscriptions).length, 1);
    expect(Hive.box<dynamic>(HiveBoxes.dashboard).get('knownScan'), 'A-known');
    expect(Hive.box<dynamic>(HiveBoxes.settings).get('userName'), 'Osvaldas');
  });

  test('an empty vault archives successfully rather than blocking sign-in',
      () async {
    // archiveVault returning false REFUSES the account switch. A user with
    // nothing stored yet must still be able to switch accounts.
    expect(await archiveVault(uidA), isTrue);
  });

  group('vaultTag', () {
    test('uids differing only in case get different boxes', () async {
      // Hive folds box names to lower case, so the raw uid cannot be used: two
      // such uids would share one archive file and overwrite each other.
      expect(vaultTag('AbCdEf123456'), isNot(vaultTag('abcdef123456')));
    });

    test('is stable for the same uid', () async {
      // The tag IS the lookup key — if it moved between runs, every archived
      // vault would become unreachable.
      expect(vaultTag(uidA), vaultTag(uidA));
    });

    test('produces a lower-case, filesystem-safe name', () async {
      final tag = vaultTag('uid-With.Dots/And+Symbols');
      expect(tag, matches(RegExp(r'^[a-z0-9]*_[0-9a-f]+$')));
    });
  });
}
