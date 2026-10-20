import 'package:energylens_mobile/core/cloud_api/cloud_household_energy.dart';
import 'package:energylens_mobile/features/design/dashboard_domain_repository.dart';
import 'package:energylens_mobile/features/design/design_page_bridge.dart';
import 'package:energylens_mobile/features/design/efficiency_domain_repository.dart';
import 'package:energylens_mobile/features/design/efficiency_trailing_30_day_bindings.dart';
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
  bool wrongPeriod = false,
  bool unavailableTotal = false,
  bool withSummary = false,
  bool withLegacyOnly = false,
  bool mismatchedSummaryCost = false,
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
  final trailing30Days = CloudHouseholdEnergyTrends.fromJson({
    ...base(
      wrongPeriod ? '2026-09-01T00:00:00-05:00' : '2026-09-07T00:00:00-05:00',
      dayEnd,
    ),
    'view': 'energy_trends',
    'granularity': 'day',
    'totals': allocation('6.00')
      ..['availability'] = unavailableTotal ? 'unavailable' : 'partial',
    if (withSummary)
      'efficiency_trailing_30_days': {
        'period_cost': {
          'amount': mismatchedSummaryCost ? '5.000000' : '6.000000',
          'currency': 'USD',
        },
        'identified_opportunity': {'amount': '16.300000', 'currency': 'USD'},
        'optimal_base': {'amount': '5.000000', 'currency': 'USD'},
        'waste_opportunity': {'amount': '1.000000', 'currency': 'USD'},
        'away_opportunity': {'amount': '4.200000', 'currency': 'USD'},
        'peak_rates_opportunity': {'amount': '4.700000', 'currency': 'USD'},
        'habits_opportunity': {'amount': '6.400000', 'currency': 'USD'},
        'night_total_opportunity': {'amount': '0.750000', 'currency': 'USD'},
        'away_total_opportunity': {'amount': '4.450000', 'currency': 'USD'},
        'chart_segment_width_percent': {
          'night': '4.60',
          'away': '27.30',
          'peak_rates': '28.84',
          'habits': '39.26',
        },
        'waste_timing_basis': 'unknown_75_25_demo_fallback',
        'evidence_basis': 'synthetic',
      },
    if (withLegacyOnly)
      'efficiency_month_to_date': {
        'month_to_date_cost': {'amount': '1.000000', 'currency': 'USD'},
        'identified_opportunity': {'amount': '1.000000', 'currency': 'USD'},
        'optimal_base': {'amount': '1.000000', 'currency': 'USD'},
        'waste_opportunity': {'amount': '1.000000', 'currency': 'USD'},
        'away_opportunity': {'amount': '1.000000', 'currency': 'USD'},
        'peak_rates_opportunity': {'amount': '1.000000', 'currency': 'USD'},
        'habits_opportunity': {'amount': '1.000000', 'currency': 'USD'},
        'night_total_opportunity': {'amount': '1.000000', 'currency': 'USD'},
        'away_total_opportunity': {'amount': '1.000000', 'currency': 'USD'},
        'chart_segment_width_percent': {
          'night': '25.00',
          'away': '25.00',
          'peak_rates': '25.00',
          'habits': '25.00',
        },
        'waste_timing_basis': 'unknown_75_25_demo_fallback',
        'evidence_basis': 'synthetic',
      },
    'buckets': [],
  }, expectedHomeId: home);
  return EfficiencyDomainSnapshot(
    page: EfficiencyPage.overview,
    energy: DashboardDomainSnapshot(dashboard, hourly, isCurrent: () => true),
    operatingEstimates: const [],
    recommendations: const [],
    trailing30Days: trailing30Days,
  );
}

void main() {
  test('keeps the full packaged fallback when rolling summary is absent', () {
    expect(prepareEfficiencyTrailing30DaysBindings(read()), isNull);
  });

  test('never substitutes legacy month-to-date summary for rolling values', () {
    final bindings = prepareEfficiencyTrailing30DaysBindings(
      read(withLegacyOnly: true),
    );
    expect(bindings, isNull);
  });

  test('binds top and breakdown values from typed API summary', () {
    final bindings = prepareEfficiencyTrailing30DaysBindings(
      read(withSummary: true),
    );
    expect(bindings!.map((row) => row.id), [
      'efficiency_text_006',
      'efficiency_text_009',
      'efficiency_text_011',
      'efficiency_text_015',
      'efficiency_text_017',
      'efficiency_text_019',
      'efficiency_text_021',
    ]);
    expect(bindings.map((row) => row.text), [
      '\$16.30',
      '\$6.00',
      '\$5.00',
      '\$0.75',
      '\$4.45',
      '\$4.70',
      '\$6.40',
    ]);
  });

  test(
    'uses API chart widths and final row amounts in current page script',
    () {
      final summary = read(withSummary: true)
          .trailing30Days!
          .efficiencyTrailing30Days!;
      const ticket = DesignPageTicket(home, 'efficiency_away', 3);
      final script = buildEfficiencyTrailing30DaysChartScript(ticket, summary);
      expect(script, contains('"widths":["4.60","27.30","28.84","39.26"]'));
      expect(
        script,
        contains('"amounts":["\$0.75","\$4.45","\$4.70","\$6.40"]'),
      );
      expect(script, contains('context.generation !== payload.generation'));
    },
  );

  test('keeps packaged value when period or total is unavailable', () {
    expect(
      prepareEfficiencyTrailing30DaysBindings(read(wrongPeriod: true)),
      isNull,
    );
    expect(
      prepareEfficiencyTrailing30DaysBindings(read(unavailableTotal: true)),
      isNull,
    );
    expect(
      prepareEfficiencyTrailing30DaysBindings(
        read(withSummary: true, mismatchedSummaryCost: true),
      ),
      isNull,
    );
  });
}
