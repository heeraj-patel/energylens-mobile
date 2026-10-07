import '../../core/cloud_api/cloud_faq.dart';

enum KnowledgeCatalogAvailability { published, localPilot, draft }

/// A reviewed FAQ label and its bounded answer route. The catalog is separate
/// from the Cloud FAQ answer operation: many labels may use one operation, and
/// a prepared general answer requires no home or device data.
class KnowledgeCatalogEntry {
  KnowledgeCatalogEntry({
    required this.id,
    required this.question,
    required this.availability,
    this.aliases = const [],
    this.preparedAnswer,
    this.cloudIntent,
  }) {
    if (!RegExp(r'^[a-z][a-z0-9_]{2,63}$').hasMatch(id) ||
        question.trim().isEmpty ||
        question.length > 180 ||
        aliases.any((alias) => alias.trim().isEmpty || alias.length > 180) ||
        (preparedAnswer != null) == (cloudIntent != null) ||
        (preparedAnswer != null && preparedAnswer!.trim().isEmpty) ||
        (cloudIntent != null && !faqIntents.containsKey(cloudIntent))) {
      throw const FormatException('Invalid FAQ catalog entry');
    }
  }

  final String id;
  final String question;
  final KnowledgeCatalogAvailability availability;
  final List<String> aliases;
  final String? preparedAnswer;
  final String? cloudIntent;

  bool get needsAppliance => cloudIntent == 'device_operating_cost';
}

class KnowledgeQuestionCatalog {
  KnowledgeQuestionCatalog(Iterable<KnowledgeCatalogEntry> entries)
    : entries = List.unmodifiable(entries) {
    if (this.entries.map((entry) => entry.id).toSet().length !=
        this.entries.length) {
      throw const FormatException('Duplicate FAQ catalog ID');
    }
  }

  final List<KnowledgeCatalogEntry> entries;

  KnowledgeCatalogEntry? find(String id, {bool localPilot = false}) {
    for (final entry in entries) {
      if (entry.id == id && _available(entry, localPilot)) return entry;
    }
    return null;
  }

  List<KnowledgeCatalogEntry> search(String query, {bool localPilot = false}) {
    final available = entries
        .where((entry) => _available(entry, localPilot))
        .toList();
    final normalized = _normalize(query);
    if (normalized.isEmpty) return List.unmodifiable(available);
    final tokens = _tokens(normalized);
    if (tokens.isEmpty) return List.unmodifiable(available);
    final ranked = <({KnowledgeCatalogEntry entry, int score, int order})>[];
    for (var index = 0; index < available.length; index++) {
      final entry = available[index];
      final label = _normalize(entry.question);
      final aliases = entry.aliases.map(_normalize).toList();
      var score = 0;
      if (label.contains(normalized)) score += 100;
      for (final alias in aliases) {
        if (alias.contains(normalized) || normalized.contains(alias)) {
          score += 45;
        }
      }
      final words = _tokens([label, ...aliases].join(' '));
      for (final token in tokens) {
        if (words.contains(token)) {
          score += 10;
        } else if (words.any((word) => _oneEditAway(word, token))) {
          score += 3;
        }
      }
      if (score > 0) ranked.add((entry: entry, score: score, order: index));
    }
    ranked.sort((a, b) {
      final byScore = b.score.compareTo(a.score);
      return byScore != 0 ? byScore : a.order.compareTo(b.order);
    });
    return List.unmodifiable(ranked.map((result) => result.entry));
  }

  bool _available(KnowledgeCatalogEntry entry, bool localPilot) =>
      entry.availability == KnowledgeCatalogAvailability.published ||
      (localPilot &&
          entry.availability == KnowledgeCatalogAvailability.localPilot);
}

String _normalize(String value) => value
    .toLowerCase()
    .replaceAll(RegExp(r'[^a-z0-9]+'), ' ')
    .trim()
    .replaceAll(RegExp(r'\s+'), ' ');

Set<String> _tokens(String value) =>
    _normalize(value)
        .split(' ')
        .where((word) => word.length > 2 && !_stopWords.contains(word))
        .toSet();

const _stopWords = <String>{
  'the',
  'and',
  'for',
  'what',
  'where',
  'could',
  'does',
  'with',
  'from',
  'how',
  'are',
  'there',
  'can',
  'why',
  'has',
  'have',
  'you',
  'your',
  'my',
};

bool _oneEditAway(String word, String query) {
  if (query.length < 5 || (word.length - query.length).abs() > 1) return false;
  var prefix = 0;
  while (prefix < word.length &&
      prefix < query.length &&
      word[prefix] == query[prefix]) {
    prefix++;
  }
  if (prefix == word.length && prefix == query.length) return true;
  if (word.length == query.length) {
    return word.substring(prefix + 1) == query.substring(prefix + 1) ||
        (prefix + 1 < word.length &&
            word[prefix] == query[prefix + 1] &&
            word[prefix + 1] == query[prefix] &&
            word.substring(prefix + 2) == query.substring(prefix + 2));
  }
  final longer = word.length > query.length ? word : query;
  final shorter = word.length > query.length ? query : word;
  return longer.substring(prefix + 1) == shorter.substring(prefix);
}
