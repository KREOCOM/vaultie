import 'package:flutter/widgets.dart';
import 'package:hive_flutter/hive_flutter.dart';
import 'package:intl/intl.dart';

import 'main.dart';

/// App-wide, user-changeable preferences, persisted in the Hive settings box
/// and exposed as [ValueNotifier]s so the whole app rebuilds when they change.
class AppPrefs {
  AppPrefs._();

  static const _kLocale = 'localeCode'; // '', 'lt' or 'en'
  static const _kCurrency = 'currency'; // symbol, e.g. '€'
  static const _kNotifications = 'notificationsEnabled';

  /// null = follow the system locale.
  static final ValueNotifier<Locale?> locale = ValueNotifier<Locale?>(null);

  /// Currency symbol used for all money formatting (defaults to euro).
  static final ValueNotifier<String> currency = ValueNotifier<String>('€');

  static Box get _box => Hive.box(HiveBoxes.settings);

  /// Loads persisted values into the notifiers. Call once at startup, after the
  /// settings box is open.
  static void load() {
    final code = _box.get(_kLocale, defaultValue: '') as String;
    locale.value = code.isEmpty ? null : Locale(code);
    currency.value = _box.get(_kCurrency, defaultValue: '€') as String;
  }

  static Future<void> setLocale(Locale? value) async {
    locale.value = value;
    await _box.put(_kLocale, value?.languageCode ?? '');
  }

  static Future<void> setCurrency(String symbol) async {
    currency.value = symbol;
    await _box.put(_kCurrency, symbol);
  }

  static bool get notificationsEnabled => Hive.isBoxOpen(HiveBoxes.settings)
      ? _box.get(_kNotifications, defaultValue: true) as bool
      : true;

  static Future<void> setNotificationsEnabled(bool value) async {
    await _box.put(_kNotifications, value);
  }
}

/// Formats [value] as money using the currently-selected currency symbol.
String formatMoney(num value) =>
    NumberFormat.currency(symbol: AppPrefs.currency.value, decimalDigits: 2)
        .format(value);
