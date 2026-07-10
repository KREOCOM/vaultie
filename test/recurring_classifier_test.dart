import 'package:flutter_test/flutter_test.dart';
import 'package:vaultie/models/subscription.dart';
import 'package:vaultie/services/banking_service.dart';
import 'package:vaultie/services/recurring_classifier.dart';

RecurringCandidate candidate(
  String name, {
  String type = 'subscription',
  bool needsReview = false,
  String category = 'other',
}) {
  return RecurringCandidate(
    name: name,
    type: type,
    cost: 9.99,
    billingCycle: BillingCycle.monthly,
    category: category,
    nextBillingDate: DateTime(2026, 8, 1),
    occurrences: 3,
    cadenceLabel: 'monthly',
    amountVaries: false,
    needsReview: needsReview,
  );
}

RecurringClassification classify(RecurringCandidate c, {Set<String>? existing}) =>
    RecurringClassifier.classify(c,
        existingNormalizedNames: existing ?? <String>{});

void main() {
  group('grouping by type', () {
    test('subscriptions and bills land in their groups', () {
      expect(classify(candidate('Netflix', type: 'subscription')).group,
          ImportGroup.subscriptions);
      expect(classify(candidate('Ignitis', type: 'bill')).group,
          ImportGroup.bills);
    });

    test('unknown type defaults to subscriptions', () {
      expect(RecurringClassifier.groupForType('whatever'),
          ImportGroup.subscriptions);
    });
  });

  group('defaults + flags', () {
    test('non-duplicates are selected by default', () {
      expect(classify(candidate('Spotify')).selectedByDefault, isTrue);
    });

    test('needsReview passes through from the candidate', () {
      expect(classify(candidate('UAB Xyz', needsReview: true)).needsReview,
          isTrue);
      expect(classify(candidate('Netflix')).needsReview, isFalse);
    });
  });

  group('duplicate detection', () {
    test('flags a candidate already in the vault, unselected', () {
      final existing = {RecurringClassifier.normalizeName('Netflix')};
      final cls = classify(candidate('NETFLIX.COM'), existing: existing);
      expect(cls.isDuplicate, isTrue);
      expect(cls.selectedByDefault, isFalse);
    });

    test('unrelated names are not duplicates', () {
      final existing = {RecurringClassifier.normalizeName('Spotify')};
      expect(classify(candidate('Ignitis'), existing: existing).isDuplicate,
          isFalse);
    });
  });
}
