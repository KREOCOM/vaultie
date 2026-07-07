import 'package:cloud_functions/cloud_functions.dart';

import '../models/subscription.dart';

/// Custom-scheme URL the bank redirects back to after consent.
/// Registered in iOS Info.plist and AndroidManifest, and (to be) registered in
/// the Enable Banking control panel.
const String kBankingCallbackScheme = 'vaultie';
const String kBankingCallbackHost = 'banking';
const String kBankingCallbackUrl = 'vaultie://banking/callback';

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
    required this.cost,
    required this.billingCycle,
    required this.category,
    required this.nextBillingDate,
    required this.occurrences,
    required this.cadenceLabel,
    required this.amountVaries,
    this.logoDomain,
  });

  final String name;
  final double cost;
  final BillingCycle billingCycle;
  final String category;
  final DateTime nextBillingDate;
  final int occurrences;
  final String cadenceLabel;
  final bool amountVaries;
  final String? logoDomain;

  factory RecurringCandidate.fromMap(Map<Object?, Object?> m) {
    return RecurringCandidate(
      name: (m['name'] ?? '') as String,
      cost: ((m['cost'] ?? 0) as num).toDouble(),
      billingCycle: _cycleFromString((m['billingCycle'] ?? 'monthly') as String),
      category: (m['category'] ?? 'Other') as String,
      nextBillingDate:
          DateTime.tryParse((m['nextBillingDate'] ?? '') as String) ?? DateTime.now(),
      occurrences: ((m['occurrences'] ?? 0) as num).toInt(),
      cadenceLabel: (m['cadenceLabel'] ?? '') as String,
      amountVaries: (m['amountVaries'] ?? false) as bool,
      logoDomain: m['logoDomain'] as String?,
    );
  }

  /// Turns this candidate into a persisted [Subscription]. [id] must be unique.
  Subscription toSubscription(String id) => Subscription(
        id: id,
        name: name,
        cost: cost,
        billingCycle: billingCycle,
        category: category,
        nextBillingDate: nextBillingDate,
        // Variable-amount bills (utilities etc.) are marked as estimates.
        isEstimated: amountVaries,
        logoDomain: logoDomain,
      );
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
      T Function(Map<Object?, Object?>) parse) async {
    try {
      final res = await _functions.httpsCallable(name).call(data);
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
      return [
        for (final b in list) Bank.fromMap((b as Map).cast<Object?, Object?>()),
      ];
    });
  }

  /// Begins consent for [bankName]; returns the bank's authorization URL to open.
  Future<String> startBankAuth(String bankName, {String country = 'LT'}) {
    return _call('start_bank_auth', {'aspspName': bankName, 'country': country},
        (m) => (m['url'] ?? '') as String);
  }

  /// Exchanges the redirect [code] for detected recurring-payment candidates.
  Future<List<RecurringCandidate>> finishBankAuth(String code) {
    return _call('finish_bank_auth', {'code': code}, (m) {
      final list = (m['candidates'] as List?) ?? const [];
      return [
        for (final c in list)
          RecurringCandidate.fromMap((c as Map).cast<Object?, Object?>()),
      ];
    });
  }

  /// Extracts the `code` query parameter from an incoming callback [uri], or
  /// null if this isn't our banking callback.
  static String? codeFromCallback(Uri uri) {
    final isCallback = uri.scheme == kBankingCallbackScheme &&
        uri.host == kBankingCallbackHost;
    if (!isCallback) return null;
    return uri.queryParameters['code'];
  }
}
