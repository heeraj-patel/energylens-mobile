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

  /// Filters only the existing supported question IDs and their approved
  /// labels. No dynamic intent discovery or answer-text search is performed.
  List<KnowledgeQuestion> search(String query) {
    final normalized = query.trim().toLowerCase();
    if (normalized.isEmpty) return questions;
    return List.unmodifiable(
      questions.where(
        (question) =>
            question.id.toLowerCase().contains(normalized) ||
            question.label.toLowerCase().contains(normalized),
      ),
    );
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

final _uuid = RegExp(
  r'^[0-9a-fA-F]{8}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{12}$',
);
