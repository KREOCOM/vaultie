import 'package:flutter_test/flutter_test.dart';
import 'package:vaultie/screens/preview/dashboard_preview.dart';

/// The AI finance summary was 100% Lithuanian structural text — "BALANSAS:",
/// "ŠIS MĖNUO", "PRENUMERATOS IR SĄSKAITOS" — regardless of the app's UI
/// language. Found live: an English-mode user asked a question in English,
/// got an English reply, then a SECOND, longer reply drifted from English into
/// Lithuanian partway through. The system prompt already said "ALWAYS respond
/// in English, never switch" as forcefully as an instruction can; the summary
/// scaffolding wrapped around every request was still entirely Lithuanian, and
/// a long reply grounded in an all-Lithuanian data block can still get pulled
/// back mid-generation.
///
/// This pins that the FIXED labels switch with `lang`, while the DATA itself
/// (bank names, category names, merchant names) is deliberately left
/// untouched — those already read naturally regardless of surrounding
/// language, the same way "MOGO" or "PAYSERA" already do.
void main() {
  final data = {
    'balance': {
      'current': 1000.0,
      'accounts': [
        {'bank': 'SEB', 'amount': 500.0},
        {'bank': 'Revolut', 'amount': 500.0},
      ],
    },
    'all': [
      {'d': '2026-06-15', 'a': -45.5, 'cat': 'Maistas, gėrimai', 'sec': 'Maistas, gėrimai'},
      {'d': '2026-06-01', 'a': 1500.0, 'pos': true, 'sec': 'Pajamos'},
    ],
    'subs': {
      'items': [
        {'name': 'Netflix', 'monthly': 12.99, 'cycle': 'monthly', 'active': true, 'type': 'subscription'},
      ],
    },
  };

  group('lang: lt (default)', () {
    test('structural labels are Lithuanian', () {
      final s = buildFinanceSummary(data);
      expect(s, contains('BALANSAS'));
      expect(s, contains('ŠIS MĖNUO'));
      expect(s, contains('Išlaidos pagal kategoriją'));
      expect(s, contains('PRENUMERATOS IR SĄSKAITOS'));
      expect(s, contains('ciklas'));
    });

    test('carries no English-mode reminder', () {
      expect(buildFinanceSummary(data), isNot(contains('entirely in English')));
    });

    test('omitting lang behaves exactly like lang: "lt"', () {
      expect(buildFinanceSummary(data), buildFinanceSummary(data, lang: 'lt'));
    });
  });

  group('lang: en', () {
    late String s;
    setUp(() => s = buildFinanceSummary(data, lang: 'en'));

    test('structural labels are English', () {
      expect(s, contains('BALANCE'));
      expect(s, contains('THIS MONTH'));
      expect(s, contains('Spending by category'));
      expect(s, contains('SUBSCRIPTIONS AND BILLS'));
      expect(s, contains('cycle'));
    });

    test('carries no leftover Lithuanian structural labels', () {
      expect(s, isNot(contains('BALANSAS')));
      expect(s, isNot(contains('ŠIS MĖNUO')));
      expect(s, isNot(contains('PRENUMERATOS IR SĄSKAITOS')));
    });

    test('ends with a language reminder, for recency in context', () {
      expect(s, contains('entirely in English'));
      // Must be the LAST thing in the block, not buried mid-summary — recency
      // is the whole point of putting it there.
      expect(s.trim().endsWith(')'), isTrue);
    });

    test('data values stay as the backend resolved them, untranslated', () {
      // Bank and merchant names are proper nouns / classified terms — they
      // read fine inline in an English sentence, same as "MOGO" already does,
      // and translating them would need a whole taxonomy table this fix
      // deliberately does not take on.
      expect(s, contains('SEB'));
      expect(s, contains('Revolut'));
      expect(s, contains('Netflix'));
      expect(s, contains('Maistas, gėrimai'));
    });
  });

  test('case-insensitive lang matching', () {
    expect(buildFinanceSummary(data, lang: 'EN'), contains('BALANCE'));
    expect(buildFinanceSummary(data, lang: 'En'), contains('BALANCE'));
  });
}
