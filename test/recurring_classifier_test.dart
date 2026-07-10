import 'package:flutter_test/flutter_test.dart';
import 'package:vaultie/models/subscription.dart';
import 'package:vaultie/services/banking_service.dart';
import 'package:vaultie/services/recurring_classifier.dart';

RecurringCandidate candidate(
  String name, {
  bool autoDetected = false,
  bool needsReview = false,
}) {
  return RecurringCandidate(
    name: name,
    type: 'subscription',
    autoDetected: autoDetected,
    cost: 9.99,
    billingCycle: BillingCycle.monthly,
    category: 'other',
    nextBillingDate: DateTime(2026, 8, 1),
    occurrences: 1,
    cadenceLabel: 'monthly',
    amountVaries: false,
    needsReview: needsReview,
  );
}

RecurringClassification classify(RecurringCandidate c, {Set<String>? existing}) =>
    RecurringClassifier.classify(c,
        existingNormalizedNames: existing ?? <String>{});

void main() {
  group('sections', () {
    test('auto-detected merchants go to the auto section, pre-selected', () {
      final cls = classify(candidate('Netflix', autoDetected: true));
      expect(cls.group, ImportGroup.autoDetected);
      expect(cls.selectedByDefault, isTrue);
    });

    test('unknown merchants go to others, NOT pre-selected', () {
      final cls = classify(candidate('MB Artusgrupe', autoDetected: false));
      expect(cls.group, ImportGroup.others);
      expect(cls.selectedByDefault, isFalse);
    });
  });

  group('duplicate detection', () {
    test('an already-tracked auto merchant is unselected', () {
      final existing = {RecurringClassifier.normalizeName('Netflix')};
      final cls =
          classify(candidate('NETFLIX.COM', autoDetected: true), existing: existing);
      expect(cls.isDuplicate, isTrue);
      expect(cls.selectedByDefault, isFalse);
    });

    test('unrelated names are not duplicates', () {
      final existing = {RecurringClassifier.normalizeName('Spotify')};
      expect(classify(candidate('Ignitis')).isDuplicate, isFalse);
      expect(classify(candidate('Ignitis'), existing: existing).isDuplicate,
          isFalse);
    });
  });

  test('needsReview passes through', () {
    expect(classify(candidate('X', needsReview: true)).needsReview, isTrue);
  });
}
