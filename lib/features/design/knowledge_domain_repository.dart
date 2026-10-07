import '../../core/cloud_api/cloud_api_client.dart';
import '../../core/cloud_api/cloud_faq.dart';

/// The Knowledge page can list and search only FAQ questions already defined
/// by the typed FAQ contract. Labels are reused verbatim from that contract.
class KnowledgeQuestion {
  const KnowledgeQuestion({required this.id, required this.label});

  final String id;
  final String label;
}

abstract interface class KnowledgeDomainSource {
  Future<CloudFaqAnswer> faqAnswer(
    String homeId,
    String questionId, {
    String? applianceId,
  });
}

class CloudKnowledgeDomainSource implements KnowledgeDomainSource {
  const CloudKnowledgeDomainSource(this.api);

  final CloudApiClient api;

  @override
  Future<CloudFaqAnswer> faqAnswer(
    String homeId,
    String questionId, {
    String? applianceId,
  }) => api.faqAnswer(homeId, questionId, applianceId: applianceId);
}

sealed class KnowledgeAnswerResult {
  const KnowledgeAnswerResult();
}

class KnowledgeAnswerAvailable extends KnowledgeAnswerResult {
  const KnowledgeAnswerAvailable(this.answer);

  final CloudFaqAnswer answer;
}

class KnowledgeAnswerUnavailable extends KnowledgeAnswerResult {
  const KnowledgeAnswerUnavailable(this.questionId);

  final String questionId;
}

/// Nonvisual FAQ adapter. It does not synthesize answers; all available
/// answers are returned by the existing typed FAQ operation.
class KnowledgeDomainRepository {
  KnowledgeDomainRepository(this.source);

  final KnowledgeDomainSource source;
  String? _homeId;
  int _generation = 0;

  static List<KnowledgeQuestion> get questions => List.unmodifiable(
    faqIntents.entries.map(
      (entry) => KnowledgeQuestion(id: entry.key, label: entry.value),
    ),
  );

  /// Ranks the five supported questions using their labels, related phrases,
  /// and small spelling corrections. It never invents an intent or answer.
  List<KnowledgeQuestion> search(String query) {
    final normalized = _normalizeSearch(query);
    if (normalized.isEmpty) return questions;
    final tokens = _searchTokens(normalized);
    if (tokens.isEmpty) return questions;
    final ranked = <({KnowledgeQuestion question, int score, int order})>[];
    for (var index = 0; index < questions.length; index++) {
      final question = questions[index];
      final label = _normalizeSearch(question.label);
      final id = _normalizeSearch(question.id);
      final aliases = _questionAliases[question.id] ?? const <String>[];
      var score = 0;
      if (label.contains(normalized) || id.contains(normalized)) score += 100;
      for (final alias in aliases) {
        final normalizedAlias = _normalizeSearch(alias);
        if (normalizedAlias.contains(normalized) ||
            normalized.contains(normalizedAlias)) {
          score += 45;
        }
      }
      final documentTokens = _searchTokens([label, id, ...aliases].join(' '));
      for (final token in tokens) {
        if (documentTokens.contains(token)) {
          score += 10;
        } else if (documentTokens.any(
          (word) => _smallSpellingDifference(word, token),
        )) {
          score += 3;
        }
      }
      if (score > 0) {
        ranked.add((question: question, score: score, order: index));
      }
    }
    ranked.sort((a, b) {
      final byScore = b.score.compareTo(a.score);
      return byScore != 0 ? byScore : a.order.compareTo(b.order);
    });
    return List.unmodifiable(ranked.map((entry) => entry.question));
  }

  void clear() {
    _homeId = null;
    _generation++;
  }

  Future<KnowledgeAnswerResult?> answer(
    String homeId,
    String questionId, {
    String? applianceId,
  }) async {
    if (!_uuid.hasMatch(homeId)) throw ArgumentError.value(homeId, 'homeId');
    _homeId = homeId;
    final generation = ++_generation;
    bool stale() => generation != _generation || _homeId != homeId;

    if (!faqIntents.containsKey(questionId) ||
        (questionId == 'device_operating_cost') != (applianceId != null)) {
      return KnowledgeAnswerUnavailable(questionId);
    }
    try {
      final answer = await source.faqAnswer(
        homeId,
        questionId,
        applianceId: applianceId,
      );
      if (stale()) return null;
      return KnowledgeAnswerAvailable(answer);
    } catch (_) {
      if (stale()) return null;
      rethrow;
    }
  }
}

const _questionAliases = <String, List<String>>{
  'high_bill_possible_contributors': [
    'why is my bill high',
    'high electricity bill',
    'what uses the most energy',
    'energy use increase',
    'power bill spike',
  ],
  'top_waste_opportunities': [
    'energy waste',
    'standby waste',
    'idle power',
    'reduce wasted energy',
    'biggest waste',
  ],
  'device_operating_cost': [
    'appliance running cost',
    'how much does my device cost',
    'cost of running my fridge',
    'device electricity cost',
  ],
  'reduce_cost': [
    'save money',
    'lower my bill',
    'cut electricity costs',
    'how to save energy',
  ],
  'programs_for_device': [
    'rebates',
    'utility programs',
    'incentives for appliances',
    'energy efficiency programs',
  ],
};

String _normalizeSearch(String value) => value
    .toLowerCase()
    .replaceAll(RegExp(r'[^a-z0-9]+'), ' ')
    .trim()
    .replaceAll(RegExp(r'\s+'), ' ');

Set<String> _searchTokens(String value) =>
    _normalizeSearch(value)
        .split(' ')
        .where((word) => word.length > 2 && !_searchStopWords.contains(word))
        .toSet();

const _searchStopWords = <String>{
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

bool _smallSpellingDifference(String word, String query) {
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

final _uuid = RegExp(
  r'^[0-9a-fA-F]{8}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{12}$',
);
