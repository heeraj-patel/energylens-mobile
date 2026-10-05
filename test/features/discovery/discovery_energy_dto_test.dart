import 'package:flutter_test/flutter_test.dart';
import 'package:energylens_mobile/features/discovery/discovery_api.dart';

void main() {
  group('manufacturer nameplate spec response', () {
    test('parses a matched rated input without energy estimate fields', () {
      final spec = ApplianceSpec.fromJson({
        'status': 'matched',
        'evidence': {
          'source_kind': 'oem_rated_input',
          'rated_input_watts': 1350,
          'source_url': 'https://example.test/manual.pdf',
          'matched_brand': 'Example',
          'matched_model': 'Kettle 1',
          'usage_basis': 'Nameplate input',
          'retrieved_at': 1790000000,
        },
      });

      expect(spec.status, 'matched');
      expect(spec.evidence?.sourceKind, 'oem_rated_input');
      expect(spec.evidence?.ratedInputWatts, 1350);
      expect(spec.evidence?.sourceUrl, 'https://example.test/manual.pdf');
      expect(spec.evidence?.matchedModel, 'Kettle 1');
    });

    test('parses no match without evidence', () {
      final spec = ApplianceSpec.fromJson({
        'status': 'not_found',
        'evidence': null,
      });
      expect(spec.status, 'not_found');
      expect(spec.evidence, isNull);
    });
  });

  test('parses baseline meter coverage without inferring computer state', () {
    final coverage = DeviceBaselineCoverage.fromJson({
      'device_id': 'meter/office',
      'appliance_id': 42,
      'window_start': '2026-09-22T12:00:00Z',
      'window_end': '2026-09-29T12:00:00Z',
      'latest_sample_at': '2026-09-29T11:59:00Z',
      'sample_count': 10081,
      'covered_secs': 475200,
      'coverage_fraction': 0.785714,
      'covered_days': 5,
      'required_days': 5,
      'status': 'sufficient_meter_coverage',
      'reason': 'coverage_gate_met',
    });

    expect(coverage.deviceId, 'meter/office');
    expect(coverage.applianceId, 42);
    expect(coverage.latestSampleAt, DateTime.utc(2026, 9, 29, 11, 59));
    expect(coverage.coveredSecs, 475200);
    expect(coverage.coverageFraction, closeTo(0.785714, 1e-7));
    expect(coverage.coveredDays, 5);
    expect(coverage.requiredDays, 5);
    expect(coverage.status, 'sufficient_meter_coverage');
    expect(coverage.reason, 'coverage_gate_met');
  });

  test('per-use value requires a ready, policy-bound attachment result', () {
    final ready = AppliancePerUseBaseline.fromJson({
      'appliance_id': 42,
      'plug_id': 'plug-7',
      'attachment_started_at': 1790000000,
      'policy_id': 8,
      'policy_revision': 2,
      'status': 'ready',
      'reason': 'sufficient_sessions',
      'evaluation': {
        'window_start': '2026-09-22T12:00:00Z',
        'window_end': '2026-09-29T12:00:00Z',
        'qualifying_sessions': 7,
        'required_sessions': 5,
        'median_kwh_per_use': 0.19,
      },
    });
    expect(ready.hasQualifiedValue, isTrue);
    expect(ready.medianKwhPerUse, 0.19);

    final unavailable = AppliancePerUseBaseline.fromJson({
      'appliance_id': 43,
      'plug_id': null,
      'attachment_started_at': null,
      'policy_id': null,
      'policy_revision': null,
      'status': 'unavailable',
      'reason': 'policy_missing',
      'evaluation': null,
    });
    expect(unavailable.hasQualifiedValue, isFalse);
    expect(unavailable.medianKwhPerUse, isNull);
  });

  group('hub device energy response', () {
    test('parses measured energy and stale regional-rate metadata', () {
      final energy = DeviceEnergy.fromJson(<String, dynamic>{
        'device_id': 'plug-7',
        'period': 'week',
        'status': 'measured',
        'readings': <Map<String, dynamic>>[
          <String, dynamic>{
            'ts': '2026-09-28T12:00:00Z',
            'watts': 42.0,
            'kwh_cumulative': null,
          },
          <String, dynamic>{
            'ts': '2026-09-28T12:05:00Z',
            'watts': 44.0,
            'kwh_cumulative': 8.2,
          },
        ],
        'latest_watts': 44.0,
        'total_kwh': 0.0036,
        'covered_secs': 300.0,
        'coverage_fraction': 0.000496,
        'observed_cost_usd': 0.0009,
        'rate_usd_per_kwh': 0.25,
        'rate_source_label': 'Texas average (EIA)',
        'rate_source': 'utility',
        'rate_as_of': '2026-07-01',
        'rate_source_url': 'https://example.test/rates/tx',
        'rate_fetched_at': 1780000000,
        'rate_is_stale': true,
        'rate_status': 'stale',
      });

      expect(energy.deviceId, 'plug-7');
      expect(energy.period, 'week');
      expect(energy.status, 'measured');
      expect(energy.readingCount, 2);
      expect(energy.coveredSecs, 300);
      expect(energy.coverageFraction, closeTo(0.000496, 1e-9));
      expect(energy.rateUsdPerKwh, 0.25);
      expect(energy.rateSource, 'utility');
      expect(energy.rateAsOf, '2026-07-01');
      expect(energy.rateSourceUrl, 'https://example.test/rates/tx');
      expect(energy.rateFetchedAt, 1780000000);
      expect(energy.rateIsStale, isTrue);
      expect(energy.rateStatus, 'stale');
    });

    test('parses a no-data response with nullable meter and rate fields', () {
      final energy = DeviceEnergy.fromJson(<String, dynamic>{
        'device_id': 'plug-empty',
        'period': 'day',
        'status': 'no_data',
        'readings': <dynamic>[],
        'latest_watts': null,
        'total_kwh': 0.0,
        'covered_secs': 0.0,
        'coverage_fraction': 0.0,
        'observed_cost_usd': null,
        'rate_usd_per_kwh': null,
        'rate_source_label': null,
        'rate_source': null,
        'rate_as_of': null,
        'rate_source_url': null,
        'rate_fetched_at': null,
        'rate_is_stale': false,
        'rate_status': 'not_requested',
      });

      expect(energy.status, 'no_data');
      expect(energy.deviceId, 'plug-empty');
      expect(energy.readingCount, 0);
      expect(energy.latestWatts, isNull);
      expect(energy.observedCostUsd, isNull);
      expect(energy.rateUsdPerKwh, isNull);
      expect(energy.rateSourceLabel, isNull);
      expect(energy.rateFetchedAt, isNull);
      expect(energy.rateIsStale, isFalse);
      expect(energy.rateStatus, 'not_requested');
    });
  });

  group('hub appliance estimate response', () {
    test('parses estimated energy with stale regional-rate provenance', () {
      final estimate = EnergyEstimate.fromJson(<String, dynamic>{
        'status': 'estimated',
        'reason': null,
        'period': 'month',
        'estimated_kwh': 11.102,
        'estimated_cost_usd': 2.2204,
        'active_kwh': 10.4,
        'standby_kwh': 0.702,
        'active_cost_usd': 2.08,
        'standby_cost_usd': 0.1404,
        'rate_usd_per_kwh': 0.2,
        'rate_source': 'utility',
        'rate_source_label': 'Texas average (EIA)',
        'rate_as_of': '2026-07-01',
        'rate_source_url': 'https://example.test/rates/tx',
        'rate_fetched_at': 1780000000,
        'rate_is_stale': true,
        'rate_status': 'stale',
        'bulb_count': null,
        'evidence': <String, dynamic>{
          'source_kind': 'energy_star',
          'dataset_id': 'energystar-2026',
          'source_url': 'https://example.test/energy-star/model',
          'matched_brand': 'Example',
          'matched_model': 'Washer 10',
          'energy_star_model_identifier': 'ES-12345',
          'annual_kwh': 133.224,
          'standby_watts': null,
          'usage_basis': 'Annual energy rating; annual kWh divided by 12',
          'retrieved_at': 1779900000,
        },
        'measurement_coverage_fraction': null,
      });

      expect(estimate.status, 'estimated');
      expect(estimate.period, 'month');
      expect(estimate.estimatedKwh, closeTo(11.102, 1e-9));
      expect(estimate.rateStatus, 'stale');
      expect(estimate.isStale, isTrue);
      expect(estimate.fetchedAt, 1780000000);
      expect(estimate.measurementCoverageFraction, isNull);
      expect(estimate.evidence?.energyStarModelIdentifier, 'ES-12345');
      expect(estimate.evidence?.standbyWatts, isNull);
    });

    test('parses measured appliance response without estimate breakdown', () {
      final estimate = EnergyEstimate.fromJson(<String, dynamic>{
        'status': 'measured',
        'reason': null,
        'period': 'month',
        'estimated_kwh': 10.0,
        'estimated_cost_usd': 2.0,
        'active_kwh': null,
        'standby_kwh': null,
        'active_cost_usd': null,
        'standby_cost_usd': null,
        'rate_usd_per_kwh': 0.2,
        'rate_source': 'household_entered',
        'rate_source_label': 'Your electricity rate',
        'rate_as_of': null,
        'rate_source_url': null,
        'rate_fetched_at': null,
        'rate_is_stale': false,
        'rate_status': 'available',
        'bulb_count': null,
        'evidence': null,
        'measurement_coverage_fraction': 0.72,
      });

      expect(estimate.status, 'measured');
      expect(estimate.measurementCoverageFraction, 0.72);
      expect(estimate.estimatedKwh, 10);
      expect(estimate.activeKwh, isNull);
      expect(estimate.standbyKwh, isNull);
      expect(estimate.evidence, isNull);
      expect(estimate.rateAsOf, isNull);
      expect(estimate.rateSourceUrl, isNull);
    });

    test('parses no-estimate response with nullable values', () {
      final estimate = EnergyEstimate.fromJson(<String, dynamic>{
        'status': 'no_estimate',
        'reason': 'not_checked',
        'period': 'month',
        'estimated_kwh': null,
        'estimated_cost_usd': null,
        'active_kwh': null,
        'standby_kwh': null,
        'active_cost_usd': null,
        'standby_cost_usd': null,
        'rate_usd_per_kwh': null,
        'rate_source': null,
        'rate_source_label': null,
        'rate_as_of': null,
        'rate_source_url': null,
        'rate_fetched_at': null,
        'rate_is_stale': false,
        'rate_status': 'not_requested',
        'bulb_count': 2,
        'evidence': null,
        'measurement_coverage_fraction': null,
      });

      expect(estimate.status, 'no_estimate');
      expect(estimate.reason, 'not_checked');
      expect(estimate.estimatedKwh, isNull);
      expect(estimate.estimatedCostUsd, isNull);
      expect(estimate.rateUsdPerKwh, isNull);
      expect(estimate.bulbCount, 2);
      expect(estimate.evidence, isNull);
      expect(estimate.measurementCoverageFraction, isNull);
    });
  });
}
