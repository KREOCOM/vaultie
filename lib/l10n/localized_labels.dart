import '../models/subscription.dart';
import 'app_localizations.dart';

/// Localized display label for a [BillingCycle].
String billingCycleLabel(AppLocalizations l, BillingCycle cycle) =>
    switch (cycle) {
      BillingCycle.weekly => l.billingWeekly,
      BillingCycle.monthly => l.billingMonthly,
      BillingCycle.quarterly => l.billingQuarterly,
      BillingCycle.yearly => l.billingYearly,
    };

/// Localized display label for a stored category key.
///
/// Categories are persisted using their canonical English value (see
/// [SubscriptionCategory.all]); this maps that key to the user's language and
/// falls back to the raw key for anything unrecognised.
String categoryLabel(AppLocalizations l, String key) => switch (key) {
      'Streaming' => l.categoryStreaming,
      'Music' => l.categoryMusic,
      'Software' => l.categorySoftware,
      'Gaming' => l.categoryGaming,
      'News' => l.categoryNews,
      'Fitness' => l.categoryFitness,
      'Cloud' => l.categoryCloud,
      'Other' => l.categoryOther,
      _ => key,
    };
