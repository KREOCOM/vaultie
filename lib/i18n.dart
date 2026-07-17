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
};
