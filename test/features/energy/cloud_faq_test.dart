import 'package:energylens_mobile/core/cloud_api/cloud_faq.dart';
import 'package:energylens_mobile/core/cloud_api/cloud_home.dart';
import 'package:flutter_test/flutter_test.dart';

const home = CloudHome(
  id: '11111111-1111-4111-8111-111111111111',
  name: 'Home',
  timezone: 'America/Chicago',
  countryCode: 'US',
  postalCode: '60601',
);
const appliance = '22222222-2222-4222-8222-222222222222';
const catalog = '33333333-3333-4333-8333-333333333333';
const tariff = '44444444-4444-4444-8444-444444444444';

Map<String, Object?> _cost() {
  final refs = [
    {'id': catalog, 'kind': 'catalog_fact', 'revision': 2},
    {'id': tariff, 'kind': 'tariff', 'revision': 1},
  ];
  return {
    'question_id': 'device_operating_cost',
    'status': 'supported',
    'answer': 'An operating cost estimate is available for this device.',
    'findings': [
      {
        'label': 'estimate',
        'text':
            'Estimated operating cost: 0.00 USD for 2026-10-01 to 2026-11-01.',
        'evidence_refs': refs,
      },
    ],
    'evidence_refs': refs,
    'as_of': '2026-10-01T00:00:00Z',
  };
}

void main() {
  test(
    'accepts current cautious high-use observation and rejects bill cause',
    () {
      final refs = [
        {'id': catalog, 'kind': 'weather_window', 'revision': 1},
      ];
      final supported = {
        'question_id': 'high_bill_possible_contributors',
        'status': 'partial',
        'answer': 'These observations give context for possible energy demand. They do not establish a change in home energy use or a bill cause.',
        'findings': [
          {
            'label': 'observation',
            'text': 'Warm weather was observed during this period.',
            'evidence_refs': refs,
          },
        ],
        'evidence_refs': refs,
        'as_of': '2026-10-01T00:00:00Z',
      };
      expect(
        CloudFaqAnswer.fromJson(
          supported,
          'high_bill_possible_contributors',
        ).findings.single.label,
        'observation',
      );
      supported['answer'] = 'Warm weather caused your bill to rise.';
      expect(
        () => CloudFaqAnswer.fromJson(
          supported,
          'high_bill_possible_contributors',
        ),
        throwsFormatException,
      );
    },
  );

  test('rejects unsourced or fabricated device cost', () {
    expect(
      CloudFaqAnswer.fromJson(
        _cost(),
        'device_operating_cost',
      ).findings.single.text,
      contains('0.00 USD'),
    );
    final unsourced = _cost();
    final finding =
        (unsourced['findings'] as List).single as Map<String, Object?>;
    finding['evidence_refs'] = [
      {'id': catalog, 'kind': 'catalog_fact', 'revision': 2},
    ];
    unsourced['evidence_refs'] = finding['evidence_refs'];
    expect(
      () => CloudFaqAnswer.fromJson(unsourced, 'device_operating_cost'),
      throwsFormatException,
    );
    final invented = _cost();
    (invented['findings'] as List).single['text'] =
        'Your bill increased by 20%.';
    expect(
      () => CloudFaqAnswer.fromJson(invented, 'device_operating_cost'),
      throwsFormatException,
    );
  });

  test('accepts Datawiz cost evidence without accepting mixed sources', () {
    final resolved = _cost();
    final refs = [
      {'id': appliance, 'kind': 'datawiz_resolution', 'revision': 1},
      {'id': tariff, 'kind': 'tariff', 'revision': 1},
    ];
    (resolved['findings'] as List).single['evidence_refs'] = refs;
    resolved['evidence_refs'] = refs;
    expect(
      CloudFaqAnswer.fromJson(
        resolved,
        'device_operating_cost',
        applianceId: appliance,
      ).findings.single.refs.first.kind,
      'datawiz_resolution',
    );
    for (final badRefs in [
      [refs.first],
      [refs.first, refs.first, refs.last],
      [
        refs.first,
        {'id': catalog, 'kind': 'catalog_fact', 'revision': 2},
        refs.last,
      ],
      [
        {'id': appliance, 'kind': 'datawiz_resolution', 'revision': 2},
        refs.last,
      ],
      [
        {'id': catalog, 'kind': 'datawiz_resolution', 'revision': 1},
        refs.last,
      ],
    ]) {
      final bad = _cost();
      (bad['findings'] as List).single['evidence_refs'] = badRefs;
      bad['evidence_refs'] = badRefs;
      expect(
        () => CloudFaqAnswer.fromJson(
          bad,
          'device_operating_cost',
          applianceId: appliance,
        ),
        throwsFormatException,
      );
    }
  });
}
