import 'package:flutter/widgets.dart';
import 'package:hive_flutter/hive_flutter.dart';
import 'package:intl/intl.dart';

import 'main.dart';
import 'services/fx_rates.dart';
import 'ui/design_system.dart';

/// App-wide, user-changeable preferences, persisted in the Hive settings box
/// and exposed as [ValueNotifier]s so the whole app rebuilds when they change.
class AppPrefs {
  AppPrefs._();

  static const _kLocale = 'localeCode'; // '', 'lt' or 'en'
  static const _kCurrency = 'currency'; // symbol, e.g. '€'
  static const _kCurrencyCode = 'currencyCode'; // ISO code, e.g. 'EUR'
  static const _kNotifications = 'notificationsEnabled';
  static const _kBudget = 'monthlyBudget'; // double, or unset for no budget
  static const _kDarkMode = 'darkContentTheme'; // bool

  /// null = follow the system locale.
  static final ValueNotifier<Locale?> locale = ValueNotifier<Locale?>(null);

  /// Currency symbol used for all money formatting (defaults to euro).
  static final ValueNotifier<String> currency = ValueNotifier<String>('€');

  /// The user's chosen DISPLAY currency (ISO code). Amounts are stored in EUR
  /// and converted for display via [FxRates]. Default 'EUR'. Bumps [currency]
  /// (the symbol) so the whole app rebuilds when it changes.
  static final ValueNotifier<String> currencyCode =
      ValueNotifier<String>('EUR');

  /// Optional monthly spending target; null = no budget set.
  static final ValueNotifier<double?> budget = ValueNotifier<double?>(null);

  /// Whether the content screens (dashboard, analytics, settings, add) use the
  /// dark theme. Defaults to false — the light "Frost" look is the app's primary
  /// theme; the user can switch to dark in Settings. Auth/splash are unaffected.
  static final ValueNotifier<bool> darkMode = ValueNotifier<bool>(false);

  static Box get _box => Hive.box(HiveBoxes.settings);

  /// Loads persisted values into the notifiers. Call once at startup, after the
  /// settings box is open.
  static void load() {
    // Defensive reads: a stored value whose type no longer matches (a corrupt
    // record, or a key whose type changed across an app update) must default,
    // never throw — a cast crash here happens before runApp() and would brick the
    // app on launch with no recovery. `is`-checks keep boot resilient.
    final code = _box.get(_kLocale);
    locale.value = (code is String && code.isNotEmpty) ? Locale(code) : null;
    final cur = _box.get(_kCurrency);
    currency.value = cur is String ? cur : '€';
    final cc = _box.get(_kCurrencyCode);
    currencyCode.value = cc is String ? cc : 'EUR';
    applyDisplayCurrency();
    final b = _box.get(_kBudget);
    budget.value = b is num ? b.toDouble() : null;
    // Frost (light) is the primary theme — the app opens light unless the user
    // chose dark.
    final dm = _box.get(_kDarkMode);
    darkMode.value = dm is bool ? dm : false;
  }

  static Future<void> setDarkMode(bool value) async {
    darkMode.value = value;
    await _box.put(_kDarkMode, value);
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

  /// Change the display currency (ISO code). Persists it and re-applies the
  /// EUR→base rate + symbol to [Money] so every amount reformats.
  static Future<void> setCurrencyCode(String code) async {
    currencyCode.value = code.toUpperCase();
    await _box.put(_kCurrencyCode, currencyCode.value);
    applyDisplayCurrency();
  }

  /// Point [Money] at the current display currency's live rate + symbol, and
  /// bump [currency] so listeners rebuild. Safe to call repeatedly (e.g. when a
  /// fresh FX table lands). Falls back to EUR (rate 1.0) when the rate is absent.
  static void applyDisplayCurrency() {
    final info = currencyByCode(currencyCode.value);
    Money.rate = FxRates.instance.rateFor(info.code);
    Money.symbol = info.symbol;
    currency.value = info.symbol; // legacy notifier → triggers rebuilds
  }

  static bool get notificationsEnabled => Hive.isBoxOpen(HiveBoxes.settings)
      ? _box.get(_kNotifications, defaultValue: true) as bool
      : true;

  static Future<void> setNotificationsEnabled(bool value) async {
    await _box.put(_kNotifications, value);
  }

  // Whether the user dismissed the "notifications are denied" dashboard banner.
  static const _kNotifBannerDismissed = 'notifBannerDismissed';

  static bool get notifBannerDismissed => Hive.isBoxOpen(HiveBoxes.settings)
      ? _box.get(_kNotifBannerDismissed, defaultValue: false) as bool
      : false;

  static Future<void> setNotifBannerDismissed(bool value) async {
    await _box.put(_kNotifBannerDismissed, value);
  }

  // Opt-in: allow sending unresolved BUSINESS merchant names (only) to the AI
  // classifier for better categorisation. Off by default. Never sends amounts,
  // IBANs, identifiers, dates or person/P2P names.
  static const _kAiEnrichment = 'aiEnrichment';

  // Default ON. It is what categorises the long tail — any shop in Europe the
  // deterministic pipeline (name rules → KB → offline index) can't place, since
  // banks send no MCC over Enable Banking (measured: 0% on the tested banks). A
  // merchant is classified once, cached server-side, and the answer is reused
  // for every user, so "Kita" is the exception, not the rule. Only BUSINESS
  // merchant names are sent — a person-name guard drops likely P2P names, and
  // never any amount, IBAN, date, or identifier. Disclosed in the privacy policy
  // and switchable off in Settings, so it is on-by-default with a real opt-out.
  static bool get aiEnrichment => Hive.isBoxOpen(HiveBoxes.settings)
      ? _box.get(_kAiEnrichment, defaultValue: true) as bool
      : true;

  static Future<void> setAiEnrichment(bool value) async {
    await _box.put(_kAiEnrichment, value);
  }

  // Whether the user accepted the one-time AI-chat disclosure (their finance
  // summary is sent to the AI provider to answer questions; not used for
  // training; not financial advice). Gates the first use of the AI chat.
  static const _kAiChatConsent = 'aiChatConsent';

  static bool get aiChatConsent => Hive.isBoxOpen(HiveBoxes.settings)
      ? _box.get(_kAiChatConsent, defaultValue: false) as bool
      : false;

  static Future<void> setAiChatConsent(bool value) async {
    await _box.put(_kAiChatConsent, value);
  }

  // The user's display name (Settings → profile). Persisted so it survives
  // reopening the app (was a local field that reset to "Vartotojas").
  static const _kUserName = 'userName';

  static String get userName => Hive.isBoxOpen(HiveBoxes.settings)
      ? _box.get(_kUserName, defaultValue: '') as String
      : '';

  static Future<void> setUserName(String value) async {
    await _box.put(_kUserName, value.trim());
  }

  static const _kOnboardingComplete = 'onboardingComplete';

  /// Whether the post-login "How would you like to start?" choice has been made.
  /// Read synchronously so navigation can gate on it. Once true the choice
  /// screen is skipped and the user goes straight to the dashboard.
  static bool get onboardingComplete => Hive.isBoxOpen(HiveBoxes.settings)
      ? _box.get(_kOnboardingComplete, defaultValue: false) as bool
      : false;

  static Future<void> setOnboardingComplete(bool value) async {
    await _box.put(_kOnboardingComplete, value);
  }

  static const _kOnboarded = 'onboarded';

  /// Whether the pre-login intro chain (OnbIntro → … → OnbConnect) has been
  /// walked. Distinct from [onboardingComplete], which covers the *post*-login
  /// "How would you like to start?" choice — the two gate different screens and
  /// a user can have one without the other.
  ///
  /// Lives here rather than as a raw `'onboarded'` Hive key: it used to be
  /// written by hand in two screens that are no longer on any path, so the live
  /// chain never set it and release builds replayed onboarding on every launch.
  /// Debug hid it by force-setting the key at startup.
  static bool get onboarded => Hive.isBoxOpen(HiveBoxes.settings)
      ? _box.get(_kOnboarded, defaultValue: false) as bool
      : false;

  static Future<void> setOnboarded(bool value) async {
    await _box.put(_kOnboarded, value);
  }
}

/// The default UI locale when the user hasn't chosen a language in Settings:
/// Lithuanian only when the device *Region* (iOS Settings → Language & Region →
/// Region) is Lithuania, English everywhere else. iOS reports the region as the
/// locale's country subtag (e.g. `en-LT`), so we key off the country — not the
/// phone's display language — to match "in Lithuania → Lithuanian".
Locale localeForRegion() {
  final region = WidgetsBinding.instance.platformDispatcher.locale.countryCode;
  return region == 'LT' ? const Locale('lt') : const Locale('en');
}

/// The locale the app should actually use: an explicit Settings choice wins,
/// otherwise the region-based default.
Locale effectiveLocale() => AppPrefs.locale.value ?? localeForRegion();

/// Formats [value] as money using the selected currency symbol and the app's
/// active language for grouping/decimal separators and symbol placement — e.g.
/// "€1,234.56" in English but "1 234,56 €" in Lithuanian. Without a locale,
/// intl would always use en_US-style formatting regardless of the UI language.
String formatMoney(num value) {
  final code = effectiveLocale().languageCode;
  // The app only ships English and Lithuanian; map anything else to English so
  // an unrelated device locale can't produce a surprising format.
  final localeTag = code == 'lt' ? 'lt' : 'en';
  return NumberFormat.currency(
    locale: localeTag,
    symbol: AppPrefs.currency.value,
    decimalDigits: 2,
  ).format(value);
}
