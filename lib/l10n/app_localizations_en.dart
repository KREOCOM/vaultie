// ignore: unused_import
import 'package:intl/intl.dart' as intl;
import 'app_localizations.dart';

// ignore_for_file: type=lint

/// The translations for English (`en`).
class AppLocalizationsEn extends AppLocalizations {
  AppLocalizationsEn([String locale = 'en']) : super(locale);

  @override
  String get skip => 'Skip';

  @override
  String get continueLabel => 'Continue';

  @override
  String get getStarted => 'Get started';

  @override
  String get onboard1Title => 'Where does your money disappear?';

  @override
  String get onboard1Body =>
      'The average person pays for 12 subscriptions — and forgets about half of them.';

  @override
  String get onboard2Title => 'Vaultie hunts them all down';

  @override
  String get onboard2Body =>
      'Every charge, neatly scanned and sorted in one place.';

  @override
  String get onboard3Title => 'Take back control';

  @override
  String get onboard3Body =>
      'See what is coming, cancel what you do not need, and keep more every month.';

  @override
  String get authWelcomeBack => 'Welcome back';

  @override
  String get authCreateVault => 'Create your account';

  @override
  String get authSignInSubtitle => 'Sign in to see your subscriptions.';

  @override
  String get authCreateSubtitle => 'A few details and Vaultie is yours.';

  @override
  String get email => 'Email';

  @override
  String get emailEmptyError => 'Enter your email';

  @override
  String get emailInvalidError => 'That email looks off';

  @override
  String get password => 'Password';

  @override
  String get passwordError => 'At least 6 characters';

  @override
  String get signIn => 'Sign in';

  @override
  String get createAccount => 'Create account';

  @override
  String get authToggleToCreate => 'New here? Create an account';

  @override
  String get authToggleToSignIn => 'Already have an account? Sign in';

  @override
  String get monthlySpend => 'Monthly spend';

  @override
  String activeSubscriptions(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count active subscriptions',
      one: '1 active subscription',
      zero: 'No active subscriptions',
    );
    return '$_temp0';
  }

  @override
  String get viewAnalytics => 'View analytics';

  @override
  String get addButton => 'Add';

  @override
  String get renewOverdue => 'Overdue';

  @override
  String get renewToday => 'Renews today';

  @override
  String get renewTomorrow => 'Renews tomorrow';

  @override
  String renewInDays(int days) {
    return 'Renews in $days days';
  }

  @override
  String removedFromVault(String name) {
    return '$name removed';
  }

  @override
  String get vaultEmptyTitle => 'Add your first payment';

  @override
  String get vaultEmptyBody =>
      'Rent, insurance, subscriptions — add what you pay for regularly, and we’ll remind you before every one.';

  @override
  String get addSubscriptionTitle => 'Add subscription';

  @override
  String get popularServices => 'Popular services';

  @override
  String get name => 'Name';

  @override
  String get nameHint => 'Netflix, Spotify…';

  @override
  String get nameError => 'Give it a name';

  @override
  String get cost => 'Cost';

  @override
  String get costError => 'Enter a valid cost';

  @override
  String get billingCycle => 'Billing cycle';

  @override
  String get category => 'Category';

  @override
  String get nextBillingDate => 'Next billing date';

  @override
  String get colour => 'Colour';

  @override
  String get saveToVault => 'Save';

  @override
  String get analyticsTitle => 'Analytics';

  @override
  String get analyticsEmpty =>
      'Add a few subscriptions to unlock your spending insights.';

  @override
  String get perMonth => 'Per month';

  @override
  String get perYear => 'Per year';

  @override
  String get slashMonth => '/ month';

  @override
  String get byCategory => 'By category';

  @override
  String get billingWeekly => 'Weekly';

  @override
  String get billingMonthly => 'Monthly';

  @override
  String get billingQuarterly => 'Quarterly';

  @override
  String get billingYearly => 'Yearly';

  @override
  String get categoryStreaming => 'Streaming';

  @override
  String get categoryMusic => 'Music';

  @override
  String get categorySoftware => 'Software';

  @override
  String get categoryGaming => 'Gaming';

  @override
  String get categoryNews => 'News';

  @override
  String get categoryFitness => 'Fitness';

  @override
  String get categoryCloud => 'Cloud';

  @override
  String get categoryOther => 'Other';
}
