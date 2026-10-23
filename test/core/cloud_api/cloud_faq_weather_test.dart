import 'package:energylens_mobile/core/cloud_api/cloud_faq.dart';
import 'package:flutter_test/flutter_test.dart';

const _ref = {
  'id': '33333333-3333-4333-8333-333333333333',
  'kind': 'weather_day',
  'revision': 2,
};
const _alertRef = {
  'id': '33333333-3333-4333-8333-333333333333',
  'kind': 'weather_alert',
  'revision': 2,
};
const _base = {
  'question_id': 'weather_tips',
  'as_of': '2026-10-23T16:00:00Z',
  'weather_status': 'available',
};

CloudFaqAnswer _parse(Map<String, dynamic> json) =>
    CloudFaqAnswer.fromJson({..._base, ...json}, 'weather_tips');

void main() {
  test('weather_tips is accepted but not a listed question', () {
    expect(isFaqIntent('weather_tips'), isTrue);
    expect(faqIntents.containsKey('weather_tips'), isFalse);
    expect(isFaqIntent('other'), isFalse);
  });

  test('supported with tips keeps source_url and dedupes refs', () {
    final answer = _parse({
      'status': 'supported',
      'answer': 'Weather tips apply.',
      'findings': [
        {
          'label': 'hypothesis',
          'text': 'Close blinds during the day.',
          'evidence_refs': [_ref],
          'source_url': 'https://www.pge.com/x',
        },
        {
          'label': 'observation',
          'text': 'Heat Advisory',
          'evidence_refs': [_alertRef],
        },
      ],
      'evidence_refs': [_ref],
    });
    expect(answer.weatherStatus, 'available');
    expect(answer.findings.first.sourceUrl.toString(), 'https://www.pge.com/x');
    expect(answer.findings.last.sourceUrl, isNull);
  });

  test('supported with no active trigger', () {
    final answer = _parse({
      'status': 'supported',
      'answer': faqWeatherNoTipsAnswer,
      'findings': [],
      'evidence_refs': [],
    });
    expect(answer.findings, isEmpty);
    expect(answer.adaptiveQuestions, isFalse);
    for (final bad in [
      {'status': 'supported', 'answer': 'Nothing.'},
      {'status': 'partial', 'answer': faqWeatherNoTipsAnswer},
    ]) {
      expect(
        () => _parse({...bad, 'findings': [], 'evidence_refs': []}),
        throwsFormatException,
      );
    }
  });

  test('weather unavailable carries status and reason', () {
    final answer = _parse({
      'weather_status': 'missing',
      'weather_reason': 'provider_unavailable',
      'status': 'insufficient_information',
      'answer': faqInsufficientAnswer,
      'findings': [],
      'evidence_refs': [],
      'next_action': {
        'kind': 'adaptive_questions',
        'flow_id': 'faq-contributors/v1',
      },
    });
    expect(answer.adaptiveQuestions, isTrue);
    expect(answer.weatherStatus, 'missing');
    expect(answer.weatherReason, 'provider_unavailable');
  });

  test('non-https source_url is dropped, unreferenced evidence rejected', () {
    final finding = {
      'label': 'hypothesis',
      'text': 'Tip.',
      'evidence_refs': [_ref],
      'source_url': 'http://www.pge.com/x',
    };
    final answer = _parse({
      'status': 'supported',
      'answer': 'Weather tips apply.',
      'findings': [finding],
      'evidence_refs': [_ref],
    });
    expect(answer.findings.single.sourceUrl, isNull);
    expect(
      () => _parse({
        'status': 'supported',
        'answer': 'Weather tips apply.',
        'findings': [finding],
        'evidence_refs': [_alertRef],
      }),
      throwsFormatException,
    );
  });
}
