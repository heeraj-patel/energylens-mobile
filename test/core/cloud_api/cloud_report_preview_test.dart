import 'package:flutter_test/flutter_test.dart';
import 'package:energylens_mobile/core/cloud_api/cloud_report_preview.dart';

const home = '11111111-1111-4111-8111-111111111111';
const appliance = '22222222-2222-4222-8222-222222222222';
const fact = '33333333-3333-4333-8333-333333333333';
const tariff = '44444444-4444-4444-8444-444444444444';
const id = '55555555-5555-4555-8555-555555555555';

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
}
