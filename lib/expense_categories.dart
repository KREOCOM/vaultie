import 'package:flutter/material.dart';

import 'models/subscription.dart';

/// A top-level category for any recurring expense (not just subscriptions).
///
/// The [key] is the stable string persisted in [Subscription.category]; it must
/// never change once shipped. Everything else (icon, colour, default cycle,
/// label, suggestions) is presentation and can evolve freely.
class ExpenseCategory {
  const ExpenseCategory({
    required this.key,
    required this.icon,
    required this.color,
    required this.defaultCycle,
  });

  final String key;
  final IconData icon;
  final Color color;
  final BillingCycle defaultCycle;

  String label(bool isLt) => categoryLabel(key, isLt);
  List<String> suggestions(bool isLt) => categorySuggestions(key, isLt);
}

/// The flat category set shown in the picker. Order is the grid order.
const List<ExpenseCategory> kExpenseCategories = [
  ExpenseCategory(
    key: 'housing',
    icon: Icons.home_rounded,
    color: Color(0xFF2E7D4F),
    defaultCycle: BillingCycle.monthly,
  ),
  ExpenseCategory(
    key: 'utilities',
    icon: Icons.bolt_rounded,
    color: Color(0xFFE9A23B),
    defaultCycle: BillingCycle.monthly,
  ),
  ExpenseCategory(
    key: 'connectivity',
    icon: Icons.wifi_rounded,
    color: Color(0xFF29B6F6),
    defaultCycle: BillingCycle.monthly,
  ),
  ExpenseCategory(
    key: 'insurance',
    icon: Icons.shield_rounded,
    color: Color(0xFF4A6FA5),
    defaultCycle: BillingCycle.monthly,
  ),
  ExpenseCategory(
    key: 'transport',
    icon: Icons.directions_car_rounded,
    color: Color(0xFF7E57C2),
    defaultCycle: BillingCycle.monthly,
  ),
  ExpenseCategory(
    key: 'health',
    icon: Icons.favorite_rounded,
    color: Color(0xFFEC407A),
    defaultCycle: BillingCycle.monthly,
  ),
  ExpenseCategory(
    key: 'entertainment',
    icon: Icons.play_circle_fill_rounded,
    color: Color(0xFFE53935),
    defaultCycle: BillingCycle.monthly,
  ),
  ExpenseCategory(
    key: 'finance',
    icon: Icons.account_balance_rounded,
    color: Color(0xFF00897B),
    defaultCycle: BillingCycle.monthly,
  ),
  ExpenseCategory(
    key: 'education',
    icon: Icons.school_rounded,
    color: Color(0xFF5C6BC0),
    defaultCycle: BillingCycle.monthly,
  ),
  ExpenseCategory(
    key: 'other',
    icon: Icons.receipt_long_rounded,
    color: Color(0xFF8A968F),
    defaultCycle: BillingCycle.monthly,
  ),
];

/// Legacy subscription-only category keys (shipped before the expense
/// expansion) mapped onto the new taxonomy, so existing records render with a
/// sensible icon and group correctly. Stored values are left untouched.
const Map<String, String> _legacyKeys = {
  'Streaming': 'entertainment',
  'Music': 'entertainment',
  'Gaming': 'entertainment',
  'News': 'entertainment',
  'Software': 'other',
  'Cloud': 'other',
  'Fitness': 'health',
  'Other': 'other',
};

const ExpenseCategory _fallback = ExpenseCategory(
  key: 'other',
  icon: Icons.receipt_long_rounded,
  color: Color(0xFF8A968F),
  defaultCycle: BillingCycle.monthly,
);

/// Resolves any stored category string (new key or legacy value) to its
/// canonical taxonomy key.
String normalizeCategoryKey(String key) {
  if (_legacyKeys.containsKey(key)) return _legacyKeys[key]!;
  final known = kExpenseCategories.any((c) => c.key == key);
  return known ? key : 'other';
}

/// The [ExpenseCategory] for any stored category string, never null.
ExpenseCategory categoryFor(String key) {
  final norm = normalizeCategoryKey(key);
  for (final c in kExpenseCategories) {
    if (c.key == norm) return c;
  }
  return _fallback;
}

/// Localized category name for a stored key (new or legacy).
String categoryLabel(String key, bool isLt) => switch (normalizeCategoryKey(key)) {
      'housing' => isLt ? 'Būstas' : 'Housing',
      'utilities' => isLt ? 'Komunaliniai' : 'Utilities',
      'connectivity' => isLt ? 'Internetas ir telefonas' : 'Internet & phone',
      'insurance' => isLt ? 'Draudimas' : 'Insurance',
      'transport' => isLt ? 'Transportas' : 'Transport',
      'health' => isLt ? 'Sveikata ir sportas' : 'Health & fitness',
      'entertainment' =>
        isLt ? 'Pramogos ir prenumeratos' : 'Entertainment & subscriptions',
      'finance' => isLt ? 'Finansai' : 'Finance',
      'education' => isLt ? 'Švietimas' : 'Education',
      _ => isLt ? 'Kita' : 'Other',
    };

/// Name-suggestion chips shown after a category is picked, to fill the name in
/// one tap. Empty for categories with no obvious presets.
List<String> categorySuggestions(String key, bool isLt) =>
    switch (normalizeCategoryKey(key)) {
      'housing' => isLt
          ? ['Nuoma', 'Būsto paskola', 'Komunaliniai mokesčiai']
          : ['Rent', 'Mortgage', 'HOA fees'],
      'utilities' => isLt
          ? ['Elektra', 'Dujos', 'Vanduo', 'Šildymas', 'Šiukšlės']
          : ['Electricity', 'Gas', 'Water', 'Heating', 'Waste'],
      'connectivity' => isLt
          ? ['Internetas', 'Mobilusis', 'Kabelinė TV']
          : ['Internet', 'Mobile phone', 'Cable TV'],
      'insurance' => isLt
          ? ['Automobilio', 'Būsto', 'Sveikatos', 'Gyvybės']
          : ['Car', 'Home', 'Health', 'Life'],
      'transport' => isLt
          ? ['Parkavimas', 'Viešasis transportas', 'Kuras', 'Automobilio paskola']
          : ['Parking', 'Transit pass', 'Fuel', 'Car loan'],
      'health' => isLt
          ? ['Sporto klubas', 'Odontologas', 'Terapija']
          : ['Gym', 'Dentist', 'Therapy'],
      'finance' => isLt
          ? ['Paskola', 'Kredito kortelė', 'Investicijos']
          : ['Loan', 'Credit card', 'Investing'],
      'education' => isLt
          ? ['Kursai', 'Mokslas', 'Kalbų programa']
          : ['Course', 'Tuition', 'Language app'],
      _ => const [],
    };
