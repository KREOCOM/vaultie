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

  static const _contactEmail = 'support@vaultie.app';

  factory LegalScreen.privacy(bool isLt) {
    return LegalScreen(
      title: isLt ? 'Privatumo politika' : 'Privacy Policy',
      updated: isLt ? 'Atnaujinta: 2026-07-02' : 'Last updated: 2026-07-02',
      intro: isLt
          ? 'Vaultie gerbia tavo privatumą. Ši politika paaiškina, kokius duomenis renkame, kaip juos naudojame ir kokias teises turi.'
          : 'Vaultie respects your privacy. This policy explains what data we collect, how we use it, and the choices you have.',
      sections: [
        LegalSection(
          isLt ? 'Kokius duomenis renkame' : 'Data we collect',
          isLt
              ? 'Susikuriant paskyrą renkame tavo el. pašto adresą (per Firebase Authentication). Prenumeratų duomenys (pavadinimai, kainos, datos) saugomi tik lokaliai tavo įrenginyje.'
              : 'When you create an account we collect your email address (via Firebase Authentication). Your subscription data (names, prices, dates) is stored locally on your device only.',
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
              ? 'Autentifikacijai naudojame Google Firebase. Prekių ženklų logotipai užkraunami per Google favicon paslaugą pagal paslaugos pavadinimą. Neparduodame tavo duomenų.'
              : 'We use Google Firebase for authentication. Brand logos are loaded via the Google favicon service based on the service name. We do not sell your data.',
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
              ? 'Paskyrą ir su ja susietą el. paštą gali ištrinti bet kada per Nustatymai → Ištrinti paskyrą. Prenumeratų duomenys pašalinami išdiegus programą.'
              : 'You can delete your account and its email at any time via Settings → Delete account. Subscription data is removed when you uninstall the app.',
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
      updated: isLt ? 'Atnaujinta: 2026-07-02' : 'Last updated: 2026-07-02',
      intro: isLt
          ? 'Naudodamasis Vaultie sutinki su šiomis sąlygomis. Jei nesutinki, programos nenaudok.'
          : 'By using Vaultie you agree to these terms. If you do not agree, please do not use the app.',
      sections: [
        LegalSection(
          isLt ? 'Paslauga' : 'The service',
          isLt
              ? 'Vaultie – prenumeratų sekimo programa, padedanti stebėti pasikartojančias išlaidas ir gauti priminimus. Ji teikia informaciją, o ne finansines konsultacijas.'
              : 'Vaultie is a subscription tracker that helps you monitor recurring costs and get reminders. It provides information, not financial advice.',
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
          isLt ? 'Mokėjimai' : 'Payments',
          isLt
              ? 'Šiuo metu Vaultie nemokama. Mokamos „Pro" funkcijos gali atsirasti ateityje; sąlygos bus pateiktos prieš pirkimą.'
              : 'Vaultie is currently free. Paid "Pro" features may be offered in the future; terms will be shown before any purchase.',
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
