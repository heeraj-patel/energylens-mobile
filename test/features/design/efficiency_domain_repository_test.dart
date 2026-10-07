import 'dart:async';

import 'package:energylens_mobile/core/cloud_api/cloud_appliance.dart';
import 'package:energylens_mobile/core/cloud_api/cloud_estimate.dart';
import 'package:energylens_mobile/core/cloud_api/cloud_household_energy.dart';
import 'package:energylens_mobile/core/cloud_api/cloud_recommendations.dart';
import 'package:energylens_mobile/features/design/efficiency_domain_repository.dart';
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
CloudHouseholdEnergyTrends _trends(String home, {String? scope}) {
  final body = _body('energy_trends', home);
  if (scope != null) body['scope'] = scope;
  return CloudHouseholdEnergyTrends.fromJson(body, expectedHomeId: home);
}

CloudAppliance _appliance(String home) => CloudAppliance(
  id: applianceId,
  homeId: home,
  name: 'Device',
  category: 'television',
  room: null,
  brand: 'Brand',
  fullModel: 'Model',
  fuel: 'electricity',
  matchQuality: 'unresolved',
);

CloudEstimate _estimate({String id = applianceId, String end = '2026-11-01'}) =>
    CloudEstimate(
      id: 'estimate',
      applianceId: id,
      kind: 'estimated_operating_cost',
      period: CloudEstimatePeriod(
        start: '2026-10-01',
        end: end,
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
      identityQuality: 'exact',
      consumptionQuality: 'estimated',
      sourceQuality: 'reviewed',
      contextQuality: 'estimated',
      rateQuality: 'estimated',
      waste: 'not_yet_assessed',
      evidenceRefs: const [],
      formulaVersion: 'v1',
      asOf: DateTime.utc(2026, 10, 6),
      unavailableReason: null,
    );

class _Source implements EfficiencyDomainSource {
  _Source({
    this.dashboardRead,
    this.trendsRead,
    this.inventoryRead,
    this.estimatesRead,
    this.recommendationsRead,
  });
  final Future<CloudHouseholdDashboard> Function(String)? dashboardRead;
  final Future<CloudHouseholdEnergyTrends> Function(String)? trendsRead;
  final Future<List<CloudAppliance>> Function(String)? inventoryRead;
  final Future<CloudEstimateBatch> Function(String)? estimatesRead;
  final Future<CloudRecommendationBatch> Function(String)? recommendationsRead;
  int calls = 0;

  @override
  Future<CloudHouseholdDashboard> dashboard(String home) {
    calls++;
    return dashboardRead?.call(home) ?? Future.value(_dashboard(home));
  }

  @override
  Future<CloudHouseholdEnergyTrends> trends(String home) {
    calls++;
    return trendsRead?.call(home) ?? Future.value(_trends(home));
  }

  @override
  Future<List<CloudAppliance>> appliances(String home) {
    calls++;
    return inventoryRead?.call(home) ?? Future.value([_appliance(home)]);
  }

  @override
  Future<CloudEstimateBatch> estimates(String home) {
    calls++;
    return estimatesRead?.call(home) ??
        Future.value(
          CloudEstimateBatch(
            estimates: [_estimate()],
            asOf: DateTime.utc(2026, 10, 6),
          ),
        );
  }

  @override
  Future<CloudRecommendationBatch> recommendations(
    String home,
    Set<String> ids,
  ) {
    calls++;
    return recommendationsRead?.call(home) ??
        Future.value(
          CloudRecommendationBatch(const [], DateTime.utc(2026, 10, 6)),
        );
  }
}

void main() {
  test(
    'all four pages retain aggregate evidence and unknown categories',
    () async {
      for (final page in EfficiencyPage.values) {
        final snapshot = await EfficiencyDomainRepository(_Source())
            .fetch(homeA, page);
        expect(snapshot?.page, page);
        expect(snapshot?.homeId, homeA);
        expect(snapshot?.totals.cost?.amount, '4.80');
        expect(snapshot?.totals.wasteCost, isNull);
        expect(snapshot?.operatingEstimates.single.cost, '0.40');
        expect(snapshot?.opportunityAmount, isNull);
        expect(snapshot?.awaySavingsAmount, isNull);
        expect(snapshot?.peakSavingsAmount, isNull);
        expect(snapshot?.habitsSavingsAmount, isNull);
        expect(snapshot?.awayOccupancyEvidence, isNull);
        expect(snapshot?.timeOfUseRate, isNull);
      }
    },
  );

  test('rejects inconsistent household scope before appliance reads', () async {
    final source = _Source(
      trendsRead: (home) async =>
          _trends(home, scope: 'whole_home_including_unattributed_load'),
    );
    await expectLater(
      EfficiencyDomainRepository(source).fetch(homeA, EfficiencyPage.overview),
      throwsFormatException,
    );
    expect(source.calls, 2);
  });

  test('rejects cross-home inventory and estimate identity', () async {
    final wrongInventory = _Source(
      inventoryRead: (_) async => [_appliance(homeB)],
    );
    await expectLater(
      EfficiencyDomainRepository(wrongInventory)
          .fetch(homeA, EfficiencyPage.away),
      throwsFormatException,
    );
    final wrongEstimate = _Source(
      estimatesRead: (_) async => CloudEstimateBatch(
        estimates: [_estimate(id: homeB)],
        asOf: DateTime.utc(2026, 10, 6),
      ),
    );
    await expectLater(
      EfficiencyDomainRepository(wrongEstimate)
          .fetch(homeA, EfficiencyPage.habits),
      throwsFormatException,
    );
    final wrongRecommendation = _Source(
      recommendationsRead: (_) async => CloudRecommendationBatch(const [
        CloudRecommendation(
          ruleId: 'television.quick_start',
          applianceId: homeB,
          state: 'candidate',
          title: 'Recommendation',
          explanation: 'Evidence',
          nextQuestion: 'hours_per_week',
          evidenceCount: 0,
        ),
      ], DateTime.utc(2026, 10, 6)),
    );
    await expectLater(
      EfficiencyDomainRepository(wrongRecommendation)
          .fetch(homeA, EfficiencyPage.overview),
      throwsFormatException,
    );
  });

  test('rejects invalid independent estimate period', () async {
    final source = _Source(
      estimatesRead: (_) async => CloudEstimateBatch(
        estimates: [_estimate(end: '2026-09-01')],
        asOf: DateTime.utc(2026, 10, 6),
      ),
    );
    await expectLater(
      EfficiencyDomainRepository(source).fetch(homeA, EfficiencyPage.peak),
      throwsFormatException,
    );
  });

  test('home switch and sign-out discard in-flight responses', () async {
    final pendingDashboard = Completer<CloudHouseholdDashboard>();
    final source = _Source(
      dashboardRead: (home) => home == homeA
          ? pendingDashboard.future
          : Future.value(_dashboard(home)),
    );
    final repository = EfficiencyDomainRepository(source);
    final old = repository.fetch(homeA, EfficiencyPage.overview);
    final current = await repository.fetch(homeB, EfficiencyPage.peak);
    expect(current?.homeId, homeB);
    pendingDashboard.complete(_dashboard(homeA));
    expect(await old, isNull);

    final pendingEstimates = Completer<CloudEstimateBatch>();
    final signOutRepository = EfficiencyDomainRepository(
      _Source(estimatesRead: (_) => pendingEstimates.future),
    );
    final signedOut = signOutRepository.fetch(homeA, EfficiencyPage.habits);
    await Future<void>.delayed(Duration.zero);
    signOutRepository.clear();
    pendingEstimates.complete(
      CloudEstimateBatch(
        estimates: [_estimate()],
        asOf: DateTime.utc(2026, 10, 6),
      ),
    );
    expect(await signedOut, isNull);
  });

  test('invalid home IDs do not dispatch reads', () async {
    final source = _Source();
    await expectLater(
      EfficiencyDomainRepository(source).fetch('bad', EfficiencyPage.overview),
      throwsArgumentError,
    );
    expect(source.calls, 0);
  });
}
