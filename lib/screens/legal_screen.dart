import 'package:flutter/material.dart';

import '../content_theme.dart';

/// A simple scrollable legal document screen (Privacy Policy / Terms of Use).
///
/// Content lives in-app so the Settings links always open something real — a
/// requirement for App Review. Text is bilingual (LT/EN).
///
/// No longer template-grade: it names the actual controller (MB Živitoma, the
/// company that holds the Enable Banking agreement), states a legal basis per
/// purpose, retention periods, the data-subject rights and the supervisory
/// authority. Before this it described the product accurately but did not say
/// WHO was processing the data or under what basis — the parts the GDPR is
/// actually built around.
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

  static const _contactEmail = 'support@vaultieapp.com';

  // The data controller under the GDPR — the party that decides why and how
  // personal data is processed. That is the company, because the Enable Banking
  // (PSD2) contract that permits access to bank data is held by it: naming a
  // private individual here would not match the agreement the access runs under.
  // The App Store seller may be an individual account; that is a distribution
  // channel and a separate question from who operates the service.
  static const _companyName = 'MB Živitoma';
  static const _companyCode = '304754869';
  static const _companyAddress = 'Vytauto g. 118-4, LT-00153 Palanga, Lietuva';
  static const _companyAddressEn =
      'Vytauto g. 118-4, LT-00153 Palanga, Lithuania';

  factory LegalScreen.privacy(bool isLt) {
    return LegalScreen(
      title: isLt ? 'Privatumo politika' : 'Privacy Policy',
      updated: isLt ? 'Atnaujinta: 2026-09-01' : 'Last updated: 2026-09-01',
      intro: isLt
          ? 'Vaultie gerbia tavo privatumą. Ši politika paaiškina, kokius duomenis renkame, kaip juos naudojame ir kokias teises turi.'
          : 'Vaultie respects your privacy. This policy explains what data we collect, how we use it, and the choices you have.',
      sections: [
        // GDPR Art. 13 opens with the identity of the controller. It was missing
        // entirely, which is the first thing a data-protection complaint looks
        // for and the first thing a reviewer of a finance app notices.
        LegalSection(
          isLt ? 'Kas mes esame (duomenų valdytojas)' : 'Who we are (data controller)',
          isLt
              ? 'Tavo asmens duomenų valdytojas yra $_companyName, juridinio '
                  'asmens kodas $_companyCode, registruota adresu '
                  '$_companyAddress. Susisiekti gali el. paštu $_contactEmail.\n\n'
                  'Vaultie nėra licencijuota mokėjimo įstaiga. Prieigą prie banko '
                  'sąskaitų informacijos suteikia „Enable Banking“ — licencijuotas '
                  'sąskaitos informacijos paslaugos teikėjas, veikiantis pagal '
                  'PSD2 direktyvą, su kuriuo $_companyName yra sudariusi sutartį.'
              : 'The controller of your personal data is $_companyName, company '
                  'registration number $_companyCode, registered at '
                  '$_companyAddressEn. You can reach us at $_contactEmail.\n\n'
                  'Vaultie is not a licensed payment institution. Access to bank '
                  'account information is provided by Enable Banking, a licensed '
                  'account information service provider operating under PSD2, with '
                  'which $_companyName holds an agreement.',
        ),
        LegalSection(
          isLt ? 'Teisinis tvarkymo pagrindas' : 'Legal basis for processing',
          isLt
              ? 'Paskyros duomenis (el. paštą) ir prenumeratos būseną tvarkome '
                  'sutarties vykdymo pagrindu (BDAR 6 str. 1 d. b p.) — be jų '
                  'negalime suteikti paslaugos.\n\n'
                  'Banko sąskaitos duomenis ir AI funkcijas tvarkome tik tavo '
                  'sutikimo pagrindu (BDAR 6 str. 1 d. a p.). Sutikimą gali bet '
                  'kada atšaukti — atjungdamas banką, išjungdamas AI funkciją '
                  'nustatymuose arba nustodamas naudotis funkcija. Atšaukimas '
                  'negalioja atgaline data.\n\n'
                  'Klaidų ataskaitas ir programos saugumą tvarkome teisėto '
                  'intereso pagrindu (BDAR 6 str. 1 d. f p.) — kad programa '
                  'veiktų ir būtų taisoma.'
              : 'Account data (your email) and subscription status are processed '
                  'to perform our contract with you (GDPR Art. 6(1)(b)) — without '
                  'them we cannot provide the service.\n\n'
                  'Bank account data and the AI features are processed solely on '
                  'the basis of your consent (GDPR Art. 6(1)(a)). You can withdraw '
                  'consent at any time by disconnecting your bank, switching the AI '
                  'feature off in Settings, or ceasing to use the feature. '
                  'Withdrawal does not affect processing carried out beforehand.\n\n'
                  'Crash reports and app security rely on our legitimate interest '
                  '(GDPR Art. 6(1)(f)) in keeping the app working and fixable.',
        ),
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
                  'Programai nulūžus, „Firebase Crashlytics" gauna klaidos '
                  'ataskaitą: įrenginio modelį, sistemos versiją ir techninį '
                  'klaidos pėdsaką, kad galėtume ją pataisyti. Kartu siunčiamas '
                  'tavo Vaultie paskyros identifikatorius — be el. pašto, vardo '
                  'ar banko duomenų. '
                  'Prekių ženklų logotipai saugomi pačioje programoje — jokių '
                  'užklausų trečiosioms šalims dėl jų nesiunčiama. Neparduodame '
                  'tavo duomenų.'
              : 'We use Google Firebase for authentication, plus Sign in with '
                  'Apple if you choose it. In-app purchases are handled by '
                  'RevenueCat, which receives your App Store transaction data. '
                  'If you connect a bank, Enable Banking (a licensed PSD2 provider) '
                  'securely retrieves your account data on our behalf. If the app '
                  'crashes, Firebase Crashlytics receives a crash report: your '
                  'device model, OS version and a technical stack trace, so we can '
                  'fix it. Your Vaultie account identifier is included — no email, '
                  'no name, no bank data. Brand logos '
                  'are bundled in the app itself — no third-party requests are made '
                  'for them. We do not sell your data.',
        ),
        LegalSection(
          isLt ? 'AI funkcijos' : 'AI features',
          isLt
              ? 'AI pokalbis, mėnesio santraukos, kvito skenavimas ir prekybininkų '
                  'kategorizavimas naudoja „Anthropic" AI paslaugą — visos keturios '
                  'funkcijos NUMATYTAI IŠJUNGTOS ir įsijungia TIK po to, kai '
                  'programėlėje aiškiai ir sąmoningai sutinki: langas įvardina '
                  '„Anthropic" ir tiksliai aprašo, kas bus siunčiama, PRIEŠ '
                  'pradedant siųsti.\n\n'
                  'Kad atsakytų į klausimus ar parašytų santrauką, siunčiame TIK '
                  'suvestinę: banko likučius, išlaidas pagal kategoriją ir tavo '
                  'pasikartojančių mokėjimų pavadinimus (pvz. „Netflix"). '
                  'NESIUNČIAME atskirų sandorių, IBAN‑ų ar kortelių numerių. '
                  'Šių duomenų nesaugome — jie egzistuoja tik tos vienos užklausos '
                  'metu.\n\n'
                  'Kvito skenavimui siunčiame nufotografuotą kvitą — jis '
                  'panaudojamas prekėms ir sumai atpažinti ir NIEKUR neišsaugomas.\n\n'
                  'Prekybininkų kategorizavimui, kai prijungtas bankas IR esi tai '
                  'įjungęs, verslo prekybininkų pavadinimus (pvz. parduotuvės) '
                  'siunčiame AI, kad atpažintume kategoriją. Siunčiami TIK verslo '
                  'pavadinimai — niekada žmonių vardai, sumos, datos ar IBAN‑ai '
                  '(veikia žmonių vardų filtras). Rezultatas išsaugomas mūsų '
                  'serveryje pakartotiniam naudojimui, kad tas pats prekybininkas '
                  'nebūtų siunčiamas antrą kartą.\n\n'
                  '„Anthropic" nenaudoja šių duomenų dirbtinio intelekto '
                  'treniravimui. Bet kurią iš šių funkcijų gali bet kada išjungti '
                  'Nustatymuose.'
              : 'The AI chat, monthly summaries, receipt scanning, and merchant '
                  'categorisation all use the Anthropic AI service — and all four '
                  'are OFF by default and only ever activate after you give '
                  'explicit, informed consent in the app, naming Anthropic and '
                  'describing exactly what is sent, before anything is shared.\n\n'
                  'To answer questions or write a summary we send ONLY a summary: '
                  'bank balances, spending by category, and the names of your '
                  'recurring payments (e.g. "Netflix"). We do NOT send individual '
                  'transactions, IBANs, or card numbers. We do not store this data '
                  '— it exists only for that single request.\n\n'
                  'For receipt scanning we send the photographed receipt itself — '
                  'used to recognise the items and total, and never stored '
                  'anywhere.\n\n'
                  'For merchant categorisation, when a bank is connected and you '
                  'have turned this on, we send business merchant names (e.g. a '
                  'shop) to the AI to recognise the category. Only business names '
                  'are sent — never people\'s names, amounts, dates, or IBANs (a '
                  'person-name filter applies). The result is stored on our '
                  'server for reuse, so the same merchant is never sent twice.\n\n'
                  'Anthropic does not use this data to train AI models. You can '
                  'turn any of these features off at any time in Settings.',
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
          isLt ? 'Kiek laiko saugome' : 'How long we keep it',
          isLt
              ? 'Banko operacijos NĖRA saugomos — jos apdorojamos laikinai ir '
                  'iškart pamirštamos; įrenginyje lieka tik tai, ką pats '
                  'pasirenki.\n\n'
                  'Paskyros duomenys (el. paštas) saugomi tol, kol turi paskyrą. '
                  'Ištrynus paskyrą programoje, jie panaikinami nedelsiant, o '
                  'vietiniai duomenys sunaikinami kartu su jais.\n\n'
                  'Klaidų ataskaitos saugomos iki 90 dienų. Prekybininkų '
                  'kategorijos (be jokių tavo duomenų — tik verslo pavadinimas ir '
                  'kategorija) saugomos neribotai, nes jos nėra asmens duomenys.'
              : 'Bank transactions are NOT retained — they are processed '
                  'transiently and immediately discarded; only what you choose to '
                  'keep stays on your device.\n\n'
                  'Account data (your email) is kept for as long as you have an '
                  'account. Deleting your account in the app erases it '
                  'immediately, and your local data is destroyed with it.\n\n'
                  'Crash reports are kept for up to 90 days. Merchant categories '
                  '(containing none of your data — just a business name and a '
                  'category) are kept indefinitely, as they are not personal data.',
        ),
        LegalSection(
          isLt ? 'Tavo teisės' : 'Your rights',
          isLt
              ? 'Pagal BDAR turi teisę: susipažinti su savo duomenimis; juos '
                  'ištaisyti; ištrinti („teisė būti pamirštam“); apriboti '
                  'tvarkymą; nesutikti su tvarkymu; perkelti duomenis; ir bet '
                  'kada atšaukti sutikimą.\n\n'
                  'Daugumą jų gali įgyvendinti pats programoje: duomenys guli '
                  'tavo telefone, o paskyrą ir visus duomenis gali ištrinti '
                  'Nustatymuose. Bet kuriuo kitu atveju rašyk $_contactEmail — '
                  'atsakome ne vėliau kaip per 30 dienų.\n\n'
                  'Jei manai, kad tvarkome tavo duomenis neteisėtai, turi teisę '
                  'pateikti skundą Valstybinei duomenų apsaugos inspekcijai '
                  '(vdai.lrv.lt), L. Sapiegos g. 17, Vilnius.'
              : 'Under the GDPR you have the right to: access your data; have it '
                  'corrected; have it erased (the "right to be forgotten"); '
                  'restrict processing; object to processing; receive your data in '
                  'a portable form; and withdraw consent at any time.\n\n'
                  'You can exercise most of these yourself: your data sits on your '
                  'own phone, and you can delete your account together with all of '
                  'it in Settings. For anything else write to $_contactEmail — we '
                  'reply within 30 days at the latest.\n\n'
                  'If you believe we process your data unlawfully, you have the '
                  'right to complain to the Lithuanian State Data Protection '
                  'Inspectorate (vdai.lrv.lt), L. Sapiegos g. 17, Vilnius, or to '
                  'the supervisory authority in your own country.',
        ),
        LegalSection(
          isLt ? 'Duomenų perdavimas už ES ribų' : 'Transfers outside the EU',
          isLt
              ? 'Kai kurie mūsų paslaugų teikėjai („Google Firebase“, '
                  '„RevenueCat“, „Anthropic“) yra JAV. Perdavimai vyksta pagal '
                  'Europos Komisijos patvirtintas standartines sutarčių sąlygas '
                  'arba ES–JAV duomenų privatumo sistemą. Banko operacijų '
                  'duomenys apdorojami ES (Firebase regionas europe-west1) ir už '
                  'ES ribų neperduodami.'
              : 'Some of our providers (Google Firebase, RevenueCat, Anthropic) '
                  'are based in the United States. Those transfers rely on the '
                  'European Commission\'s Standard Contractual Clauses or the '
                  'EU–US Data Privacy Framework. Bank transaction data is '
                  'processed inside the EU (Firebase region europe-west1) and is '
                  'not transferred outside it.',
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
              ? '$_companyName, kodas $_companyCode\n$_companyAddress\n'
                  'El. paštas: $_contactEmail'
              : '$_companyName, company number $_companyCode\n'
                  '$_companyAddressEn\nEmail: $_contactEmail',
        ),
      ],
    );
  }

  factory LegalScreen.terms(bool isLt) {
    return LegalScreen(
      title: isLt ? 'Naudojimo sąlygos' : 'Terms of Use',
      updated: isLt ? 'Atnaujinta: 2026-07-27' : 'Last updated: 2026-07-27',
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
              ? 'Vaultie veikia tik su prenumerata — programai naudoti reikia '
                  'aktyvaus „Vaultie Pro" plano: mėnesinio (4,99 €/mėn.) arba '
                  'metinio (39,99 €/metus). Jei siūlomas nemokamas bandomasis '
                  'laikotarpis, jo trukmė ir sąlygos parodomos pirkimo ekrane '
                  'prieš patvirtinant; mokestis nuskaičiuojamas tik jam '
                  'pasibaigus, nebent atšauksi anksčiau. '
                  'Pirkimus tvarko „Apple App Store" ir jie nuskaičiuojami iš '
                  '„Apple ID"; kainos parodomos prieš pirkimą ir gali skirtis '
                  'pagal regioną. Prenumerata atsinaujina automatiškai, nebent '
                  'atšaukiama likus ne mažiau kaip 24 val. iki laikotarpio '
                  'pabaigos. Valdyti ar atšaukti galima bet kada „App Store" '
                  'nustatymuose → jūsų vardas → Prenumeratos; programos ištrynimas '
                  'jos neatšaukia. Grąžinimams taikomos „Apple" taisyklės ir '
                  'įstatymai.'
              : 'Vaultie is subscription-only — using the app requires an active '
                  'Vaultie Pro plan: monthly (€4.99/month) or yearly '
                  '(€39.99/year). Where a free trial is offered, its length and '
                  'terms are shown on the purchase screen before you confirm; you '
                  'are charged only when it ends, unless you cancel first. '
                  'Purchases are processed by the Apple App Store and charged to '
                  'your Apple ID; prices are shown before you buy and may vary by '
                  'region. The subscription renews automatically unless cancelled '
                  'at least 24 hours before the end of the current period. Manage '
                  'or cancel anytime in App Store settings → your name → '
                  'Subscriptions; deleting the app does not cancel it. Refunds are '
                  'subject to Apple\'s policies and applicable law.',
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
          // The Terms need the operator named as plainly as the Privacy Policy
          // does — "questions? email us" identifies nobody to contract with.
          isLt
              ? 'Paslaugą teikia $_companyName, kodas $_companyCode, '
                  '$_companyAddress.\nKlausimais rašyk: $_contactEmail'
              : 'The service is provided by $_companyName, company number '
                  '$_companyCode, $_companyAddressEn.\n'
                  'Questions? Contact us at $_contactEmail',
        ),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: cBg,
      appBar: AppBar(
        backgroundColor: cBg,
        foregroundColor: cInk,
        surfaceTintColor: cBg,
        elevation: 0,
        scrolledUnderElevation: 0,
        title: Text(title, style: TextStyle(color: cInk, fontWeight: FontWeight.w800)),
      ),
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.all(24),
          children: [
            Text(
              updated,
              style: TextStyle(
                color: cSubtle,
                fontSize: 13,
              ),
            ),
            const SizedBox(height: 16),
            Text(
              intro,
              style: TextStyle(
                fontSize: 15,
                height: 1.5,
                color: cInk,
              ),
            ),
            const SizedBox(height: 24),
            for (final s in sections) ...[
              Text(
                s.heading,
                style: TextStyle(
                  fontSize: 17,
                  fontWeight: FontWeight.w700,
                  color: cInk,
                ),
              ),
              const SizedBox(height: 6),
              Text(
                s.body,
                style: TextStyle(
                  fontSize: 15,
                  height: 1.5,
                  color: cSubtle,
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
