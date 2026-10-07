import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:energylens_mobile/core/cloud_api/cloud_faq.dart';
import 'package:energylens_mobile/features/design/knowledge_domain_repository.dart';

const _homeId = '123e4567-e89b-12d3-a456-426614174000';

CloudFaqAnswer _answer(String intent) => CloudFaqAnswer.fromJson({
  'question_id': intent,
  'status': 'insufficient_information',
  'answer': faqInsufficientAnswer,
  'findings': <Object>[],
  'evidence_refs': <Object>[],
  'as_of': '2026-10-06T12:00:00Z',
  'next_action': {
    'kind': 'adaptive_questions',
    'flow_id': 'faq-contributors/v1',
  },
}, intent);

class _Source implements KnowledgeDomainSource {
  final calls = <({String homeId, String questionId, String? applianceId})>[];
  Future<CloudFaqAnswer> Function(String, String, {String? applianceId})?
  onAnswer;

  @override
  Future<CloudFaqAnswer> faqAnswer(
    String homeId,
    String questionId, {
    String? applianceId,
  }) {
    calls.add((
      homeId: homeId,
      questionId: questionId,
      applianceId: applianceId,
    ));
    return onAnswer?.call(homeId, questionId, applianceId: applianceId) ??
        Future.value(_answer(questionId));
  }
}

void main() {
  test(
    'catalog and local search expose only the existing FAQ IDs and labels',
    () {
      final repository = KnowledgeDomainRepository(_Source());

      expect(
        KnowledgeDomainRepository.questions.map((question) => question.id),
        faqIntents.keys,
      );
      expect(repository.search('operating').map((question) => question.id), [
        'device_operating_cost',
      ]);
      expect(repository.search('TOP_WASTE').map((question) => question.id), [
        'top_waste_opportunities',
      ]);
      expect(repository.search('no matching approved question'), isEmpty);
    },
  );

  test(
    'unsupported intent is unavailable and makes no backend request',
    () async {
      final source = _Source();
      final result = await KnowledgeDomainRepository(source)
          .answer(_homeId, 'how_to_install_solar');

      expect(result, isA<KnowledgeAnswerUnavailable>());
      expect(
        (result! as KnowledgeAnswerUnavailable).questionId,
        'how_to_install_solar',
      );
      expect(source.calls, isEmpty);
    },
  );

  test(
    'appliance FAQ is unavailable without its required appliance ID',
    () async {
      final source = _Source();
      final result = await KnowledgeDomainRepository(source)
          .answer(_homeId, 'device_operating_cost');

      expect(result, isA<KnowledgeAnswerUnavailable>());
      expect(source.calls, isEmpty);
    },
  );

  test('supported intent returns only the typed backend answer', () async {
    final source = _Source();
    final result = await KnowledgeDomainRepository(source)
        .answer(_homeId, 'high_bill_possible_contributors');

    expect(result, isA<KnowledgeAnswerAvailable>());
    expect(
      (result! as KnowledgeAnswerAvailable).answer.intent,
      'high_bill_possible_contributors',
    );
    expect(source.calls.single.questionId, 'high_bill_possible_contributors');
  });

  test('operating cost forwards the selected appliance ID', () async {
    final source = _Source();
    final applianceId = '123e4567-e89b-12d3-a456-426614174001';
    final result = await KnowledgeDomainRepository(source)
        .answer(_homeId, 'device_operating_cost', applianceId: applianceId);

    expect(result, isA<KnowledgeAnswerAvailable>());
    expect(source.calls.single.applianceId, applianceId);
  });

  test(
    'clear discards an answer that completes after context invalidation',
    () async {
      final source = _Source();
      final pending = Completer<CloudFaqAnswer>();
      source.onAnswer = (_, _, {applianceId}) => pending.future;
      final repository = KnowledgeDomainRepository(source);
      final request = repository.answer(
        _homeId,
        'high_bill_possible_contributors',
      );

      repository.clear();
      pending.complete(_answer('high_bill_possible_contributors'));

      expect(await request, isNull);
    },
  );
}
