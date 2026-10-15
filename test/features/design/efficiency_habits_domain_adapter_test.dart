import 'dart:async';

import 'package:energylens_mobile/core/cloud_api/cloud_appliance.dart';
import 'package:energylens_mobile/core/cloud_api/cloud_estimate.dart';
import 'package:energylens_mobile/core/cloud_api/cloud_household_energy.dart';
import 'package:energylens_mobile/core/cloud_api/cloud_recommendations.dart';
import 'package:energylens_mobile/features/design/efficiency_domain_repository.dart';
import 'package:energylens_mobile/features/design/efficiency_habits_domain_adapter.dart';
import 'package:flutter_test/flutter_test.dart';

const homeA = '11111111-1111-4111-8111-111111111111';
const homeB = '22222222-2222-4222-8222-222222222222';
const applianceId = '33333333-3333-4333-8333-333333333333';

Map<String, dynamic> _allocation() => {
  'energy': {'value': '24', 'unit': 'kWh'},
  'cost': {'amount': '4.80', 'currency': 'USD'},
  'useful_energy': null,
  'useful_cost': null,
  'waste_energy': null,
  'waste_cost': null,
  'unclassified_energy': {'value': '24', 'unit': 'kWh'},
  'unclassified_cost': {'amount': '4.80', 'currency': 'USD'},
  'availability': 'partial',
  'evidence_basis': 'synthetic',
};

Map<String, dynamic> _body(String view, String home) => {
  'schema_revision': 'household_energy_v1',
  'content_revision': 'synthetic_household_v1',
  'home_id': home,
  'data_mode': 'sample',
  'fixture_revision': 'synthetic_household_v1',
  'snapshot_id': 'sample-snapshot',
  'generated_at': '2026-10-06T18:00:00Z',
  'as_of': null,
  'timezone': 'America/Chicago',
  'period': {
    'start_local': '2026-10-06T00:00:00-05:00',
    'end_exclusive_local': '2026-10-07T00:00:00-05:00',
  },
  'scope': 'attributed_devices',
  'availability': 'partial',
  'evidence_basis': 'synthetic',
  'view': view,
  'totals': _allocation(),
  if (view == 'dashboard') ...{
    'trend_period': 'day',
    'top_recommendation_id': null,
    'assistant_intent_id': null,
  } else ...{
    'granularity': 'hour',
    'buckets': <Object>[],
  },
};

CloudHouseholdDashboard _dashboard(String home) =>
    CloudHouseholdDashboard.fromJson(
      _body('dashboard', home),
      expectedHomeId: home,
    );
CloudHouseholdEnergyTrends _trends(String home) =>
    CloudHouseholdEnergyTrends.fromJson(
      _body('energy_trends', home),
      expectedHomeId: home,
    );

class _Source implements EfficiencyDomainSource {
  _Source({this.dashboardRead});
  final Future<CloudHouseholdDashboard> Function(String)? dashboardRead;

  @override
  Future<CloudHouseholdDashboard> dashboard(String home) =>
      dashboardRead?.call(home) ?? Future.value(_dashboard(home));
  @override
  Future<CloudHouseholdEnergyTrends> trends(String home) =>
      Future.value(_trends(home));
  @override
  Future<List<CloudAppliance>> appliances(String home) => Future.value([
    CloudAppliance(
      id: applianceId,
      homeId: home,
      name: 'Device',
      category: 'television',
      room: null,
      brand: 'Brand',
      fullModel: 'Model',
      fuel: 'electricity',
      matchQuality: 'unresolved',
    ),
  ]);
  @override
  Future<CloudEstimateBatch> estimates(String home) => Future.value(
    CloudEstimateBatch(estimates: const [], asOf: DateTime.utc(2026, 10, 6)),
  );
  @override
  Future<CloudRecommendationBatch> recommendations(
    String home,
    Set<String> ids,
  ) => Future.value(
    CloudRecommendationBatch([
      const CloudRecommendation(
        ruleId: 'computer.sleep_settings',
        applianceId: applianceId,
        state: 'candidate',
        title: 'Reviewed action',
        explanation: 'Evidence-backed action',
        nextQuestion: 'schedule',
        evidenceCount: 1,
        scenarioRefs: [],
      ),
    ], DateTime.utc(2026, 10, 6)),
  );
}

void main() {
  test(
    'projects observed totals and reviewed actions; leaves habits unknown',
    () async {
      final adapter = EfficiencyHabitsDomainAdapter(
        EfficiencyDomainRepository(_Source()),
      );
      final snapshot = await adapter.fetch(homeA);
      expect(snapshot?.homeId, homeA);
      expect(snapshot?.totals.cost?.amount, '4.80');
      expect(snapshot?.recommendations.single.state, 'candidate');
      expect(snapshot?.routineClassification, isNull);
      expect(snapshot?.routineSavingsAmount, isNull);
    },
  );

  test('drops an in-flight response after switching homes', () async {
    final pending = Completer<CloudHouseholdDashboard>();
    final adapter = EfficiencyHabitsDomainAdapter(
      EfficiencyDomainRepository(
        _Source(
          dashboardRead: (home) =>
              home == homeA ? pending.future : Future.value(_dashboard(home)),
        ),
      ),
    );
    final old = adapter.fetch(homeA);
    expect((await adapter.fetch(homeB))?.homeId, homeB);
    pending.complete(_dashboard(homeA));
    expect(await old, isNull);
  });

  test('clearing the adapter invalidates pending responses', () async {
    final pending = Completer<CloudHouseholdDashboard>();
    final adapter = EfficiencyHabitsDomainAdapter(
      EfficiencyDomainRepository(_Source(dashboardRead: (_) => pending.future)),
    );
    final result = adapter.fetch(homeA);
    await Future<void>.delayed(Duration.zero);
    adapter.clear();
    pending.complete(_dashboard(homeA));
    expect(await result, isNull);
  });
}
