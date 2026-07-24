import 'dart:convert';
import 'dart:math';

import 'package:crypto/crypto.dart';
import 'package:hive_flutter/hive_flutter.dart';
import 'package:local_auth/local_auth.dart';

import '../main.dart';

/// App lock: an optional PIN (with optional Face ID / Touch ID) that gates the
/// app on launch and on return from background.
///
/// The PIN is never stored in the clear — only a salted SHA-256 hash lives on
/// device (Hive settings box). Biometrics go through the OS via `local_auth`;
/// we never see the face/fingerprint, only a pass/fail.
class AppLock {
  AppLock._();

  static const _kPinHash = 'lockPinHash';
  static const _kPinSalt = 'lockPinSalt';
  static const _kFaceId = 'lockFaceId';

  static final _auth = LocalAuthentication();
  static Box get _box => Hive.box(HiveBoxes.settings);
  static bool _boxReady() => Hive.isBoxOpen(HiveBoxes.settings);

  /// Whether a PIN is set — the master switch for the whole lock.
  static bool get isPinSet =>
      _boxReady() && (_box.get(_kPinHash) as String?)?.isNotEmpty == true;

  /// Whether Face ID / Touch ID unlock is enabled (only meaningful with a PIN).
  static bool get faceIdEnabled =>
      _boxReady() && (_box.get(_kFaceId, defaultValue: false) as bool) && isPinSet;

  static String _hash(String pin, String salt) =>
      sha256.convert(utf8.encode('$salt|$pin')).toString();

  /// Set (or replace) the PIN. Generates a fresh random salt each time.
  static Future<void> setPin(String pin) async {
    final salt = base64Url.encode(
        List<int>.generate(16, (_) => Random.secure().nextInt(256)));
    await _box.put(_kPinSalt, salt);
    await _box.put(_kPinHash, _hash(pin, salt));
  }

  /// Remove the PIN (and, with it, Face ID unlock).
  static Future<void> clearPin() async {
    await _box.delete(_kPinHash);
    await _box.delete(_kPinSalt);
    await _box.put(_kFaceId, false);
  }

  static bool verifyPin(String pin) {
    if (!isPinSet) return true;
    final salt = _box.get(_kPinSalt) as String? ?? '';
    return _hash(pin, salt) == (_box.get(_kPinHash) as String?);
  }

  static const _kPinFails = 'lockPinFails';
  static const _kPinLockUntil = 'lockPinLockUntil';

  /// Seconds the PIN keypad is locked for after too many wrong tries (0 = open).
  /// A 4-digit PIN is only 10 000 combinations; without a cooldown someone with
  /// the unlocked phone could hand- or script-guess it against all the financial
  /// data. Escalates so honest fat-fingering is barely affected.
  static int pinLockoutSecondsRemaining() {
    if (!_boxReady()) return 0;
    final until = _box.get(_kPinLockUntil);
    if (until is! int) return 0;
    final ms = until - DateTime.now().millisecondsSinceEpoch;
    return ms > 0 ? (ms / 1000).ceil() : 0;
  }

  /// Record a wrong PIN; from the 5th consecutive failure on, lock the keypad for
  /// an escalating cooldown (30s → 1m → 5m → 15m).
  static Future<void> registerPinFailure() async {
    if (!_boxReady()) return;
    final fails = ((_box.get(_kPinFails) as int?) ?? 0) + 1;
    await _box.put(_kPinFails, fails);
    final secs = fails >= 8
        ? 900
        : fails == 7
            ? 300
            : fails == 6
                ? 60
                : fails == 5
                    ? 30
                    : 0;
    if (secs > 0) {
      await _box.put(_kPinLockUntil,
          DateTime.now().millisecondsSinceEpoch + secs * 1000);
    }
  }

  /// Clear the failure count and any lockout — called on a correct PIN.
  static Future<void> resetPinFailures() async {
    if (!_boxReady()) return;
    await _box.delete(_kPinFails);
    await _box.delete(_kPinLockUntil);
  }

  static Future<void> setFaceId(bool value) async {
    await _box.put(_kFaceId, value && isPinSet);
  }

  /// Whether this device can actually do biometrics (has a face/fingerprint
  /// enrolled). Used to hide the Face ID toggle where it can't work.
  static Future<bool> canUseBiometrics() async {
    try {
      final supported = await _auth.isDeviceSupported();
      final can = await _auth.canCheckBiometrics;
      final enrolled = await _auth.getAvailableBiometrics();
      return supported && can && enrolled.isNotEmpty;
    } catch (_) {
      return false;
    }
  }

  /// Prompt the OS biometric check. Returns true only on a successful match.
  /// True while the system biometric sheet is on screen.
  ///
  /// iOS reports the app as backgrounded for as long as that sheet is up, so
  /// without this the lock gate re-locks the instant Face ID succeeds — and the
  /// fresh lock screen prompts again, which reads as the app scanning over and
  /// over. The gate checks this flag before acting on a resume.
  static bool biometricInFlight = false;

  static Future<bool> authenticateBiometric() async {
    biometricInFlight = true;
    try {
      return await _auth.authenticate(
        localizedReason: 'Atrakink Vaultie',
        biometricOnly: true,
        persistAcrossBackgrounding: true,
      );
    } catch (_) {
      return false;
    } finally {
      // The resume event lands a frame or two after authenticate() returns, so
      // the flag has to outlive the call itself.
      Future<void>.delayed(const Duration(milliseconds: 700),
          () => biometricInFlight = false);
    }
  }
}
