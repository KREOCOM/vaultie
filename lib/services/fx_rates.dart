import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:hive_flutter/hive_flutter.dart';

import '../main.dart';

/// A displayable currency: ISO code, human name (LT / EN), and the symbol shown
/// after the amount. The live rate for each comes from [FxRates].
class CurrencyInfo {
  const CurrencyInfo(this.code, this.nameLt, this.nameEn, this.symbol);
  final String code;
  final String nameLt;
  final String nameEn;
  final String symbol;
}

/// The currencies the picker offers — EUR plus the ones the ECB (via Frankfurter)
/// publishes. Real, useful currencies only; the per-currency rate is live from
/// [FxRates.rates]. Crypto is a later phase — the ECB feed has none.
const List<CurrencyInfo> kCurrencies = [
  CurrencyInfo('EUR', 'Euras', 'Euro', '€'),
  CurrencyInfo('USD', 'JAV doleris', 'US Dollar', '\$'),
  CurrencyInfo('GBP', 'Svaras sterlingų', 'British Pound', '£'),
  CurrencyInfo('NOK', 'Norvegijos krona', 'Norwegian Krone', 'kr'),
  CurrencyInfo('SEK', 'Švedijos krona', 'Swedish Krona', 'kr'),
  CurrencyInfo('DKK', 'Danijos krona', 'Danish Krone', 'kr'),
  CurrencyInfo('PLN', 'Lenkijos zlotas', 'Polish Zloty', 'zł'),
  CurrencyInfo('CHF', 'Šveicarijos frankas', 'Swiss Franc', 'CHF'),
  CurrencyInfo('CZK', 'Čekijos krona', 'Czech Koruna', 'Kč'),
  CurrencyInfo('BGN', 'Bulgarijos levas', 'Bulgarian Lev', 'lv'),
  CurrencyInfo('RON', 'Rumunijos lėja', 'Romanian Leu', 'lei'),
  CurrencyInfo('HUF', 'Vengrijos forintas', 'Hungarian Forint', 'Ft'),
  CurrencyInfo('ISK', 'Islandijos krona', 'Icelandic Krona', 'kr'),
  CurrencyInfo('TRY', 'Turkijos lira', 'Turkish Lira', '₺'),
  CurrencyInfo('JPY', 'Japonijos jena', 'Japanese Yen', '¥'),
  CurrencyInfo('CNY', 'Kinijos juanis', 'Chinese Yuan', '¥'),
  CurrencyInfo('AUD', 'Australijos doleris', 'Australian Dollar', '\$'),
  CurrencyInfo('CAD', 'Kanados doleris', 'Canadian Dollar', '\$'),
];

/// Look up the catalog entry for a code, defaulting to EUR when unknown.
CurrencyInfo currencyByCode(String code) {
  final c = code.toUpperCase();
  for (final ci in kCurrencies) {
    if (ci.code == c) return ci;
  }
  return kCurrencies.first;
}

/// Live EUR-based FX rates (ECB daily, via the free, key-less frankfurter.app).
///
/// Amounts across the app are stored in EUR; a display currency is presented by
/// multiplying by `rateFor(code)`. Fails soft: a rate we can't fetch falls back
/// to the last cache, or to EUR-only — money display degrades, never crashes.
class FxRates {
  FxRates._();
  static final FxRates instance = FxRates._();

  static const _kRates = 'fxRates'; // Map<code, EUR->code rate>
  static const _kRatesAt = 'fxRatesAt'; // ISO timestamp of the last good fetch
  static const _url = 'https://api.frankfurter.app/latest?from=EUR';

  /// EUR → code rates; EUR is always 1.0. Widgets can listen to re-render when a
  /// refresh lands.
  final ValueNotifier<Map<String, double>> rates =
      ValueNotifier<Map<String, double>>({'EUR': 1.0});

  Box get _box => Hive.box(HiveBoxes.settings);

  double rateFor(String code) => rates.value[code.toUpperCase()] ?? 1.0;

  /// Load the cached table; refresh in the background when stale (>12h) or
  /// missing. Never awaited on the network — a slow feed must not delay launch.
  Future<void> init() async {
    final cached = _box.get(_kRates);
    if (cached is Map) {
      final m = <String, double>{'EUR': 1.0};
      for (final e in cached.entries) {
        final v = e.value;
        if (v is num) m[e.key.toString()] = v.toDouble();
      }
      if (m.length > 1) rates.value = m;
    }
    final ts = DateTime.tryParse((_box.get(_kRatesAt) as String?) ?? '');
    if (ts == null || DateTime.now().difference(ts) > const Duration(hours: 12)) {
      refresh(); // fire and forget
    }
  }

  Future<void> refresh() async {
    HttpClient? client;
    try {
      client = HttpClient()..connectionTimeout = const Duration(seconds: 8);
      final req = await client.getUrl(Uri.parse(_url));
      final resp = await req.close().timeout(const Duration(seconds: 10));
      if (resp.statusCode != 200) return;
      final body = await resp.transform(utf8.decoder).join();
      final data = jsonDecode(body) as Map<String, dynamic>;
      final raw = (data['rates'] as Map?) ?? const {};
      final r = <String, double>{'EUR': 1.0};
      for (final e in raw.entries) {
        final v = e.value;
        if (v is num && v > 0) r[e.key.toString()] = v.toDouble();
      }
      if (r.length < 2) return; // nothing useful — keep what we have
      rates.value = r;
      await _box.put(_kRates, r);
      await _box.put(_kRatesAt, DateTime.now().toIso8601String());
    } catch (_) {
      // Keep the existing cache (or EUR-only). Display never breaks on this.
    } finally {
      client?.close();
    }
  }
}
