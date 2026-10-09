import 'package:energylens_mobile/core/cloud_api/cloud_household_energy.dart';
import 'package:energylens_mobile/features/design/dashboard_domain_repository.dart';
import 'package:energylens_mobile/features/design/efficiency_domain_repository.dart';
import 'package:energylens_mobile/features/design/efficiency_rolling_bindings.dart';
import 'package:flutter_test/flutter_test.dart';

const home = '11111111-1111-4111-8111-111111111111';

Map<String, dynamic> allocation(String cost) => {
  'energy': {'value': '1', 'unit': 'kWh'},
  'cost': {'amount': cost, 'currency': 'USD'},
  'useful_energy': {'value': '0.5', 'unit': 'kWh'},
  'useful_cost': {'amount': '0.10', 'currency': 'USD'},
  'waste_energy': {'value': '0.25', 'unit': 'kWh'},
  'waste_cost': {'amount': '0.05', 'currency': 'USD'},
  'unclassified_energy': {'value': '0.25', 'unit': 'kWh'},
  'unclassified_cost': {'amount': '0.05', 'currency': 'USD'},
  'availability': 'partial',
  'evidence_basis': 'synthetic',
};

Map<String, dynamic> base(String start, String end) => {
  'schema_revision': 'household_energy_v1',
  'content_revision': 'synthetic_household_energy_v2',
  'home_id': home,
  'data_mode': 'sample',
  'fixture_revision': 'synthetic_household_v1',
  'snapshot_id': 'snapshot',
  'generated_at': '2026-10-06T18:00:00Z',
  'as_of': null,
  'timezone': 'America/Chicago',
  'period': {'start_local': start, 'end_exclusive_local': end},
  'scope': 'attributed_devices',
  'availability': 'partial',
  'evidence_basis': 'synthetic',
};

EfficiencyDomainSnapshot read({
  bool missingDay = false,
  bool wrongTotal = false,
}) {
  const dayStart = '2026-10-06T00:00:00-05:00';
  const dayEnd = '2026-10-07T00:00:00-05:00';
  final dashboard = CloudHouseholdDashboard.fromJson({
    ...base(dayStart, dayEnd),
    'view': 'dashboard',
    'totals': allocation('0.20'),
    'trend_period': 'day',
    'top_recommendation_id': null,
    'assistant_intent_id': null,
  }, expectedHomeId: home);
  final hourly = CloudHouseholdEnergyTrends.fromJson({
    ...base(dayStart, dayEnd),
    'view': 'energy_trends',
    'granularity': 'hour',
    'totals': allocation('0.20'),
    'buckets': [],
  }, expectedHomeId: home);
  final first = DateTime.utc(2026, 9, 7);
  String local(DateTime value) =>
      '${value.year}-${value.month.toString().padLeft(2, '0')}-${value.day.toString().padLeft(2, '0')}T00:00:00-05:00';
  final buckets = [
    for (var index = 0; index < 30; index++)
      if (!(missingDay && index == 15))
        {
          'start_local': local(first.add(Duration(days: index))),
          'end_exclusive_local': local(first.add(Duration(days: index + 1))),
          'allocation': allocation('0.20'),
          'coverage_fraction': null,
        },
  ];
  final rolling = CloudHouseholdEnergyTrends.fromJson({
    ...base('2026-09-07T00:00:00-05:00', dayEnd),
    'view': 'energy_trends',
    'granularity': 'day',
    'totals': allocation(wrongTotal ? '5.99' : '6.00'),
    'buckets': buckets,
  }, expectedHomeId: home);
  return EfficiencyDomainSnapshot(
    page: EfficiencyPage.overview,
    energy: DashboardDomainSnapshot(dashboard, hourly, isCurrent: () => true),
    operatingEstimates: const [],
    recommendations: const [],
    rolling30Days: rolling,
  );
}

void main() {
  test(
    'approved spend pair binds only a complete reconciled 30-day window',
    () {
      final bindings = prepareEfficiencyRollingBindings(read());
      expect(bindings!.map((row) => row.id), [
        'efficiency_text_008',
        'efficiency_text_009',
      ]);
      expect(bindings.map((row) => row.text), ['Last 30 days', '\$6.00']);
    },
  );

  test('missing day and inconsistent total keep packaged period intact', () {
    expect(prepareEfficiencyRollingBindings(read(missingDay: true)), isNull);
    expect(prepareEfficiencyRollingBindings(read(wrongTotal: true)), isNull);
  });
}
