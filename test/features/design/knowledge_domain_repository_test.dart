import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:energylens_mobile/core/cloud_api/cloud_faq.dart';
import 'package:energylens_mobile/features/design/knowledge_domain_repository.dart';
import 'package:energylens_mobile/features/design/knowledge_question_catalog.dart';

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
  test('bundled catalog stages all approved labels while exposing answerable entries', () {
    final repository = KnowledgeDomainRepository(_Source());

    expect(repository.catalog.entries, hasLength(34));
    expect(
      repository.catalog.entries.where(
        (entry) => entry.availability == KnowledgeCatalogAvailability.draft,
      ),
      hasLength(17),
    );
    expect(
      KnowledgeDomainRepository.questions.map((question) => question.id),
      faqIntents.keys,
    );
    expect(repository.search('operating').map((question) => question.id), [
      'device_cost',
    ]);
    expect(repository.search('TOP_WASTE').first.id, 'reduce_waste');
    expect(repository.search('no matching approved question'), isEmpty);
    expect(repository.search('kilowatt').first.id, 'kilowatt_hour');
    expect(
      repository
          .search('AC power')
          .any((question) => question.id == 'ac_afternoon'),
      isFalse,
    );
    expect(
      repository.search('AC power', localPilot: true).first.id,
      'ac_afternoon',
    );
  });

  test('related phrases and spelling variants rank supported questions', () {
    final repository = KnowledgeDomainRepository(_Source());
    String? first(String query) => repository.search(query).firstOrNull?.id;

    expect(first('why is my power bill high'), 'high_use');
    expect(first('standby waste'), 'reduce_waste');
    expect(first('how much does my fridge cost to run'), 'device_cost');
    expect(first('lower my bill'), 'reduce_cost');
    expect(first('utility rebates'), 'device_programs');
    expect(first('rebtaes'), 'device_programs');
    expect(repository.search('zzzz qqqq'), isEmpty);
    expect(
      repository
          .search('rebates')
          .every((question) => repository.catalog.find(question.id) != null),
      isTrue,
    );
    expect(
      repository.search('phantom standby', localPilot: true).first.id,
      'standby_cost',
    );
    expect(
      repository.search('cheap washing', localPilot: true).first.id,
      'laundry_now',
    );
  });

  test('approved general answer works without a selected home', () async {
    final source = _Source();
    final result = await KnowledgeDomainRepository(source)
        .answerEntry(null, 'kilowatt_hour');
    expect(
      (result as KnowledgePreparedAnswerAvailable).text,
      'One kilowatt-hour is the energy used by a 1,000-watt device running for one hour.',
    );
    expect(source.calls, isEmpty);
  });

  test(
    'bundled pilot answers are exact existing demo text and never live',
    () async {
      final source = _Source();
      final repository = KnowledgeDomainRepository(source);
      const expected = <String, String>{
        'ac_afternoon': 'Outdoor heat peaked at 91°F. Your heat pump cycled more frequently between 2 PM and 5 PM.',
        'standby_cost': r'Around $0.11/day (~$3.30/mo), mostly from your study workstation and living room AV dock.',
        'laundry_now': 'Yes! Tier 1 off-peak pricing is active until 4:00 PM.',
      };
      for (final entry in expected.entries) {
        expect(
          await repository.answerEntry(_homeId, entry.key),
          isA<KnowledgeAnswerUnavailable>(),
        );
        final result = await repository.answerEntry(
          null,
          entry.key,
          localPilot: true,
        );
        expect((result as KnowledgePreparedAnswerAvailable).text, entry.value);
      }
      expect(source.calls, isEmpty);
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

  test(
    'catalog provides general answers without home or backend data',
    () async {
      final source = _Source();
      final repository = KnowledgeDomainRepository(
        source,
        catalog: KnowledgeQuestionCatalog([
          KnowledgeCatalogEntry(
            id: 'energy_unit',
            question: 'What is a kilowatt-hour?',
            availability: KnowledgeCatalogAvailability.published,
            preparedAnswer: 'A kilowatt-hour is 1,000 watts used for one hour.',
          ),
          KnowledgeCatalogEntry(
            id: 'demo_ac',
            question: 'Why did my AC power jump this afternoon?',
            availability: KnowledgeCatalogAvailability.localPilot,
            preparedAnswer: 'Illustrative demo answer.',
          ),
        ]),
      );

      expect(repository.search('kilowatt'), hasLength(1));
      expect(repository.search('AC power'), isEmpty);
      expect(
        repository.search('AC power', localPilot: true).single.id,
        'demo_ac',
      );
      final result = await repository.answerEntry(null, 'energy_unit');
      expect(result, isA<KnowledgePreparedAnswerAvailable>());
      expect(
        (result! as KnowledgePreparedAnswerAvailable).text,
        contains('1,000 watts'),
      );
      expect(
        await repository.answerEntry(null, 'demo_ac'),
        isA<KnowledgeAnswerUnavailable>(),
      );
      expect(source.calls, isEmpty);
    },
  );

  test(
    'catalog label routes only to its existing typed Cloud operation',
    () async {
      final source = _Source();
      final repository = KnowledgeDomainRepository(
        source,
        catalog: KnowledgeQuestionCatalog([
          KnowledgeCatalogEntry(
            id: 'running_fridge',
            question: 'What does my refrigerator cost to run?',
            availability: KnowledgeCatalogAvailability.published,
            cloudIntent: 'device_operating_cost',
          ),
        ]),
      );
      expect(
        await repository.answerEntry(_homeId, 'running_fridge'),
        isA<KnowledgeAnswerUnavailable>(),
      );
      expect(source.calls, isEmpty);
      const applianceId = '123e4567-e89b-12d3-a456-426614174001';
      expect(
        await repository.answerEntry(
          _homeId,
          'running_fridge',
          applianceId: applianceId,
        ),
        isA<KnowledgeAnswerAvailable>(),
      );
      expect(source.calls.single.questionId, 'device_operating_cost');
      expect(source.calls.single.applianceId, applianceId);
    },
  );
}
