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

// Category labels moved to `expense_categories.dart` (categoryLabel(key, isLt))
// as part of the recurring-expense expansion.
