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
  'Taupomoji': 'Savings',
  'Kortelės sąskaita': 'Card account',
  'Paskolos sąskaita': 'Loan account',

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
  'Dar nėra pajamų duomenų': 'No income data yet',
  'Sutaupei': 'You saved',
  'Viršyta': 'Over by',
  'praėjusio mėn.': 'last month',
  'iš viso': 'total',
  'Kur išleidai daugiausiai': 'Where you spent the most',
  'Paskutinių': 'Last',
  'Visos operacijos': 'All transactions',
  'Šio mėnesio operacijos': 'This month’s transactions',

  // ── Home: Finance Agent banner ── (const Text, never wrapped in tr() —
  // stayed Lithuanian even with the app language set to English)
  'Finansų Agentas': 'Finance Agent',
  'Klausk manęs visko apie savo pinigus. Aš čia, kad padėčiau!':
      'Ask me anything about your money. I\'m here to help!',

  // ── Cash on hand (Home hero + Paskyra net worth) ── ('Grynieji' itself is
  // already translated below, in Sub-categories & transaction labels)
  'Kiek turi grynųjų?': 'How much cash do you have?',
  'Kiek gavai grynais?': 'How much cash did you get?',
  'Kiek išleidai grynais?': 'How much cash did you spend?',

  // ── Filters / week ──
  'Filtras': 'Filter',
  'Visas laikas': 'All time',
  'Šios savaitės išlaidos': 'This week’s spending',
  'vidurkis': 'average',
  'Šią savaitę išėjo': 'Left your account this week',
  'Šią savaitę išleista': 'Spent this week',
  'Praėjusią savaitę išleista': 'Spent last week',
  'Išėjo, ne išlaidos': 'Left, not spending',

  // ── Subscriptions card ──
  'PRENUMERATOS IR SĄSKAITOS': 'SUBSCRIPTIONS & BILLS',
  'Tvarkyti': 'Manage',
  'aktyvūs mokėjimai': 'active payments',
  'baigėsi': 'ended',

  // ── Month feed / headers ──
  'Išleista': 'Spent',
  'Gauta': 'Received',
  'grynasis': 'net',
  'Rodyti senesnius': 'Show older',
  'sandoriai': 'transactions',
  'sandorių': 'transactions',
  'apžvalga': 'review',
  'Peržiūrėti': 'View',

  // ── AI chat ──
  'Klausk apie savo pinigus': 'Ask about your money',
  'Pabandyk paklausti:': 'Try asking:',
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
  'Jungiklis — įjungtas skaičiuojasi į mėnesio sumą. Nebemoki ar tai ne prenumerata → išjunk.':
      'Toggle — on counts towards the monthly total. Not sure if it\'s a subscription anymore → turn it off.',
  'Šiukšlinė — paslėpti visai (jei tai ne pasikartojantis mokėjimas).':
      'Trash — hide it completely (if it isn\'t a recurring payment).',
  'Bakstelk pavadinimą — pervadinti arba pakeisti tipą (prenumerata ↔ sąskaita).':
      'Tap the name — rename it or switch its type (subscription ↔ bill).',
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
  'Reikia bent 2 mėnesių duomenų grafikui': 'Need at least 2 months of data for a chart',
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
  'Sek savo investicijas': 'Track your investments',
  'Įvesk akciją ir kiek jos turi — parodysime tikrą dabartinę kainą ir kiek uždirbai ar praradai.':
      'Add a stock and how much you have — we\'ll show the real current price and what you\'ve gained or lost.',
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
  'Nerasta — kol kas turime tik populiariausias akcijas.':
      'Not found — for now we only cover the most popular stocks.',
  'Keisti': 'Change',
  'Kiek akcijų turi?': 'How many shares do you have?',
  'Kaina per pastarąsias dienas': 'Price over the last few days',
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
  'Kaina — praėjusios dienos uždarymo kursas, ne gyva realaus laiko rinka.':
      'Price is yesterday\'s closing price, not a live real-time market feed.',
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
  'Gerai': 'OK',
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
  'Kad atpažintų prekes ir sumą, „Vaultie" siunčia NUFOTOGRAFUOTĄ kvitą mūsų AI tiekėjui (Anthropic).\n\n• Nuotrauka NIEKUR neišsaugoma — panaudota atpažinimui ir iškart pašalinama.\n• Siunčiama tik pati kvito nuotrauka, jokių kitų tavo duomenų.':
      'To recognise the items and total, "Vaultie" sends the PHOTOGRAPHED receipt to our AI provider (Anthropic).\n\n• The photo is never stored anywhere — it\'s used for recognition and discarded immediately.\n• Only the receipt photo itself is sent, none of your other data.',
  'Atpažinsime prekes ir sumą, sutikrinsime su banko operacija arba, jei mokėjai grynais, pridėsime kaip naują įrašą.':
      'We\'ll recognise the items and total, match it to a bank transaction, or — if you paid cash — add it as a new entry.',
  'Automatiškai suras atitinkančią banko operaciją':
      'Automatically finds the matching bank transaction',
  'Gali padalinti kvitą į kelias kategorijas':
      'You can split the receipt into several categories',
  'Jei mokėjai grynais — pridėsime be papildomų žingsnių':
      'If you paid cash — we\'ll add it with no extra steps',
  'Sumokėjai grynais?': 'Paid with cash?',
  'Bankas grynųjų operacijų nemato — pridėk jas pats, kad Bendras likutis liktų tikslus.':
      'The bank can\'t see cash transactions — add them yourself so your Total balance stays accurate.',
  'Nufotografuok kvitą — automatiškai atpažinsime sumą':
      'Photograph the receipt — we\'ll recognise the total automatically',
  'Arba įvesk sumą ranka per kelias sekundes':
      'Or enter the amount by hand in a few seconds',
  'Grynųjų likutis atsinaujins iš karto': 'Your cash balance updates instantly',
  'Supratau, tęsti': 'Got it, continue',
  'Įvesk sumą ir pasirink kategoriją per kelias sekundes':
      'Enter the amount and pick a category in a few seconds',
  'Arba nuskenuok kvitą — tik jei apmokėjai grynaisiais':
      'Or scan the receipt — only if you paid in cash',
  'Tik jeigu kvitas apmokėtas grynaisiais pinigais':
      'Only if the receipt was paid in cash',
  'Moki grynais?': 'Paying with cash?',
  'Bankas nemato tavo grynųjų išlaidų — pridėk jas pats, kad likutis būtų tikslus.':
      'The bank can\'t see your cash spending — add it yourself so the balance stays accurate.',
  'Įvesk sumą ir pasirink kategoriją': 'Enter the amount and pick a category',
  'Nuskenuok kvitą, jei mokėjai grynais':
      'Scan the receipt, if you paid in cash',
  'Grynieji likučiai atsinaujins iš karto': 'Your cash balance updates instantly',
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
  'Viskas paskirstyta': 'Fully assigned',
  'Nepavyko atpažinti kvito — pabandyk dar kartą arba įvesk rankiniu būdu':
      'Could not read the receipt — try again or enter it manually',
  'NAUJA': 'NEW',
  'Pasirink kvito nuotrauką — automatiškai suskaidysime pirkinį pagal kategorijas':
      'Pick a photo of the receipt — we\'ll split the purchase by category automatically',
  'Nepavyko atpažinti kvito — pabandyk kitą nuotrauką':
      'Could not read the receipt — try a different photo',
  'Su kuria operacija susieti?': 'Which transaction is this?',
  'Nerasta panašios operacijos per pastarąsias dienas. Atidaryk ją Transakcijose ir suskaidyk iš ten — "Skaidyti".':
      'No matching transaction found in the last few days. Open it in Transactions and split it from there — "Split".',
  'Atpažinta suma': 'Recognised total',
  'pasirink, kuri banko operacija tai yra': 'pick which bank transaction this is',
  'Padalink sąskaitą tarp žmonių — niekas neišsaugoma':
      'Split the bill between people — nothing is saved',
  'Padalinti sąskaitą': 'Split the bill',
  'Niekas neišsaugoma': 'Nothing is saved',
  'Kas dalinasi?': 'Who\'s splitting?',
  'Vardas…': 'Name…',
  'Kas ką pirko?': 'Who bought what?',
  'Pirmiau pridėk bent vieną žmogų.': 'Add at least one person first.',
  'Nepriskirta': 'Unassigned',
  'Uždaryti': 'Close',

  // ── Recurring status / cadence / kind / payment-type (variable-resolved) ──
  'Aktyvus': 'Active',
  'Vėluoja': 'Late',
  'Baigėsi': 'Ended',
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
  'Euras (EUR)': 'Euro (EUR)',
  'Norvegijos krona (NOK)': 'Norwegian krone (NOK)',
  'JAV doleris (USD)': 'US dollar (USD)',
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
  'Įrašas pridėtas': 'Entry added',

  // ── Manual entry ──
  'Pridėti ranka': 'Add manually',
  'Įrašyk tai, ko ': 'Record what ',
  'bankas nemato': "the bank can't see",
  ' — grynuosius, skolą draugui, pervedimą tarp savo sąskaitų.':
      ' — cash, a loan to a friend, a transfer between your own accounts.',
  'Išlaida': 'Expense',
  'Pinigai, kuriuos išleidai — pvz. sumokėjai grynais.':
      'Money you spent — e.g. paid in cash.',
  'Didina mėnesio išlaidas': 'Increases monthly spending',
  'Gauti pinigai — atlyginimas grynais, dovana, grąžinta skola.':
      'Money received — salary in cash, a gift, a repaid loan.',
  'Didina mėnesio pajamas': 'Increases monthly income',
  'Vidinis pervedimas': 'Internal transfer',
  'Perkėlei pinigus tarp savo sąskaitų arba išsiėmei grynųjų.':
      'You moved money between your own accounts or withdrew cash.',
  'Neįskaičiuojama į išlaidas ar pajamas': "Not counted as spending or income",
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
  'sporto klubą': 'the gym',
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
  'Šiuo laikotarpiu operacijų nerasta.': 'No transactions found for this period.',
  'Išleidau grynais': 'Cash expense',
  'Apmokėta grynais': 'Paid in cash',
  'Filtruota': 'Filtered',
  'Rodoma tik': 'Showing only',
  'Mokėjau grynais': 'Paid with cash',
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
  '€ — sulėtink.': '€ — ease off.',
  '— sulėtink.': '— slow down.',
  'Pasiūlyta pagal tavo išlaidas · keisk':
      'Suggested from your spending · edit',
  'Tavo biudžetas · keisk': 'Your budget · edit',
  'virš pasiūlymo': 'over the suggestion',
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
  'aktyvūs mokėjimai — bakstelėk tvarkyti': 'active payments — tap to manage',
  'įskaičiuota': 'counted',
  'Pasikartojančius mokėjimus atpažinti sunku — patikrink. Įjungti (žali) skaičiuojami į mėnesio sumą; nebemoki arba tai ne sąskaita — išjunk.':
      "Recurring payments are hard to detect — check them. Ones that are on (green) count toward the monthly total; if you no longer pay or it isn't a bill — turn it off.",
  'Pasikartojančių mokėjimų nerasta.': 'No recurring payments found.',
  'Įskaičiuota': 'Counted',
  'Išjungta': 'Off',
  'Neįskaičiuota': 'Not counted',
  'Pavadinti prenumeratą': 'Name the subscription',
  'Bankas nepasako, kas tai. Pavadink, kad atpažintum.':
      "The bank won't say what this is. Name it so you recognise it.",
  'pvz. ChatGPT, iCloud, Spotify': 'e.g. ChatGPT, iCloud, Spotify',
  'Palikti kaip': 'Keep as',
  'paskutinį kartą': 'last charged',

  // ── Overview extras ──
  'Žymos': 'Tags',
  'Pridėti žymą': 'Add tag',
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
  'Naujiena: matyk visą savo turtą': 'New: see all your wealth',
  'Pridėk būstą, investicijas, paskolas ir daugiau — visą finansinį vaizdą vienoje vietoje.':
      'Add property, investments, loans and more — your whole financial picture in one place.',
  'Geresni AI patarimai, kai Vaultie mato visą tavo situaciją.':
      'Better AI advice when Vaultie sees your whole picture.',
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
  'Būsena: Bandomasis laikotarpis': 'Status: Trial period',
  'Vaultie — prenumerata pagrįstas produktas. Mūsų nefinansuoja reklama ir mes neparduodame duomenų — mus finansuoji tu. Tavo mokestis išlaiko Vaultie be reklamų, privatų ir nuolat tobulėjantį. 💜':
      "Vaultie is a subscription-based product. We aren't funded by ads and we don't sell data — you fund us. Your payment keeps Vaultie ad-free, private and always improving. 💜",
  'Susisiekti su pagalba': 'Contact support',
  'Atsijungti?': 'Sign out?',
  'Grįši į prisijungimo ekraną. Tavo duomenys liks išsaugoti šiame telefone ir bus vėl matomi prisijungus.':
      "You'll return to the sign-in screen. Your data stays saved on this phone and reappears when you sign back in.",
  'Atsijungti galima tik tikroje programoje.':
      'You can only sign out in the real app.',
  'Ištrinti paskyrą?': 'Delete account?',
  'Tai VISAM LAIKUI ištrins tavo Vaultie paskyrą ir visus duomenis šiame telefone — sandorius, prenumeratas, biudžetus. Banko ryšys bus atjungtas. Šio veiksmo anuliuoti negalima.':
      'This will PERMANENTLY delete your Vaultie account and all data on this phone — transactions, subscriptions, budgets. The bank connection will be disconnected. This action cannot be undone.',
  'Ištrinti paskyrą galima tik tikroje programoje.':
      'You can only delete your account in the real app.',
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
  'Kad atsakytų į klausimus, „Vaultie" siunčia mūsų AI tiekėjui (Anthropic) TAVO finansų SANTRAUKĄ — banko likučius, išlaidas pagal kategoriją ir tavo pasikartojančių mokėjimų pavadinimus (pvz. „Netflix").\n\n• Nesiunčiami atskiri sandoriai, IBAN‑ai ar kortelių numeriai.\n• Duomenys NENAUDOJAMI dirbtinio intelekto treniravimui.\n• Tai nėra finansinė konsultacija.':
      'To answer your questions, the app sends our AI provider (Anthropic) a SUMMARY of YOUR finances — bank balances, spending by category and the names of your recurring payments (e.g. "Netflix").\n\n• Individual transactions, IBANs or card numbers are not sent.\n• The data is NOT used to train AI.\n• This is not financial advice.',
  'Sutinku ir tęsiu': 'I agree and continue',
  'Atsiprašau, nepavyko atsakyti. Pabandyk dar kartą.':
      "Sorry, I couldn't answer. Please try again.",
  'Nepavyko susisiekti su serveriu. Patikrink ryšį ir bandyk dar kartą.':
      'Could not reach the server. Check your connection and try again.',

  // ── AI categorisation consent (Settings toggle) ──
  'Kai įjungta, prekybininko pavadinimą, kurio Vaultie pati neatpažįsta, siunčiame mūsų AI tiekėjui (Anthropic), kad padėtų priskirti kategoriją.\n\n• Siunčiamas TIK verslo pavadinimas — niekada suma, IBAN, data ar kito žmogaus vardas.\n• Asmeniniai pervedimai (žmonių vardai) niekada nesiunčiami.\n• Duomenys NENAUDOJAMI dirbtinio intelekto treniravimui.\n\nBet kada gali išjungti čia, Nustatymuose.':
      "When on, a merchant name Vaultie itself can't recognise is sent to our AI provider (Anthropic) to help assign a category.\n\n• ONLY the business name is sent — never an amount, IBAN, date, or another person's name.\n• Personal transfers (people's names) are never sent.\n• The data is NOT used to train AI.\n\nYou can turn this off anytime here, in Settings.",
  'Sutinku ir įjungiu': 'I agree and turn it on',

  // ══ Onboarding flow ══
  // ── Landing ──
  'Sužinok, kur dingsta\ntavo pinigai': 'See where your\nmoney goes',
  'Nuoma, prenumeratos, draudimas — viskas vienoje vietoje.':
      'Rent, subscriptions, insurance — all in one place.',
  'Pradėti': 'Get started',
  'Jau turiu paskyrą': 'I already have an account',
  'KAS MĖNESĮ IŠEINA': 'LEAVES EVERY MONTH',
  'Nuoma': 'Rent',
  'nenaudota 3 mėn.': 'unused 3 mo',

  // ── Annual bars ──
  'Net mažos išlaidos per metus\nvirsta didele suma.':
      'Even small costs add up\nto a big sum over a year.',
  'Vaultie automatiškai apskaičiuoja, kiek tavo prenumeratos ir kitos pasikartojančios išlaidos kainuoja per metus.':
      'Vaultie automatically calculates how much your subscriptions and other recurring costs add up to per year.',

  // ── Subscription stream ──
  'Toliau': 'Next',
  'Visos tavo prenumeratos.\nVienoje vietoje.':
      'All your subscriptions.\nIn one place.',
  'Vaultie automatiškai suranda pasikartojančius mokėjimus banko išraše.':
      'Vaultie automatically finds recurring payments in your bank statement.',
  'nenaudota 3 mėn': 'unused 3 mo',
  '−12€/mėn': '−€12/mo',
  '10,99 € / mėn': '€10.99 / mo',
  'Būsto paskola': 'Mortgage',
  '420,00 € / mėn': '€420.00 / mo',
  '28,00 € / mėn': '€28.00 / mo',
  'nenaudota 4 mėn': 'unused 4 mo',
  '−35€/mėn': '−€35/mo',
  '11,99 € / mėn': '€11.99 / mo',
  'Sporto salė': 'Gym',

  // ── Reminders ──
  'Įspėsim prieš kiekvieną\nmokėjimą.': "We'll warn you before every\npayment.",
  'Jokių netikėtų nurašymų — spėsi atšaukti, kol pinigai dar nenuskaityti.':
      "No surprise charges — you'll have time to cancel before the money is taken.",
  'dabar': 'now',
  'Rytoj nurašys Netflix — 12,99 €': 'Netflix charges tomorrow — €12.99',
  'Po 2 d. atsinaujins Spotify — 10,99 €': 'Spotify renews in 2 days — €10.99',
  'YouTube Premium po 4 d. — 11,99 €': 'YouTube Premium in 4 days — €11.99',
  'Disney+ nenaudotas 2 mėn — gal atšaukti?':
      'Disney+ unused for 2 mo — cancel?',
  'iCloud+ nurašys rytoj — 2,99 €': 'iCloud+ charges tomorrow — €2.99',

  // ── Bank scale ──
  'Jungiamės prie 2 500+ bankų\nvisoje Europoje.':
      'We connect to 2,500+ banks\nacross Europe.',
  '2 500+ bankų · saugus ryšys': '2,500+ banks · secure connection',

  // ── Two paths ──
  'Prijunk banką': 'Connect a bank',
  'Vaultie automatiškai suras visas tavo prenumeratas ir pasikartojančius mokėjimus.':
      'Vaultie will automatically find all your subscriptions and recurring payments.',
  'Prijungti banką': 'Connect a bank',
  'Pradėti rankiniu būdu': 'Start manually',
  'Nemokamai iki 5 prenumeratų. Banką galėsi prijungti bet kuriuo metu.':
      'Free for up to 5 subscriptions. You can connect a bank anytime.',
  'Saugus prisijungimas per Enable Banking — licencijuotą ES partnerį.':
      'Secure connection via Enable Banking — a licensed EU partner.',

  // ── Account (sign up) ──
  'Sukurk paskyrą': 'Create your account',
  'Prisijunk per Google, Apple arba el. paštą.\nTai užtruks mažiau nei minutę.':
      'Sign in with Google, Apple or email.\nIt takes less than a minute.',
  'Tęsti su Google': 'Continue with Google',
  'Tęsti su Apple': 'Continue with Apple',
  'Tęsti su el. paštu': 'Continue with email',
  'Šifruota · Privatūs duomenys · GDPR': 'Encrypted · Private data · GDPR',
  'Tęsdamas sutinki su ': 'By continuing you agree to the ',
  'Sąlygomis': 'Terms',
  ' ir ': ' and ',
  'Jau turi paskyrą? ': 'Already have an account? ',
  'Prisijunk': 'Sign in',

  // ── Onboarding paywall ──
  'Leisk Vaultie pasirūpinti tavo prenumeratomis.':
      'Let Vaultie take care of your subscriptions.',
  'Automatiškai suranda prenumeratas': 'Automatically finds your subscriptions',
  'Įspėja prieš artėjančius mokėjimus': 'Warns you before upcoming payments',
  'Parodo, kur iš tikrųjų išleidi pinigus':
      'Shows where your money really goes',
  'Viskas vienoje vietoje – be rankinio darbo':
      'Everything in one place – no manual work',
  'Metinis': 'Annual',
  '7 dienos nemokamai': '7 days free',
  'Mėnesinis': 'Monthly',
  'Pradėti 7 dienų bandymą': 'Start 7-day trial',
  '€2,50/mėn': '€2.50/mo',
  'SUTAUPAI 37%': 'SAVE 37%',
  'Pirkimas nepavyko. Bandyk dar kartą.': 'Purchase failed. Please try again.',
  'Planai kol kas nepasiekiami. Bandyk vėliau arba praleisk.':
      'Plans are unavailable right now. Try again later or skip.',
  'Pirkimas atkurtas.': 'Purchase restored.',
  'Sveiki 👋': 'Hi 👋',
  'Kuo galiu padėti?': 'How can I help?',
  'Patikrink pasikartojančius': 'Review recurring',
  'Patikrink pasikartojančius mokėjimus': 'Review recurring payments',
  'Pašalinta iš sąrašo': 'Removed from list',
  'Pridėti prie pasikartojančių': 'Add to recurring',
  'Ar tai prenumerata, ar sąskaita?': 'Is this a subscription or a bill?',
  'Pridėta prie prenumeratų': 'Added to subscriptions',
  'Pridėta prie sąskaitų': 'Added to bills',
  'nauja': 'new',
  'sumokėta': 'paid',
  'laukiama': 'pending',
  'Rūšiuoti pagal': 'Sort by',
  'Procentai': 'Percent',
  'Pokytis': 'Change',
  'Paslėpti': 'Hidden',
  'Grąžinti': 'Restore',
  'Tipas': 'Type',
  'Prenumerata': 'Subscription',
  'Pridėti pasikartojantį': 'Add recurring',
  'Pridėti': 'Add',
  'mėn': 'mo',
  'pvz. Sporto klubas': 'e.g. Gym',
  'PASIKARTOJANTYS': 'RECURRING',
  'Ar tikrai juos seki?': 'Are they really yours?',
  'Šių tiksliai neatpažinome — ar tikrai juos seki?':
      "We couldn't identify these for sure — are they really yours?",
  'Šių mokėjimų tiksliai neatpažinome. Patvirtink, kad tai tavo pasikartojantis mokėjimas, arba pašalink.':
      "We couldn't identify these payments for sure. Confirm each is a recurring payment of yours, or remove it.",
  'Taip, seku': 'Yes, I track it',
  'Ne, pašalinti': 'No, remove',
  'Viskas patikrinta': 'All reviewed',
  'Nieko tikrinti nereikėjo.': 'Nothing needed reviewing.',
  'Ačiū — pasikartojantys sutvarkyti.':
      'Thanks — your recurring payments are sorted.',
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
  'Atjungsime tave, kad galėtum prisijungti iš naujo ir nusistatyti naują PIN. Tavo duomenys liks šiame telefone.':
      'We\'ll sign you out so you can sign in again and set a new PIN. Your data stays on this phone.',
  'Nerasta pirkimų atkurti.': 'No purchases to restore.',
  // Free-trial copy. Composed around the day count, which comes from the live
  // store product — see OnbPaywall._trialLabel.
  'Išbandyti': 'Try',
  'd. nemokamai': 'days free',
  'pirmos': 'first',
  'd. nemokamai, tada': 'days free, then',
  '7 dienos nemokamai. Atšaukus iki bandomojo laikotarpio pabaigos, mokestis nebus nuskaičiuotas. Vėliau taikomas pasirinkto plano mokestis, kol atsisakysi App Store nustatymuose.':
      "7 days free. Cancel before the trial ends and you won't be charged. After that, the selected plan's price applies until you cancel in App Store settings.",
  // ── onboarding intro ──
  'Geriau suprask\nsavo pinigus': 'Understand your\nmoney better',
  'Stebėk išlaidas, analizuok įpročius\nir atrask, kur gali sutaupyti.':
      'Track spending, spot habits\nand find where you can save.',
  'Prisijungimai prie': 'Connects to',
  'bankų': 'banks',
  'visoje Europoje': 'across Europe',
  'Populiariausi bankai': 'Most popular banks',
  'Daugiau': 'More',
  'Jūsų pasitikėjimas mums svarbiausias': 'Your trust matters most',
  'Naudojame bankų lygio saugumą, esame licencijuoti ir atitinkame visus ES standartus.':
      'We use bank-level security, we are licensed and we meet all EU standards.',
  'Bankų lygio\napsauga': 'Bank-level\nsecurity',
  'Licencijuoti\nES': 'Licensed\nin the EU',
  'Atitinka PSD2\nreglamentą': 'PSD2\ncompliant',
  // ── bank connect CTA ──
  // Key follows onb_intro.dart's headline exactly. It read "pinigus" here long
  // after the screen had been changed to "finansus", so the lookup missed and
  // English devices were shown the Lithuanian headline.
  'Suprask savo\nfinansus geriau': 'Understand your\nmoney better',
  'Prijunk banką ir Vaultie automatiškai\natras tai, ko nepastebi banko programėlė.':
      'Connect your bank and Vaultie will find\nwhat your banking app does not show.',
  'Banko lygio saugumas': 'Bank-level security',
  'Naudojame bankų lygio šifravimą ir laikomės aukščiausių ES saugumo standartų.':
      'We use bank-level encryption and follow the highest EU security standards.',
  'Greitas prisijungimas': 'Quick to connect',
  'Prisijungi savo banko puslapyje — taip pat, kaip įprastai.':
      'You sign in on your own bank\u2019s page, exactly as you normally would.',
  'Jūsų duomenys – jūsų kontrolėje': 'Your data stays yours',
  'Jūsų prisijungimo duomenys niekada nėra saugomi Vaultie.':
      'Your bank login details are never stored by Vaultie.',
  'Reguliuojama ir licencijuota': 'Regulated and licensed',
  'Prisijungimą vykdo licencijuota Enable Banking, veikianti pagal PSD2 direktyvą.':
      'Handled by Enable Banking, a licensed institution operating under PSD2.',
  'Saugu. Patikima. Sukurta jums.': 'Secure. Reliable. Built for you.',
  'Jūsų finansinė informacija yra visiškai apsaugota.':
      'Your financial information is fully protected.',
  // ── paywall ──
  'Visos funkcijos vienoje vietoje.\nDaugiau įžvalgų, kontrolės ir sutaupytų pinigų.':
      'Everything in one place.\nMore insight, more control, more money saved.',
  'AI finansų\nanalizė': 'AI money\nanalysis',
  'Išlaidų\nsekimas': 'Spending\ntracking',
  'Prenumeratų\nsekimas': 'Subscription\ntracking',
  'Išmanios\nįžvalgos': 'Smart\ninsights',
  'Neriboti\nbankai': 'Unlimited\nbanks',
  'Mėnesinis planas': 'Monthly plan',
  'Metinis planas': 'Annual plan',
  'Visos Premium funkcijos.': 'All Premium features.',
  'POPULIARUS PASIRINKIMAS': 'MOST POPULAR',
  'Sutaupyk': 'Save',
  'Sutaupai': 'You save',
  '/ mėn.': '/ mo.',
  '/ metus': '/ yr.',
  'metams': 'per year',
  'mėnesiui': 'per month',
  'Pasirinkus metinį planą, lyginant su mėnesiniu.':
      'Choosing the annual plan instead of monthly.',
  'Atsinaujina automatiškai, kol neatšauksi App Store nustatymuose likus ne mažiau kaip 24 val. iki laikotarpio pabaigos.':
      'Renews automatically unless cancelled in App Store settings at least 24 hours before the period ends.',
  // ── onboarding demonstrations (onb_welcome / month / planning / security / chat) ──
  'Birželis': 'June',
  'Liepa': 'July',
  'Euras': 'Euro',
  'Sinchronizuota': 'Synced',
  'Sužinok, kur dingsta': 'Find out where',
  'tavo pinigai': 'your money goes',
  'Vaultie automatiškai surenka\ntavo finansus į vieną vietą ir\npadeda lengviau juos suprasti.':
      'Vaultie gathers your finances\ninto one place and makes them\neasier to understand.',
  '5 aktyvūs mokėjimai · 2 baigėsi': '5 active payments · 2 ended',
  'Visas mėnuo': 'The whole month',
  'vienoje vietoje': 'in one place',
  'Kur nuėjo pinigai, kas pasikeitė\nir kiek tai kainuoja per dieną.':
      'Where the money went, what changed\nand what it costs you per day.',
  'Liepos apžvalga': 'July overview',
  'Liepos finansų momentas 📸': 'July at a glance 📸',
  'Liepos suma': 'July total',
  'Susikurk biudžetą': 'Set a budget',
  'ir laikykis jo': 'and stick to it',
  'Limitą pasiūlysime pagal tavo\nrealų mėnesių vidurkį.':
      'We will suggest a limit from\nyour real monthly average.',
  'Užrakink ir': 'Lock it and',
  'pritaikyk sau': 'make it yours',
  'PIN, Face ID ir tamsi tema —\nviskas per kelias sekundes.':
      'PIN, Face ID and dark mode —\nall in a few seconds.',
  'Naujas PIN kodas': 'New PIN code',
  'Sugalvok 4 skaitmenų kodą': 'Choose a 4-digit code',
  'Agentas, kuris mato': 'An agent that sees',
  'tavo skaičius': 'your numbers',
  'Paklausk, kur nueina pinigai —\natsakys iš karto ir konkrečiai.':
      'Ask where the money goes —\nyou get a straight answer.',
  'Tavo finansų agentas': 'Your finance agent',
  'Tęsti': 'Continue',
  'Atkurti pirkimus': 'Restore purchases',
  // ── onboarding: AI replies, recap, and labels the narrow filter missed ──
  '34 prekybininkai': '34 merchants',
  'Liepos {d}': 'July {d}',
  'Daugiausia moki už {a} — {b} per mėnesį. Po jo eina {c} ({d}) ir {e} ({f}). Iš viso penkios prenumeratos sudaro {g} per mėnesį, arba {h} per metus.':
      'You pay the most for {a} — {b} per month. Next come {c} ({d}) and {e} ({f}). In total, five subscriptions come to {g} per month, or {h} per year.',
  'Liepą daugiausia nusinešė būstas ir sąskaitos — {a}. Maistui išleidai {b}, tai 62 € mažiau nei birželį. Realiausia sutaupyti ties transportu ({c}) ir pramogomis ({d}) — sumažinus juos penktadaliu, per mėnesį liktų apie {e} € daugiau.':
      'In July, housing and bills took the most — {a}. You spent {b} on food, 62 € less than in June. The most realistic saving is on transport ({c}) and entertainment ({d}) — cutting each by a fifth would leave about {e} € more per month.',
  'Liepa buvo tvarkinga. Gavai {a} €, išleidai {b} €, tad atsidėjai {c} € — santaupų norma {d} %, virš 20 % tikslo. Daugiausia nusinešė būstas ir sąskaitos ({e} €) bei maistas ({f} €).':
      'July was tidy. You received {a} €, spent {b} €, so you set aside {c} € — a savings rate of {d} %, above the 20 % target. Housing and bills took the most ({e} €), then food ({f} €).',
  'Pr': 'Mon',
  'An': 'Tue',
  'Tr': 'Wed',
  'Kt': 'Thu',
  'Pn': 'Fri',
  'Št': 'Sat',
  'Sk': 'Sun',

  // ── Recurring review / disconnect / currency notes ──
  'Kaip naudotis': 'How to use',
  'Sistema pati atrinko galimus pasikartojančius mokėjimus — tavo darbas patvirtinti, kurie tikri:':
      'The system picked out the likely recurring payments — your job is to confirm which are real:',
  'Atjungti bankus ir pradėti iš naujo': 'Disconnect banks and start over',
  'Atjungti bankus?': 'Disconnect banks?',
  'Atjungti VISUS bankus?': 'Disconnect ALL banks?',
  'Pašalinsime visus prijungtus bankus ir jų duomenis iš šio telefono. Galėsi prijungti iš naujo. Tavo paskyra ir prenumerata nenukentės.':
      "We'll remove every connected bank and its data from this phone. You can reconnect later. Your account and subscription stay intact.",
  'Pašalinsime visus prijungtus bankus ir jų duomenis iš šio telefono. Kadangi appsas be banko nieko negali parodyti, iš karto atsidursi banko prijungimo lange — galėsi prisijungti iš naujo tada, kai norėsi. Tavo paskyra ir prenumerata nenukentės.':
      "We'll remove every connected bank and its data from this phone. Since the app can't show anything without a bank, you'll land straight on the bank-connect screen — you can reconnect whenever you're ready. Your account and subscription stay intact.",
  'Kursas nepasiekiamas': 'Rate unavailable',
  'Suskleisti': 'Show less',
  'sąsk.': 'accounts',
  'tuščios': 'empty',
  'šį mėn. dar nėra': 'not yet this month',
  'Atjungti': 'Disconnect',
  'valiutos — sąskaitos kitomis valiutomis suvedamos į vieną bendrą sumą.':
      'currencies — accounts in other currencies are rolled into one total.',
  'Kitos valiutos': 'Other currencies',
  'Reikia aktyvios „Vaultie Pro" prenumeratos.':
      'An active Vaultie Pro subscription is required.',
  'Kažkas nepavyko. Bandyk dar kartą.':
      'Something went wrong. Please try again.',
  'Kaip prijungsime tavo banką': 'How we\'ll connect your bank',
  'Prisijungti banke': 'Sign in at your bank',
  'Kitos valiutos atsiras, kai sumos bus ir perskaičiuojamos, o ne tik perrašomos kitu ženklu.':
      "Other currencies will appear once amounts are actually converted, not just relabelled with a different symbol.",

  // ── Onboarding pages (intro / features / connect) ──
  'Vaultie padeda aiškiau matyti, kur keliauja tavo pinigai, priimti geresnius sprendimus ir viską stebėti vienoje vietoje.':
      'Vaultie helps you see where your money goes, make better decisions and keep everything in one place.',
  'Pritaikyk\nVaultie sau': 'Make Vaultie\nyours',
  'Kelios funkcijos, kurias nusistatai pagal save.':
      'A few features you set up your own way.',
  'Prieigą\nkontroliuoji tu': 'You control\nthe access',
  '2 700+ bankų visoje Europoje': '2,700+ banks across Europe',

  // ── Onboarding chain 2026-08-19 redesign (onb_intro/banks/month/overview/
  // ai_chat/features/connect.dart) — audited every current tr() key in that
  // chain against this map on 2026-08-19 and found most of it missing, so an
  // English-locale device fell straight through to Lithuanian on nearly
  // every page — the exact bug the "pages 2–7" section above was written to
  // catch, just for copy that was rewritten after that audit ran.
  'Suprask savo\nfinansus aiškiau': 'Understand your\nfinances more clearly',
  'Jungiame 2 700+ bankų\nvisoje Europoje': 'Connecting 2,700+\nbanks across Europe',
  'Visi tavo bankai, visos tavo sąskaitos vienoje vietoje.':
      'All your banks, all your accounts, in one place.',
  'Matyk visą finansų vaizdą': 'See your whole financial picture',
  'Balansai, išlaidos, pajamos, biudžetas vienoje aiškioje vietoje.':
      'Balances, spending, income and budget in one clear place.',
  'Stebėk, kur gali sutaupyti': 'Track where you can save',
  'Atrask prenumeratas, sąskaitas ir sek savo santaupų normą.':
      'Discover subscriptions, bills, and track your savings rate.',
  'Klausk agento apie savo finansus': 'Ask the agent about your finances',
  'Gauk atsakymus, paremtus tavo realiais finansiniais duomenimis.':
      'Get answers based on your real financial data.',
  'Daugiau funkcijų.\n': 'More features.\n',
  'Daugiau kontrolės.': 'More control.',
  'Tvarkyk išlaidas, biudžetą, sąskaitas ir kasdienius pinigus vienoje aplikacijoje.':
      'Manage spending, budgets, bills and everyday money in one app.',
  'Išlaidos ir kvitai': 'Expenses and receipts',
  'Skenuok kvitus ir automatiškai rūšiuok pirkinius į kategorijas.':
      'Scan receipts and automatically sort purchases into categories.',
  'Biudžetas ir tikslai': 'Budget and goals',
  'Nustatyk biudžetus, stebėk išlaidas ir siek savo finansinių tikslų.':
      'Set budgets, track spending and work toward your financial goals.',
  'Sąskaitos ir mokėjimai': 'Bills and payments',
  'Dalinkis sąskaitomis, valdyk mokėjimus ir gauk priminimus laiku.':
      'Split bills, manage payments and get reminders on time.',
  'Bankai ir valiutos': 'Banks and currencies',
  'Prijunk bankus, stebėk sąskaitas ir konvertuok':
      'Connect banks, track accounts and convert',
  'skirtingas valiutas.': 'different currencies.',
  'Eksportas ir atsarginės kopijos': 'Export and backups',
  'Eksportuok duomenis į CSV arba PDF formatus ir turėk viską po ranka.':
      'Export your data to CSV or PDF and keep everything on hand.',
  'Saugumas ir patogumas': 'Security and convenience',
  'Face ID, PIN kodas ir kiti saugumo sprendimai, kuriais gali pasitikėti.':
      'Face ID, a PIN code and other security features you can rely on.',
  'Pritaikyta tau': 'Made for you',
  'Pasirink kalbą (LT / EN) ir temą (šviesi / tamsi) taip, kaip tau patogiausia.':
      'Choose your language (LT / EN) and theme (light / dark) — whatever suits you.',
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
  'Investicijos šalia tavo finansų': 'Investments alongside your finances',
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
  'Atsijungia ir grąžina į onboardingo pradžią':
      'Signs out and returns to the start of onboarding',
  'Visada rodyti onboardingą': 'Always show onboarding',
  'Kol įjungta, kiekvienas paleidimas rodo onboardingą iš naujo':
      'While on, every launch shows onboarding again',
  'Prijunk savo banką\n': 'Connect your bank\n',
  'saugiai ir greitai': 'safely and quickly',
  'Prisijunk prie banko per savo banko sistemą. Vaultie niekada nemato tavo prisijungimo duomenų.':
      'Sign in through your own bank’s system. Vaultie never sees your login details.',
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
  'Visos funkcijos vienoje vietoje.': 'Every feature in one place.',
  'Atšaukti gali bet kada.': 'Cancel any time.',
  'Išbandyk': 'Try',
  'atšaukti gali bet kada': 'cancel any time',

  // ── Sign-in terms line ──
  'Tęsdamas (-a) sutinki su ': 'By continuing you agree to the ',

  // ── Transfer caveat in the "Gauta" breakdown ──
  'Prijungus kelis bankus, pervedimai tarp tavo paties sąskaitų čia gali būti suskaičiuoti kaip įplauka, jei bankas neatskleidžia gavėjo sąskaitos.':
      'With several banks connected, transfers between your own accounts can be counted as income here when the bank does not reveal the receiving account.',

  // ── Onboarding showcase / demo chat (marketing copy over sample data) ──
  'Mėnesio rezultatas': 'This month',
  'Paskutiniai 5 mėn.': 'Last 5 months',
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
  'Vaultie rado pasikartojančių mokėjimų tavo banko istorijoje. Padėk mums atpažinti, kuriuos iš jų nori sekti.':
      'Vaultie found recurring payments in your bank history. Help us tell which ones you want to track.',
  'Peržiūrėti mokėjimus': 'Review payments',
  'Ieškok pats savo tranzakcijose': 'Search your own transactions',
  'Nieko naujo nerasta': 'Nothing new found',
  'kada nusiskaito?': 'when does it charge?',
  'Appsas numato dieną iš paskutinio tikro mokėjimo — jeigu bankas nuskaito kitą dieną, pasirink tikrąją. Tai nekeičia, kaip appsas atpažįsta pačią sąskaitą, tik parodomą/priminimo dieną.':
      "The app predicts the day from your last real payment — if the bank charges on a different day, pick the real one. This doesn't change how the app recognises the bill itself, only the day shown/reminded.",
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
  'Šį mėnesį išleidai 1 836 € — 32 % mažiau nei uždirbai. Daugiausia nuėjo būstui (620 €) ir maistui (450 €).':
      'You spent €1,836 this month — 32% less than you earned. Mostly on housing (€620) and food (€450).',
  '1 836 € — 32 % mažiau nei uždirbai. Daugiausia būstui (620 €) ir maistui (450 €).':
      '€1,836 — 32% less than you earned. Mostly housing (€620) and food (€450).',
  'Prenumeratos — 57,94 € per mėnesį, 695 € per metus. Dvi nenaudotos nuo balandžio.':
      'Subscriptions — €57.94 a month, €695 a year. Two unused since April.',

  // ── Onboarding pages 2–7 (onb_features/month/overview/ai_chat/budget/
  // connect/notifications.dart) — every one of these was tr()-wrapped in code
  // already but had no _en entry, so an English-locale device fell all the way
  // through onboarding still reading Lithuanian. Found 2026-08-03 by auditing
  // every onb_*.dart file against this map, prompted by a reviewer-visibility
  // concern right before submission — App Review may walk the full first-run
  // chain, not just sign in with the demo account.
  'Mėnesio biudžetas': 'Monthly budget',
  'Nusistatyk ribą, o Vaultie kasdien rodys, kiek dar gali išleisti.':
      'Set a limit, and Vaultie shows you every day how much you have left to spend.',
  'PIN kodas ir Face ID': 'PIN code and Face ID',
  'Uždaryta programėlė lieka užrakinta, net jei telefonas atrakintas.':
      'A closed app stays locked, even if your phone is unlocked.',
  'Pranešam prieš nurašymą, kad nė vienas neužkluptų netikėtai.':
      "We notify you before a charge, so none catches you by surprise.",
  'Mėnesio santrauka': 'Monthly summary',
  'Mėnesiui pasibaigus — kur nukeliavo pinigai ir kiek sutaupei.':
      'When the month ends — where your money went and how much you saved.',
  'Šviesus ir tamsus': 'Light and dark',
  'Programėlė prisitaiko prie tavęs, ne atvirkščiai.':
      'The app adapts to you, not the other way around.',

  'Kiekviena išlaida\nsavo vietoje': 'Every expense\nin its place',
  'Vaultie automatiškai atpažįsta pirkinius, suskirsto juos į kategorijas ir padeda aiškiai matyti, kur išleidi pinigus.':
      'Vaultie automatically recognises your purchases, sorts them into categories, and helps you clearly see where your money goes.',
  'Atpažįsta tūkstančius prekybininkų': 'Recognises thousands of merchants',
  'Mokosi iš tavo pataisymų': 'Learns from your corrections',
  'Jokio rankinio vedimo': 'No manual entry',

  'Matyk visą\nfinansų vaizdą': 'See your whole\nfinancial picture',
  'Balansai, išlaidos, pajamos ir biudžetas vienoje aiškioje vietoje.':
      'Balances, spending, income and budget in one clear place.',
  'Visos sąskaitos viename vaizde': 'All accounts in one view',
  'Kasdien atnaujinami duomenys': 'Data updated every day',
  'Aiškios įžvalgos be skaičių chaoso': 'Clear insights, no number chaos',

  'Paklausk.\nGauk atsakymą.': 'Ask.\nGet an answer.',
  'Paklausk apie savo finansus paprastais žodžiais, o Vaultie atsakys pagal tavo tikrus duomenis.':
      'Ask about your finances in plain words, and Vaultie answers using your real data.',
  'Atsako pagal tavo operacijas': 'Answers based on your transactions',
  'Jokie duomenys nenaudojami AI mokymui': 'No data is used to train AI',
  'Privatumas išlieka tavo rankose': 'Privacy stays in your hands',

  'Nepraleisk nė vienos\nprenumeratos': "Don't miss a single\nsubscription",
  'Vaultie automatiškai aptinka pasikartojančius mokėjimus ir padeda kontroliuoti jų kainą.':
      'Vaultie automatically detects recurring payments and helps you keep their cost in check.',
  'Matyk kitą mokėjimo datą': 'See the next payment date',
  'Pastebėk kainų pokyčius': 'Notice price changes',
  'Žinok metinę išlaidų sumą': 'Know your total yearly cost',

  'Pasirink, ką prijungti': 'Choose what to connect',
  'Prijunk tik tas sąskaitas, kurias nori.':
      'Connect only the accounts you want.',
  'Tik skaitymo prieiga': 'Read-only access',
  'Vaultie negali atlikti mokėjimų ar pervesti pinigų.':
      'Vaultie cannot make payments or transfer money.',
  'Saugus prisijungimas': 'Secure sign-in',
  'Prisijungimą patvirtini savo banke pagal PSD2 standartą.':
      'You confirm the connection at your own bank, under the PSD2 standard.',
  'Tavo duomenys': 'Your data',
  'Jie niekada neparduodami ir visada lieka tavo kontrolėje.':
      'They are never sold and always stay under your control.',
  'Licencijuota paslauga': 'Licensed service',
  'Duomenis teikia Enable Banking — licencijuota ES atviro bankininkystės tiekėja.':
      'Data is provided by Enable Banking — a licensed EU open banking provider.',
  'Tik skaitymo prieiga, saugus prisijungimas':
      'Read-only access, secure sign-in',
  'Vaultie negali atlikti mokėjimų ar pervesti pinigų; prisijungimą patvirtini savo banke pagal PSD2 standartą.':
      'Vaultie cannot make payments or transfer money; you confirm the connection at your own bank, under the PSD2 standard.',
  'Tavo duomenys saugūs': 'Your data is safe',
  'Niekada neparduodami ir visada lieka tavo kontrolėje. Duomenis teikia Enable Banking — licencijuota ES atviro bankininkystės tiekėja.':
      'Never sold and always stays under your control. Data is provided by Enable Banking — a licensed EU open banking provider.',
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
  'Degalai': 'Fuel',
  'Būsto draudimas': 'Home insurance',
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
  'Liepos 18': 'July 18',
  'Liepos 21': 'July 21',
  'Liepos 25': 'July 25',
  'Rugpjūčio 1': 'August 1',
  'Rugpjūčio 2': 'August 2',
  'Rugpjūčio 3': 'August 3',
  'Rugpjūčio 5': 'August 5',
  'Rugpjūčio 8': 'August 8',
  'Rugpjūčio 9': 'August 9',
  'Rugpjūčio 10': 'August 10',
  'Rugpjūčio 12': 'August 12',
  'Rugpjūčio 15': 'August 15',
  'Rugpjūčio 18': 'August 18',
  'Rugpjūčio 22': 'August 22',

  // ── bank_how_it_works.dart — the pre-connect explainer + its "Why this is
  // safe" sheet. Every string here was tr()-wrapped but had no _en entry,
  // same class of bug as onboarding: found from a device screenshot showing
  // English chrome (title, Continue button) around fully-Lithuanian body
  // text. 2026-08-03.
  'Pasirink savo banką': 'Choose your bank',
  'Iš 2 700+ Europos bankų sąrašo.': 'From a list of 2,700+ European banks.',
  'Patvirtink prieigą banke': 'Confirm access at your bank',
  'Nukreipsim į tavo banko programėlę ar svetainę. Prisijungi ir patvirtini prieigą — taip pat, kaip prisijungdamas prie savo banko. Vaultie tavo prisijungimo duomenų nemato.':
      "We'll take you to your bank's app or website. You sign in and confirm access — just like signing in to your bank normally. Vaultie never sees your login details.",
  'Grįžk į Vaultie': 'Back to Vaultie',
  'Kai patvirtinsi, grįši į Vaultie — kai kurie bankai grąžina automatiškai, kiti paprašys tiesiog grįžti pačiam. Tavo operacijos susitvarkys pačios.':
      "Once you confirm, you'll be back in Vaultie — some banks return you automatically, others just ask you to switch back. Your transactions will sort themselves out.",
  'Kodėl tai saugu': 'Why this is safe',
  'Jungiamės per Enable Banking — licencijuotą ES atvirosios bankininkystės tiekėją (PSD2). Prieiga tik skaitymo. Atšaukti gali bet kada.':
      'We connect through Enable Banking — a licensed EU open banking provider (PSD2). Read-only access. Cancel anytime.',
  'Licencijuotas tarpininkas': 'Licensed intermediary',
  'Jungiamės per Enable Banking — ES reguliuojamą atvirosios bankininkystės tiekėją, veikiantį pagal PSD2 direktyvą.':
      'We connect through Enable Banking — an EU-regulated open banking provider operating under the PSD2 directive.',
  'Niekada nematome tavo slaptažodžio': 'We never see your password',
  'Prisijungi tik savo banke. Vaultie gauna leidimą skaityti operacijas — ne tavo prisijungimo duomenis.':
      "You sign in only at your own bank. Vaultie gets permission to read transactions — not your login details.",
  'Tik skaitymas': 'Read-only',
  'Vaultie negali atlikti mokėjimų, pervesti ar keisti nieko tavo sąskaitoje.':
      'Vaultie cannot make payments, transfer money, or change anything in your account.',
  'Duomenys lieka tavo telefone': 'Your data stays on your phone',
  'Operacijos saugomos tavo telefone, o ne mūsų serveriuose, ir niekada neparduodamos.':
      'Transactions are stored on your phone, not our servers, and are never sold.',
  'AI — tik tavo sutikimu': 'AI — only with your consent',
  'Jei įjungi AI funkcijas, mūsų tiekėjui siunčiame tik apibendrintus skaičius: likučius, išlaidas pagal kategoriją ir pasikartojančių mokėjimų pavadinimus. Ne atskirus sandorius, ne IBAN‑us.':
      'If you enable AI features, we send our provider only summarised numbers: balances, spending by category, and recurring payment names. Not individual transactions, not IBANs.',
  'Tu valdai prieigą': 'You control access',
  'Bet kada gali ją atšaukti — Vaultie nustatymuose arba savo banke.':
      'You can revoke it anytime — in Vaultie settings or at your bank.',
  'Sutikimas galioja ribotą laiką ir yra atnaujinamas pagal PSD2. Atšaukti gali bet kada.':
      'Consent lasts a limited time and is renewed under PSD2. Cancel anytime.',

  'Pervadink, kad geriau atpažintum sąraše.':
      'Rename it so it\'s easier to recognise in the list.',
};
