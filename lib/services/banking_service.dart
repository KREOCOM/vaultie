import 'dart:convert';

import 'package:cloud_functions/cloud_functions.dart';
import 'package:flutter/foundation.dart';

import '../models/subscription.dart';

/// Custom-scheme deep link the app itself listens for. The bank redirects to
/// [kBankingRedirectUrl] (an https bridge page), which then forwards to this.
/// Registered in iOS Info.plist and AndroidManifest.
const String kBankingCallbackScheme = 'vaultie';
const String kBankingCallbackHost = 'banking';
const String kBankingCallbackUrl = 'vaultie://banking/callback';

/// The https redirect URL registered with Enable Banking. Custom app schemes
/// aren't accepted as redirect URLs, so the bank returns here; the hosted page
/// at public/banking/callback/index.html forwards to [kBankingCallbackUrl].
const String kBankingRedirectUrl =
    'https://vaultie-1a2c4.web.app/banking/callback';

/// A bank the user can connect (from the `list_banks` endpoint).
class Bank {
  const Bank({required this.name, required this.country, this.logo, this.sandbox = false});

  final String name;
  final String country;
  final String? logo;
  final bool sandbox;

  factory Bank.fromMap(Map<Object?, Object?> m) => Bank(
        name: (m['name'] ?? '') as String,
        country: (m['country'] ?? 'LT') as String,
        logo: m['logo'] as String?,
        sandbox: (m['sandbox'] ?? false) as bool,
      );
}

/// A detected recurring payment returned by `finish_bank_auth`, ready to become
/// a [Subscription] the user can import.
class RecurringCandidate {
  const RecurringCandidate({
    required this.name,
    required this.type,
    this.autoDetected = false,
    required this.cost,
    required this.billingCycle,
    required this.category,
    required this.nextBillingDate,
    required this.occurrences,
    required this.cadenceLabel,
    required this.amountVaries,
    this.needsReview = false,
    this.confident = false,
    this.logoDomain,
  });

  final String name;

  /// Recurring type from detection: `subscription` or `bill`.
  final String type;

  /// True when a known merchant from the DB — pre-selected on the import screen.
  /// False for merchants the user reviews and picks themselves.
  final bool autoDetected;
  final double cost;
  final BillingCycle billingCycle;
  final String category;
  final DateTime nextBillingDate;
  final int occurrences;
  final String cadenceLabel;
  final bool amountVaries;

  /// True when the pattern algorithm (not the whitelist) inferred this, so the
  /// UI should flag it for a second look.
  final bool needsReview;

  /// True when seen ≥2 times — safe to count toward the recurring total and
  /// pre-select on import. Single sightings are shown but left for the user to
  /// confirm (they shouldn't inflate the monthly total).
  final bool confident;
  final String? logoDomain;

  factory RecurringCandidate.fromMap(Map<Object?, Object?> m) {
    return RecurringCandidate(
      name: (m['name'] ?? '') as String,
      type: (m['type'] ?? 'subscription') as String,
      autoDetected: (m['autoDetected'] ?? false) as bool,
      cost: ((m['cost'] ?? 0) as num).toDouble(),
      billingCycle: _cycleFromString((m['billingCycle'] ?? 'monthly') as String),
      category: (m['category'] ?? 'Other') as String,
      nextBillingDate:
          DateTime.tryParse((m['nextBillingDate'] ?? '') as String) ?? DateTime.now(),
      occurrences: ((m['occurrences'] ?? 0) as num).toInt(),
      cadenceLabel: (m['cadenceLabel'] ?? '') as String,
      amountVaries: (m['amountVaries'] ?? false) as bool,
      needsReview: (m['needsReview'] ?? false) as bool,
      confident: (m['confident'] ?? false) as bool,
      logoDomain: m['logoDomain'] as String?,
    );
  }

  /// Turns this candidate into a persisted [Subscription]. [id] must be unique.
  /// [categoryOverride] lets the importer store the classifier's refined
  /// category instead of the thin backend guess.
  Subscription toSubscription(String id, {String? categoryOverride}) =>
      Subscription(
        id: id,
        name: name,
        cost: cost,
        billingCycle: billingCycle,
        category: categoryOverride ?? category,
        nextBillingDate: nextBillingDate,
        // Variable-amount bills (utilities etc.) are marked as estimates.
        isEstimated: amountVaries,
        logoDomain: logoDomain,
      );
}

/// A frequent-spending merchant (fast food, groceries…). Never recurring — the
/// bank scan surfaces these for the feed only, not as importable subscriptions.
class FrequentMerchant {
  const FrequentMerchant({
    required this.name,
    required this.category,
    required this.occurrences,
    required this.totalSpent,
    this.logoDomain,
  });

  final String name;
  final String category;
  final int occurrences;
  final double totalSpent;
  final String? logoDomain;

  factory FrequentMerchant.fromMap(Map<Object?, Object?> m) => FrequentMerchant(
        name: (m['name'] ?? '') as String,
        category: (m['category'] ?? 'other') as String,
        occurrences: ((m['occurrences'] ?? 0) as num).toInt(),
        totalSpent: ((m['totalSpent'] ?? 0) as num).toDouble(),
        logoDomain: m['logoDomain'] as String?,
      );
}

/// Result of a bank scan: importable recurring candidates + frequent-spending
/// merchants surfaced for information only.
class BankScanResult {
  const BankScanResult({required this.candidates, required this.frequent, this.dash});
  final List<RecurringCandidate> candidates;
  final List<FrequentMerchant> frequent;

  /// Full dashboard payload (every transaction classified + feed/week/subs/
  /// balance) for the new dashboard. Null if the backend couldn't build it.
  final Map<String, dynamic>? dash;
}

BillingCycle _cycleFromString(String s) => switch (s) {
      'weekly' => BillingCycle.weekly,
      'quarterly' => BillingCycle.quarterly,
      'yearly' => BillingCycle.yearly,
      _ => BillingCycle.monthly,
    };

/// Thrown when a banking Cloud Function call fails; carries a user-safe message.
class BankingException implements Exception {
  BankingException(this.message);
  final String message;
  @override
  String toString() => message;
}

/// Talks to the Enable Banking Cloud Functions. All calls require a signed-in
/// Firebase user (the callable transport attaches the auth token automatically).
class BankingService {
  BankingService._();
  static final BankingService instance = BankingService._();

  // Functions are deployed to europe-west1 — the region MUST match or the call
  // 404s. See functions/main.py.
  final FirebaseFunctions _functions =
      FirebaseFunctions.instanceFor(region: 'europe-west1');

  Future<T> _call<T>(String name, Map<String, dynamic> data,
      T Function(Map<Object?, Object?>) parse, {Duration? timeout}) async {
    try {
      final callable = timeout != null
          ? _functions.httpsCallable(name,
              options: HttpsCallableOptions(timeout: timeout))
          : _functions.httpsCallable(name);
      final res = await callable.call(data);
      return parse((res.data as Map).cast<Object?, Object?>());
    } on FirebaseFunctionsException catch (e) {
      throw BankingException(e.message ?? 'Something went wrong. Please try again.');
    } catch (_) {
      throw BankingException('Could not reach the server. Check your connection.');
    }
  }

  /// Banks the user can connect for [country] (default LT).
  Future<List<Bank>> listBanks({String country = 'LT'}) {
    return _call('list_banks', {'country': country}, (m) {
      final list = (m['banks'] as List?) ?? const [];
      if (kDebugMode) {
        debugPrint('=== LIST_BANKS ($country): ${list.length} banks ===');
        for (final b in list) {
          debugPrint('  BANK $b');
        }
      }
      return [
        for (final b in list) Bank.fromMap((b as Map).cast<Object?, Object?>()),
      ];
    });
  }

  /// Begins consent for [bankName]; returns the bank's authorization URL to open.
  Future<String> startBankAuth(String bankName, {String country = 'LT'}) {
    return _call(
        'start_bank_auth',
        {
          'aspspName': bankName,
          'country': country,
          'redirectUrl': kBankingRedirectUrl,
        },
        (m) => (m['url'] ?? '') as String);
  }

  /// Exchanges the redirect [code] for the scan result: importable recurring
  /// candidates plus frequent-spending merchants (never recurring, feed-only).
  Future<BankScanResult> finishBankAuth(String code, {bool aiEnrichment = false}) {
    return _call('finish_bank_auth',
        // AI enrichment OFF: it depends on ANTHROPIC_API_KEY, which firebase's
        // discovery keeps dropping from the deployed secrets, so accessing it is
        // fragile. It's meant to be opt-in/off before launch anyway, and the KB
        // classifies the vast majority without it. 6-month window (fits the 60s
        // timeout firebase resets the function to).
        {'code': code, 'debug': kDebugMode, 'aiEnrichment': false,
         'monthsBack': 6}, (m) {
      final cands = (m['candidates'] as List?) ?? const [];
      final freq = (m['frequent'] as List?) ?? const [];
      if (kDebugMode) {
        final report = (m['debugReport'] as List?) ?? const [];
        for (final line in report) {
          debugPrint('DIAG| $line');
        }
        debugPrint('=== BANK SCAN RESULT ===');
        debugPrint('accounts=${m['accountCount']} txns=${m['transactionCount']} '
            'candidates=${cands.length} frequent=${freq.length} '
            'dash=${m['dash'] != null}');
        debugPrint('SCAN DIAG: ${m['scanDiag']}');
        final dashMap = m['dash'];
        if (dashMap is Map && dashMap['meta'] is Map) {
          final meta = dashMap['meta'] as Map;
          debugPrint('CLASS SAMPLE: ${meta['sample']}');
          debugPrint('SALARY SOURCES: ${meta['salarySources']}');
          debugPrint('INCOME: ${meta['income']}');
          debugPrint('INCOMING TRANSFERS: ${meta['incomingTransfers']}');
        }
        for (final c in cands) {
          debugPrint('  CANDIDATE $c');
        }
        for (final f in freq) {
          debugPrint('  FREQUENT $f');
        }
      }
      // Deep-convert the nested dashboard map (Firebase hands back
      // Map<Object?,Object?>) into a clean Map<String,dynamic> via a JSON
      // round-trip, so the dashboard's typed `.cast<Map<String,dynamic>>()`
      // access works.
      Map<String, dynamic>? dash;
      final rawDash = m['dash'];
      if (rawDash != null) {
        try {
          dash = jsonDecode(jsonEncode(rawDash)) as Map<String, dynamic>;
        } catch (_) {
          dash = null;
        }
      }
      return BankScanResult(
        candidates: [
          for (final c in cands)
            RecurringCandidate.fromMap((c as Map).cast<Object?, Object?>()),
        ],
        frequent: [
          for (final f in freq)
            FrequentMerchant.fromMap((f as Map).cast<Object?, Object?>()),
        ],
        dash: dash,
      );
      // The 12-month windowed scan can take well over the default ~70s callable
      // timeout on a cold start, so give it a generous ceiling.
    }, timeout: const Duration(minutes: 5));
  }

  /// Extracts the `code` query parameter from an incoming callback [uri], or
  /// null if this isn't our banking callback.
  ///
  /// Accepts two forms:
  ///  * the Universal Link — `https://vaultie-1a2c4.web.app/banking/callback?code=…`
  ///    — which opens the app directly with no "Open in Vaultie?" prompt (the
  ///    happy path once Associated Domains + AASA are live), and
  ///  * the custom-scheme fallback — `vaultie://banking/callback?code=…` — used
  ///    when the app isn't installed or the Universal Link doesn't fire.
  static String? codeFromCallback(Uri uri) {
    final isCustomScheme = uri.scheme == kBankingCallbackScheme &&
        uri.host == kBankingCallbackHost;
    // Recognise the Universal Link off the same source of truth as the
    // registered redirect, so host/path can't drift out of sync.
    final redirect = Uri.parse(kBankingRedirectUrl);
    final isUniversalLink = uri.scheme == redirect.scheme &&
        uri.host == redirect.host &&
        uri.path.startsWith(redirect.path);
    if (!isCustomScheme && !isUniversalLink) return null;
    return uri.queryParameters['code'];
  }
}
