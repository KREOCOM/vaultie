import 'package:flutter_test/flutter_test.dart';
import 'package:vaultie/models/subscription.dart';
import 'package:vaultie/services/banking_service.dart';
import 'package:vaultie/services/recurring_classifier.dart';

RecurringCandidate candidate(
  String name, {
  double cost = 9.99,
  int occurrences = 3,
  bool amountVaries = false,
  String category = 'Other',
  String? logoDomain,
}) {
  return RecurringCandidate(
    name: name,
    cost: cost,
    billingCycle: BillingCycle.monthly,
    category: category,
    nextBillingDate: DateTime(2026, 8, 1),
    occurrences: occurrences,
    cadenceLabel: 'monthly',
    amountVaries: amountVaries,
    logoDomain: logoDomain,
  );
}

RecurringClassification classify(RecurringCandidate c, {Set<String>? existing}) =>
    RecurringClassifier.classify(c,
        existingNormalizedNames: existing ?? <String>{});

void main() {
  group('grouping', () {
    test('streaming brands land in Services and are selected', () {
      final cls = classify(candidate('NETFLIX.COM', logoDomain: 'netflix.com'));
      expect(cls.group, ImportGroup.services);
      expect(cls.categoryKey, 'entertainment');
      expect(cls.selectedByDefault, isTrue);
    });

    test('utilities land in Housing', () {
      expect(classify(candidate('UAB Ignitis')).group, ImportGroup.housing);
      expect(classify(candidate('Vilniaus vandenys')).group, ImportGroup.housing);
      expect(classify(candidate('Telia Lietuva, AB')).group, ImportGroup.housing);
    });

    test('rent lands in Housing', () {
      final cls = classify(candidate('Buto nuoma'));
      expect(cls.group, ImportGroup.housing);
      expect(cls.categoryKey, 'housing');
    });

    test('loans and insurance land in Finance', () {
      expect(classify(candidate('Būsto paskola')).group, ImportGroup.finance);
      expect(classify(candidate('SB lizingas')).group, ImportGroup.finance);
      expect(classify(candidate('Gjensidige draudimas')).group,
          ImportGroup.finance);
    });
  });

  group('person / peer-to-peer detection', () {
    test('a bare two-word name is treated as a person → Other, unselected', () {
      final cls = classify(candidate('Milda Dirsiene'));
      expect(cls.likelyPerson, isTrue);
      expect(cls.group, ImportGroup.other);
      expect(cls.confidence, ImportConfidence.low);
      expect(cls.selectedByDefault, isFalse);
    });

    test('company legal form is not a person', () {
      expect(RecurringClassifier.isLikelyPerson('UAB Maxima'), isFalse);
    });

    test('a known logo domain is never a person', () {
      expect(
        RecurringClassifier.isLikelyPerson('Apple Music', logoDomain: 'apple.com'),
        isFalse,
      );
    });

    test('names with digits/domains/refs are not persons', () {
      expect(RecurringClassifier.isLikelyPerson('pildyk.lt'), isFalse);
      expect(RecurringClassifier.isLikelyPerson('Ref 12345'), isFalse);
    });
  });

  group('duplicate detection', () {
    test('flags a candidate already in the vault, unselected', () {
      final existing = {RecurringClassifier.normalizeName('Netflix')};
      final cls = classify(candidate('NETFLIX.COM', logoDomain: 'netflix.com'),
          existing: existing);
      expect(cls.isDuplicate, isTrue);
      expect(cls.selectedByDefault, isFalse);
    });

    test('unrelated names are not duplicates', () {
      final existing = {RecurringClassifier.normalizeName('Spotify')};
      expect(classify(candidate('Ignitis'), existing: existing).isDuplicate,
          isFalse);
    });
  });

  group('never-recurring blacklist', () {
    test('fast food and groceries are blacklisted', () {
      for (final n in [
        'Hesburger Vilnius',
        'McDonalds',
        'MAXIMA LT 4231',
        'Rimi Lietuva',
        'Lidl',
        'Norfa',
        'IKI, Vilnius',
      ]) {
        expect(RecurringClassifier.isNeverRecurring(n), isTrue, reason: n);
      }
    });

    test('"iki" only matches as a whole word, not inside other words', () {
      expect(RecurringClassifier.isNeverRecurring('Vaikiškas pasaulis'), isFalse);
      expect(RecurringClassifier.isNeverRecurring('Netflix'), isFalse);
    });
  });

  group('confidence', () {
    test('classified, frequent, stable amount → high', () {
      final cls = classify(candidate('Spotify', occurrences: 5));
      expect(cls.confidence, ImportConfidence.high);
    });

    test('unknown merchant seen twice → low', () {
      final cls = classify(candidate('Zzz Xyz Ltd', occurrences: 2));
      // Has a company token so not a person, but unclassified + infrequent.
      expect(cls.group, ImportGroup.other);
      expect(cls.confidence, ImportConfidence.low);
    });
  });
}
