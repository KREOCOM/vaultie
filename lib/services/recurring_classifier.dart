import 'banking_service.dart';

/// The two sections on the bank-import review screen. Detection returns EVERY
/// outgoing merchant tagged `autoDetected`, so the screen splits them into the
/// known ones (pre-selected) and everything else (the user picks).
enum ImportGroup { autoDetected, others }

const List<ImportGroup> kImportGroupOrder = [
  ImportGroup.autoDetected,
  ImportGroup.others,
];

String importGroupLabel(ImportGroup g, bool isLt) => switch (g) {
      ImportGroup.autoDetected => isLt ? 'Auto-aptikti' : 'Auto-detected',
      ImportGroup.others => isLt ? 'Kiti merchant\'ai' : 'Other merchants',
    };

/// Verdict for one candidate: its section, whether it duplicates something
/// already tracked, whether detection flagged it, and the default checkbox.
class RecurringClassification {
  const RecurringClassification({
    required this.group,
    required this.isDuplicate,
    required this.needsReview,
    required this.autoDetected,
  });

  final ImportGroup group;
  final bool isDuplicate;
  final bool needsReview;
  final bool autoDetected;

  /// Pre-checked only for auto-detected merchants (and never a duplicate); the
  /// user opts other merchants in themselves.
  bool get selectedByDefault => autoDetected && !isDuplicate;
}

/// Sorts bank-import candidates into the auto-detected / others sections and
/// flags duplicates of payments already in the vault.
class RecurringClassifier {
  static ImportGroup groupFor(bool autoDetected) =>
      autoDetected ? ImportGroup.autoDetected : ImportGroup.others;

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
      group: groupFor(c.autoDetected),
      isDuplicate: _isDuplicate(c.name, existingNormalizedNames),
      needsReview: c.needsReview,
      autoDetected: c.autoDetected,
    );
  }
}
