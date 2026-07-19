import 'package:firebase_auth/firebase_auth.dart';
import 'package:hive_flutter/hive_flutter.dart';

import 'app_prefs.dart';
import 'main.dart';
import 'models/subscription.dart';
import 'services/notification_service.dart';
import 'services/purchase_service.dart';

/// Key (in the settings box) recording which account owns the local vault.
const _kDataOwner = 'dataOwnerUid';

/// Scopes the on-device vault to the currently signed-in account.
///
/// Vaultie stores expenses locally (Hive), so without this a second account
/// signing in on the same phone would see the first account's data. This wipes
/// everything when a *different* user signs in, then claims the vault for them —
/// so accounts never share data or entitlements. Call after auth resolves and
/// before showing the dashboard.
Future<void> ensureLocalDataForCurrentUser() async {
  final uid = FirebaseAuth.instance.currentUser?.uid;
  if (uid == null) return;
  final settings = Hive.box(HiveBoxes.settings);
  final owner = settings.get(_kDataOwner) as String?;
  if (owner != uid) {
    if (owner != null) {
      await _wipeLocalData(); // different account → start fresh
    }
    await settings.put(_kDataOwner, uid);
  }
  // Point RevenueCat at this account so premium follows the account.
  await PurchaseService.instance.setUser(uid);
}

/// Wipes all per-user local data and detaches the account. Used on account
/// deletion (and could be used on an explicit "reset"). After this the next
/// sign-in starts from zero.
Future<void> wipeLocalDataAndForget() async {
  await _wipeLocalData();
  await Hive.box(HiveBoxes.settings).delete(_kDataOwner);
  await PurchaseService.instance.setUser(null);
}

/// Detaches billing from the account on sign-out (data is kept so the *same*
/// user keeps their vault when they sign back in; a *different* user triggers a
/// wipe via [ensureLocalDataForCurrentUser]).
Future<void> onSignedOut() async {
  await PurchaseService.instance.setUser(null);
}

Future<void> _wipeLocalData() async {
  await NotificationService.instance.cancelAll();
  await Hive.box<Subscription>(HiveBoxes.subscriptions).clear();
  await _clearBox(HiveBoxes.cancellations);
  await _clearBox(HiveBoxes.monthlyStats);
  await _clearBox(HiveBoxes.dashboard);
  final settings = Hive.box(HiveBoxes.settings);
  // Clear per-user state; keep device-level prefs (onboarded, language, currency).
  //
  // The list below was 'premium' and 'monthlyBudget' only, which left three
  // kinds of the previous account's state behind on the device:
  //
  //  · the PIN — the next person was locked out of the app by a code they
  //    could not know, and deleting your account bricked it for them too;
  //  · the AI chat consent — the next person's finance summary went to
  //    Anthropic without the disclosure dialog ever being shown to them, which
  //    is one data subject's consent record being applied to another;
  //  · the display name — the app greeted them by the previous owner's name.
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
  AppPrefs.budget.value = null;
}

Future<void> _clearBox(String name) async {
  final box = Hive.isBoxOpen(name) ? Hive.box(name) : await Hive.openBox(name);
  await box.clear();
}
