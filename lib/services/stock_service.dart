import 'package:cloud_functions/cloud_functions.dart';
import 'package:flutter/foundation.dart';

/// Client for the stock_quote/stock_search/stock_profile Cloud Functions —
/// see functions/stock_quote.py's own docstring for the provider (Finnhub,
/// free tier) and why there's no price-history chart right now.
///
/// PROTOTYPE (2026-08-27), isolated on purpose: this file, stock_quote.py,
/// its registrations in main.py, and investing_tab.dart are the whole
/// feature. Nothing outside those touches this class.
class StockService {
  StockService._();
  static final StockService instance = StockService._();

  final FirebaseFunctions _functions =
      FirebaseFunctions.instanceFor(region: 'europe-west1');

  /// {"price","prevClose","open","high","low": double} or null on any
  /// failure — caller shows a "couldn't load a price" state, never a crash.
  /// open/high/low are TODAY's real values (free on Finnhub's tier) — used
  /// for the portfolio hero's "since market open" chart, see investing_tab.
  Future<Map<String, dynamic>?> quote(String symbol) async {
    try {
      final res =
          await _functions.httpsCallable('stock_quote').call({'symbol': symbol});
      final data = Map<String, dynamic>.from(res.data as Map);
      final price = (data['price'] as num?)?.toDouble() ?? 0.0;
      return {
        'price': price,
        'prevClose': (data['prevClose'] as num?)?.toDouble() ?? 0.0,
        'open': (data['open'] as num?)?.toDouble() ?? price,
        'high': (data['high'] as num?)?.toDouble() ?? price,
        'low': (data['low'] as num?)?.toDouble() ?? price,
      };
    } catch (e) {
      if (kDebugMode) debugPrint('StockService.quote($symbol) failed: $e');
      return null;
    }
  }

  /// Live global ticker search (any stock, not a fixed list) — [{'symbol','name'}],
  /// empty on any failure or empty query.
  Future<List<Map<String, String>>> search(String query) async {
    if (query.trim().isEmpty) return const [];
    try {
      final res =
          await _functions.httpsCallable('stock_search').call({'query': query});
      final data = Map<String, dynamic>.from(res.data as Map);
      final results = (data['results'] as List?) ?? const [];
      return results
          .map((e) => Map<String, dynamic>.from(e as Map))
          .map((e) => {
                'symbol': (e['symbol'] as String?) ?? '',
                'name': (e['name'] as String?) ?? '',
              })
          .where((e) => e['symbol']!.isNotEmpty)
          .toList();
    } catch (e) {
      if (kDebugMode) debugPrint('StockService.search($query) failed: $e');
      return const [];
    }
  }

  /// The real brand domain (e.g. "apple.com") for CategoryIcon's existing
  /// merchant-logo proxy — called ONCE when a search result is picked, not
  /// per row. Null on any failure (caller falls back to a generic icon).
  Future<String?> domainFor(String symbol) async {
    try {
      final res =
          await _functions.httpsCallable('stock_profile').call({'symbol': symbol});
      final data = Map<String, dynamic>.from(res.data as Map);
      final domain = data['domain'] as String?;
      return (domain != null && domain.isNotEmpty) ? domain : null;
    } catch (e) {
      if (kDebugMode) debugPrint('StockService.domainFor($symbol) failed: $e');
      return null;
    }
  }
}
