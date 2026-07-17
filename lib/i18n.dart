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
  'Planavimas': 'Planning',
  'Paskyra': 'Account',

  // ── Home / balance hero ──
  'Bendras likutis': 'Total balance',
  'gyvai': 'live',
  'Sinchronizuojama': 'Syncing',
  'nuo praėjusio mėn.': 'vs last month',
  'Likutis iš banko · grafikas = likučio kitimas laike':
      'Bank balance · chart = balance over time',

  // ── Filters / week ──
  'Filtras': 'Filter',
  'Visas laikas': 'All time',
  'Šios savaitės išlaidos': 'This week’s spending',
  'vidurkis': 'average',

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
  'Kokia mano brangiausia prenumerata?': 'What’s my most expensive subscription?',
  'Kur galėčiau sutaupyti?': 'Where could I save?',
  'Į ką daugiausiai išleidžiu?': 'What do I spend the most on?',

  // ── Overview / analytics ──
  'Kategorija': 'Category',
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
  'Maisto prekės': 'Groceries',
  'Kavinės, restoranai': 'Cafes & restaurants',
  'Alkoholis, tabakas': 'Alcohol & tobacco',
  'Kuras': 'Fuel',
  'Taksi, pavėžėja': 'Taxi & rideshare',
  'Automobilis': 'Car',
  'Viešasis transportas': 'Public transport',
  'Drabužiai': 'Clothing',
  'Elektronika, prekės': 'Electronics & goods',
  'Namų prekės': 'Household',
  'Nuoma, būstas': 'Rent & housing',
  'Komunaliniai': 'Utilities',
  'Ryšys, internetas': 'Phone & internet',
  'Draudimas': 'Insurance',
  'Sveikata': 'Health',
  'Sportas': 'Sport',
  'Vaistinė': 'Pharmacy',
  'Prenumeratos': 'Subscriptions',
  'Kelionės': 'Travel',
  'Mokesčiai': 'Taxes',
  'Bankas, komisiniai': 'Bank & fees',
  'Investicijos': 'Investments',
  'Mokslas': 'Education',
  'Kursai, knygos': 'Courses & books',
  'Grynieji': 'Cash',
  'Asmeninis pervedimas': 'Personal transfer',
  'Atlyginimas': 'Salary',

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
  'Išsaugoti': 'Save',
  'Gerai': 'OK',
  'Ištrinti': 'Delete',
  'Redaguoti': 'Edit',
  'Netrukus': 'Coming soon',

  // ── Recurring status / cadence / kind / payment-type (variable-resolved) ──
  'Aktyvus': 'Active',
  'Vėluoja': 'Late',
  'Baigėsi': 'Ended',
  'Naujas': 'New',
  'kas savaitę': 'weekly',
  'kas ketvirtį': 'quarterly',
  'kas metus': 'yearly',
  'kas mėnesį': 'monthly',
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
  'Visi pinigai, kurie įkrito į tavo sąskaitą.': 'All the money that came into your account.',
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
  'Pinigai, kuriuos išleidai — pvz. sumokėjai grynais.': 'Money you spent — e.g. paid in cash.',
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
  'bus pašalintas. Šio veiksmo anuliuoti negalima.': 'will be removed. This action cannot be undone.',
  'Pakeitimai išsaugoti': 'Changes saved',
  'Pažymėta kaip vidinis pervedimas': 'Marked as an internal transfer',
  'Grąžinta į įprastą (kategorija „Kita")': 'Restored to a normal transaction (category "Other")',
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
  'Įžvalgos': 'Insights',
  'Prekybininkai': 'Merchants',
  'Didžiausios išlaidos': 'Largest expenses',
  'Sekamose kategorijose išleidai': 'In the tracked categories you spent',
  'iš': 'of',
  'Viršijai sekamų kategorijų limitą': 'You exceeded the tracked categories limit by',
  'biudžetas*': 'budget*',
  '* pavyzdiniai limitai': '* example limits',
  'Kategorijai': 'In category',
  'nei praėjusį mėnesį.': 'than last month.',
  'daugiau': 'more',
  'mažiau': 'less',
  'Nusistatyti biudžetą': 'Set a budget',
  'prekybininkai': 'merchants',
  'Laikotarpis': 'Period',
  'Pasirink mėnesį': 'Pick a month',
  'Biudžetai padeda suvaldyti išlaidas': 'Budgets help you control spending',
  'Susikurk biudžetą kategorijai — limitą pasiūlysime pagal tavo realų mėnesių vidurkį.':
      "Create a budget for a category — we'll suggest a limit from your real monthly average.",
  'visas biudžetas': 'total budget',
  'Tokiu tempu mėnesį baigsi ~': "At this pace you'll finish the month around ~",
  '— telpi į biudžetą.': '— you fit in the budget.',
  'Tokiu tempu peršoksi biudžetą ~': "At this pace you'll exceed the budget by ~",
  '— sulėtink.': '— slow down.',
  'Pasiūlyta pagal tavo išlaidas · keisk': 'Suggested from your spending · edit',
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
  'Bankas nepasako, kas tai. Pavadink, kad atpažintum.': "The bank won't say what this is. Name it so you recognise it.",
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
  'Geresni AI patarimai, kai Vaultie mato visą tavo situaciją.': 'Better AI advice when Vaultie sees your whole picture.',
  'Grynasis turtas': 'Net worth',
  'Banko sąskaitos': 'Bank accounts',
  'Pridėti grynų ar santaupų': 'Add cash or savings',
  'Turto kategorija': 'Asset category',
  'Vertė': 'Value',
  'Pavadinimas (pvz. Grynieji, Santaupos)': 'Name (e.g. Cash, Savings)',
  'Sąskaitos': 'Accounts',
  'Likutis': 'Balance',
  'Prijungti kitą banką': 'Connect another bank',
  'Turi pastabų?': 'Have feedback?',
  'Pasakyk, ką galvoji': 'Tell us what you think',
  'Palikti atsiliepimą': 'Leave feedback',
  'Parašyk mums: labas@vaultie.app': 'Write to us: labas@vaultie.app',

  // ── Settings ──
  'Nustatymai': 'Settings',
  'Privatumas': 'Privacy',
  'PIN kodas': 'PIN code',
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
  'Atsijungti galima tik tikroje programoje.': 'You can only sign out in the real app.',
  'Ištrinti paskyrą?': 'Delete account?',
  'Tai VISAM LAIKUI ištrins tavo Vaultie paskyrą ir visus duomenis šiame telefone — sandorius, prenumeratas, biudžetus. Banko ryšys bus atjungtas. Šio veiksmo anuliuoti negalima.':
      'This will PERMANENTLY delete your Vaultie account and all data on this phone — transactions, subscriptions, budgets. The bank connection will be disconnected. This action cannot be undone.',
  'Ištrinti paskyrą galima tik tikroje programoje.': 'You can only delete your account in the real app.',
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
  'Kad atsakytų į klausimus, appsas siunčia mūsų AI tiekėjui (Anthropic) TAVO finansų SANTRAUKĄ — banko likučius, išlaidas pagal kategoriją ir tavo pasikartojančių mokėjimų pavadinimus (pvz. „Netflix").\n\n• Nesiunčiami atskiri sandoriai, IBAN‑ai ar kortelių numeriai.\n• Duomenys NENAUDOJAMI dirbtinio intelekto treniravimui.\n• Tai nėra finansinė konsultacija.':
      'To answer your questions, the app sends our AI provider (Anthropic) a SUMMARY of YOUR finances — bank balances, spending by category and the names of your recurring payments (e.g. "Netflix").\n\n• Individual transactions, IBANs or card numbers are not sent.\n• The data is NOT used to train AI.\n• This is not financial advice.',
  'Sutinku ir tęsiu': 'I agree and continue',
  'Atsiprašau, nepavyko atsakyti. Pabandyk dar kartą.': "Sorry, I couldn't answer. Please try again.",
  'Nepavyko susisiekti su serveriu. Patikrink ryšį ir bandyk dar kartą.':
      'Could not reach the server. Check your connection and try again.',

  // ══ Onboarding flow ══
  // ── Landing ──
  'Sužinok, kur dingsta\ntavo pinigai': 'See where your\nmoney goes',
  'Nuoma, prenumeratos, draudimas — viskas vienoje vietoje.': 'Rent, subscriptions, insurance — all in one place.',
  'Pradėti': 'Get started',
  'Jau turiu paskyrą': 'I already have an account',
  'KAS MĖNESĮ IŠEINA': 'LEAVES EVERY MONTH',
  'Nuoma': 'Rent',
  'nenaudota 3 mėn.': 'unused 3 mo',

  // ── Annual bars ──
  'Net mažos išlaidos per metus\nvirsta didele suma.': 'Even small costs add up\nto a big sum over a year.',
  'Vaultie automatiškai apskaičiuoja, kiek tavo prenumeratos ir kitos pasikartojančios išlaidos kainuoja per metus.':
      'Vaultie automatically calculates how much your subscriptions and other recurring costs add up to per year.',

  // ── Subscription stream ──
  'Toliau': 'Next',
  'Visos tavo prenumeratos.\nVienoje vietoje.': 'All your subscriptions.\nIn one place.',
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
  'Disney+ nenaudotas 2 mėn — gal atšaukti?': 'Disney+ unused for 2 mo — cancel?',
  'iCloud+ nurašys rytoj — 2,99 €': 'iCloud+ charges tomorrow — €2.99',

  // ── Bank scale ──
  'Jungiamės prie 2 500+ bankų\nvisoje Europoje.': 'We connect to 2,500+ banks\nacross Europe.',
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
  'Leisk Vaultie pasirūpinti tavo prenumeratomis.': 'Let Vaultie take care of your subscriptions.',
  'Automatiškai suranda prenumeratas': 'Automatically finds your subscriptions',
  'Įspėja prieš artėjančius mokėjimus': 'Warns you before upcoming payments',
  'Parodo, kur iš tikrųjų išleidi pinigus': 'Shows where your money really goes',
  'Viskas vienoje vietoje – be rankinio darbo': 'Everything in one place – no manual work',
  'Metinis': 'Annual',
  '7 dienos nemokamai': '7 days free',
  'Mėnesinis': 'Monthly',
  'Pradėti 7 dienų bandymą': 'Start 7-day trial',
  '€2,50/mėn': '€2.50/mo',
  'SUTAUPAI 37%': 'SAVE 37%',
  'Pirkimas nepavyko. Bandyk dar kartą.': 'Purchase failed. Please try again.',
  '7 dienos nemokamai. Atšaukus iki bandomojo laikotarpio pabaigos, mokestis nebus nuskaičiuotas. Vėliau taikomas pasirinkto plano mokestis, kol atsisakysi App Store nustatymuose.':
      "7 days free. Cancel before the trial ends and you won't be charged. After that, the selected plan's price applies until you cancel in App Store settings.",
};
