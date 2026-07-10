import 'banking_service.dart';

/// The two importable groups on the bank-import review screen. Detection now
/// assigns each candidate a `type` (from the Firestore merchant DB), so grouping
/// is by type, not category. Frequent-spending merchants are NOT candidates —
/// they arrive in a separate list and are shown for information only.
enum ImportGroup { subscriptions, bills }

/// Display order (Subscriptions first).
const List<ImportGroup> kImportGroupOrder = [
  ImportGroup.subscriptions,
  ImportGroup.bills,
];

String importGroupLabel(ImportGroup g, bool isLt) => switch (g) {
      ImportGroup.subscriptions => isLt ? 'Prenumeratos' : 'Subscriptions',
      ImportGroup.bills => isLt ? 'Sąskaitos' : 'Bills',
    };

/// The classifier's verdict for one candidate: which group it belongs to,
/// whether it duplicates something already tracked, whether detection flagged it
/// for review, and the resulting default checkbox state.
class RecurringClassification {
  const RecurringClassification({
    required this.group,
    required this.isDuplicate,
    required this.needsReview,
  });

  final ImportGroup group;

  /// A payment with the same (normalised) name is already in the vault.
  final bool isDuplicate;

  /// Detection (the algorithm or a "possible" merchant) flagged it for a look.
  final bool needsReview;

  /// Checked on first render — everything except a duplicate.
  bool get selectedByDefault => !isDuplicate;
}

/// Groups bank-import candidates by their detected type and flags duplicates
/// of payments already in the vault.
class RecurringClassifier {
  static ImportGroup groupForType(String type) =>
      type == 'bill' ? ImportGroup.bills : ImportGroup.subscriptions;

  /// Normalised form for duplicate matching: lowercase, letters/digits only
  /// (keeps LT diacritics), so "Netflix" == "netflix.com" == "NETFLIX*".
  static String normalizeName(String s) =>
      s.toLowerCase().replaceAll(RegExp(r'[^a-z0-9ąčęėįšųūž]+'), '');

  static bool _isDuplicate(String name, Set<String> existingNormalized) {
    final n = normalizeName(name);
    if (n.isEmpty) return false;
    if (existingNormalized.contains(n)) return true;
    for (final e in existingNormalized) {
      if (e.length >= 4 && n.length >= 4 && (e.contains(n) || n.contains(e))) {
        return true;
      }
    }
    return false;
  }

  static RecurringClassification classify(
    RecurringCandidate c, {
    required Set<String> existingNormalizedNames,
  }) {
    return RecurringClassification(
      group: groupForType(c.type),
      isDuplicate: _isDuplicate(c.name, existingNormalizedNames),
      needsReview: c.needsReview,
    );
  }
}
