import 'package:flutter_test/flutter_test.dart';
import 'package:energylens_mobile/features/discovery/discovery_api.dart';
import 'package:energylens_mobile/features/energy/daily_cost.dart';

EnergyEvidence evidence() => const EnergyEvidence(
  sourceKind: 'energy_star',
  datasetId: 'dataset',
  sourceUrl: 'https://example.com',
  matchedBrand: 'Example',
  matchedModel: 'Model',
  annualKwh: 120,
  usageBasis: 'standard',
  retrievedAt: 1,
);

EnergyEstimate estimate({
  String status = 'estimated',
  String period = 'month',
  double? cost = 30,
  EnergyEvidence? sourceEvidence,
}) => EnergyEstimate(
  status: status,
  period: period,
  estimatedCostUsd: cost,
  evidence: sourceEvidence ?? evidence(),
);

DeviceEnergy meterReading({
  String period = 'today',
  double coverage = 0.8,
  double? latestWatts = 100,
  DateTime? latestAt,
  double? cost = 0.25,
}) => DeviceEnergy(
  status: 'measured',
  period: period,
  totalKwh: 0.1,
  coverageFraction: coverage,
  coveredSecs: 20_000,
  latestWatts: latestWatts,
  observedCostUsd: cost,
  readings: latestAt == null
      ? const []
      : [EnergyReading(ts: latestAt, watts: 100)],
);

void main() {
  group('sourceDailyCostUsd', () {
    test('converts day, week, month, and unspecified periods', () {
      expect(sourceDailyCostUsd(estimate(period: 'day')), 30);
      expect(
        sourceDailyCostUsd(estimate(period: 'week')),
        closeTo(30 / 7, 1e-10),
      );
      expect(sourceDailyCostUsd(estimate(period: 'month')), 1);
      // An empty period is the API's unspecified value and uses its 30-day default.
      expect(sourceDailyCostUsd(estimate(period: '')), 1);
      // The model default also represents an unspecified API period.
      expect(
        sourceDailyCostUsd(
          const EnergyEstimate(
            status: 'estimated',
            estimatedCostUsd: 30,
            evidence: EnergyEvidence(
              sourceKind: 'energy_star',
              datasetId: 'dataset',
              sourceUrl: 'https://example.com',
              matchedBrand: 'Example',
              matchedModel: 'Model',
              annualKwh: 120,
              usageBasis: 'standard',
              retrievedAt: 1,
            ),
          ),
        ),
        1,
      );
    });

    test('returns null for invalid or unsupported data', () {
      expect(sourceDailyCostUsd(null), isNull);
      expect(sourceDailyCostUsd(estimate(cost: null)), isNull);
      expect(sourceDailyCostUsd(estimate(cost: double.nan)), isNull);
      expect(sourceDailyCostUsd(estimate(cost: double.infinity)), isNull);
      expect(sourceDailyCostUsd(estimate(cost: -0.01)), isNull);
      expect(sourceDailyCostUsd(estimate(period: 'year')), isNull);
      expect(
        sourceDailyCostUsd(const EnergyEstimate(status: 'estimated')),
        isNull,
      );
    });

    test('excludes metered estimates', () {
      expect(sourceDailyCostUsd(estimate(status: 'measured')), isNull);
    });
  });

  group('freshMeteredTodayCostUsd', () {
    final now = DateTime.utc(2026, 10, 5, 12);

    test('uses a fresh reading with at least 80% coverage', () {
      expect(
        freshMeteredTodayCostUsd(
          meterReading(latestAt: now.subtract(const Duration(seconds: 150))),
          now: now,
        ),
        0.25,
      );
    });

    test('rejects insufficient coverage, stale or missing readings', () {
      expect(
        freshMeteredTodayCostUsd(
          meterReading(coverage: 0.799, latestAt: now),
          now: now,
        ),
        isNull,
      );
      expect(
        freshMeteredTodayCostUsd(
          meterReading(latestAt: now.subtract(const Duration(seconds: 151))),
          now: now,
        ),
        isNull,
      );
      expect(freshMeteredTodayCostUsd(meterReading(), now: now), isNull);
      expect(
        freshMeteredTodayCostUsd(
          meterReading(latestAt: now.add(const Duration(seconds: 1))),
          now: now,
        ),
        isNull,
      );
      expect(
        freshMeteredTodayCostUsd(
          meterReading(latestAt: now, latestWatts: null),
          now: now,
        ),
        isNull,
      );
      expect(
        freshMeteredTodayCostUsd(
          meterReading(period: 'day', latestAt: now),
          now: now,
        ),
        isNull,
      );
    });
  });
}
