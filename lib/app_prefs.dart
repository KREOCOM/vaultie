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
  static const _kBudget = 'monthlyBudget'; // double, or unset for no budget

  /// null = follow the system locale.
  static final ValueNotifier<Locale?> locale = ValueNotifier<Locale?>(null);

  /// Currency symbol used for all money formatting (defaults to euro).
  static final ValueNotifier<String> currency = ValueNotifier<String>('€');

  /// Optional monthly spending target; null = no budget set.
  static final ValueNotifier<double?> budget = ValueNotifier<double?>(null);

  static Box get _box => Hive.box(HiveBoxes.settings);

  /// Loads persisted values into the notifiers. Call once at startup, after the
  /// settings box is open.
  static void load() {
    final code = _box.get(_kLocale, defaultValue: '') as String;
    locale.value = code.isEmpty ? null : Locale(code);
    currency.value = _box.get(_kCurrency, defaultValue: '€') as String;
    budget.value = (_box.get(_kBudget) as num?)?.toDouble();
  }

  static Future<void> setBudget(double? value) async {
    budget.value = value;
    if (value == null) {
      await _box.delete(_kBudget);
    } else {
      await _box.put(_kBudget, value);
    }
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

/// Formats [value] as money using the selected currency symbol and the app's
/// active language for grouping/decimal separators and symbol placement — e.g.
/// "€1,234.56" in English but "1 234,56 €" in Lithuanian. Without a locale,
/// intl would always use en_US-style formatting regardless of the UI language.
String formatMoney(num value) {
  final code = AppPrefs.locale.value?.languageCode ??
      WidgetsBinding.instance.platformDispatcher.locale.languageCode;
  // The app only ships English and Lithuanian; map anything else to English so
  // an unrelated device locale can't produce a surprising format.
  final localeTag = code == 'lt' ? 'lt' : 'en';
  return NumberFormat.currency(
    locale: localeTag,
    symbol: AppPrefs.currency.value,
    decimalDigits: 2,
  ).format(value);
}
