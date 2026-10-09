import 'package:flutter_test/flutter_test.dart';
import 'package:energylens_mobile/core/cloud_api/cloud_report_preview.dart';

const home = '11111111-1111-4111-8111-111111111111';
const appliance = '22222222-2222-4222-8222-222222222222';
const fact = '33333333-3333-4333-8333-333333333333';
const tariff = '44444444-4444-4444-8444-444444444444';
const id = '55555555-5555-4555-8555-555555555555';
const seeded = '839e2376-d211-5137-b5fb-09486a7d978a';

Map<String, dynamic> payload() => {
  'id': id,
  'snapshot_sha256': 'a' * 64,
  'home_id': home,
  'schema_version': 'manual-preview/v1',
  'created_at': '2026-09-28T12:00:00Z',
  'expires_at': '2026-09-29T12:00:00Z',
  'scope': 'selected_appliances',
  'home_total_status': 'unavailable_incomplete_scope',
  'measured_status': 'not_included',
  'recommendations_status': 'not_included',
  'assumptions': ['Only selected appliances are included.'],
  'items': [
    {
      'appliance_id': appliance,
      'category': 'washer',
      'explanation': 'Estimate only.',
      'estimate': {
        'kind': 'estimated_operating_cost',
        'energy_kwh': '0',
        'cost_usd': '0.00',
        'period_start': '2026-09-01',
        'period_end': '2026-10-01',
        'as_of': '2026-09-28T12:00:00Z',
        'source_refs': [
          {'id': fact, 'kind': 'catalog_fact', 'revision': 2},
          {'id': tariff, 'kind': 'tariff', 'revision': 1},
        ],
      },
    },
  ],
  'stale': false,
};

void main() {
  test(
    'accepts v2 seeded and mixed previews with version-specific statuses',
    () {
      final v2 = {
        ...payload(),
        'schema_version': 'manual-preview/v2',
        'measured_status': 'unavailable',
        'recommendations_status': 'unavailable',
        'items': [
          {
            'appliance_id': seeded,
            'category': 'other',
            'explanation': 'No current reviewed monthly estimate is available.',
            'estimate': null,
          },
          ...(payload()['items'] as List),
        ],
      };
      final preview = CloudReportPreview.fromJson(v2, home, {
        seeded,
        appliance,
      });
      expect(preview.items.length, 2);
      expect(preview.items.first.estimate, isNull);
      expect(preview.items.last.estimate!.costUsd, '0.00');
      for (final measured in ['unavailable', 'partial']) {
        for (final recommendations in ['unavailable', 'available']) {
          expect(
            CloudReportPreview.fromJson(
              {
                ...v2,
                'measured_status': measured,
                'recommendations_status': recommendations,
              },
              home,
              {seeded, appliance},
            ).items.length,
            2,
          );
        }
      }
      for (final bad in [
        {...v2, 'measured_status': 'not_included'},
        {...v2, 'recommendations_status': 'not_included'},
        {...payload(), 'measured_status': 'partial'},
        {
          ...v2,
          'items': [(v2['items'] as List).first, (v2['items'] as List).first],
        },
      ]) {
        expect(
          () => CloudReportPreview.fromJson(bad, home, {seeded, appliance}),
          throwsFormatException,
        );
      }
    },
  );

  test('validates home, fingerprint, source evidence and local expiry', () {
    final preview = CloudReportPreview.fromJson(payload(), home, {appliance});
    expect(preview.items.single.estimate!.costUsd, '0.00');
    expect(preview.snapshotSha256, 'a' * 64);
    expect(preview.isStale, isTrue);
    expect(
      () => CloudReportPreview.fromJson(
        {...payload(), 'snapshot_sha256': 'bad'},
        home,
        {appliance},
      ),
      throwsFormatException,
    );
    expect(
      () => CloudReportPreview.fromJson(payload(), fact, {appliance}),
      throwsFormatException,
    );
    expect(
      () => CloudReportPreview.fromJson(payload(), home, {fact}),
      throwsFormatException,
    );
    final unsourced = payload();
    ((unsourced['items'] as List).single['estimate']['source_refs'] as List)
        .removeLast();
    expect(
      () => CloudReportPreview.fromJson(unsourced, home, {appliance}),
      throwsFormatException,
    );
  });

  test('parses optional recipient-free latest delivery status', () {
    final base = payload();
    expect(
      CloudReportPreview.fromJson(base, home, {appliance}).latestDelivery,
      isNull,
    );
    final withNull = {...base, 'latest_delivery': null};
    expect(
      CloudReportPreview.fromJson(withNull, home, {appliance}).latestDelivery,
      isNull,
    );

    final delivered = CloudReportPreview.fromJson(
      {
        ...base,
        'latest_delivery': {
          'id': '66666666-6666-4666-8666-666666666666',
          'state': 'sent',
          'created_at': '2026-09-28T12:01:00Z',
          'sent_at': '2026-09-28T12:02:00Z',
        },
      },
      home,
      {appliance},
    );
    expect(delivered.latestDelivery!.state, 'sent');
    expect(delivered.latestDelivery!.sentAt, DateTime.utc(2026, 9, 28, 12, 2));
    // Delivery metadata is outside the immutable preview approval hash.
    expect(delivered.snapshotSha256, 'a' * 64);
  });

  test(
    'rejects malformed, recipient-bearing, and cross-preview delivery data',
    () {
      final invalidStatuses = <Map<String, dynamic>>[
        {
          'id': '66666666-6666-4666-8666-666666666666',
          'state': 'pending',
          'created_at': '2026-09-28T12:01:00Z',
          'sent_at': '2026-09-28T12:02:00Z',
        },
        {
          'id': '66666666-6666-4666-8666-666666666666',
          'state': 'sent',
          'created_at': '2026-09-28T12:01:00Z',
          'sent_at': null,
        },
        {
          'id': '66666666-6666-4666-8666-666666666666',
          'state': 'pending',
          'created_at': '2026-09-28T12:01:00Z',
          'sent_at': null,
          'recipients': ['owner@example.com'],
        },
        {
          'id': id,
          'state': 'canceled',
          'created_at': '2026-09-28T12:01:00Z',
          'sent_at': null,
        },
      ];
      for (final status in invalidStatuses) {
        expect(
          () => CloudReportPreview.fromJson(
            {...payload(), 'latest_delivery': status},
            home,
            {appliance},
          ),
          throwsFormatException,
        );
      }
    },
  );
}
