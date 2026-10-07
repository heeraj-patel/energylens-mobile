import '../../core/cloud_api/cloud_api_client.dart';
import '../../core/cloud_api/cloud_faq.dart';
import 'knowledge_question_catalog.dart';

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

class KnowledgePreparedAnswerAvailable extends KnowledgeAnswerResult {
  const KnowledgePreparedAnswerAvailable(this.questionId, this.text);

  final String questionId;
  final String text;
}

class KnowledgeAnswerUnavailable extends KnowledgeAnswerResult {
  const KnowledgeAnswerUnavailable(this.questionId);

  final String questionId;
}

/// Nonvisual FAQ adapter. It does not synthesize answers; all available
/// answers are returned by the existing typed FAQ operation.
class KnowledgeDomainRepository {
  KnowledgeDomainRepository(this.source, {KnowledgeQuestionCatalog? catalog})
    : catalog = catalog ?? _defaultCatalog();

  final KnowledgeDomainSource source;
  final KnowledgeQuestionCatalog catalog;
  String? _homeId;
  int _generation = 0;

  static List<KnowledgeQuestion> get questions => List.unmodifiable(
    faqIntents.entries.map(
      (entry) => KnowledgeQuestion(id: entry.key, label: entry.value),
    ),
  );

  /// A bundled reviewed catalog can contain general and contextual questions
  /// beyond the five existing Cloud answer operations.
  List<KnowledgeQuestion> search(String query, {bool localPilot = false}) =>
      List.unmodifiable(
        catalog
            .search(query, localPilot: localPilot)
            .map(
              (entry) => KnowledgeQuestion(id: entry.id, label: entry.question),
            ),
      );

  Future<KnowledgeAnswerResult?> answerEntry(
    String? homeId,
    String questionId, {
    String? applianceId,
    bool localPilot = false,
  }) async {
    final entry = catalog.find(questionId, localPilot: localPilot);
    if (entry == null) return KnowledgeAnswerUnavailable(questionId);
    if (entry.preparedAnswer case final text?) {
      return KnowledgePreparedAnswerAvailable(questionId, text);
    }
    if (homeId == null) return KnowledgeAnswerUnavailable(questionId);
    return answer(homeId, entry.cloudIntent!, applianceId: applianceId);
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

KnowledgeQuestionCatalog _defaultCatalog() => KnowledgeQuestionCatalog(
  faqIntents.entries.map(
    (entry) => KnowledgeCatalogEntry(
      id: entry.key,
      question: entry.value,
      availability: KnowledgeCatalogAvailability.published,
      aliases: [entry.key, ...?_questionAliases[entry.key]],
      cloudIntent: entry.key,
    ),
  ),
);

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

final _uuid = RegExp(
  r'^[0-9a-fA-F]{8}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{12}$',
);
