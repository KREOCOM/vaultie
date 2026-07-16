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
  static Future<bool> authenticateBiometric() async {
    try {
      return await _auth.authenticate(
        localizedReason: 'Atrakink Vaultie',
        biometricOnly: true,
        persistAcrossBackgrounding: true,
      );
    } catch (_) {
      return false;
    }
  }
}
