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
  'Sąskaita': 'Account',

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
  'suma': 'net',
  'grynasis': 'net',
  'Rodyti senesnius': 'Show older',
  'sandoriai': 'transactions',
  'sandorių': 'transactions',
  'apžvalga': 'review',
  'Peržiūrėti': 'View',

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
