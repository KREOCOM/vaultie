import 'package:flutter/material.dart';

import '../main.dart';

/// A simple scrollable legal document screen (Privacy Policy / Terms of Use).
///
/// Content lives in-app so the Settings links always open something real — a
/// requirement for App Review. Text is bilingual (LT/EN) and intentionally
/// template-grade: review/adjust with your own details before release.
class LegalScreen extends StatelessWidget {
  const LegalScreen({
    super.key,
    required this.title,
    required this.updated,
    required this.intro,
    required this.sections,
  });

  final String title;
  final String updated;
  final String intro;
  final List<LegalSection> sections;

  static const _contactEmail = 'osva50042@gmail.com';

  factory LegalScreen.privacy(bool isLt) {
    return LegalScreen(
      title: isLt ? 'Privatumo politika' : 'Privacy Policy',
      updated: isLt ? 'Atnaujinta: 2026-07-07' : 'Last updated: 2026-07-07',
      intro: isLt
          ? 'Vaultie gerbia tavo privatumą. Ši politika paaiškina, kokius duomenis renkame, kaip juos naudojame ir kokias teises turi.'
          : 'Vaultie respects your privacy. This policy explains what data we collect, how we use it, and the choices you have.',
      sections: [
        LegalSection(
          isLt ? 'Kokius duomenis renkame' : 'Data we collect',
          isLt
              ? 'Susikuriant paskyrą renkame tavo el. pašto adresą (per Firebase '
                  'Authentication — el. paštas, „Google" arba „Apple"). '
                  'Prenumeratų duomenys (pavadinimai, kainos, datos) saugomi tik '
                  'lokaliai tavo įrenginyje. Kai perki „Vaultie Pro", mūsų '
                  'teikėjas „RevenueCat" apdoroja „App Store" pirkimą, kad '
                  'atrakintų prieigą.'
              : 'When you create an account we collect your email address (via '
                  'Firebase Authentication — email/password, Google, or Apple). '
                  'Your subscription data (names, prices, dates) is stored '
                  'locally on your device only. When you buy Vaultie Pro, our '
                  'provider RevenueCat processes your App Store purchase to '
                  'unlock your entitlement. If you choose to connect a bank '
                  '(an optional Pro feature), we access your account information — '
                  'see "Bank connection" below.',
        ),
        LegalSection(
          isLt ? 'Banko prijungimas (atviroji bankininkystė)' : 'Bank connection (Open Banking)',
          isLt
              ? 'Banko prijungimas yra neprivaloma „Vaultie Pro" funkcija. Jei ją '
                  'naudoji, per licencijuotą atviros bankininkystės teikėją '
                  '„Enable Banking" (veikiantį pagal PSD2) su tavo aiškiu sutikimu '
                  'gauname tavo sąskaitos informaciją: sąskaitų duomenis, likučius '
                  'ir operacijų istoriją. Tai naudojame tik pasikartojantiems '
                  'mokėjimams aptikti. Prisijungi ir patvirtini prieigą savo banko '
                  'puslapyje — mes niekada nematome tavo banko slaptažodžio. '
                  'Operacijos apdorojamos laikinai mūsų serveryje (Firebase Cloud '
                  'Functions) ir NĖRA saugomos; įrenginyje išsaugomi tik tie '
                  'pasikartojantys mokėjimai, kuriuos pats pasirenki importuoti. '
                  'Sutikimas galioja ribotą laiką ir gali būti bet kada atšauktas '
                  'per savo banką arba nustojus naudotis funkcija.'
              : 'Connecting a bank is an optional Vaultie Pro feature. If you use '
                  'it, we access your account information through Enable Banking, a '
                  'licensed open-banking provider operating under PSD2, with your '
                  'explicit consent: account details, balances, and transaction '
                  'history. We use this solely to detect your recurring payments. '
                  'You sign in and approve access on your bank\'s own page — we '
                  'never see your bank password. Transactions are processed '
                  'transiently on our server (Firebase Cloud Functions) and are '
                  'NOT stored; only the recurring payments you choose to import are '
                  'saved on your device. Consent is time-limited and can be '
                  'revoked at any time through your bank or by no longer using the '
                  'feature.',
        ),
        LegalSection(
          isLt ? 'Kaip naudojame duomenis' : 'How we use your data',
          isLt
              ? 'El. paštą naudojame prisijungimui, paskyros patvirtinimui ir svarbiems pranešimams. Prenumeratų duomenys naudojami priminimams ir išlaidų apžvalgai tavo įrenginyje.'
              : 'We use your email to sign you in, verify your account, and send essential account messages. Subscription data powers reminders and spending insights on your device.',
        ),
        LegalSection(
          isLt ? 'Trečiosios šalys' : 'Third parties',
          isLt
              ? 'Autentifikacijai naudojame Google Firebase ir „Sign in with '
                  'Apple" (jei pasirenki). Programinius pirkimus tvarko '
                  '„RevenueCat", gaunantis tavo „App Store" operacijų duomenis. '
                  'Jei prijungi banką, „Enable Banking" (licencijuotas PSD2 '
                  'teikėjas) saugiai gauna tavo sąskaitos duomenis mūsų vardu. '
                  'Prekių ženklų logotipai užkraunami iš Google favicon paslaugos '
                  'pagal iš pavadinimo atspėtą domeną, todėl tavo sekamos '
                  'paslaugos matomos „Google" šiose užklausose. Neparduodame tavo '
                  'duomenų.'
              : 'We use Google Firebase for authentication, plus Sign in with '
                  'Apple if you choose it. In-app purchases are handled by '
                  'RevenueCat, which receives your App Store transaction data. '
                  'If you connect a bank, Enable Banking (a licensed PSD2 provider) '
                  'securely retrieves your account data on our behalf. Brand logos '
                  'are fetched from Google\'s favicon service using a domain '
                  'guessed from each subscription\'s name, so the services you '
                  'track are visible to Google in those requests. We do not sell '
                  'your data.',
        ),
        LegalSection(
          isLt ? 'Pranešimai' : 'Notifications',
          isLt
              ? 'Su tavo sutikimu siunčiame vietinius pranešimus prieš prenumeratų atsinaujinimą. Juos gali išjungti nustatymuose arba įrenginio nustatymuose.'
              : 'With your permission we send local notifications before subscriptions renew. You can turn these off in Settings or your device settings.',
        ),
        LegalSection(
          isLt ? 'Duomenų ištrynimas' : 'Data deletion',
          isLt
              ? 'Paskyrą ir su ja susietą el. paštą gali ištrinti bet kada per Nustatymai → Ištrinti paskyrą. Prenumeratų duomenys pašalinami išdiegus programą. Banko prieigą gali atšaukti bet kada savo banke; mes nesaugome tavo banko operacijų.'
              : 'You can delete your account and its email at any time via Settings → Delete account. Subscription data is removed when you uninstall the app. You can revoke bank access at any time through your bank; we do not store your bank transactions.',
        ),
        LegalSection(
          isLt ? 'Vaikai' : 'Children',
          isLt
              ? 'Vaultie neskirta jaunesniems nei 13 metų vartotojams.'
              : 'Vaultie is not intended for users under 13 years of age.',
        ),
        LegalSection(
          isLt ? 'Susisiekimas' : 'Contact',
          isLt
              ? 'Klausimais dėl privatumo rašyk: $_contactEmail'
              : 'For privacy questions, contact us at $_contactEmail',
        ),
      ],
    );
  }

  factory LegalScreen.terms(bool isLt) {
    return LegalScreen(
      title: isLt ? 'Naudojimo sąlygos' : 'Terms of Use',
      updated: isLt ? 'Atnaujinta: 2026-07-07' : 'Last updated: 2026-07-07',
      intro: isLt
          ? 'Naudodamasis Vaultie sutinki su šiomis sąlygomis. Jei nesutinki, programos nenaudok.'
          : 'By using Vaultie you agree to these terms. If you do not agree, please do not use the app.',
      sections: [
        LegalSection(
          isLt ? 'Paslauga' : 'The service',
          isLt
              ? 'Vaultie – prenumeratų sekimo programa, padedanti stebėti pasikartojančias išlaidas ir gauti priminimus. Neprivaloma „Vaultie Pro" funkcija leidžia prijungti banką per licencijuotą PSD2 teikėją „Enable Banking" ir automatiškai aptikti pasikartojančius mokėjimus (tik skaitymui — mokėjimų neinicijuojame). Vaultie teikia informaciją, o ne finansines konsultacijas.'
              : 'Vaultie is a subscription tracker that helps you monitor recurring costs and get reminders. An optional Vaultie Pro feature lets you connect a bank via Enable Banking, a licensed PSD2 provider, to automatically detect recurring payments (read-only — we do not initiate payments). Vaultie provides information, not financial advice.',
        ),
        LegalSection(
          isLt ? 'Paskyra' : 'Your account',
          isLt
              ? 'Esi atsakingas už savo prisijungimo duomenų saugumą ir už veiklą savo paskyroje. Pateik tikslų el. pašto adresą.'
              : 'You are responsible for keeping your credentials secure and for activity under your account. Provide an accurate email address.',
        ),
        LegalSection(
          isLt ? 'Priimtinas naudojimas' : 'Acceptable use',
          isLt
              ? 'Nesinaudok programa neteisėtiems tikslams ir nebandyk trikdyti jos veikimo ar saugumo.'
              : 'Do not use the app for unlawful purposes or attempt to disrupt its operation or security.',
        ),
        LegalSection(
          isLt ? 'Prenumeratos ir mokėjimai' : 'Subscriptions & payments',
          isLt
              ? 'Vaultie nemokama iki penkių prenumeratų. Vaultie Pro atrakina '
                  'neribotą prenumeratų skaičių kaip mėnesinę automatiškai '
                  'atsinaujinančią prenumeratą (3,99 €/mėn.) arba vienkartinį '
                  '„Visam laikui" pirkimą (29,99 €). Pirkimus tvarko „Apple App '
                  'Store" ir jie nuskaičiuojami iš „Apple ID"; kainos parodomos '
                  'prieš pirkimą ir gali skirtis pagal regioną. Mėnesinė '
                  'prenumerata atsinaujina automatiškai, nebent atšaukiama likus '
                  'ne mažiau kaip 24 val. iki laikotarpio pabaigos. Valdyti ar '
                  'atšaukti galima bet kada „App Store" nustatymuose → jūsų '
                  'vardas → Prenumeratos; programos ištrynimas jos neatšaukia. '
                  'Grąžinimams taikomos „Apple" taisyklės ir įstatymai.'
              : 'Vaultie is free for up to five subscriptions. Vaultie Pro '
                  'unlocks unlimited subscriptions as a monthly auto-renewable '
                  'subscription (€3.99/month) or a one-time Lifetime purchase '
                  '(€29.99). Purchases are processed by the Apple App Store and '
                  'charged to your Apple ID; prices are shown before you buy and '
                  'may vary by region. The monthly subscription renews '
                  'automatically unless cancelled at least 24 hours before the '
                  'end of the current period. Manage or cancel anytime in App '
                  'Store settings → your name → Subscriptions; deleting the app '
                  'does not cancel it. Refunds are subject to Apple\'s policies '
                  'and applicable law.',
        ),
        LegalSection(
          isLt ? 'Atsakomybės ribojimas' : 'Disclaimer',
          isLt
              ? 'Vaultie teikiama „tokia, kokia yra". Neatsakome už praleistus mokėjimus ar sprendimus, priimtus remiantis programos duomenimis. Visada pasitikrink oficialiuose paslaugų šaltiniuose.'
              : 'Vaultie is provided "as is". We are not liable for missed payments or decisions made based on the app\'s data. Always verify with the official service providers.',
        ),
        LegalSection(
          isLt ? 'Pakeitimai' : 'Changes',
          isLt
              ? 'Šias sąlygas galime atnaujinti. Toliau naudodamasis programa sutinki su atnaujinta versija.'
              : 'We may update these terms. Continued use of the app means you accept the updated version.',
        ),
        LegalSection(
          isLt ? 'Susisiekimas' : 'Contact',
          isLt
              ? 'Klausimais rašyk: $_contactEmail'
              : 'Questions? Contact us at $_contactEmail',
        ),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        backgroundColor: VaultieColors.primary,
        foregroundColor: Colors.white,
        elevation: 0,
        title: Text(title),
      ),
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.all(24),
          children: [
            Text(
              updated,
              style: const TextStyle(
                color: VaultieColors.subtle,
                fontSize: 13,
              ),
            ),
            const SizedBox(height: 16),
            Text(
              intro,
              style: const TextStyle(
                fontSize: 15,
                height: 1.5,
                color: VaultieColors.ink,
              ),
            ),
            const SizedBox(height: 24),
            for (final s in sections) ...[
              Text(
                s.heading,
                style: const TextStyle(
                  fontSize: 17,
                  fontWeight: FontWeight.w700,
                  color: VaultieColors.ink,
                ),
              ),
              const SizedBox(height: 6),
              Text(
                s.body,
                style: const TextStyle(
                  fontSize: 15,
                  height: 1.5,
                  color: VaultieColors.subtle,
                ),
              ),
              const SizedBox(height: 20),
            ],
          ],
        ),
      ),
    );
  }
}

class LegalSection {
  const LegalSection(this.heading, this.body);
  final String heading;
  final String body;
}
