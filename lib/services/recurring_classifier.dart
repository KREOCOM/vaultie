import '../expense_categories.dart';
import 'banking_service.dart';

/// Coarse buckets the bank-import review screen groups detected recurring
/// payments into. Vaultie tracks ANY recurring payment (not just
/// subscriptions), so the buckets are broad on purpose.
enum ImportGroup {
  /// Netflix, Spotify, phone, gym, software… — things you subscribe to.
  services,

  /// Rent, utilities, home internet — anything tied to the home.
  housing,

  /// Loans, leasing, insurance.
  finance,

  /// Unknown merchants and person-to-person transfers. The only group left
  /// UNCHECKED by default, because it's where false positives hide.
  other,
}

/// Display order of the groups (checked-by-default first, "other" last).
const List<ImportGroup> kImportGroupOrder = [
  ImportGroup.services,
  ImportGroup.housing,
  ImportGroup.finance,
  ImportGroup.other,
];

String importGroupLabel(ImportGroup g, bool isLt) => switch (g) {
      ImportGroup.services => isLt ? 'Paslaugos' : 'Services',
      ImportGroup.housing => isLt ? 'Būstas' : 'Housing',
      ImportGroup.finance => isLt ? 'Finansai' : 'Finance',
      ImportGroup.other => isLt ? 'Kita' : 'Other',
    };

/// How sure we are a candidate is a real, recurring commitment.
enum ImportConfidence { high, medium, low }

/// The classifier's verdict for one candidate: a refined category, its group,
/// a confidence, whether it duplicates something already tracked, and the
/// resulting default checkbox state.
class RecurringClassification {
  const RecurringClassification({
    required this.categoryKey,
    required this.group,
    required this.confidence,
    required this.isDuplicate,
    required this.likelyPerson,
  });

  /// Refined [ExpenseCategory] key (better than the thin backend guess), used
  /// both for grouping and as the stored category when imported.
  final String categoryKey;
  final ImportGroup group;
  final ImportConfidence confidence;

  /// A payment with the same (normalised) name is already in the vault.
  final bool isDuplicate;

  /// The counterparty looks like a person's name (peer-to-peer transfer).
  final bool likelyPerson;

  /// Checked on first render? Everything except the "Other" group — and never
  /// a duplicate, to avoid adding the same commitment twice.
  bool get selectedByDefault => group != ImportGroup.other && !isDuplicate;
}

/// Name-based classification of recurring-payment candidates.
///
/// The backend only enriches a handful of global brands, so most real LT
/// payments (rent, Ignitis, telecoms, loans, insurance, peer transfers) arrive
/// as "Other". This fills that gap with keyword matching over the merchant
/// name, plus a person-name heuristic, so the import screen can group sensibly
/// and default-select only the confident ones.
class RecurringClassifier {
  /// Ordered (keyword substring -> [ExpenseCategory] key). First match wins, so
  /// specific brands come before generic words. Lowercase; matched against a
  /// lowercased merchant name.
  static const List<(String, String)> _keywordCategory = [
    // --- Services: streaming / software / digital ---
    ('netflix', 'entertainment'),
    ('spotify', 'entertainment'),
    ('youtube', 'entertainment'),
    ('disney', 'entertainment'),
    ('hbo', 'entertainment'),
    ('viaplay', 'entertainment'),
    ('go3', 'entertainment'),
    ('twitch', 'entertainment'),
    ('patreon', 'entertainment'),
    ('audible', 'entertainment'),
    ('storytel', 'entertainment'),
    ('playstation', 'entertainment'),
    ('xbox', 'entertainment'),
    ('nintendo', 'entertainment'),
    ('steam', 'entertainment'),
    ('icloud', 'entertainment'),
    ('itunes', 'entertainment'),
    ('apple', 'entertainment'),
    ('google', 'entertainment'),
    ('youtube premium', 'entertainment'),
    ('microsoft', 'entertainment'),
    ('office365', 'entertainment'),
    ('adobe', 'entertainment'),
    ('dropbox', 'entertainment'),
    ('openai', 'entertainment'),
    ('chatgpt', 'entertainment'),
    ('anthropic', 'entertainment'),
    ('claude', 'entertainment'),
    ('github', 'entertainment'),
    ('replit', 'entertainment'),
    ('notion', 'entertainment'),
    ('canva', 'entertainment'),
    ('amazon prime', 'entertainment'),
    // --- Services: health / fitness / education ---
    ('gym', 'health'),
    ('fitness', 'health'),
    ('impuls', 'health'),
    ('lemon', 'health'),
    ('wellness', 'health'),
    ('yoga', 'health'),
    ('sport', 'health'),
    ('udemy', 'education'),
    ('coursera', 'education'),
    ('skillshare', 'education'),
    ('duolingo', 'education'),
    ('babbel', 'education'),
    // --- Finance: loans / leasing / insurance (checked before Housing so a
    //     "Būsto paskola" (mortgage) reads as Finance, not Housing) ---
    ('paskol', 'finance'),
    ('loan', 'finance'),
    ('kredit', 'finance'),
    ('credit', 'finance'),
    ('lizing', 'finance'),
    ('leasing', 'finance'),
    ('financing', 'finance'),
    ('bigbank', 'finance'),
    ('vivus', 'finance'),
    ('ferratum', 'finance'),
    ('draudim', 'insurance'),
    ('insurance', 'insurance'),
    ('gjensidige', 'insurance'),
    ('compensa', 'insurance'),
    ('allianz', 'insurance'),
    ('ergo', 'insurance'),
    (' pzu', 'insurance'),
    ('bta', 'insurance'),
    // --- Housing: connectivity (phone / internet / TV) ---
    ('telia', 'connectivity'),
    ('tele2', 'connectivity'),
    ('bite', 'connectivity'),
    ('bitė', 'connectivity'),
    ('cgates', 'connectivity'),
    ('mezon', 'connectivity'),
    ('splius', 'connectivity'),
    ('balticum', 'connectivity'),
    ('pildyk', 'connectivity'),
    ('ežys', 'connectivity'),
    ('ezys', 'connectivity'),
    ('internet', 'connectivity'),
    ('broadband', 'connectivity'),
    // --- Housing: rent / utilities ---
    ('nuoma', 'housing'),
    ('rent', 'housing'),
    ('būsto', 'housing'),
    ('busto', 'housing'),
    ('mortgage', 'housing'),
    ('hipotek', 'housing'),
    ('administrav', 'housing'),
    ('ignitis', 'utilities'),
    ('vandenys', 'utilities'),
    ('vanduo', 'utilities'),
    ('water', 'utilities'),
    ('elektra', 'utilities'),
    ('dujos', 'utilities'),
    ('šildym', 'utilities'),
    ('sildym', 'utilities'),
    ('šilum', 'utilities'),
    ('silum', 'utilities'),
    ('energij', 'utilities'),
    ('atliek', 'utilities'),
    ('komunal', 'utilities'),
  ];

  /// Company/legal-form tokens that rule OUT the person heuristic.
  static final RegExp _companyToken = RegExp(
    r'\b(uab|ab|mb|všį|vsi|iį|ii|ltd|inc|llc|oy|gmbh|as|sia|plc|corp|co)\b',
    caseSensitive: false,
  );

  static final RegExp _personWord =
      RegExp(r'^[A-ZĄČĘĖĮŠŲŪŽ][a-ząčęėįšųūž]+$');

  /// True when [name] looks like a person's name (e.g. "Milda Dirsiene") rather
  /// than a merchant — the signature of a peer-to-peer transfer that shouldn't
  /// be imported as a recurring bill. A known logo domain always means merchant.
  static bool isLikelyPerson(String name, {String? logoDomain}) {
    if (logoDomain != null && logoDomain.isNotEmpty) return false;
    final n = name.trim();
    if (n.isEmpty) return false;
    if (_companyToken.hasMatch(n)) return false;
    // Domains, IBANs, references, amounts → not a bare person name.
    if (RegExp(r'[0-9@/.]').hasMatch(n)) return false;
    final tokens = n.split(RegExp(r'\s+')).where((t) => t.isNotEmpty).toList();
    if (tokens.length < 2 || tokens.length > 3) return false;
    return tokens.every(_personWord.hasMatch);
  }

  /// Refined category key for [c]: a keyword match, else the (normalised)
  /// backend category, else "other". Person-like names go straight to "other".
  static String categoryKeyFor(RecurringCandidate c) {
    if (isLikelyPerson(c.name, logoDomain: c.logoDomain)) return 'other';
    final hay = c.name.toLowerCase();
    for (final (needle, key) in _keywordCategory) {
      if (hay.contains(needle)) return key;
    }
    return normalizeCategoryKey(c.category);
  }

  static ImportGroup groupForCategory(String key) =>
      switch (normalizeCategoryKey(key)) {
        'housing' || 'utilities' || 'connectivity' => ImportGroup.housing,
        'finance' || 'insurance' => ImportGroup.finance,
        'entertainment' ||
        'health' ||
        'education' ||
        'transport' =>
          ImportGroup.services,
        _ => ImportGroup.other,
      };

  /// Normalised form used for duplicate matching: lowercase, letters/digits only
  /// (keeps LT diacritics), so "Netflix" == "netflix.com" == "NETFLIX*".
  static String normalizeName(String s) =>
      s.toLowerCase().replaceAll(RegExp(r'[^a-z0-9ąčęėįšųūž]+'), '');

  static bool _isDuplicate(String name, Set<String> existingNormalized) {
    final n = normalizeName(name);
    if (n.isEmpty) return false;
    if (existingNormalized.contains(n)) return true;
    // Substring match for short brand names (e.g. "netflix" in "netflixeur").
    for (final e in existingNormalized) {
      if (e.length >= 4 && n.length >= 4 && (e.contains(n) || n.contains(e))) {
        return true;
      }
    }
    return false;
  }

  /// Full verdict for one candidate against the names already in the vault.
  static RecurringClassification classify(
    RecurringCandidate c, {
    required Set<String> existingNormalizedNames,
  }) {
    final person = isLikelyPerson(c.name, logoDomain: c.logoDomain);
    final key = categoryKeyFor(c);
    final group = groupForCategory(key);
    final classified = key != 'other';

    final ImportConfidence confidence;
    if (person) {
      confidence = ImportConfidence.low;
    } else if (c.occurrences >= 3 && classified && !c.amountVaries) {
      confidence = ImportConfidence.high;
    } else if (classified || c.occurrences >= 3) {
      confidence = ImportConfidence.medium;
    } else {
      confidence = ImportConfidence.low;
    }

    return RecurringClassification(
      categoryKey: key,
      group: group,
      confidence: confidence,
      isDuplicate: _isDuplicate(c.name, existingNormalizedNames),
      likelyPerson: person,
    );
  }
}
