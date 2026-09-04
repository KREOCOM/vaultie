import 'app_prefs.dart';

/// Lightweight retrofit localization.
///
/// The app was written entirely in Lithuanian with the strings hard-coded in the
/// widgets. Rather than migrate everything to ARB files at once, this keeps the
/// Lithuanian text as the KEY: when the UI language is English, [tr] looks up a
/// translation and falls back to the original Lithuanian if none exists — so a
/// not-yet-translated string just stays Lithuanian instead of breaking or going
/// blank. Localize screens incrementally by adding entries to [_en].
///
/// IMPORTANT: only wrap DISPLAY strings with [tr]. Never wrap a string that is
/// used as a data key or in a comparison (e.g. `t['sec'] == 'Pervedimai'`) — the
/// translated value would no longer match the data.
String tr(String lt) {
  if (effectiveLocale().languageCode != 'en') return lt;
  return _en[lt] ?? lt;
}

/// Convenience for interpolated strings: `trf('% per mėn', {'%': '12'})` isn't
/// used yet, but [tr] handles the common case (translate the static template and
/// interpolate around it in the caller).

const Map<String, String> _en = {
  // ── Bottom navigation ──
  'Pradžia': 'Home',
  'Apžvalga': 'Overview',
  'AI pokalbis': 'AI chat',
  'Agentas': 'Agent',
  'Planavimas': 'Planning',
  'Paskyra': 'Account',
  'Transakcijos': 'Transactions',

  // ── Account type labels (Enable Banking cash_account_type) ──

  // ── Missing entries found 2026-08-19 auditing dashboard_preview.dart
  // (the live-embedded Home/hero screen the onboarding chain shows) against
  // this map — an English-locale device saw these still in Lithuanian. ──
  'Dalybos': 'Split',
  'Klausk manęs apie savo finansus.': 'Ask me about your finances.',
  'Fotografuoti': 'Take photo',
  'Keisti nuotrauką': 'Change photo',
  'Pasirinkti iš galerijos': 'Choose from gallery',
  'Pašalinti nuotrauką': 'Remove photo',
  'Nepavyko įrašyti nuotraukos': "Couldn't save the photo",
  'Priminimai išjungti': 'Reminders are off',
  'Įjunk pranešimus telefono nustatymuose, kad negautum vėluojančių mokėjimų priminimų.':
      "Turn on notifications in your phone's settings so you don't miss payment reminders.",
  'Prenumeratos kainuoja 106 € per mėnesį, o dvi iš jų nenaudotos '
          'nuo balandžio. Jas atsisakius liktų 68 € kas mėnesį.':
      'Subscriptions cost €106 a month, and two of them haven’t been '
          'used since April. Cancelling those would leave €68 a month.',
  'Kokia mano finansinė padėtis šiuo metu?':
      'What’s my financial situation right now?',
  'Šiuo metu esi teigiamoje pusėje: šį mėnesį uždirbai 2 957 €, '
          'išleidai 1 828 €, o santaupų norma — 27 %.':
      'You’re in good shape right now: this month you earned €2,957, '
          'spent €1,828, and your savings rate is 27%.',

  // ── Home / balance hero ──
  'Sveiki sugrįžę': 'Welcome back',
  'Bendras likutis': 'Total balance',
  'gyvai': 'live',
  'Sinchronizuojama': 'Syncing',
  'nuo praėjusio mėn.': 'vs last month',
  'Likutis iš banko · grafikas = likučio kitimas laike':
      'Bank balance · chart = balance over time',
  'Sutaupei': 'You saved',
  'praėjusio mėn.': 'last month',
  'iš viso': 'total',
  'Kur išleidai daugiausiai': 'Where you spent the most',
  'Paskutinių': 'Last',
  'Visos operacijos': 'All transactions',
  'Šio mėnesio operacijos': 'This month’s transactions',

  // ── Home: Finance Agent banner ── (const Text, never wrapped in tr() —
  // stayed Lithuanian even with the app language set to English)
  'Finansų Agentas': 'Finance Agent',

  // ── Cash on hand (Home hero + Paskyra net worth) ── ('Grynieji' itself is
  // already translated below, in Sub-categories & transaction labels)
  'Kiek turi grynųjų?': 'How much cash do you have?',
  'Kiek gavai grynais?': 'How much cash did you get?',
  'Kiek išleidai grynais?': 'How much cash did you spend?',

  // ── Filters / week ──
  'Filtras': 'Filter',
  'Visas laikas': 'All time',
  'vidurkis': 'average',
  'Šią savaitę išleista': 'Spent this week',
  'Praėjusią savaitę išleista': 'Spent last week',

  // ── Subscriptions card ──
  'PRENUMERATOS IR SĄSKAITOS': 'SUBSCRIPTIONS & BILLS',

  // ── Month feed / headers ──
  'Išleista': 'Spent',
  'Gauta': 'Received',
  'grynasis': 'net',
  'Rodyti senesnius': 'Show older',
  'reguliariai': 'regularly',
  'tikslas': 'target',
  'Sujungtos operacijos — keisis pavadinimas ir kategorija visoms':
      'Merged transactions — the name and category will change for all of them',
  'sandoriai': 'transactions',
  'sandorių': 'transactions',
  'apžvalga': 'review',
  'Peržiūrėti': 'View',

  // ── AI chat ──
  'Klausk apie savo pinigus': 'Ask about your money',
  'Klausk apie savo finansus…': 'Ask about your finances…',
  'Pirma prijunk banką': 'Connect a bank first',
  'Prijunk banką, kad galėčiau atsakyti apie tavo finansus.':
      'Connect a bank so I can answer questions about your finances.',
  'Kiek išleidau šį mėnesį?': 'How much did I spend this month?',
  'Kokia mano brangiausia prenumerata?':
      'What’s my most expensive subscription?',
  'Kur galėčiau sutaupyti?': 'Where could I save?',
  'Kur daugiausiai išleidžiu?': 'What do I spend the most on?',
  'Kokia mano santaupų norma?': 'What’s my savings rate?',
  'Labas 👋 Galiu padėti suprasti, kur keliauja tavo pinigai. Ko norėtum paklausti?':
      'Hi 👋 I can help you understand where your money goes. What would you like to ask?',

  // ── Overview / analytics ──
  'Kategorija': 'Category',
  'Kategorijos': 'Categories',
  'per 31 d.': 'in the last 31 days',
  'Suma': 'Amount',
  'Santaupų norma': 'Savings rate',
  'suma': 'total',
  'Vidutinės dienos išlaidos': 'Average daily spending',
  'Šį mėnesį': 'This month',
  'Praėjusio mėn. statusas': 'Last month’s status',
  'Paskutinių 6 mėn. normos': 'Last 6 months’ rates',
  'santaupos / pajamos': 'savings / income',
  'pajamos': 'income',
  'santaupos': 'savings',
  'išleista': 'spent',
  'uždirbta': 'earned',
  'santaupų': 'savings',
  'd.': '',

  // ── Section (category) names ──
  'Maistas, gėrimai': 'Food & drinks',
  'Transportas': 'Transport',
  'Apsipirkimas': 'Shopping',
  'Būstas, sąskaitos': 'Housing & bills',
  'Sveikata, sportas': 'Health & sport',
  'Pramogos': 'Entertainment',
  'Finansai': 'Finance',
  'Švietimas': 'Education',
  'Pajamos ir pervedimai': 'Income & transfers',
  'Pervedimai': 'Transfers',
  'Pajamos': 'Income',
  'Kita': 'Other',

  // ── Sub-categories & transaction labels ──
  'Neigiama': 'Negative',
  'Teigiama': 'Positive',
  'Maisto prekės': 'Groceries',
  'Kavinės, restoranai': 'Cafes & restaurants',
  'Alkoholis, tabakas': 'Alcohol & tobacco',
  'Kuras': 'Fuel',
  'Taksi': 'Taxi',
  'Automobilis': 'Car',
  'Viešasis transportas': 'Public transport',
  'Parkavimas': 'Parking',
  'Drabužiai': 'Clothing',
  'Elektronika, prekės': 'Electronics & goods',
  'Namų prekės': 'Household',
  'Higiena': 'Hygiene',
  'Būstas, nuoma': 'Rent & housing',
  'Komunaliniai': 'Utilities',
  'Ryšys, internetas': 'Phone & internet',
  'Draudimas': 'Insurance',
  'Namų priežiūra, meistrai': 'Home services & repairs',
  'Vaikai, ugdymas': 'Kids & education',
  'Paskola, lizingas': 'Loan & leasing',
  'Sveikata': 'Health',
  'Sportas': 'Sport',
  'Vaistinė': 'Pharmacy',
  'Grožis, kirpykla': 'Beauty & hairdresser',
  'Naminiai gyvūnai': 'Pets',
  'Prenumeratos': 'Subscriptions',
  'Kelionės': 'Travel',
  'Mokesčiai': 'Taxes',
  'Bankas, komisiniai': 'Bank & fees',
  'Investicijos': 'Investments',
  'Mokslas': 'Education',
  'Kursai, knygos': 'Courses & books',
  'Grynieji': 'Cash',
  'Reguliarios paslaugos — Netflix, sporto salė, programėlės.':
      'Regular services — Netflix, gym, apps.',
  'Nuoma, komunaliniai, telefonas, paskolos, draudimas.':
      'Rent, utilities, phone, loans, insurance.',
  'Asmeninis pervedimas': 'Personal transfer',
  'Atlyginimas': 'Salary',
  // Emitted by dashboard.py's classifier (_classify) as the `cat` on a row —
  // read straight off the row and passed through tr() in "Largest expenses"
  // (_largest) and the transaction feed, same as every other cat string here.
  // Missing from this map for both, so an English-mode user with any currency
  // exchange or own-account transfer among their biggest transactions saw
  // "Exchanged to ... Valiutos keitimas" — the one Lithuanian word left in an
  // otherwise fully English screen.
  'Valiutos keitimas': 'Currency exchange',
  'Savas pervedimas': 'Own-account transfer',

  // ── Transaction badges ──
  'Sąskaita': 'Bill',
  'Rezervuota': 'Reserved',
  'Prekybininkas': 'Merchant',

  // ── Common words ──
  'per metus': 'per year',
  '/ mėn': '/ mo',
  '/mėn': '/mo',
  'per mėn': 'per mo',
  'Šis mėnuo': 'This month',
  'Atšaukti': 'Cancel',
  // 2026-09-04: Settings' notification toggle now warns when the OS
  // permission is actually off, instead of just reflecting the app's own
  // (separate) preference.
  'Išjungta telefono nustatymuose — priminimai neateis':
      'Turned off in phone settings — reminders won\'t arrive',
  // 2026-09-04: subs_bills_live.dart's new remove-confirmation dialog.
  'Nebesekti šios prenumeratos?': 'Stop tracking this subscription?',
  'Nebesekti šios sąskaitos?': 'Stop tracking this bill?',
  'daugiau nebebus rodoma šiame sąraše. Jei persigalvosi, ją reikės pridėti rankomis.':
      'won\'t show in this list anymore. If you change your mind, you\'ll need to add it back manually.',
  'Nebesekti': 'Stop tracking',
  'Ryšys su serveriu užtruko per ilgai. Patikrink interneto ryšį ir bandyk dar kartą.':
      'The connection to the server took too long. Check your internet connection and try again.',
  'Išsaugoti': 'Save',
  'Pervadinti': 'Rename',
  'Radome automatiškai iš tavo banko duomenų — pašalink, jei kas netinka':
      'Found automatically from your bank data — remove anything that doesn\'t belong',
  'Taupymo tikslas': 'Savings goal',
  'Matyk, kiek realiai sutaupai': 'See how much you\'re really saving',
  'Nustatyk mėnesio ir bendrą taupymo tikslą — skaičiuosime iš tavo realių pajamų ir išlaidų.':
      'Set a monthly and total savings goal — we\'ll calculate it from your real income and expenses.',
  'Dar neturi taupymo tikslo': 'No savings goal yet',
  'Nustatyti tikslą': 'Set a goal',
  'Sutaupei nuo': 'Saved since',
  'Taupai': 'You\'re saving',
  'pajamų per pastaruosius 6 mėn.': 'of your income over the last 6 months',
  'Taupymo tendencija': 'Savings trend',
  'Pirmas laikotarpis baigsis': 'Your first period ends',
  'Kaupiame pirmuosius duomenis': 'Gathering your first data',
  'Pirmas rezultatas': 'First result on',
  'tada atsiras grafikas': 'then the chart will appear',
  'Kiek nori sutaupyti per kas 30 dienų nuo pradžios datos.':
      'How much you want to save every 30 days from the start date.',
  'Kiek iš viso nori sutaupyti nuo pradžios datos.':
      'How much you want to save in total from the start date.',
  'Įvykdyta': 'Complete',
  'Tikslas': 'Goal',
  'Mėnesio tikslas': 'Monthly goal',
  'Bendras tikslas': 'Total goal',
  'Mėnesio taupymo tikslas': 'Monthly savings goal',
  'Bendras taupymo tikslas': 'Total savings goal',
  'Nuo kada skaičiuoti?': 'Count from when?',
  'Investavimas': 'Investing',
  'Pridėti akciją': 'Add a stock',
  'Pridėti akciją, kriptovaliutą': 'Add a stock, crypto',
  'Portfelio vertė': 'Portfolio value',
  'šiandien': 'today',
  'nuo pirkimo': 'since purchase',
  'vnt.': 'shares',
  'Bandyti vėl': 'Try again',
  'Kiek turi?': 'How much do you have?',
  'Ieškok pvz. Tesla, Apple...': 'Search e.g. Tesla, Apple...',
  'Populiariausios': 'Most popular',
  'Keisti': 'Change',
  'Kiek akcijų turi?': 'How many shares do you have?',
  'Kiek turi': 'You have',
  'Kaina už 1 vnt.': 'Price per share',
  'Vakarykštė kaina': 'Yesterday\'s price',
  'Pirkimo kaina': 'Purchase price',
  'Nepavyko įkelti kainų — patikrink ryšį ir bandyk vėl.':
      'Couldn\'t load prices — check your connection and try again.',
  '1 pozicija neįtraukta — nepavyko gauti kainos':
      '1 position not included — couldn\'t get its price',
  'pozicijos neįtrauktos — nepavyko gauti kainų':
      'positions not included — couldn\'t get their prices',
  'Kiekis': 'Quantity',
  'Suma (€)': 'Amount (€)',
  'Už kiek pirkai?': 'How much did you pay?',
  'Kraunama kaina...': 'Loading price...',
  'Nepavyko gauti dabartinės kainos.': 'Couldn\'t get the current price.',
  'Dabartinė kaina': 'Current price',
  'Netrukus — kol kas turime tik šiandienos kainą.':
      'Coming soon — for now we only have today\'s price.',
  'Kaina gali vėluoti kelias minutes nuo tikros rinkos kainos.':
      'The price may lag the real market by a few minutes.',
  'Turi investavęs į kryptovaliutą ar akcijas?':
      'Do you hold crypto or stocks?',
  'Sek savo akcijas bei kriptovaliutą ir matyk jų pokyčius realiu laiku.':
      'Track your stocks and crypto and see their moves in real time.',
  'Pridėti pirmą investiciją': 'Add your first investment',
  '+ Pridėti': '+ Add',
  'Bankai': 'Banks',
  'Tikros rinkos kainos, konvertuotos į eurus':
      'Real market prices, converted to euros',
  'Tik sekimas — jokių sujungimų su brokeriu':
      'Tracking only — no broker connections',
  'Tinka ir akcijoms, ir kriptovaliutai': 'Works for both stocks and crypto',
  'Viskas vienoje vietoje su tavo finansais':
      'Everything in one place with your finances',
  'Ištrinti': 'Delete',
  'Redaguoti': 'Edit',
  'Netrukus': 'Coming soon',
  'Skaidyti': 'Split',
  'Skaidyti operaciją': 'Split transaction',
  'Anuliuoti skaidymą': 'Undo split',
  'Išskaidytas sandoris': 'Split transaction',
  'Išskaidyta į': 'Split into',
  'Pridėti eilutę': 'Add line',
  'Pasirink kategoriją': 'Pick a category',
  'Paskirstyta viskas': 'Fully allocated',
  'Trūksta': 'Short by',
  'Priskirta per daug': 'Over-allocated by',
  'Pataisyti paskutinę eilutę': 'Fix the last line',
  'Išsaugoti skaidymą': 'Save split',
  'Skenuoti kvitą': 'Scan receipt',
  // ── "Kvitas"/"Grynieji" hero quick-action first-use explainers ──
  'Nuskenuok kvitą': 'Scan the receipt',
  'Kvito skenavimas': 'Receipt scanning',
  'Supratau, tęsti': 'Got it, continue',
  'Tik jeigu kvitas apmokėtas grynaisiais pinigais':
      'Only if the receipt was paid in cash',
  'Moki grynais?': 'Paying with cash?',
  'Bankas nemato tavo grynųjų išlaidų — pridėk jas pats, kad likutis būtų tikslus.':
      'The bank can\'t see your cash spending — add it yourself so the balance stays accurate.',
  'Įvesk sumą ir pasirink kategoriją': 'Enter the amount and pick a category',
  'Nuskenuok kvitą, jei mokėjai grynais':
      'Scan the receipt, if you paid in cash',
  'Grynieji likučiai atsinaujins iš karto':
      'Your cash balance updates instantly',
  'Atpažinsime prekes ir sumą bei susiesime kvitą su atitinkama banko operacija.':
      'We\'ll recognise the items and total, and link the receipt to the matching bank transaction.',
  'Automatiškai surasime atitinkančią banko operaciją':
      'We\'ll automatically find the matching bank transaction',
  'Kvitą galėsi padalinti į kelias kategorijas':
      'You\'ll be able to split the receipt into several categories',
  'Išlaidas priskirsime pagal kvite esančią informaciją':
      'We\'ll assign the spending based on what\'s on the receipt',
  'Dar nėra išsaugotų skaidymų.': 'No saved splits yet.',
  'Naujas skaidymas': 'New split',
  'Anksčiau išsaugoti': 'Previously saved',
  '1 žmogus': '1 person',
  'žmonės': 'people',
  'Kvitas': 'Receipt',
  'Peržiūrėti kvitą': 'Review receipt',
  'prekės rasta': 'items found',
  'Kiti mokesčiai': 'Other charges',
  'Iš viso': 'Total',
  'Pridėti žmones': 'Add people',
  'Vardas': 'Name',
  'Pridėti žmogų': 'Add person',
  'Priskirti prekes': 'Assign items',
  'Peržiūrėti skaidymą': 'Review split',
  'Dalinama lygiai visiems': 'Split equally between everyone',
  'Patvirtinti ir išsaugoti': 'Confirm and save',
  'Atmesti': 'Discard',
  'Ištrinti skaidymą?': 'Delete this split?',
  'Šio veiksmo anuliuoti negalima.': 'This can\'t be undone.',
  'Skaidymas išsaugotas!': 'Split saved!',
  'Dalintis suvestine': 'Share summary',
  'Skenuojama…': 'Scanning…',
  'Atpažįstame prekes ir kainas': 'Recognising items and prices',
  'Nepavyko atpažinti kvito — pabandyk dar kartą arba įvesk rankiniu būdu':
      'Could not read the receipt — try again or enter it manually',
  'NAUJA': 'NEW',
  'Pasirink kvito nuotrauką — automatiškai suskaidysime pirkinį pagal kategorijas':
      'Pick a photo of the receipt — we\'ll split the purchase by category automatically',
  'Nepavyko atpažinti kvito — pabandyk kitą nuotrauką':
      'Could not read the receipt — try a different photo',
  'Su kuria operacija susieti?': 'Which transaction is this?',
  'Atpažinta suma': 'Recognised total',
  'pasirink, kuri banko operacija tai yra':
      'pick which bank transaction this is',
  'Padalink sąskaitą tarp žmonių — niekas neišsaugoma':
      'Split the bill between people — nothing is saved',
  'Vardas…': 'Name…',
  'Nepriskirta': 'Unassigned',
  'Uždaryti': 'Close',

  // ── Recurring status / cadence / kind / payment-type (variable-resolved) ──
  'Naujas': 'New',
  'kas savaitę': 'weekly',
  'kas 2 savaites': 'every 2 weeks',
  'kas pusmetį': 'every 6 months',
  'kas ketvirtį': 'quarterly',
  'kas metus': 'yearly',
  'kas mėnesį': 'monthly',
  'kitas mokėjimas': 'next payment',
  'Naujos pajamos': 'New income',
  'Nauja išlaida': 'New expense',
  'Pervedimas': 'Transfer',
  'Dažnas pirkimas': 'Frequent purchase',
  'Vienkartinis': 'One-time',

  // ── Settings values (variable-resolved) ──
  'Bazinė valiuta': 'Base currency',
  'Lietuvių': 'Lithuanian',
  'Sistemos numatytoji': 'System default',
  'English': 'English',
  'Tamsi': 'Dark',
  'Šviesi': 'Light',

  // ── Filter types + extra manual categories ──
  'Visi': 'All',
  'Išlaidos': 'Expenses',
  'Užkandžiai, kava': 'Snacks & coffee',
  'Paspirtukai, dalinimasis': 'Scooters & sharing',
  'Dovana': 'Gift',
  'Sąskaitos papildymas': 'Account top-up',
  'Grąžinimas': 'Refund',
  'Atlyginimas (iš NOK)': 'Salary (from NOK)',

  // ── Received / net-worth breakdown ──
  'Visi pinigai, kurie įkrito į tavo sąskaitą.':
      'All the money that came into your account.',
  'Atpažintos pajamos': 'Recognised income',
  'atlyginimas, reguliarios įplaukos': 'salary, regular inflows',
  'Kiti pervedimai / įplaukos': 'Other transfers / inflows',
  'pavedimai iš žmonių, papildymai': 'transfers from people, top-ups',
  'Į santaupų normą įskaičiuojamos tik atpažintos pajamos — pervedimai iš kitų nelaikomi uždarbiu.':
      'Only recognised income counts toward the savings rate — transfers from others are not treated as earnings.',

  // ── Sync / refresh messages ──
  'Nepavyko atnaujinti:': 'Could not refresh:',
  'kol kas neatiduoda naujų duomenų. Rodomi paskutiniai — atsinaujins savaime, kai bankas vėl leis.':
      "isn't giving new data yet. Showing the latest — it'll refresh on its own once the bank allows again.",
  'Rodomi paskutiniai duomenys — perjunk banką, jei kartojasi.':
      'Showing the latest data — reconnect the bank if this repeats.',
  'Duomenys ką tik atnaujinti.': 'Data was just refreshed.',

  // ── Feed / month cards ──
  'Nėra išlaidų': 'No spending',
  'Liko': 'Left',
  'Skrituliai · kategorijos · kalendorius': 'Donuts · categories · calendar',

  // ── Manual entry ──
  'Išlaida': 'Expense',
  'Vidinis pervedimas': 'Internal transfer',
  'Šiandien': 'Today',
  'Vakar': 'Yesterday',
  'Pavadinimas (nebūtina)': 'Name (optional)',
  'Pastaba (nebūtina)': 'Note (optional)',
  'Vidiniai pervedimai neįskaičiuojami į išlaidas ar pajamas.':
      "Internal transfers aren't counted as spending or income.",

  // ── Filter sheet ──
  'Išvalyti': 'Clear',
  'TIPAS': 'TYPE',
  'KATEGORIJOS': 'CATEGORIES',
  'Taikyti': 'Apply',

  // ── Balance history / truncation ──
  'Balanso istorijos dar nėra': 'No balance history yet',
  'Kai atsiras operacijų, čia matysi kaip keitėsi tavo likutis.':
      "Once there are transactions, you'll see how your balance changed here.",
  'Rodoma': 'Showing',
  'mėn. — tiek istorijos grąžino bankas. Daugiau prisipildys laikui bėgant.':
      "mo — that's how much history the bank returned. More will fill in over time.",

  // ── Transaction detail ──
  'Įprastas sandoris': 'Normal transaction',
  'Data': 'Date',
  'Įvesta ranka': 'Entered manually',
  'Kategorizuota automatiškai': 'Categorised automatically',
  'Sandorio informacija': 'Transaction details',
  'Žyma': 'Tag',
  'Į vidinį pervedimą': 'To internal transfer',
  'Į įprastą': 'To normal',
  'biudžetas': 'budget',
  'viršyta': 'over',
  'liko': 'left',
  'Panašūs sandoriai': 'Similar transactions',
  'ir dar': 'and',
  'SANDORIS': 'TRANSACTION',
  'Pasirinkti kategoriją': 'Choose a category',
  'Ieškoti': 'Search',
  'Ištrinti sandorį?': 'Delete transaction?',
  'bus pašalintas. Šio veiksmo anuliuoti negalima.':
      'will be removed. This action cannot be undone.',
  'Pakeitimai išsaugoti': 'Changes saved',
  'Pažymėta kaip vidinis pervedimas': 'Marked as an internal transfer',
  'Grąžinta į įprastą (kategorija „Kita")':
      'Restored to a normal transaction (category "Other")',
  'Kategorija pakeista į': 'Category changed to',

  // ── Month review ──
  'išleidai': 'you spent',
  'mėnesį uždirbai': 'you earned',
  'o išleidai': 'and spent',
  'Grynasis rezultatas': 'Net result',
  'Daugiausia išleidai kategorijoje': 'You spent the most on',
  'Santaupų norma šį mėnesį —': 'Savings rate this month —',
  'Šį mėnesį pajamų nebuvo, tad santaupų norma neskaičiuojama.':
      'There was no income this month, so the savings rate is not calculated.',
  'SANTRAUKA': 'SUMMARY',
  'finansų momentas 📸': 'money snapshot 📸',
  'AI rašo santrauką…': 'AI is writing a summary…',
  'balansas': 'balance',
  'santaupų klubas': 'savings club',
  'mėn. iš eilės': 'mo in a row',
  'gaunamas NOK (Nergard) ir automatiškai konvertuojamas į EUR. Rodoma bazine valiuta — EUR.':
      'is received in NOK (Nergard) and automatically converted to EUR. Shown in the base currency — EUR.',

  // ── Planning: budgets & insights ──
  'Biudžetai': 'Budgets',
  'Pasikartojantys': 'Recurring',
  'Nuo': 'From',
  'Nuo kada sekti?': 'Track from when?',
  'Nuo mėnesio pradžios': 'From the start of the month',
  'Nuo šiandien': 'From today',
  'keisk': 'edit',
  'Įžvalgos': 'Insights',
  'Analitika': 'Analytics',
  'Vartotojas': 'User',
  'TESTAS': 'TEST',
  'Dar nėra duomenų.': 'No data yet.',
  'Per daug bandymų. Palauk': 'Too many attempts. Wait',
  'Pirkimas apdorojamas — palauk akimirką.':
      'Processing your purchase — one moment.',
  'Planai kol kas nepasiekiami. Bandyk vėliau.':
      'Plans are unavailable right now. Try again later.',
  'Prekybininkai': 'Merchants',
  'Didžiausios išlaidos': 'Largest expenses',
  'Sekamose kategorijose išleidai': 'In the tracked categories you spent',
  'iš': 'of',
  'Viršijai sekamų kategorijų limitą':
      'You exceeded the tracked categories limit by',
  'biudžetas*': 'budget*',
  '* pavyzdiniai limitai': '* example limits',
  'Kategorijai': 'In category',
  'nei praėjusį mėnesį.': 'than last month.',
  'daugiau': 'more',
  'mažiau': 'less',
  'Nusistatyti biudžetą': 'Set a budget',
  'prekybininkai': 'merchants',
  'Laikotarpis': 'Period',
  'Visas laikotarpis': 'Whole period',
  'Šiuo laikotarpiu operacijų nerasta.':
      'No transactions found for this period.',
  'Išleidau grynais': 'Cash expense',
  'Apmokėta grynais': 'Paid in cash',
  'Filtruota': 'Filtered',
  'Rodoma tik': 'Showing only',
  'Nenurodei, kiek turi grynųjų': 'You haven\'t said how much cash you have',
  'Ši išlaida jau įskaičiuota į kategorijas, bet neatimta iš jokio balanso — dar nesi nurodęs, kiek grynųjų turi iš viso.':
      'This expense already counts in your categories, but wasn\'t deducted from any balance — you haven\'t said how much cash you have in total yet.',
  'Praleisti': 'Skip',
  'Nurodyti dabar': 'Set it now',
  'Tai ne banko operacija — pridėsime kaip naują grynųjų įrašą.':
      'Not a bank transaction — we\'ll add it as a new cash entry.',
  'Grynųjų pirkinys': 'Cash purchase',
  'Nerasta panašios banko operacijos per pastarąsias dienas.':
      'No matching bank transaction found in the last few days.',
  'Atrodo, kad tai grynųjų išėmimas.': 'This looks like a cash withdrawal.',
  'prie sekamų grynųjų?': 'to your tracked cash?',
  'Pasirink mėnesį': 'Pick a month',
  'Biudžetai padeda suvaldyti išlaidas': 'Budgets help you control spending',
  'Susikurk biudžetą kategorijai — limitą pasiūlysime pagal tavo realų mėnesių vidurkį.':
      "Create a budget for a category — we'll suggest a limit from your real monthly average.",
  'visas biudžetas': 'total budget',
  'Tokiu tempu mėnesį baigsi ~':
      "At this pace you'll finish the month around ~",
  '— telpi į biudžetą.': '— you fit in the budget.',
  'Tokiu tempu peršoksi biudžetą ~':
      "At this pace you'll exceed the budget by ~",
  '— sulėtink.': '— slow down.',
  'Pasiūlyta pagal tavo išlaidas · keisk':
      'Suggested from your spending · edit',
  'Tavo biudžetas · keisk': 'Your budget · edit',
  'virš pasiūlymo': 'over the suggestion',
  'virš biudžeto': 'over budget',
  'Šį limitą pasiūlėme pagal tavo ~3 mėn. vidurkį. Gali pakeisti į savo.':
      'We suggested this limit from your ~3-month average. You can change it to your own.',
  'Keisk savo mėnesio limitą.': 'Change your monthly limit.',
  'Mėnesio limitas': 'Monthly limit',
  'Pašalinti': 'Remove',
  'Pridėti biudžetą': 'Add a budget',
  'Dar neturi biudžetų': "You don't have any budgets yet",
  'Pridėk kategoriją — pasiūlysim limitą pagal tavo tikras išlaidas, o tu patvirtinsi ar pakeisi.':
      "Add a category — we'll suggest a limit from your real spending, and you confirm or change it.",
  'Naujas biudžetas': 'New budget',
  'siūlome': 'we suggest',

  // ── Recurring manager ──
  'įskaičiuota': 'counted',
  'Išjungta': 'Off',

  // ── Overview extras ──
  'Paskutiniai 6 mėn.': 'Last 6 months',
  'Kas tai?': 'What is this?',
  'Santaupų norma rodo, kokią dalį gautų pajamų per mėnesį NEišleidai.':
      "The savings rate shows what share of the income you received in a month you did NOT spend.",
  '(pajamos − išlaidos) ÷ pajamos': '(income − spending) ÷ income',
  'Pvz. uždirbai 1 000 €, išleidai 750 € → norma 25 %. Kuo didesnė, tuo daugiau atsidedi. Neblogas tikslas — 20 % ar daugiau.':
      'E.g. you earned €1,000, spent €750 → rate 25%. The higher, the more you set aside. A good target — 20% or more.',
  'Skaičiuojama tik iš mėnesių, kuriuose matomos pajamos. Jei atlyginimo ar kitų pajamų neaptikta — rodoma „—".':
      'Calculated only from months with visible income. If no salary or other income is detected — "—" is shown.',
  'mėn.': 'mo',
  '% klubas': '% club',

  // ── Account tab / net worth ──
  'Grynasis turtas': 'Net worth',
  'Banko sąskaitos': 'Bank accounts',
  'Pridėti grynų ar santaupų': 'Add cash or savings',
  'Turto kategorija': 'Asset category',
  'Vertė': 'Value',
  'Pavadinimas (pvz. Grynieji, Santaupos)': 'Name (e.g. Cash, Savings)',
  // "Sąskaitos" is homonymous in Lithuanian — bank accounts AND recurring
  // bills. Every remaining tr('Sąskaitos') call site is the bills meaning
  // (the recurring-payments group header, the subs/bills split card); the
  // bank-account list header was changed to the distinct, more precise
  // tr('Banko sąskaitos') below instead of sharing this key.
  'Sąskaitos': 'Bills',
  'Likutis': 'Balance',
  'Prijungti kitą banką': 'Connect another bank',
  'Pažymėti': 'Starred',
  'Nėra pažymėtų sandorių': 'No starred transactions',
  'Kol kas nėra sandorių': 'No transactions yet',
  'Kai bankas atsiųs operacijas, čia matysi išlaidų apžvalgą, kategorijas ir tendencijas.':
      "Once your bank sends transactions, you'll see your spending overview, categories and trends here.",
  'neatnaujinta': 'not updated',
  'Pažymėti bankai kol kas neatidavė naujų duomenų — rodomi paskutiniai žinomi.':
      "The marked banks haven't returned fresh data yet — showing the last known.",
  'Turi pastabų?': 'Have feedback?',
  'Pasakyk, ką galvoji': 'Tell us what you think',
  'Palikti atsiliepimą': 'Leave feedback',
  'Parašyk mums: support@vaultieapp.com': 'Write to us: support@vaultieapp.com',

  // ── Settings ──
  'Nustatymai': 'Settings',
  'Privatumas': 'Privacy',
  'PIN kodas': 'PIN code',
  'Atrakink Vaultie': 'Unlock Vaultie',
  'Atrakink Vaultie su PIN': 'Unlock Vaultie with a PIN',
  'Face ID atrakinimas': 'Face ID unlock',
  'Atrakink Vaultie veidu': 'Unlock Vaultie with your face',
  'Įjunk PIN, kad naudotum Face ID': 'Turn on a PIN to use Face ID',
  'Numatytoji valiuta': 'Default currency',
  'Kalba': 'Language',
  'Tema': 'Theme',
  'Pranešimai': 'Notifications',
  'Priminimai apie mokėjimus': 'Payment reminders',
  'Vaultie prenumerata': 'Vaultie subscription',
  'Atsiskaitymo informacija': 'Billing information',
  'Eksportuoti sandorius': 'Export transactions',
  'Atsisiųsk CSV ar PDF': 'Download CSV or PDF',
  'Atsiliepimai': 'Feedback',
  'Atsijungti': 'Sign out',
  'Grįžti į prisijungimą': 'Back to sign-in',
  'Ištrinti paskyrą': 'Delete account',
  'Ištrink savo Vaultie paskyrą': 'Delete your Vaultie account',
  'Dokumentai': 'Documents',
  'Naudojimo sąlygos': 'Terms of Use',
  'Privatumo politika': 'Privacy Policy',
  'Versija': 'Version',
  'Tavo vardas': 'Your name',
  'Įrašyk vardą': 'Enter a name',
  'Išjungti PIN?': 'Turn off PIN?',
  'Vaultie nebebus užrakinta. Galėsi bet kada vėl įjungti PIN.':
      "Vaultie will no longer be locked. You can turn the PIN back on anytime.",
  'Išjungti': 'Turn off',
  'Skaičiuoklei (Excel, Numbers)': 'For spreadsheets (Excel, Numbers)',
  'Spausdinti ar dalintis ataskaita': 'Print or share a report',
  'Nėra sandorių eksportui': 'No transactions to export',
  'Nepavyko eksportuoti': 'Could not export',
  'Vaultie — sandoriai': 'Vaultie — transactions',
  'bendra suma': 'total',
  'Pavadinimas': 'Name',
  'Suma €': 'Amount €',
  'Pakategorė': 'Subcategory',
  'Prenumeratos informacija': 'Subscription information',
  'Vaultie — prenumerata pagrįstas produktas. Mūsų nefinansuoja reklama ir mes neparduodame duomenų — mus finansuoji tu. Tavo mokestis išlaiko Vaultie be reklamų, privatų ir nuolat tobulėjantį. 💜':
      "Vaultie is a subscription-based product. We aren't funded by ads and we don't sell data — you fund us. Your payment keeps Vaultie ad-free, private and always improving. 💜",
  'Atsijungti?': 'Sign out?',
  'Grįši į prisijungimo ekraną. Tavo duomenys liks išsaugoti šiame telefone ir bus vėl matomi prisijungus.':
      "You'll return to the sign-in screen. Your data stays saved on this phone and reappears when you sign back in.",
  'Atsijungti galima tik tikroje programoje.':
      'You can only sign out in the real app.',
  'Ištrinti paskyrą?': 'Delete account?',
  'Tai VISAM LAIKUI ištrins tavo Vaultie paskyrą ir visus duomenis šiame telefone — sandorius, prenumeratas, biudžetus. Bandysime atjungti banko ryšį. Šio veiksmo anuliuoti negalima.':
      'This will PERMANENTLY delete your Vaultie account and all data on this phone — transactions, subscriptions, budgets. We’ll also try to disconnect the bank connection. This action cannot be undone.',
  // 2026-09-04: added alongside the active-subscription warning in the
  // delete-account dialog — see _confirmDelete's own comment for why.
  'Tai VISAM LAIKUI ištrins tavo Vaultie paskyrą ir visus duomenis šiame telefone — sandorius, prenumeratas, biudžetus. Bandysime atjungti banko ryšį. Šio veiksmo anuliuoti negalima.\n\nTavo „Vaultie Pro" prenumerata App Store\'e liks aktyvi ir toliau bus skaičiuojama — paskyros ištrynimas jos NEATŠAUKIA. Pirma atšauk ją per „Valdyti prenumeratą" žemiau.':
      'This will PERMANENTLY delete your Vaultie account and all data on this phone — transactions, subscriptions, budgets. We’ll also try to disconnect the bank connection. This action cannot be undone.\n\nYour "Vaultie Pro" subscription will stay active on the App Store and keep being charged — deleting your account does NOT cancel it. Cancel it first via "Manage subscription" below.',
  'Patvirtink slaptažodį': 'Confirm your password',
  'Slaptažodis': 'Password',
  'Patvirtinti': 'Confirm',
  'Neteisingas slaptažodis.': 'Wrong password.',

  // ── Search ──
  'Ieškok prekybininko ar kategorijos…': 'Search a merchant or category…',
  'Įrašyk, ko ieškai — pvz. „Maxima", „kuras", „Netflix".':
      'Type what you\'re looking for — e.g. "Maxima", "fuel", "Netflix".',
  'Nieko nerasta': 'Nothing found',
  'sandoris': 'transaction',

  // ── AI chat consent / errors ──
  'AI pokalbis apie tavo finansus': 'AI chat about your finances',
  'Sutinku ir tęsiu': 'I agree and continue',
  'Atsiprašau, nepavyko atsakyti. Pabandyk dar kartą.':
      "Sorry, I couldn't answer. Please try again.",
  'Nepavyko susisiekti su serveriu. Patikrink ryšį ir bandyk dar kartą.':
      'Could not reach the server. Check your connection and try again.',

  // ── AI categorisation consent (Settings toggle) ──
  'Sutinku ir įjungiu': 'I agree and turn it on',

  // ══ Onboarding flow ══
  // ── Landing ──
  'Pradėti': 'Get started',
  'Nuoma': 'Rent',

  // ── Annual bars ──

  // ── Subscription stream ──
  'Toliau': 'Next',
  'Būsto paskola': 'Mortgage',

  // ── Reminders ──
  'dabar': 'now',

  // ── Bank scale ──

  // ── Two paths ──
  'Prijunk banką': 'Connect a bank',
  'Prijungti banką': 'Connect a bank',
  'Pradėti rankiniu būdu': 'Start manually',

  // ── Account (sign up) ──
  'Sukurk paskyrą': 'Create your account',
  'Prisijunk per Google, Apple arba el. paštą.\nTai užtruks mažiau nei minutę.':
      'Sign in with Google, Apple or email.\nIt takes less than a minute.',
  'Tęsti su Google': 'Continue with Google',
  'Tęsti su Apple': 'Continue with Apple',
  'Tęsti su el. paštu': 'Continue with email',
  'Šifruota · Privatūs duomenys · GDPR': 'Encrypted · Private data · GDPR',
  'Sąlygomis': 'Terms',
  ' ir ': ' and ',
  'Jau turi paskyrą? ': 'Already have an account? ',
  'Prisijunk': 'Sign in',

  // ── Onboarding paywall ──
  'Metinis': 'Annual',
  '7 dienos nemokamai': '7 days free',
  'Mėnesinis': 'Monthly',
  'Pirkimas nepavyko. Bandyk dar kartą.': 'Purchase failed. Please try again.',
  'Pirkimas atkurtas.': 'Purchase restored.',
  'Patikrink pasikartojančius': 'Review recurring',
  'Patikrink pasikartojančius mokėjimus': 'Review recurring payments',
  'Pridėti prie pasikartojančių': 'Add to recurring',
  'Ar tai prenumerata, ar sąskaita?': 'Is this a subscription or a bill?',
  'Pridėta prie prenumeratų': 'Added to subscriptions',
  'Pridėta prie sąskaitų': 'Added to bills',
  'nauja': 'new',
  'Rūšiuoti pagal': 'Sort by',
  'Procentai': 'Percent',
  'Pokytis': 'Change',
  'Prenumerata': 'Subscription',
  'Pridėti': 'Add',
  'mėn': 'mo',
  'Matau tik suvestines — jokių atskirų operacijų ar vardų.':
      'I only see summaries — no individual transactions or names.',
  'AI kategorizavimas': 'AI categorisation',
  'Tiksliau atpažįsta parduotuves. Siunčia tik verslo pavadinimus.':
      'More accurate merchant recognition. Sends business names only.',
  // ── subscription info ──
  'Valdyti prenumeratą': 'Manage subscription',
  'Planą pakeisti ar atšaukti gali „App Store“ nustatymuose.':
      'You can change or cancel your plan in App Store settings.',
  'Nepavyko įkelti būsenos.': "Couldn't load your status.",
  'Būsena: neaktyvi': 'Status: inactive',
  'Vaultie Pro': 'Vaultie Pro',
  'bandomasis laikotarpis': 'free trial',
  'nemokamas bandymas iki': 'free trial until',
  'atšaukta': 'cancelled',
  'galioja iki': 'active until',
  'atsinaujina': 'renews',
  'Kraunama…': 'Loading…',
  // ── app lock ──
  'Įvesk PIN kodą': 'Enter your PIN',
  'Vaultie užrakinta': 'Vaultie is locked',
  'Neteisingas PIN — bandyk dar': 'Wrong PIN — try again',
  'Pakartok PIN': 'Repeat your PIN',
  'PIN nesutapo — pradėk iš naujo': "PINs didn't match — start again",
  'Įvesk tą patį kodą dar kartą': 'Enter the same code again',
  'Pamiršai PIN kodą?': 'Forgot your PIN?',
  'Nerasta pirkimų atkurti.': 'No purchases to restore.',
  // Free-trial copy. Composed around the day count, which comes from the live
  // store product — see OnbPaywall._trialLabel.
  'Išbandyti': 'Try',
  'd. nemokamai': 'days free',
  'pirmos': 'first',
  'd. nemokamai, tada': 'days free, then',
  // ── onboarding intro ──
  'bankų': 'banks',
  'visoje Europoje': 'across Europe',
  'Daugiau': 'More',
  // ── bank connect CTA ──
  // Key follows onb_intro.dart's headline exactly. It read "pinigus" here long
  // after the screen had been changed to "finansus", so the lookup missed and
  // English devices were shown the Lithuanian headline.
  // ── paywall ──
  'Mėnesinis planas': 'Monthly plan',
  'Metinis planas': 'Annual plan',
  'Visos Premium funkcijos.': 'All Premium features.',
  'POPULIARUS PASIRINKIMAS': 'MOST POPULAR',
  'Sutaupyk': 'Save',
  'Sutaupai': 'You save',
  '/ mėn.': '/ mo.',
  '/ metus': '/ yr.',
  // 2026-09-04: was 'per year'/'per month' — its only call site
  // (onb_paywall.dart's `_bottom()`) always concatenates it as
  // '$price / $per', which doubled the preposition in English
  // ("€39.99 / per year"). Bare word here; the '/' already reads as "per".
  'metams': 'year',
  'mėnesiui': 'month',
  'Atsinaujina automatiškai, kol neatšauksi App Store nustatymuose likus ne mažiau kaip 24 val. iki laikotarpio pabaigos.':
      'Renews automatically unless cancelled in App Store settings at least 24 hours before the period ends.',
  // ── onboarding demonstrations (onb_welcome / month / planning / security / chat) ──
  'Birželis': 'June',
  'Liepa': 'July',
  'Euras': 'Euro',
  'tavo pinigai': 'your money goes',
  'vienoje vietoje': 'in one place',
  'Liepos suma': 'July total',
  'Susikurk biudžetą': 'Set a budget',
  'Naujas PIN kodas': 'New PIN code',
  'Sugalvok 4 skaitmenų kodą': 'Choose a 4-digit code',
  'Tavo finansų agentas': 'Your finance agent',
  'Tęsti': 'Continue',
  'Atkurti pirkimus': 'Restore purchases',
  // ── onboarding: AI replies, recap, and labels the narrow filter missed ──
  'Pr': 'Mon',
  'An': 'Tue',
  'Tr': 'Wed',
  'Kt': 'Thu',
  'Pn': 'Fri',
  'Št': 'Sat',
  'Sk': 'Sun',

  // ── Recurring review / disconnect / currency notes ──
  'Atjungti bankus ir pradėti iš naujo': 'Disconnect banks and start over',
  'Atjungti VISUS bankus?': 'Disconnect ALL banks?',
  'Kursas nepasiekiamas': 'Rate unavailable',
  'Suskleisti': 'Show less',
  'sąsk.': 'accounts',
  'tuščios': 'empty',
  'šį mėn. dar nėra': 'not yet this month',
  'Atjungti': 'Disconnect',
  'Reikia aktyvios „Vaultie Pro" prenumeratos.':
      'An active Vaultie Pro subscription is required.',
  'Kažkas nepavyko. Bandyk dar kartą.':
      'Something went wrong. Please try again.',
  'Kaip prijungsime tavo banką': 'How we\'ll connect your bank',
  'Prisijungti banke': 'Sign in at your bank',

  // ── Onboarding pages (intro / features / connect) ──
  'Vaultie padeda aiškiau matyti, kur keliauja tavo pinigai, priimti geresnius sprendimus ir viską stebėti vienoje vietoje.':
      'Vaultie helps you see where your money goes, make better decisions and keep everything in one place.',
  '2 700+ bankų visoje Europoje': '2,700+ banks across Europe',

  // ── Onboarding chain 2026-08-19 redesign (onb_intro/banks/month/overview/
  // ai_chat/features/connect.dart) — audited every current tr() key in that
  // chain against this map on 2026-08-19 and found most of it missing, so an
  // English-locale device fell straight through to Lithuanian on nearly
  // every page — the exact bug the "pages 2–7" section above was written to
  // catch, just for copy that was rewritten after that audit ran.
  // 2026-09-03: page 1's headline split into three tr() calls (a gradient
  // accent on the middle word needs its own TextSpan) — same phrase as the
  // line above, just in three pieces so each one still resolves in English.
  'Suprask savo\n': 'Understand your\n',
  'finansus': 'finances',
  ' aiškiau': ' more clearly',
  'VAULTIE': 'VAULTIE',
  // 2026-09-04: split into three tr() calls for the gradient-accented "2
  // 700+" — same phrase as the line above, just in pieces.
  'Jungiame ': 'Connecting ',
  '2 700+': '2,700+',
  ' bankų\nvisoje Europoje': '\nbanks across Europe',
  'Visi tavo bankai, visos tavo sąskaitos vienoje vietoje.':
      'All your banks, all your accounts, in one place.',
  // 2026-09-04: split for the gradient-accented "finansų" — same phrase.
  'Matyk visą ': 'See your whole ',
  'finansų': 'financial',
  ' vaizdą': ' picture',
  'Balansai, išlaidos, pajamos, biudžetas vienoje aiškioje vietoje.':
      'Balances, spending, income and budget in one clear place.',
  // 2026-09-04: split for the gradient-accented "sutaupyti" — same phrase.
  'Stebėk, kur gali ': 'Track where you can ',
  'sutaupyti': 'save',
  'Atrask prenumeratas, sąskaitas ir sek savo santaupų normą.':
      'Discover subscriptions, bills, and track your savings rate.',
  // 2026-09-04: split for the gradient-accented "finansus" (reuses page 1's
  // own translation for that word) — same phrase as the line above.
  'Klausk agento apie savo ': 'Ask the agent about your ',
  'Gauk atsakymus, paremtus tavo realiais finansiniais duomenimis.':
      'Get answers based on your real financial data.',
  'Daugiau funkcijų.\n': 'More features.\n',
  'Daugiau kontrolės.': 'More control.',
  'Išlaidos ir kvitai': 'Expenses and receipts',
  'Biudžetas ir tikslai': 'Budget and goals',
  // 2026-09-02: OnbFeatures condensed to 5 cards — new/changed strings from
  // that redesign. Added immediately, not left to fall back to Lithuanian —
  // that fallback is exactly what made this page show a mix of languages in
  // the first place (the OLD strings just above already had EN entries; new
  // ones next to them on the same screen didn't yet).
  'Tvarkyk savo kasdienius finansus vienoje vietoje.':
      'Manage your everyday finances in one place.',
  'Skenuok kvitus, sek išlaidas ir kategorijas.':
      'Scan receipts, track expenses and categories.',
  'Nustatyk biudžetus ir siek savo tikslų.':
      'Set budgets and reach your goals.',
  'Sąskaitos ir priminimai': 'Bills and reminders',
  'Sek prenumeratas, sąskaitas ir mokėk laiku.':
      'Track subscriptions, bills, and pay on time.',
  'Bankai, valiutos, eksportas': 'Banks, currencies, export',
  'Prijunk bankus, konvertuok valiutas, eksportuok duomenis.':
      'Connect banks, convert currencies, export your data.',
  'Saugumas ir pritaikymas': 'Security and personalisation',
  'Face ID, PIN, kalba ir tema — kaip tau patogu.':
      'Face ID, PIN, language and theme — however you like.',
  // OnbInvest (2026-09-01/02) — same missing-translation bug, same fix.
  ' šalia tavo finansų': ' alongside your finances',
  'Akcijas ir kriptovaliutas stebėk kartu su kasdieniais pinigais.':
      'Track stocks and crypto alongside your everyday money.',
  'Akcijos': 'Stocks',
  'Tesla, Apple, Google ir kitos populiariausios akcijos.':
      'Tesla, Apple, Google and other popular stocks.',
  'Kriptovaliuta': 'Crypto',
  'Bitcoin, Ethereum ir kitos kriptovaliutos.':
      'Bitcoin, Ethereum and other cryptocurrencies.',
  'Pokyčiai realiu laiku': 'Real-time changes',
  'Kainos kyla ir krenta — matai iš karto.':
      'Prices rise and fall — you see it instantly.',
  // Dev-only onboarding-replay tools (Settings + LoginScreen) — never shown
  // in a release build, but the same missing-translation bug either way.
  'Peržiūrėti onboardingą': 'Replay onboarding',
  'Peržiūrėti onboardingą iš naujo': 'Replay onboarding from the start',
  'Peržiūrėti paywall': 'Preview paywall',
  'Šifruota': 'Encrypted',
  'Atšauk bet kada': 'Cancel anytime',
  '2 700+ bankų': '2,700+ banks',
  'Atsijungia ir grąžina į onboardingo pradžią':
      'Signs out and returns to the start of onboarding',
  'Visada rodyti onboardingą': 'Always show onboarding',
  'Kol įjungta, kiekvienas paleidimas rodo onboardingą iš naujo':
      'While on, every launch shows onboarding again',
  'Prijunk savo ': 'Connect your ',
  'banką\n': 'bank\n',
  'saugiai ir greitai': 'safely and quickly',
  'Prisijunk prie banko per savo banko sistemą. Tavo prisijungimo duomenys lieka tik banke.':
      'Sign in through your own bank’s system. Your login details stay with the bank.',
  'Tu kontroliuoji prieigą': 'You control access',
  'Tu nusprendi, kokius duomenis bendrinti ir kada atšaukti prieigą.':
      'You decide what data to share and when to revoke access.',
  'Saugumas pirmoje vietoje': 'Security comes first',
  'Jungiamės per licencijuotą Open Banking infrastruktūrą pagal PSD2 standartą.':
      'We connect through licensed Open Banking infrastructure under the PSD2 standard.',
  'Mes galime tik skaityti tavo duomenis. Mokėjimų neatliekame.':
      'We can only read your data. We never make payments.',
  'Tavo duomenys – tavo nuosavybė': 'Your data is yours',
  'Duomenys yra apsaugoti ir naudojami tik tavo Vaultie patirčiai pagerinti.':
      'Your data is protected and only ever used to improve your Vaultie experience.',

  // ── Paywall ──
  'Atšaukti gali bet kada.': 'Cancel any time.',
  'Išbandyk': 'Try',

  // ── Sign-in terms line ──
  'Tęsdamas (-a) sutinki su ': 'By continuing you agree to the ',

  // ── Transfer caveat in the "Gauta" breakdown ──
  'Prijungus kelis bankus, pervedimai tarp tavo paties sąskaitų čia gali būti suskaičiuoti kaip įplauka, jei bankas neatskleidžia gavėjo sąskaitos.':
      'With several banks connected, transfers between your own accounts can be counted as income here when the bank does not reveal the receiving account.',

  // ── Onboarding showcase / demo chat (marketing copy over sample data) ──
  'Per mėnesį': 'Per month',
  'Per metus': 'Per year',

  // ── Prenumeratos / Sąskaitos (subs_bills_live.dart) — 2026-08-16 ──
  'Kaip pavadinti?': 'What should we call it?',
  'įvesk tikrąjį pavadinimą. Pervadinimas paveiks tik šitos kainos mokėjimus.':
      'enter the real name. Renaming only affects payments at this price.',
  'Nerasta sinchronizuotų banko duomenų šiame įrenginyje.\n'
          'Atidaryk tikrąją Vaultie ir susisiek su banku bent kartą.':
      'No synced bank data found on this device.\n'
          'Open the real Vaultie and connect a bank at least once.',
  'Rask savo prenumeratas': 'Find your subscriptions',
  'Rask savo sąskaitas': 'Find your bills',
  'Peržiūrėti mokėjimus': 'Review payments',
  'Ieškok pats savo tranzakcijose': 'Search your own transactions',
  'Nieko naujo nerasta': 'Nothing new found',
  'kada nusiskaito?': 'when does it charge?',
  'Atstatyti numatytą dieną': 'Reset to the predicted day',
  'Rasti naują prenumeratą': 'Find a new subscription',
  'Rasti naują sąskaitą': 'Find a new bill',
  'pridėta': 'added',
  'Peržiūrėk mokėjimus': 'Review payments',
  'Ieškoti pagal pavadinimą…': 'Search by name…',
  'Nieko nerasta.': 'Nothing found.',
  'Viskas peržiūrėta.': 'Everything reviewed.',
  'Neradai automatiškai? Iš tavo tranzakcijų:':
      "Didn't find it automatically? From your transactions:",
  'Ne': 'No',
  'Taip, prenumerata': 'Yes, subscription',
  'Taip, sąskaita': 'Yes, bill',
  'Pridėti prie prenumeratų': 'Add to subscriptions',
  'Pridėti prie sąskaitų': 'Add to bills',
  'matyta': 'seen',
  // 'vidurkis' → 'average' already defined above (line ~73).

  'sąskaitos': 'bills',
  'aktyvios': 'active',
  'kitas': 'next',

  // ── Onboarding pages 2–7 (onb_features/month/overview/ai_chat/budget/
  // connect/notifications.dart) — every one of these was tr()-wrapped in code
  // already but had no _en entry, so an English-locale device fell all the way
  // through onboarding still reading Lithuanian. Found 2026-08-03 by auditing
  // every onb_*.dart file against this map, prompted by a reviewer-visibility
  // concern right before submission — App Review may walk the full first-run
  // chain, not just sign in with the demo account.
  'Mėnesio biudžetas': 'Monthly budget',
  'Tik skaitymo prieiga': 'Read-only access',
  'Tavo duomenys': 'Your data',
  'Jungiame prie ': 'We connect to ',
  '2 500+ bankų': '2,500+ banks',
  ' visoje Europoje': ' across Europe',
  'Priminsime prieš laiką': "We'll remind you in time",
  'Pranešime prieš mokėjimą, kai baigsis banko prieiga ir kai bus paruošta mėnesio ataskaita.':
      "We'll notify you before a payment, when your bank access is about to expire, and when your monthly report is ready.",
  'Mokėjimas po 2 d.': 'Payment in 2 days',
  'Banko prieiga baigiasi': 'Bank access expiring',
  'Po 7 d. reikės prisijungti iš naujo, kad duomenys nesustotų.':
      "In 7 days you'll need to reconnect, so your data doesn't stop updating.",
  'vakar': 'yesterday',
  'Mėnesio ataskaita paruošta': 'Monthly report ready',
  'Pažiūrėk, kiek išleidai praėjusį mėnesį.':
      'See how much you spent last month.',
  'prieš 3 d.': '3 days ago',
  'Įjungti priminimus': 'Enable reminders',
  'Ne dabar': 'Not now',

  'tada': 'then',

  // ── Onboarding scene showcase (lib/screens/preview/showcase.dart) — the
  // LIVE demo phone replayed inside the onboarding artwork. Its sample bills/
  // subscriptions/category names and dates are tr()-wrapped in code but had
  // no _en entries at all, so an English-locale device saw fully Lithuanian
  // category names and dates ("Rugpjūčio 1") inside an otherwise-English
  // onboarding screen. Found 2026-08-03 from a device screenshot.
  'Būstas': 'Housing',
  'Maistas': 'Food',
  'Kavinė': 'Café',
  'Elektra': 'Electricity',
  'Internetas': 'Internet',
  'Mobilusis': 'Mobile',
  'Vanduo': 'Water',
  'Sporto klubas': 'Gym',
  'Automobilio draudimas': 'Car insurance',
  'Lie': 'Jul',
  'Rgp': 'Aug',
  'Rgs': 'Sep',
  'Spa': 'Oct',
  'Lap': 'Nov',
  'Liepos 14': 'July 14',

  // ── bank_how_it_works.dart — the pre-connect explainer + its "Why this is
  // safe" sheet. Every string here was tr()-wrapped but had no _en entry,
  // same class of bug as onboarding: found from a device screenshot showing
  // English chrome (title, Continue button) around fully-Lithuanian body
  // text. 2026-08-03.
  'Pasirink savo banką': 'Choose your bank',
  'Patvirtink prieigą banke': 'Confirm access at your bank',
  'Grįžk į Vaultie': 'Back to Vaultie',
  'Kodėl tai saugu': 'Why this is safe',
  'Licencijuotas tarpininkas': 'Licensed intermediary',
  // 2026-09-03's copy rewrite of this same screen (shorter step cards, a
  // new safety-card heading) shipped without updating this map either —
  // the exact same class of bug as the 2026-08-03 entries just above,
  // found again by the 2026-09-04 audit. Added, not replacing the old
  // entries above (which may still be reachable from cached strings).
  'Vos 3 žingsniai iki prijungto banko.': 'Just 3 steps to a connected bank.',
  'Iš daugiau nei 2 700+ Europos bankų.': 'From over 2,700+ European banks.',
  'Tavo banko duomenys saugūs': 'Your bank details are safe',
  'Niekada nematome tavo slaptažodžio': 'We never see your password',
  'Tik skaitymas': 'Read-only',
  'Duomenys lieka tavo telefone': 'Your data stays on your phone',
  'AI — tik tavo sutikimu': 'AI — only with your consent',
  'Tu valdai prieigą': 'You control access',
};
