import 'dart:async';

import 'package:energylens_mobile/core/cloud_api/cloud_appliance.dart';
import 'package:energylens_mobile/core/cloud_api/cloud_estimate.dart';
import 'package:energylens_mobile/core/cloud_api/cloud_household_energy.dart';
import 'package:energylens_mobile/core/cloud_api/cloud_recommendations.dart';
import 'package:energylens_mobile/features/design/efficiency_away_domain_adapter.dart';
import 'package:energylens_mobile/features/design/efficiency_domain_repository.dart';
import 'package:flutter_test/flutter_test.dart';

const _homeA = '11111111-1111-4111-8111-111111111111';
const _homeB = '22222222-2222-4222-8222-222222222222';
const _applianceId = '33333333-3333-4333-8333-333333333333';

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
  'content_revision': 'sample_v1',
  'home_id': home,
  'data_mode': 'sample',
  'fixture_revision': 'sample_v1',
  'snapshot_id': 'snapshot-$home',
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
  Future<CloudHouseholdDashboard> dashboard(String homeId) =>
      dashboardRead?.call(homeId) ?? Future.value(_dashboard(homeId));
  @override
  Future<CloudHouseholdEnergyTrends> trends(String homeId) =>
      Future.value(_trends(homeId));
  @override
  Future<List<CloudAppliance>> appliances(String homeId) => Future.value([
    CloudAppliance(
      id: _applianceId,
      homeId: homeId,
      name: 'Heater',
      category: 'heating',
      room: 'Office',
      brand: 'Brand',
      fullModel: 'Model',
      fuel: 'electricity',
      matchQuality: 'unresolved',
    ),
  ]);
  @override
  Future<CloudEstimateBatch> estimates(String homeId) => Future.value(
    CloudEstimateBatch(
      estimates: [
        CloudEstimate(
          id: 'operating-estimate',
          applianceId: _applianceId,
          kind: 'estimated_operating_cost',
          period: const CloudEstimatePeriod(
            start: '2026-10-01',
            end: '2026-11-01',
            timezone: 'America/Chicago',
          ),
          energy: const CloudEstimateQuantity(
            value: '2',
            unit: 'kWh',
            fuel: 'electricity',
          ),
          cost: '0.40',
          currency: 'USD',
          rateKind: 'flat',
          identityQuality: 'unresolved',
          consumptionQuality: 'estimated',
          sourceQuality: 'reviewed',
          contextQuality: 'estimated',
          rateQuality: 'estimated',
          waste: 'not_yet_assessed',
          evidenceRefs: const [],
          formulaVersion: 'v1',
          asOf: DateTime.utc(2026, 10, 6),
          unavailableReason: null,
        ),
      ],
      asOf: DateTime.utc(2026, 10, 6),
    ),
  );
  @override
  Future<CloudRecommendationBatch> recommendations(
    String homeId,
    Set<String> applianceIds,
  ) => Future.value(
    CloudRecommendationBatch(const [], DateTime.utc(2026, 10, 6)),
  );
}

EfficiencyAwayDomainAdapter _adapter(_Source source) =>
    EfficiencyAwayDomainAdapter(EfficiencyDomainRepository(source));

void main() {
  test('discards an in-flight response after switching homes', () async {
    final delayed = Completer<CloudHouseholdDashboard>();
    final adapter = _adapter(
      _Source(
        dashboardRead: (home) =>
            home == _homeA ? delayed.future : Future.value(_dashboard(home)),
      ),
    );

    final oldRead = adapter.fetch(_homeA);
    final currentRead = await adapter.fetch(_homeB);
    expect(currentRead?.homeId, _homeB);

    delayed.complete(_dashboard(_homeA));
    expect(await oldRead, isNull);
  });

  test(
    'operating evidence does not imply occupancy, events, or savings',
    () async {
      final snapshot = await _adapter(_Source()).fetch(_homeA);

      expect(snapshot?.operatingEstimates.single.cost, '0.40');
      expect(snapshot?.occupancyAvailability, AwayEvidenceAvailability.unknown);
      expect(
        snapshot?.awayEventAvailability,
        AwayEvidenceAvailability.unsupported,
      );
      expect(snapshot?.awayEvents, isEmpty);
      expect(
        snapshot?.savingsAvailability,
        AwayEvidenceAvailability.unsupported,
      );
      expect(snapshot?.savingsAmount, isNull);
    },
  );
}
