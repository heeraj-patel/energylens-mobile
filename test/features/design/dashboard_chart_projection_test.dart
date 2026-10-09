import 'package:energylens_mobile/core/cloud_api/cloud_household_energy.dart';
import 'package:energylens_mobile/features/design/dashboard_chart_projection.dart';
import 'package:energylens_mobile/features/design/dashboard_chart_renderer.dart';
import 'package:energylens_mobile/features/design/dashboard_domain_repository.dart';
import 'package:energylens_mobile/features/design/design_page_bridge.dart';
import 'package:flutter_test/flutter_test.dart';

const home = '11111111-1111-4111-8111-111111111111';

Map<String, dynamic> allocation({bool split = true}) => {
  'energy': {'value': '5', 'unit': 'kWh'},
  'cost': {'amount': '1.00', 'currency': 'USD'},
  'useful_energy': split ? {'value': '3.5', 'unit': 'kWh'} : null,
  'useful_cost': split ? {'amount': '0.70', 'currency': 'USD'} : null,
  'waste_energy': split ? {'value': '1', 'unit': 'kWh'} : null,
  'waste_cost': split ? {'amount': '0.20', 'currency': 'USD'} : null,
  'unclassified_energy': {'value': '0.5', 'unit': 'kWh'},
  'unclassified_cost': {'amount': '0.10', 'currency': 'USD'},
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

Map<String, dynamic> trend(
  String granularity,
  String start,
  String end,
  List<Map<String, dynamic>> buckets,
) => {
  ...base(start, end),
  'view': 'energy_trends',
  'granularity': granularity,
  'totals': allocation(),
  'buckets': buckets,
};

Map<String, dynamic> bucket(String start, String end, {bool split = true}) => {
  'start_local': start,
  'end_exclusive_local': end,
  'allocation': allocation(split: split),
  'coverage_fraction': '1',
};

DashboardDomainSnapshot snapshot(
  String granularity,
  List<Map<String, dynamic>> buckets, {
  bool Function()? isCurrent,
  String? generatedAt,
}) {
  const dayStart = '2026-10-06T00:00:00-05:00';
  const dayEnd = '2026-10-07T00:00:00-05:00';
  final dashboard = CloudHouseholdDashboard.fromJson({
    ...base(dayStart, dayEnd),
    'generated_at': generatedAt ?? '2026-10-06T18:00:00Z',
    'view': 'dashboard',
    'totals': allocation(),
    'trend_period': 'day',
    'top_recommendation_id': null,
    'assistant_intent_id': null,
  }, expectedHomeId: home);
  final hourly = CloudHouseholdEnergyTrends.fromJson({
    ...trend('hour', dayStart, dayEnd, []),
    'generated_at': generatedAt ?? '2026-10-06T18:00:00Z',
  }, expectedHomeId: home);
  final period = switch (granularity) {
    'day' => ('2026-10-05T00:00:00-05:00', '2026-10-12T00:00:00-05:00'),
    'week' => ('2026-10-01T00:00:00-05:00', '2026-11-01T00:00:00-05:00'),
    _ => ('2026-01-01T00:00:00-06:00', '2027-01-01T00:00:00-06:00'),
  };
  final selected = CloudHouseholdEnergyTrends.fromJson({
    ...trend(granularity, period.$1, period.$2, buckets),
    'generated_at': generatedAt ?? '2026-10-06T18:00:00Z',
  }, expectedHomeId: home);
  return DashboardDomainSnapshot(
    dashboard,
    hourly,
    periodTrends: {granularity: selected},
    isCurrent: isCurrent ?? () => true,
  );
}

void main() {
  test('mock current day is available at its local midnight', () {
    final chart = DashboardChartProjection.fromSnapshot(
      snapshot('day', [
        bucket('2026-10-06T00:00:00-05:00', '2026-10-07T00:00:00-05:00'),
      ], generatedAt: '2026-10-06T05:00:00Z'),
      'day',
    );
    expect(chart?.bars.single.label, 'Tue');
  });
  test('day chart uses observed split buckets and excludes future days', () {
    final read = snapshot('day', [
      bucket('2026-10-05T00:00:00-05:00', '2026-10-06T00:00:00-05:00'),
      bucket('2026-10-06T00:00:00-05:00', '2026-10-07T00:00:00-05:00'),
      bucket(
        '2026-10-07T00:00:00-05:00',
        '2026-10-08T00:00:00-05:00',
        split: false,
      ),
    ]);
    final chart = DashboardChartProjection.fromSnapshot(read, 'day');
    expect(chart!.bars.map((row) => row.label), ['Mon', 'Tue']);
    expect(chart.bars.last.usefulCents, BigInt.from(70));
    expect(chart.periodTotal, '\$1.00');
    expect(chart.usefulTotal, '\$0.70');
    expect(chart.wasteTotal, '\$0.20');
  });

  test('monthly chart takes the last five observed months', () {
    final buckets = <Map<String, dynamic>>[];
    for (var month = 1; month <= 12; month++) {
      final start = DateTime.utc(2026, month, 1);
      final end = DateTime.utc(2026, month + 1, 1);
      String local(DateTime date) {
        final offset = date.month >= 4 && date.month <= 11
            ? '-05:00'
            : '-06:00';
        return '${date.year}-${date.month.toString().padLeft(2, '0')}-01T00:00:00$offset';
      }

      buckets.add(bucket(local(start), local(end), split: month <= 10));
    }
    final chart = DashboardChartProjection.fromSnapshot(
      snapshot('month', buckets),
      'month',
    );
    expect(chart!.bars.map((row) => row.label), [
      'Jun',
      'Jul',
      'Aug',
      'Sep',
      'Oct',
    ]);
  });

  test('missing split and stale context never produce a live chart', () {
    final rows = [
      bucket(
        '2026-10-05T00:00:00-05:00',
        '2026-10-06T00:00:00-05:00',
        split: false,
      ),
    ];
    expect(
      DashboardChartProjection.fromSnapshot(snapshot('day', rows), 'day'),
      isNull,
    );
    expect(
      DashboardChartProjection.fromSnapshot(
        snapshot('day', rows, isCurrent: () => false),
        'day',
      ),
      isNull,
    );
  });

  test('chart script requires the current Dashboard home ticket', () {
    final chart = DashboardChartProjection.fromSnapshot(
      snapshot('day', [
        bucket('2026-10-05T00:00:00-05:00', '2026-10-06T00:00:00-05:00'),
      ]),
      'day',
    )!;
    final gate = DesignPageRequestGate();
    final renderer = DashboardChartRenderer(gate);
    final ticket = gate.select(home, 'dashboard');
    expect(renderer.script(ticket, chart), contains('dashboard-trends'));
    gate.select(home, 'devices');
    expect(renderer.script(ticket, chart), isNull);
  });
}
