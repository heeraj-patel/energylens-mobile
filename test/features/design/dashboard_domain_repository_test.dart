import 'dart:async';
import 'dart:convert';

import 'package:energylens_mobile/core/cloud_api/cloud_household_energy.dart';
import 'package:energylens_mobile/features/design/dashboard_domain_repository.dart';
import 'package:flutter_test/flutter_test.dart';

const homeA = '11111111-1111-4111-8111-111111111111';
const homeB = '22222222-2222-4222-8222-222222222222';

Map<String, dynamic> _allocation({bool sample = false}) => {
  'energy': sample ? {'value': '24', 'unit': 'kWh'} : null,
  'cost': sample ? {'amount': '4.80', 'currency': 'USD'} : null,
  'useful_energy': null,
  'useful_cost': null,
  'waste_energy': null,
  'waste_cost': null,
  'unclassified_energy': sample ? {'value': '24', 'unit': 'kWh'} : null,
  'unclassified_cost': sample ? {'amount': '4.80', 'currency': 'USD'} : null,
  'availability': sample ? 'partial' : 'unavailable',
  'evidence_basis': sample ? 'synthetic' : 'unavailable',
};

Map<String, dynamic> _body(
  String view, {
  String home = homeA,
  bool sample = false,
}) => {
  'schema_revision': 'household_energy_v1',
  'content_revision': sample
      ? 'synthetic_household_v1'
      : 'household_energy_backend_v1',
  'home_id': home,
  'data_mode': sample ? 'sample' : 'household',
  if (sample) 'fixture_revision': 'synthetic_household_v1',
  'snapshot_id': sample ? 'sample-snapshot' : 'household-snapshot',
  'generated_at': '2026-10-06T18:00:00Z',
  'as_of': null,
  'timezone': 'America/Chicago',
  'period': {
    'start_local': '2026-10-06T00:00:00-05:00',
    'end_exclusive_local': '2026-10-07T00:00:00-05:00',
  },
  'scope': 'attributed_devices',
  'availability': sample ? 'partial' : 'unavailable',
  'evidence_basis': sample ? 'synthetic' : 'unavailable',
  'view': view,
  'totals': _allocation(sample: sample),
  if (view == 'dashboard') ...{
    'trend_period': 'day',
    'top_recommendation_id': null,
    'assistant_intent_id': null,
  } else ...{
    'granularity': 'hour',
    'buckets': <Object>[],
  },
};

CloudHouseholdDashboard _dashboard(Map<String, dynamic> json) =>
    CloudHouseholdDashboard.fromJson(
      json,
      expectedHomeId: json['home_id'] as String,
    );
CloudHouseholdEnergyTrends _trends(Map<String, dynamic> json) =>
    CloudHouseholdEnergyTrends.fromJson(
      json,
      expectedHomeId: json['home_id'] as String,
    );

class _Reads implements DashboardDomainSource {
  _Reads(this.dash, this.series);
  final Future<CloudHouseholdDashboard> Function(String) dash;
  final Future<CloudHouseholdEnergyTrends> Function(String) series;
  final calls = <String>[];

  @override
  Future<CloudHouseholdDashboard> dashboard(String homeId) {
    calls.add('dashboard:$homeId');
    return dash(homeId);
  }

  @override
  Future<CloudHouseholdEnergyTrends> trends(String homeId) {
    calls.add('trends:$homeId');
    return series(homeId);
  }
}

_Reads _fixed({bool sample = false}) => _Reads(
  (home) async => _dashboard(_body('dashboard', home: home, sample: sample)),
  (home) async => _trends(_body('energy_trends', home: home, sample: sample)),
);

void main() {
  test(
    'composes matching household reads and preserves unknown values',
    () async {
      final source = _fixed();
      final snapshot = await DashboardDomainRepository(source).fetch(homeA);
      expect(snapshot?.homeId, homeA);
      expect(snapshot?.dataMode, 'household');
      expect(snapshot?.totals.cost, isNull);
      expect(snapshot?.totals.wasteEnergy, isNull);
      expect(source.calls, ['dashboard:$homeA', 'trends:$homeA']);
    },
  );

  test('sample mode uses the same adapter with explicit provenance', () async {
    final snapshot = await DashboardDomainRepository(_fixed(sample: true))
        .fetch(homeA);
    expect(snapshot?.dataMode, 'sample');
    expect(snapshot?.dashboard.fixtureRevision, 'synthetic_household_v1');
    expect(snapshot?.totals.cost?.amount, '4.80');
    expect(snapshot?.totals.evidenceBasis, 'synthetic');
  });

  test(
    'keeps measured energy and unclassified cost aligned across one bucket',
    () async {
      final dashboardJson = _body('dashboard');
      final trendsJson = _body('energy_trends');
      final allocation = {
        'energy': {'value': '13.570000000000000001', 'unit': 'kWh'},
        'cost': null,
        'useful_energy': null,
        'useful_cost': null,
        'waste_energy': null,
        'waste_cost': null,
        'unclassified_energy': {
          'value': '13.570000000000000001',
          'unit': 'kWh',
        },
        'unclassified_cost': {
          'amount': '3.000000000000000001',
          'currency': 'USD',
        },
        'availability': 'partial',
      'evidence_basis': 'mixed',
      };
      dashboardJson['totals'] = allocation;
      trendsJson['totals'] = allocation;
      trendsJson['buckets'] = [
        {
          'start_local': '2026-10-06T00:00:00-05:00',
          'end_exclusive_local': '2026-10-06T01:00:00-05:00',
          'allocation': allocation,
          'coverage_fraction': '1',
        },
      ];
      final source = _Reads(
        (_) async => _dashboard(dashboardJson),
        (_) async => _trends(trendsJson),
      );

      final snapshot = await DashboardDomainRepository(source).fetch(homeA);

      expect(snapshot!.snapshotId, 'household-snapshot');
      expect(snapshot.dashboard.snapshotId, snapshot.trends.snapshotId);
      expect(snapshot.totals.energy!.value, '13.570000000000000001');
      expect(
        snapshot.trends.buckets.single.allocation.energy!.value,
        snapshot.totals.energy!.value,
      );
      expect(snapshot.totals.unclassifiedCost!.amount, '3.000000000000000001');
      expect(
        snapshot.trends.buckets.single.allocation.unclassifiedCost!.amount,
        snapshot.totals.unclassifiedCost!.amount,
      );
      expect(snapshot.totals.unclassifiedCost!.currency, 'USD');
      expect(
        snapshot.trends.buckets.single.allocation.unclassifiedCost!.currency,
        snapshot.totals.unclassifiedCost!.currency,
      );
    },
  );

  test('rejects mixed mode, snapshot, period and totals', () async {
    for (final change in ['data_mode', 'snapshot_id', 'period', 'totals']) {
      final series = jsonDecode(
        jsonEncode(_body('energy_trends')),
      ) as Map<String, dynamic>;
      switch (change) {
        case 'data_mode':
          series['data_mode'] = 'sample';
          series['fixture_revision'] = 'synthetic_household_v1';
          break;
        case 'snapshot_id':
          series['snapshot_id'] = 'other';
          break;
        case 'period':
          series['period']['start_local'] = '2026-10-05T00:00:00-05:00';
          break;
        case 'totals':
          series['totals']['energy'] = {'value': '1', 'unit': 'kWh'};
      }
      final source = _Reads(
        (_) async => _dashboard(_body('dashboard')),
        (_) async => _trends(series),
      );
      await expectLater(
        DashboardDomainRepository(source).fetch(homeA),
        throwsFormatException,
      );
    }
  });

  test('home switch and sign-out discard in-flight reads', () async {
    final oldDashboard = Completer<CloudHouseholdDashboard>();
    final oldTrends = Completer<CloudHouseholdEnergyTrends>();
    final source = _Reads(
      (home) => home == homeA
          ? oldDashboard.future
          : Future.value(_dashboard(_body('dashboard', home: home))),
      (home) => home == homeA
          ? oldTrends.future
          : Future.value(_trends(_body('energy_trends', home: home))),
    );
    final repository = DashboardDomainRepository(source);
    final oldRead = repository.fetch(homeA);
    final newRead = await repository.fetch(homeB);
    expect(newRead?.homeId, homeB);
    oldDashboard.complete(_dashboard(_body('dashboard')));
    oldTrends.complete(_trends(_body('energy_trends')));
    expect(await oldRead, isNull);
    final signedOutDashboard = Completer<CloudHouseholdDashboard>();
    final signedOutTrends = Completer<CloudHouseholdEnergyTrends>();
    final signOut = DashboardDomainRepository(
      _Reads((_) => signedOutDashboard.future, (_) => signedOutTrends.future),
    );
    final pending = signOut.fetch(homeA);
    signOut.clear();
    signedOutDashboard.complete(_dashboard(_body('dashboard')));
    signedOutTrends.complete(_trends(_body('energy_trends')));
    expect(await pending, isNull);
  });

  test(
    'active backend errors propagate and invalid IDs do not fetch',
    () async {
      final source = _Reads(
        (_) async => throw StateError('network'),
        (_) async => _trends(_body('energy_trends')),
      );
      final repository = DashboardDomainRepository(source);
      await expectLater(repository.fetch('invalid'), throwsArgumentError);
      expect(source.calls, isEmpty);
      await expectLater(repository.fetch(homeA), throwsStateError);
    },
  );
}
