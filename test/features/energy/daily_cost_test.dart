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

void main() {
  group('sourceDailyCostUsd', () {
    test('converts day, week, month, and unspecified periods', () {
      expect(sourceDailyCostUsd(estimate(period: 'day')), 30);
      expect(sourceDailyCostUsd(estimate(period: 'week')), closeTo(30 / 7, 1e-10));
      expect(sourceDailyCostUsd(estimate(period: 'month')), 1);
      // An empty period is the API's unspecified value and uses its 30-day default.
      expect(sourceDailyCostUsd(estimate(period: '')), 1);
      // The model default also represents an unspecified API period.
      expect(sourceDailyCostUsd(const EnergyEstimate(
        status: 'estimated', estimatedCostUsd: 30, evidence: EnergyEvidence(
          sourceKind: 'energy_star', datasetId: 'dataset', sourceUrl: 'https://example.com',
          matchedBrand: 'Example', matchedModel: 'Model', annualKwh: 120,
          usageBasis: 'standard', retrievedAt: 1,
        ),
      )), 1);
    });

    test('returns null for invalid or unsupported data', () {
      expect(sourceDailyCostUsd(null), isNull);
      expect(sourceDailyCostUsd(estimate(cost: null)), isNull);
      expect(sourceDailyCostUsd(estimate(cost: double.nan)), isNull);
      expect(sourceDailyCostUsd(estimate(cost: double.infinity)), isNull);
      expect(sourceDailyCostUsd(estimate(cost: -0.01)), isNull);
      expect(sourceDailyCostUsd(estimate(period: 'year')), isNull);
      expect(sourceDailyCostUsd(const EnergyEstimate(status: 'estimated')), isNull);
    });

    test('excludes metered estimates', () {
      expect(sourceDailyCostUsd(estimate(status: 'measured')), isNull);
    });
  });
}
