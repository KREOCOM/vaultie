import 'package:flutter/widgets.dart';
import 'package:hive_flutter/hive_flutter.dart';
import 'package:intl/intl.dart';

import 'main.dart';
import 'logic/display_currency.dart';
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

  /// False when the chosen currency could NOT be applied (no FX rate yet) and
  /// amounts are therefore still euros. The picker and the settings row read
  /// this instead of each deciding for themselves whether the choice took.
  static final ValueNotifier<bool> displayConverted = ValueNotifier<bool>(true);

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

  /// What the user actually chose, straight from storage. The onboarding demo
  /// flips [darkMode] for show without writing, so it needs this to know what
  /// to put back — reading the notifier would just return its own change.
  static bool get darkModeSaved {
    final v = _box.get(_kDarkMode);
    return v is bool ? v : false;
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
    // The rate and the symbol move together, or not at all.
    //
    // They used to be set independently: a missing rate fell back to 1.0 while
    // the symbol was applied regardless, so a first launch offline with the
    // display currency set to GBP printed the untouched EUR figures under a
    // pound sign — 7 049 € shown as "7 049 £". Wrong by a fifth, and stated as
    // confidently as a correct number.
    //
    // Amounts are stored in EUR, so falling back to EUR is always truthful. When
    // the real table lands, main.dart's listener calls this again and the chosen
    // currency takes effect then.
    final d = resolveDisplayCurrency(
        info.code, info.symbol, FxRates.instance.rates.value);
    Money.rate = d.rate;
    Money.symbol = d.symbol;
    // Report whether the choice actually applied, so no screen has to re-derive
    // it and a currency change can never silently do nothing.
    displayConverted.value = d.converted;
    currency.value = Money.symbol; // legacy notifier → triggers rebuilds
  }

  /// Typed reads that fall back instead of throwing.
  ///
  /// These were `as bool` / `as String` casts. `onboarded` was already hardened
  /// for exactly this reason — a wrong-typed stored value (an older build's
  /// format, a half-written record) threw on the cast — but the rest were left
  /// as they were, and several are read on the pre-runApp path too. A default is
  /// always recoverable; a crash before the first frame is not.
  static bool _boolOr(String key, bool fallback) {
    final v = _box.get(key, defaultValue: fallback);
    return v is bool ? v : fallback;
  }

  static String _strOr(String key, String fallback) {
    final v = _box.get(key, defaultValue: fallback);
    return v is String ? v : fallback;
  }

  static bool get notificationsEnabled => Hive.isBoxOpen(HiveBoxes.settings)
      ? _boolOr(_kNotifications, true)
      : true;

  static Future<void> setNotificationsEnabled(bool value) async {
    await _box.put(_kNotifications, value);
  }

  // Whether the user dismissed the "notifications are denied" dashboard banner.
  static const _kNotifBannerDismissed = 'notifBannerDismissed';

  static bool get notifBannerDismissed => Hive.isBoxOpen(HiveBoxes.settings)
      ? _boolOr(_kNotifBannerDismissed, false)
      : false;

  static Future<void> setNotifBannerDismissed(bool value) async {
    await _box.put(_kNotifBannerDismissed, value);
  }

  // Whether the notifications explainer has been shown. The OS prompt can be
  // answered exactly once per install — ask at the wrong moment and a "no" is
  // permanent — so the explainer runs once, after the first bank connect, when
  // there are real payments to be reminded about.
  static const _kNotifAsked = 'notifIntroShown';

  static bool get notifIntroShown => Hive.isBoxOpen(HiveBoxes.settings)
      ? _boolOr(_kNotifAsked, false)
      : true; // box not open → never prompt

  static Future<void> setNotifIntroShown(bool value) async {
    await _box.put(_kNotifAsked, value);
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
      ? _boolOr(_kAiEnrichment, true)
      : true;

  static Future<void> setAiEnrichment(bool value) async {
    await _box.put(_kAiEnrichment, value);
  }

  // Whether the user accepted the one-time AI-chat disclosure (their finance
  // summary is sent to the AI provider to answer questions; not used for
  // training; not financial advice). Gates the first use of the AI chat.
  static const _kAiChatConsent = 'aiChatConsent';

  static bool get aiChatConsent => Hive.isBoxOpen(HiveBoxes.settings)
      ? _boolOr(_kAiChatConsent, false)
      : false;

  static Future<void> setAiChatConsent(bool value) async {
    await _box.put(_kAiChatConsent, value);
  }

  // The user's display name (Settings → profile). Persisted so it survives
  // reopening the app (was a local field that reset to "Vartotojas").
  static const _kUserName = 'userName';

  static String get userName => Hive.isBoxOpen(HiveBoxes.settings)
      ? _strOr(_kUserName, '')
      : '';

  static Future<void> setUserName(String value) async {
    await _box.put(_kUserName, value.trim());
  }

  static const _kOnboardingComplete = 'onboardingComplete';

  /// Whether the post-login "How would you like to start?" choice has been made.
  /// Read synchronously so navigation can gate on it. Once true the choice
  /// screen is skipped and the user goes straight to the dashboard.
  static bool get onboardingComplete => Hive.isBoxOpen(HiveBoxes.settings)
      ? _boolOr(_kOnboardingComplete, false)
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
  static bool get onboarded {
    // Read on the pre-runApp path (main.dart), so a wrong-typed stored value must
    // default, never throw — a cast crash here bricks the launch (finishes the C3
    // crash-loop hardening that AppPrefs.load already got).
    if (!Hive.isBoxOpen(HiveBoxes.settings)) return false;
    final v = _box.get(_kOnboarded, defaultValue: false);
    return v is bool ? v : false;
  }

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
