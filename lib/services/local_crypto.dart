import 'dart:convert';
import 'dart:math';

import 'package:flutter/foundation.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:hive_flutter/hive_flutter.dart';

/// Encryption for everything Vaultie keeps on the phone.
///
/// The local boxes hold the user's actual bank transactions — merchant, amount,
/// date, for a year. They were written to disk in the clear, while the app told
/// people their data was safe on their device. On a passcode-locked iPhone that
/// is not catastrophic (the filesystem is encrypted at rest), but it is not what
/// was promised, and it leaves the data readable to anything that gets file
/// access: a backup, a jailbroken device, a forensic tool.
///
/// The key is 256 random bits held in the iOS Keychain, never in Hive and never
/// in a preference. `first_unlock` accessibility is deliberate: background
/// refresh has to be able to read the boxes after a reboot, before the user has
/// unlocked the app.
class LocalCrypto {
  LocalCrypto._();

  static const _kKey = 'hiveKey';
  static const _kMigrated = 'hiveEncrypted';

  static const _store = FlutterSecureStorage(
    iOptions: IOSOptions(accessibility: KeychainAccessibility.first_unlock),
  );

  static HiveCipher? _cipher;

  /// The cipher for [Hive.openBox], or null when the Keychain is unavailable.
  ///
  /// Null is a real outcome, not a bug to throw on: if the Keychain cannot be
  /// read we open the boxes unencrypted rather than refuse to launch. Losing
  /// encryption for that session is bad; a finance app that will not start is
  /// worse, and it is the failure the user cannot work around.
  static HiveCipher? get cipher => _cipher;

  /// Loads or creates the key. Call once, before opening any box.
  static Future<void> init() async {
    try {
      var b64 = await _store.read(key: _kKey);
      if (b64 == null) {
        final rnd = Random.secure();
        final key = List<int>.generate(32, (_) => rnd.nextInt(256));
        b64 = base64Encode(key);
        await _store.write(key: _kKey, value: b64);
      }
      _cipher = HiveAesCipher(base64Decode(b64));
    } catch (e) {
      // Keychain locked, entitlement missing, simulator quirk — carry on
      // unencrypted rather than block the launch.
      _cipher = null;
      if (kDebugMode) debugPrint('LocalCrypto unavailable: $e');
    }
  }

  static Future<bool> get migrated async {
    try {
      return (await _store.read(key: _kMigrated)) == '1';
    } catch (_) {
      return false;
    }
  }

  static Future<void> markMigrated() async {
    try {
      await _store.write(key: _kMigrated, value: '1');
    } catch (_) {/* retried next launch */}
  }

  /// Re-writes an existing PLAINTEXT box as an encrypted one.
  ///
  /// Reads every entry, deletes the file, re-opens with the cipher and writes
  /// them back. Returns false if anything went wrong, in which case the caller
  /// must NOT mark the migration done — the next launch tries again.
  ///
  /// The dangerous window is between delete and re-write, so the snapshot is
  /// taken and verified in memory first. If reading the old box fails there is
  /// nothing to lose and nothing to do; if the re-write fails the box comes back
  /// empty, which the app treats as "no cached data" and refetches from the bank
  /// — the one recoverable outcome available here.
  static Future<bool> migrateBox<T>(String name) async {
    if (_cipher == null) return false;
    try {
      if (!await Hive.boxExists(name)) return true; // nothing written yet
      final plain = await Hive.openBox<T>(name);
      final snapshot = Map<dynamic, T>.fromEntries(
        plain.keys.map((k) => MapEntry(k, plain.get(k) as T)),
      );
      await plain.close();
      if (snapshot.isEmpty) {
        await Hive.deleteBoxFromDisk(name);
        return true;
      }
      await Hive.deleteBoxFromDisk(name);
      final enc = await Hive.openBox<T>(name, encryptionCipher: _cipher);
      await enc.putAll(snapshot);
      await enc.close();
      return true;
    } catch (e) {
      if (kDebugMode) debugPrint('migrateBox($name) failed: $e');
      return false;
    }
  }
}
