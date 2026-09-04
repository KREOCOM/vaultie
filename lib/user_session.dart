import 'dart:io';

import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_crashlytics/firebase_crashlytics.dart';
import 'package:flutter/foundation.dart';
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
      // A different account is taking over the phone. Their vaults must not mix
      // — but the outgoing one must not be destroyed either: Vaultie's data is
      // local-only, so a wipe here used to be silent, irreversible, and not
      // undone by signing back in. Set the previous owner's data aside first,
      // and only clear the live boxes once the copy is verified.
      if (!await archiveVault(owner)) {
        // Could not preserve it (disk full, corrupt box). Destroying it is not
        // an acceptable fallback, and neither is handing it to the new account,
        // so refuse the switch: sign back out, leaving everything untouched.
        await FirebaseAuth.instance.signOut();
        await PurchaseService.instance.setUser(null);
        return;
      }
      await _wipeLocalData();
    }
    // Bring this account's own vault back if it was archived earlier, then
    // re-read the cached prefs: the restore wrote straight to Hive, so the
    // in-memory notifiers (budget, name, currency) still hold what the wipe
    // left behind until they are reloaded.
    await restoreVault(uid);
    AppPrefs.load();
    await settings.put(_kDataOwner, uid);
  }
  // Tie crash reports to the account, so "it crashed for me" can be matched to
  // an actual stack trace. The uid is Vaultie's own identifier — no email, no
  // name, nothing from the bank.
  try {
    // Bounded. This sits between the splash and the first real screen, and it
    // had no timeout of its own — so on a flaky connection (or offline, waiting
    // out DNS) it held the branded splash for as long as it liked. Tagging a
    // crash report is best-effort; nothing waits on the answer.
    await FirebaseCrashlytics.instance
        .setUserIdentifier(uid)
        .timeout(const Duration(seconds: 3));
  } catch (_) {
    // Reporting is best-effort and must never block sign-in.
  }

  // Point RevenueCat at this account so premium follows the account, then
  // (see setUser's own doc) confirm with the server that the account
  // actually holds the entitlement RevenueCat just reported.
  //
  // Bounded on purpose. This is awaited between the splash and the first real
  // screen, and both of those are network calls with no timeout of their
  // own — so a hung billing server froze the app on the branded splash
  // permanently: no spinner, no error, no retry, indistinguishable from a
  // crash, on every launch for every signed-in user. Premium is already seeded
  // from the cached entitlement at startup and the SDK pushes the real answer
  // when it arrives, so continuing without waiting is correct rather than a
  // shortcut. Nothing about who owns the vault depends on it.
  //
  // 12s, not 6: setUser() now makes up to two sequential network calls
  // (RevenueCat's logIn, then the server's own entitlement check) instead
  // of one. 6s was tight enough on a real device's network that the SECOND
  // call routinely never got a chance to even start before this timeout
  // fired and abandoned it — which is exactly the check meant to catch a
  // device already holding someone else's entitlement.
  try {
    await PurchaseService.instance
        .setUser(uid)
        .timeout(const Duration(seconds: 12));
  } catch (_) {
    // Offline, slow, or not configured — the entitlement listener catches up.
  }
}

/// Wipes all per-user local data and detaches the account. Used on account
/// deletion (and could be used on an explicit "reset"). After this the next
/// sign-in starts from zero.
Future<void> wipeLocalDataAndForget() async {
  // Unlike an account-switch wipe (which archives this same key for a
  // possible restore, see _kVaultSettings/archiveVault), this account is
  // never coming back — so the actual photo FILE, not just the Hive path
  // pointing at it, has to go too, or it sits on disk forever ready to be
  // shown to whoever creates the next account on this phone.
  final photoPath = AppPrefs.profilePhotoPath.value;
  if (photoPath.isNotEmpty) {
    try {
      await File(photoPath).delete();
    } catch (_) {}
  }
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

// ── Per-account vault archive ───────────────────────────────────────────────
// Switching accounts moves the outgoing account's data into boxes tagged with
// its uid instead of deleting it, and moves the incoming account's back. Two
// people on one phone still never see each other's finances; neither of them
// loses anything.

/// Boxes that hold one account's data (the settings box is device-level and is
/// handled key by key below).
const _kVaultBoxes = <String>[
  HiveBoxes.cancellations,
  HiveBoxes.monthlyStats,
  HiveBoxes.dashboard,
];

/// Settings entries that belong to the account rather than the device — the
/// same list [_wipeLocalData] clears.
const _kVaultSettings = <String>[
  'premium',
  'monthlyBudget',
  'lockPinHash',
  'lockPinSalt',
  'lockFaceId',
  'aiChatConsent',
  'userName',
  // 2026-09-04: real bug, found in audit — this key was missing from both
  // this list AND _wipeLocalData's own list below, so a profile photo
  // wasn't scoped to the account at all: it leaked onto the next account
  // signing in on the same phone, and that account's own "remove photo"
  // action deleted the FIRST account's photo FILE, which — since it was
  // never archived — was gone for good. Listing it here fixes the
  // archive/restore side; the actual file is handled separately (see
  // wipeLocalDataAndForget, the one path with no restore to protect).
  'profilePhotoPath',
];

/// Box-name suffix for a uid. Hive folds box names to lower case, so the raw
/// uid can't be used directly — two uids differing only in case would land in
/// the same file. The FNV-1a hash keeps them apart.
@visibleForTesting
String vaultTag(String uid) {
  var h = 0x811c9dc5;
  for (final c in uid.codeUnits) {
    h = ((h ^ c) * 0x01000193) & 0xFFFFFFFF;
  }
  final safe = uid.toLowerCase().replaceAll(RegExp('[^a-z0-9]'), '');
  final head = safe.length > 12 ? safe.substring(0, 12) : safe;
  return '${head}_${h.toRadixString(16)}';
}

String _archiveName(String box, String tag) => '${box}__$tag';

/// Copies [owner]'s data into its archive boxes. Returns false if any box did
/// not come across intact — the caller must then leave the live data alone.
@visibleForTesting
Future<bool> archiveVault(String owner) async {
  final tag = vaultTag(owner);
  try {
    final subs = Hive.box<Subscription>(HiveBoxes.subscriptions);
    final subsArchive = await Hive.openBox<Subscription>(
        _archiveName(HiveBoxes.subscriptions, tag));
    await subsArchive.clear();
    await subsArchive.putAll(subs.toMap());
    if (subsArchive.length != subs.length) return false;

    for (final name in _kVaultBoxes) {
      final live = Hive.box(name);
      final archive = await Hive.openBox(_archiveName(name, tag));
      await archive.clear();
      await archive.putAll(live.toMap());
      if (archive.length != live.length) return false;
    }

    final settings = Hive.box(HiveBoxes.settings);
    final archive = await Hive.openBox(_archiveName(HiveBoxes.settings, tag));
    await archive.clear();
    for (final key in _kVaultSettings) {
      final v = settings.get(key);
      if (v != null) await archive.put(key, v);
    }
    return true;
  } catch (_) {
    return false; // never report success we can't stand behind
  }
}

/// Moves [uid]'s archived vault back into the live boxes, if it has one. The
/// archive is emptied only once its contents are in place.
@visibleForTesting
Future<void> restoreVault(String uid) async {
  final tag = vaultTag(uid);
  try {
    final subsName = _archiveName(HiveBoxes.subscriptions, tag);
    if (await Hive.boxExists(subsName)) {
      final archive = await Hive.openBox<Subscription>(subsName);
      final live = Hive.box<Subscription>(HiveBoxes.subscriptions);
      await live.clear();
      await live.putAll(archive.toMap());
      if (live.length == archive.length) await archive.clear();
    }
    for (final name in [...(_kVaultBoxes), HiveBoxes.settings]) {
      final archiveName = _archiveName(name, tag);
      if (!await Hive.boxExists(archiveName)) continue;
      final archive = await Hive.openBox(archiveName);
      final live = Hive.box(name);
      // The settings box is shared with device-level prefs, so its entries are
      // merged back key by key rather than replacing the whole box.
      if (name == HiveBoxes.settings) {
        for (final key in _kVaultSettings) {
          final v = archive.get(key);
          if (v != null) await live.put(key, v);
        }
        await archive.clear();
        continue;
      }
      await live.clear();
      await live.putAll(archive.toMap());
      if (live.length == archive.length) await archive.clear();
    }
  } catch (_) {
    // A failed restore leaves the archive in place, so the data is still there
    // to recover on the next sign-in rather than lost.
  }
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
    // 2026-09-04: see _kVaultSettings' own comment above — same bug, same
    // fix, this is the other list that needed it.
    'profilePhotoPath',
  ]) {
    await settings.delete(key);
  }
  AppPrefs.budget.value = null;
  AppPrefs.profilePhotoPath.value = '';
}

Future<void> _clearBox(String name) async {
  final box = Hive.isBoxOpen(name) ? Hive.box(name) : await Hive.openBox(name);
  await box.clear();
}
