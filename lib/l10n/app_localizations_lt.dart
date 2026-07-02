// ignore: unused_import
import 'package:intl/intl.dart' as intl;
import 'app_localizations.dart';

// ignore_for_file: type=lint

/// The translations for Lithuanian (`lt`).
class AppLocalizationsLt extends AppLocalizations {
  AppLocalizationsLt([String locale = 'lt']) : super(locale);

  @override
  String get skip => 'Praleisti';

  @override
  String get continueLabel => 'Tęsti';

  @override
  String get getStarted => 'Pradėti';

  @override
  String get onboard1Title => 'Kur dingsta jūsų pinigai?';

  @override
  String get onboard1Body =>
      'Vidutinis žmogus moka už 12 prenumeratų — ir pusę jų pamiršta.';

  @override
  String get onboard2Title => 'Vaultie suras jas visas';

  @override
  String get onboard2Body =>
      'Kiekvienas mokestis tvarkingai nuskaitytas ir sudėtas į vieną vietą.';

  @override
  String get onboard3Title => 'Atgaukite kontrolę';

  @override
  String get onboard3Body =>
      'Matykite, kas artėja, atšaukite, ko nereikia, ir kas mėnesį sutaupykite daugiau.';

  @override
  String get authWelcomeBack => 'Sveiki sugrįžę';

  @override
  String get authCreateVault => 'Sukurkite paskyrą';

  @override
  String get authSignInSubtitle =>
      'Prisijunkite ir matykite savo prenumeratas.';

  @override
  String get authCreateSubtitle => 'Keli duomenys ir Vaultie jūsų.';

  @override
  String get email => 'El. paštas';

  @override
  String get emailEmptyError => 'Įveskite el. paštą';

  @override
  String get emailInvalidError => 'Šis el. paštas atrodo netaisyklingai';

  @override
  String get password => 'Slaptažodis';

  @override
  String get passwordError => 'Bent 6 simboliai';

  @override
  String get signIn => 'Prisijungti';

  @override
  String get createAccount => 'Sukurti paskyrą';

  @override
  String get authToggleToCreate => 'Naujokas? Sukurkite paskyrą';

  @override
  String get authToggleToSignIn => 'Jau turite paskyrą? Prisijunkite';

  @override
  String get monthlySpend => 'Mėnesio išlaidos';

  @override
  String activeSubscriptions(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count aktyvių prenumeratų',
      few: '$count aktyvios prenumeratos',
      one: '$count aktyvi prenumerata',
      zero: 'Nėra aktyvių prenumeratų',
    );
    return '$_temp0';
  }

  @override
  String get viewAnalytics => 'Peržiūrėti analitiką';

  @override
  String get addButton => 'Pridėti';

  @override
  String get renewOverdue => 'Pradelsta';

  @override
  String get renewToday => 'Atsinaujina šiandien';

  @override
  String get renewTomorrow => 'Atsinaujina rytoj';

  @override
  String renewInDays(int days) {
    return 'Atsinaujina po $days d.';
  }

  @override
  String removedFromVault(String name) {
    return '$name pašalinta';
  }

  @override
  String get vaultEmptyTitle => 'Kol kas nėra prenumeratų';

  @override
  String get vaultEmptyBody =>
      'Palieskite „Pridėti“, kad pradėtumėte sekti pirmąją prenumeratą.';

  @override
  String get addSubscriptionTitle => 'Pridėti prenumeratą';

  @override
  String get popularServices => 'Populiarios paslaugos';

  @override
  String get name => 'Pavadinimas';

  @override
  String get nameHint => 'Netflix, Spotify…';

  @override
  String get nameError => 'Įveskite pavadinimą';

  @override
  String get cost => 'Kaina';

  @override
  String get costError => 'Įveskite teisingą kainą';

  @override
  String get billingCycle => 'Atsiskaitymo ciklas';

  @override
  String get category => 'Kategorija';

  @override
  String get nextBillingDate => 'Kita mokėjimo data';

  @override
  String get colour => 'Spalva';

  @override
  String get saveToVault => 'Išsaugoti';

  @override
  String get analyticsTitle => 'Analitika';

  @override
  String get analyticsEmpty =>
      'Pridėkite kelias prenumeratas, kad atrakintumėte išlaidų įžvalgas.';

  @override
  String get perMonth => 'Per mėnesį';

  @override
  String get perYear => 'Per metus';

  @override
  String get slashMonth => '/ mėn.';

  @override
  String get byCategory => 'Pagal kategoriją';

  @override
  String get billingWeekly => 'Kas savaitę';

  @override
  String get billingMonthly => 'Kas mėnesį';

  @override
  String get billingQuarterly => 'Kas ketvirtį';

  @override
  String get billingYearly => 'Kas metus';

  @override
  String get categoryStreaming => 'Transliacijos';

  @override
  String get categoryMusic => 'Muzika';

  @override
  String get categorySoftware => 'Programos';

  @override
  String get categoryGaming => 'Žaidimai';

  @override
  String get categoryNews => 'Naujienos';

  @override
  String get categoryFitness => 'Sportas';

  @override
  String get categoryCloud => 'Debesija';

  @override
  String get categoryOther => 'Kitos';
}
