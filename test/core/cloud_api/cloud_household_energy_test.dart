import 'dart:convert';
import 'dart:io';

import 'package:energylens_mobile/core/cloud_api/cloud_api_client.dart';
import 'package:energylens_mobile/core/cloud_api/cloud_household_energy.dart';
import 'package:energylens_mobile/core/cloud_auth/cloud_auth.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

const homeId = '11111111-1111-4111-8111-111111111111';
const config = CloudAuthConfig(
  issuer: 'https://issuer.example',
  audience: 'a',
  clientId: 'c',
  redirectUrl: 'io.energylens.app://login-callback',
  apiUrl: 'https://api.example',
);

class _Store implements CloudTokenStore {
  @override
  Future<void> clear() async {}
  @override
  Future<CloudTokens?> read() async => const CloudTokens(accessToken: 'token');
  @override
  Future<void> save(CloudTokens value) async {}
}

class _Authenticator implements CloudAuthenticator {
  @override
  Future<CloudTokens> signIn(CloudAuthConfig config) async =>
      const CloudTokens(accessToken: 'token');
  @override
  Future<CloudTokens> refresh(
    CloudAuthConfig config,
    String refreshToken,
  ) async => const CloudTokens(accessToken: 'token');
}

CloudApiClient _api(MockClient client) => CloudApiClient(
  session: CloudSession(
    config: config,
    store: _Store(),
    authenticator: _Authenticator(),
  ),
  client: client,
);

Map<String, dynamic> _allocation({bool sample = false}) => {
  'energy': {'value': '12.340000000000000001', 'unit': 'kWh'},
  'cost': {'amount': '2.4680000000000000002', 'currency': 'USD'},
  'useful_energy': null,
  'useful_cost': null,
  'waste_energy': null,
  'waste_cost': null,
  'unclassified_energy': sample
      ? {'value': '12.340000000000000001', 'unit': 'kWh'}
      : null,
  'unclassified_cost': sample
      ? {'amount': '2.4680000000000000002', 'currency': 'USD'}
      : null,
  'availability': sample ? 'available' : 'partial',
  'evidence_basis': sample ? 'synthetic' : 'measured',
};

Map<String, dynamic> _base({bool sample = false}) => {
  'schema_revision': 'household_energy_v1',
  'content_revision': 'household_energy_20261006_v1',
  'home_id': homeId,
  'data_mode': sample ? 'sample' : 'household',
  if (sample) 'fixture_revision': 'synthetic-household-v1',
  'snapshot_id': 'snap-123',
  'generated_at': '2026-10-06T12:00:00Z',
  'as_of': sample ? null : '2026-10-06T11:59:00Z',
  'timezone': 'America/Chicago',
  'period': {
    'start_local': '2026-10-06T00:00:00-05:00',
    'end_exclusive_local': '2026-10-07T00:00:00-05:00',
  },
  'scope': 'whole_home_including_unattributed_load',
  'availability': sample ? 'available' : 'partial',
  'evidence_basis': sample ? 'synthetic' : 'measured',
};

Map<String, dynamic> _dashboard({bool sample = false}) => {
  ..._base(sample: sample),
  'view': 'dashboard',
  'totals': _allocation(sample: sample),
  'trend_period': 'day',
  'top_recommendation_id': null,
  'assistant_intent_id': null,
};

Map<String, dynamic> _trends({bool sample = false}) => {
  ..._base(sample: sample),
  'view': 'energy_trends',
  'granularity': 'hour',
  'totals': _allocation(sample: sample),
  'buckets': [
    {
      'start_local': '2026-10-06T00:00:00-05:00',
      'end_exclusive_local': '2026-10-06T01:00:00-05:00',
      'allocation': _allocation(sample: sample),
      'coverage_fraction': sample ? '1' : null,
    },
  ],
};

void main() {
  test('parses mixed energy provenance with retained fixture revision', () {
    final json = _dashboard(sample: false)
      ..['data_mode'] = 'mixed'
      ..['fixture_revision'] = 'synthetic-household-v1';
    final dashboard = CloudHouseholdDashboard.fromJson(
      json,
      expectedHomeId: homeId,
    );
    expect(dashboard.dataMode, 'mixed');
    expect(dashboard.fixtureRevision, 'synthetic-household-v1');
    expect(dashboard.totals.evidenceBasis, 'measured');

    final seededSplit = _allocation(sample: true)
      ..['useful_cost'] = {'amount': '1.80', 'currency': 'USD'}
      ..['waste_cost'] = {'amount': '0.40', 'currency': 'USD'};
    final trendsJson = _trends(sample: false)
      ..['data_mode'] = 'mixed'
      ..['fixture_revision'] = 'synthetic-household-v1';
    (trendsJson['buckets'] as List).single['device_allocations'] = [
      {
        'device_id': 'demo-device-01',
        'name': 'Demo television',
        'allocation': seededSplit,
      },
    ];
    final trends = CloudHouseholdEnergyTrends.fromJson(
      trendsJson,
      expectedHomeId: homeId,
    );
    expect(trends.totals.evidenceBasis, 'measured');
    expect(
      trends.buckets.single.deviceAllocations.single.deviceId,
      'demo-device-01',
    );
    expect(
      trends
          .buckets
          .single
          .deviceAllocations
          .single
          .allocation
          .wasteCost!
          .amount,
      '0.40',
    );
  });

  test('parses waste_basis and rate_basis on Cloud allocations', () {
    final row = _allocation()
      ..['useful_energy'] = {'value': '9', 'unit': 'kWh'}
      ..['waste_energy'] = {'value': '0.5', 'unit': 'kWh'}
      ..['waste_cost'] = {'amount': '0.01', 'currency': 'USD'}
      ..['waste_basis'] = 'floor'
      ..['rate_basis'] = 'us_average';
    final json = _dashboard()
      ..['totals'] = row
      ..['device_allocations'] = [
        {'device_id': 'demo-device-02', 'name': null, 'allocation': row},
      ];
    final parsed = CloudHouseholdDashboard.fromJson(
      json,
      expectedHomeId: homeId,
    );
    expect(parsed.totals.wasteBasis, 'floor');
    expect(parsed.totals.rateBasis, 'us_average');
    final device = parsed.deviceAllocations.single.allocation;
    expect(device.wasteBasis, 'floor');
    expect(device.rateBasis, 'us_average');
    expect(CloudEnergyAllocation.fromJson(_allocation()).wasteBasis, isNull);
    for (final bad in [
      {'waste_basis': 'unknown'},
      {'rate_basis': 'regional_average'},
    ]) {
      expect(
        () => CloudEnergyAllocation.fromJson({..._allocation(), ...bad}),
        throwsFormatException,
      );
    }
  });

  test('parses gas dryer allocation and keeps old payloads valid', () {
    final parsed = CloudEnergyAllocation.fromJson({
      ..._allocation(),
      'energy': {'value': '59.4', 'unit': 'kWh'},
      'cost': {'amount': '10.88', 'currency': 'USD'},
      'fuel': 'natural_gas',
      'gas_energy': {'value': '22.7', 'unit': 'therm'},
      'gas_energy_kwh_eq': {'value': '665.3', 'unit': 'kWh'},
      'total_energy_kwh_eq': {'value': '724.7', 'unit': 'kWh'},
      'gas_cost': {'amount': '33.62', 'currency': 'USD'},
      'total_cost': {'amount': '44.50', 'currency': 'USD'},
      'standby_cost': null,
      'gas_rate_basis': 'national_average',
      'gas_basis': 'derived_from_cef',
      'waste_basis': 'rated_standby',
    });
    expect(parsed.fuel, 'natural_gas');
    expect(parsed.gasEnergy!.value, '22.7');
    expect(parsed.gasEnergy!.unit, 'therm');
    expect(parsed.gasEnergyKwhEq!.value, '665.3');
    expect(parsed.totalEnergyKwhEq!.value, '724.7');
    expect(parsed.gasCost!.amount, '33.62');
    expect(parsed.totalCost!.amount, '44.50');
    expect(parsed.standbyCost, isNull);
    expect(parsed.gasRateBasis, 'national_average');
    expect(parsed.gasBasis, 'derived_from_cef');
    expect(parsed.wasteBasis, 'rated_standby');

    final old = CloudEnergyAllocation.fromJson(_allocation());
    expect(old.fuel, isNull);
    expect(old.gasEnergy, isNull);
    expect(old.gasCost, isNull);
    expect(old.gasBasis, isNull);

    final standby = CloudEnergyAllocation.fromJson({
      ..._allocation(),
      'standby_cost': {'amount': '0.12', 'currency': 'USD'},
    });
    expect(standby.standbyCost!.amount, '0.12');
  });

  test('rejects invalid gas fields', () {
    for (final bad in [
      {
        'gas_energy': {'value': '22.7', 'unit': 'kWh'},
      },
      {
        'gas_energy_kwh_eq': {'value': '665.3', 'unit': 'therm'},
      },
      {'fuel': 'coal'},
      {'gas_rate_basis': 'home_tariff'},
      {'gas_basis': 'measured'},
    ]) {
      expect(
        () => CloudEnergyAllocation.fromJson({..._allocation(), ...bad}),
        throwsFormatException,
      );
    }
  });

  test('parses synthetic split and scoped device rows in both responses', () {
    const applianceId = '10000000-0000-4000-8000-000000000001';
    final split = _allocation(sample: true)
      ..['useful_energy'] = {'value': '9', 'unit': 'kWh'}
      ..['useful_cost'] = {'amount': '1.80', 'currency': 'USD'}
      ..['waste_energy'] = {'value': '2', 'unit': 'kWh'}
      ..['waste_cost'] = {'amount': '0.40', 'currency': 'USD'}
      ..['unclassified_energy'] = {'value': '1', 'unit': 'kWh'}
      ..['unclassified_cost'] = {'amount': '0.20', 'currency': 'USD'};
    final dashboardJson = _dashboard(sample: true)
      ..['device_allocations'] = [
        {'appliance_id': applianceId, 'allocation': split},
      ];
    final trendsJson = _trends(sample: true);
    (trendsJson['buckets'] as List).single['device_allocations'] = [
      {'appliance_id': applianceId, 'allocation': split},
    ];
    final dashboard = CloudHouseholdDashboard.fromJson(
      dashboardJson,
      expectedHomeId: homeId,
    );
    final trends = CloudHouseholdEnergyTrends.fromJson(
      trendsJson,
      expectedHomeId: homeId,
    );
    expect(dashboard.deviceAllocations.single.applianceId, applianceId);
    expect(
      trends
          .buckets
          .single
          .deviceAllocations
          .single
          .allocation
          .wasteCost!
          .amount,
      '0.40',
    );
    expect(
      dashboard.deviceAllocations.single.allocation.usefulEnergy!.value,
      '9',
    );
    dashboardJson['device_allocations'] = [
      {'appliance_id': applianceId, 'allocation': split},
      {'appliance_id': applianceId.toUpperCase(), 'allocation': split},
    ];
    expect(
      () => CloudHouseholdDashboard.fromJson(
        dashboardJson,
        expectedHomeId: homeId,
      ),
      throwsFormatException,
    );
  });

  test('parses database demo IDs with nullable names and unknown energy', () {
    final split = _allocation(sample: true)
      ..['energy'] = null
      ..['useful_energy'] = null
      ..['waste_energy'] = null
      ..['unclassified_energy'] = null;
    final json = _dashboard(sample: true)
      ..['device_allocations'] = [
        {
          'device_id': 'demo-device-01',
          'name': 'Study Desktop & Rig',
          'allocation': split,
        },
        {'device_id': 'demo-device-11', 'name': null, 'allocation': split},
      ];
    final parsed = CloudHouseholdDashboard.fromJson(
      json,
      expectedHomeId: homeId,
    );
    expect(parsed.deviceAllocations, hasLength(2));
    expect(parsed.deviceAllocations.first.deviceId, 'demo-device-01');
    expect(parsed.deviceAllocations.first.name, 'Study Desktop & Rig');
    expect(parsed.deviceAllocations.last.name, isNull);
    expect(parsed.deviceAllocations.first.allocation.energy, isNull);
    (json['device_allocations'] as List).add({
      'device_id': 'demo-device-01',
      'name': null,
      'allocation': split,
    });
    expect(
      () => CloudHouseholdDashboard.fromJson(json, expectedHomeId: homeId),
      throwsFormatException,
    );
  });

  test(
    'dashboard parses household values with exact decimals and unknowns',
    () async {
      final seen = <http.Request>[];
      final client = _api(
        MockClient((request) async {
          seen.add(request);
          return http.Response(jsonEncode(_dashboard()), 200);
        }),
      );
      final result = await client.householdDashboard(homeId);
      expect(seen.single.url.path, '/v1/homes/$homeId/dashboard');
      expect(seen.single.url.query, isEmpty);
      expect(seen.single.headers['authorization'], 'Bearer token');
      expect(result.homeId, homeId);
      expect(result.dataMode, 'household');
      expect(result.fixtureRevision, isNull);
      expect(result.snapshotId, 'snap-123');
      expect(result.timezone, 'America/Chicago');
      expect(result.totals.energy!.value, '12.340000000000000001');
      expect(result.totals.cost!.amount, '2.4680000000000000002');
      expect(result.totals.usefulEnergy, isNull);
      expect(result.totals.wasteCost, isNull);
      expect(result.asOf, isNotNull);
      client.close();
    },
  );

  test(
    'trends parses sample evidence and uses requested granularity',
    () async {
      final seen = <http.Request>[];
      final client = _api(
        MockClient((request) async {
          seen.add(request);
          final json = _trends(sample: true);
          (json['totals'] as Map<String, dynamic>)
            ..['waste_basis'] = 'demo'
            ..['rate_basis'] = 'us_average';
          ((json['buckets'] as List).single['allocation']
                  as Map<String, dynamic>)['rate_basis'] =
              'home_tariff';
          return http.Response(jsonEncode(json), 200);
        }),
      );
      final result = await client.householdEnergyTrends(
        homeId,
        granularity: 'hour',
      );
      expect(seen.single.url.path, '/v1/homes/$homeId/energy-trends');
      expect(seen.single.url.queryParameters, {'granularity': 'hour'});
      expect(result.dataMode, 'sample');
      expect(result.fixtureRevision, 'synthetic-household-v1');
      expect(result.granularity, 'hour');
      expect(result.buckets, hasLength(1));
      expect(result.buckets.single.coverageFraction, '1');
      expect(result.buckets.single.allocation.evidenceBasis, 'synthetic');
      expect(result.totals.wasteBasis, 'demo');
      expect(result.totals.rateBasis, 'us_average');
      expect(result.buckets.single.allocation.rateBasis, 'home_tariff');
      expect(
        result.buckets.single.allocation.cost!.amount,
        '2.4680000000000000002',
      );
      client.close();
    },
  );

  test(
    'trailing 30 day query is scoped and only valid for daily buckets',
    () async {
      final seen = <http.Request>[];
      final client = _api(
        MockClient((request) async {
          seen.add(request);
          final json = _trends(sample: true);
          json['granularity'] = 'day';
          (json['totals'] as Map<String, dynamic>)['rate_basis'] = 'us_average';
          return http.Response(jsonEncode(json), 200);
        }),
      );
      final result = await client.householdEnergyTrends(
        homeId,
        granularity: 'day',
        window: 'trailing_30_days',
      );
      expect(result.totals.rateBasis, 'us_average');
      expect(seen.single.url.queryParameters, {
        'granularity': 'day',
        'window': 'trailing_30_days',
      });
      await expectLater(
        client.householdEnergyTrends(
          homeId,
          granularity: 'week',
          window: 'trailing_30_days',
        ),
        throwsArgumentError,
      );
      client.close();
    },
  );

  test(
    'month-to-date query is scoped and only valid for daily buckets',
    () async {
      final seen = <http.Request>[];
      final client = _api(
        MockClient((request) async {
          seen.add(request);
          final json = _trends(sample: true);
          json['granularity'] = 'day';
          return http.Response(jsonEncode(json), 200);
        }),
      );
      await client.householdEnergyTrends(
        homeId,
        granularity: 'day',
        window: 'month_to_date',
      );
      expect(seen.single.url.queryParameters, {
        'granularity': 'day',
        'window': 'month_to_date',
      });
      await expectLater(
        client.householdEnergyTrends(
          homeId,
          granularity: 'week',
          window: 'month_to_date',
        ),
        throwsArgumentError,
      );
      client.close();
    },
  );

  test('last five occurrence queries accept day week and month only', () async {
    final seen = <http.Request>[];
    final client = _api(
      MockClient((request) async {
        seen.add(request);
        final json = _trends(sample: true);
        json['granularity'] = request.url.queryParameters['granularity'];
        return http.Response(jsonEncode(json), 200);
      }),
    );
    for (final granularity in const ['day', 'week', 'month']) {
      await client.householdEnergyTrends(
        homeId,
        granularity: granularity,
        window: 'last_5_occurrences',
      );
    }
    expect(seen.map((request) => request.url.queryParameters).toList(), [
      for (final granularity in const ['day', 'week', 'month'])
        {'granularity': granularity, 'window': 'last_5_occurrences'},
    ]);
    await expectLater(
      client.householdEnergyTrends(
        homeId,
        granularity: 'hour',
        window: 'last_5_occurrences',
      ),
      throwsArgumentError,
    );
    client.close();
  });

  test(
    'household reads preserve measured energy and estimated unclassified money',
    () async {
      final dashboardJson = _dashboard();
      final trendsJson = _trends();
      for (final body in [dashboardJson, trendsJson]) {
        final totals = body['totals'] as Map<String, dynamic>;
        totals['energy'] = {'value': '13.570000000000000001', 'unit': 'kWh'};
        totals['unclassified_energy'] = {
          'value': '13.570000000000000001',
          'unit': 'kWh',
        };
        totals['cost'] = null;
        totals['unclassified_cost'] = {
          'amount': '3.000000000000000001',
          'currency': 'USD',
        };
        totals['evidence_basis'] = 'mixed';
      }
      final bucket =
          (trendsJson['buckets'] as List).single as Map<String, dynamic>;
      final bucketAllocation = bucket['allocation'] as Map<String, dynamic>;
      bucketAllocation['energy'] = {
        'value': '13.570000000000000001',
        'unit': 'kWh',
      };
      bucketAllocation['unclassified_energy'] = {
        'value': '13.570000000000000001',
        'unit': 'kWh',
      };
      bucketAllocation['cost'] = null;
      bucketAllocation['unclassified_cost'] = {
        'amount': '3.000000000000000001',
        'currency': 'USD',
      };
      bucketAllocation['evidence_basis'] = 'mixed';
      final client = _api(
        MockClient(
          (request) async => http.Response(
            jsonEncode(
              request.url.path.endsWith('dashboard')
                  ? dashboardJson
                  : trendsJson,
            ),
            200,
          ),
        ),
      );

      final dashboard = await client.householdDashboard(homeId);
      final trends = await client.householdEnergyTrends(
        homeId,
        granularity: 'hour',
      );

      expect(dashboard.dataMode, 'household');
      expect(dashboard.totals.energy!.value, '13.570000000000000001');
      expect(dashboard.totals.cost, isNull);
      expect(dashboard.totals.unclassifiedCost!.amount, '3.000000000000000001');
      expect(dashboard.totals.unclassifiedCost!.currency, 'USD');
      expect(trends.totals.unclassifiedCost!.amount, '3.000000000000000001');
      expect(trends.totals.unclassifiedCost!.currency, 'USD');
      expect(
        trends.buckets.single.allocation.energy!.value,
        trends.totals.energy!.value,
      );
      expect(
        trends.buckets.single.allocation.unclassifiedCost!.amount,
        trends.totals.unclassifiedCost!.amount,
      );
      expect(
        trends.buckets.single.allocation.unclassifiedCost!.currency,
        trends.totals.unclassifiedCost!.currency,
      );
      client.close();
    },
  );

  test(
    'rejects invalid home IDs and trend granularity before sending',
    () async {
      var calls = 0;
      final client = _api(
        MockClient((_) async {
          calls++;
          return http.Response('{}', 200);
        }),
      );
      expect(() => client.householdDashboard('../x'), throwsArgumentError);
      expect(
        () => client.householdEnergyTrends(homeId, granularity: 'year'),
        throwsArgumentError,
      );
      expect(calls, 0);
      client.close();
    },
  );

  test(
    'rejects malformed allocation fields and response home mismatch',
    () async {
      final badAllocation = _allocation()
        ..['energy'] = {'value': 1.2, 'unit': 'kWh'};
      final malformed = _dashboard()..['totals'] = badAllocation;
      final client = _api(
        MockClient((_) async => http.Response(jsonEncode(malformed), 200)),
      );
      await expectLater(
        client.householdDashboard(homeId),
        throwsFormatException,
      );
      client.close();

      final wrongHome = _dashboard()
        ..['home_id'] = '22222222-2222-4222-8222-222222222222';
      final mismatch = _api(
        MockClient((_) async => http.Response(jsonEncode(wrongHome), 200)),
      );
      await expectLater(
        mismatch.householdDashboard(homeId),
        throwsFormatException,
      );
      mismatch.close();
    },
  );

  test(
    'rejects a trend response whose granularity differs from the request',
    () async {
      final client = _api(
        MockClient((_) async => http.Response(jsonEncode(_trends()), 200)),
      );
      await expectLater(
        client.householdEnergyTrends(homeId, granularity: 'day'),
        throwsFormatException,
      );
      client.close();
    },
  );

  test('propagates cloud authentication and HTTP errors', () async {
    final unauthorized = _api(
      MockClient(
        (_) async =>
            http.Response(jsonEncode({'code': 'not_authenticated'}), 401),
      ),
    );
    await expectLater(
      unauthorized.householdDashboard(homeId),
      throwsA(
        isA<CloudApiException>().having((e) => e.statusCode, 'status', 401),
      ),
    );
    unauthorized.close();

    final unavailable = _api(
      MockClient(
        (_) async => http.Response(jsonEncode({'code': 'not_found'}), 404),
      ),
    );
    await expectLater(
      unavailable.householdEnergyTrends(homeId, granularity: 'day'),
      throwsA(
        isA<CloudApiException>().having((e) => e.code, 'code', 'not_found'),
      ),
    );
    unavailable.close();
  });

  test(
    'failed reads retain status and request path without response text',
    () async {
      final api = _api(
        MockClient((request) async {
          if (request.url.path.endsWith('/dashboard')) {
            return http.Response('{"secret":"bad"}', 200);
          }
          return http.Response('{"code":"private-code"}', 503);
        }),
      );
      Object? parseError;
      Object? httpError;
      try {
        await api.householdDashboard(homeId);
      } catch (error) {
        parseError = error;
      }
      try {
        await api.householdEnergyTrends(homeId, granularity: 'hour');
      } catch (error) {
        httpError = error;
      }
      expect(parseError, isA<FormatException>());
      expect(cloudRequestFailureContext(parseError!)?.statusCode, 200);
      expect(
        cloudRequestFailureContext(parseError)?.path,
        '/v1/homes/$homeId/dashboard',
      );
      expect(httpError, isA<CloudApiException>());
      expect(cloudRequestFailureContext(httpError!)?.statusCode, 503);
      expect(
        cloudRequestFailureContext(httpError)?.path,
        '/v1/homes/$homeId/energy-trends',
      );
      api.close();
    },
  );

  test(
    'transport failure retains request path with unavailable status',
    () async {
      final api = _api(
        MockClient((_) async => throw const SocketException('private-host')),
      );
      Object? failure;
      try {
        await api.householdDashboard(homeId);
      } catch (error) {
        failure = error;
      }
      expect(failure, isA<SocketException>());
      final context = cloudRequestFailureContext(failure!);
      expect(context?.type, 'SocketException');
      expect(context?.statusCode, isNull);
      expect(context?.path, '/v1/homes/$homeId/dashboard');
      api.close();
    },
  );

  test('concurrent parse failures retain their own endpoint paths', () async {
    final api = _api(MockClient((_) async => http.Response('{}', 200)));
    Future<Object> failure(Future<Object> request) async {
      try {
        await request;
      } catch (error) {
        return error;
      }
      throw StateError('Expected a parse failure');
    }

    final errors = await Future.wait([
      failure(api.householdDashboard(homeId)),
      failure(api.householdEnergyTrends(homeId, granularity: 'hour')),
    ]);
    expect(errors, everyElement(isA<FormatException>()));
    expect(errors[0], isNot(same(errors[1])));
    expect(
      cloudRequestFailureContext(errors[0])?.path,
      '/v1/homes/$homeId/dashboard',
    );
    expect(
      cloudRequestFailureContext(errors[1])?.path,
      '/v1/homes/$homeId/energy-trends',
    );
    api.close();
  });

  test(
    'malformed appliance, estimate and hub reads retain 200 and path',
    () async {
      final api = _api(MockClient((_) async => http.Response('{}', 200)));
      final reads = <String, Future<Object>>{
        '/v1/homes/$homeId/appliances': api.applianceList(homeId),
        '/v1/homes/$homeId/estimates': api.estimates(homeId),
        '/v1/homes/$homeId/hubs': api.hubs(homeId),
      };
      for (final entry in reads.entries) {
        Object? failure;
        try {
          await entry.value;
        } catch (error) {
          failure = error;
        }
        expect(failure, isA<FormatException>());
        expect(cloudRequestFailureContext(failure!)?.statusCode, 200);
        expect(cloudRequestFailureContext(failure)?.path, entry.key);
      }
      api.close();
    },
  );

  test(
    'sample dashboard preserves null as-of and requires fixture revision',
    () {
      final parsed = CloudHouseholdDashboard.fromJson(
        _dashboard(sample: true),
        expectedHomeId: homeId,
      );
      expect(parsed.asOf, isNull);
      expect(parsed.dataMode, 'sample');
      expect(parsed.fixtureRevision, 'synthetic-household-v1');
      final invalid = _dashboard(sample: true)..remove('fixture_revision');
      expect(
        () => CloudHouseholdDashboard.fromJson(invalid, expectedHomeId: homeId),
        throwsFormatException,
      );
      final invalidBasis = _dashboard(sample: true)
        ..['evidence_basis'] = 'measured';
      expect(
        () => CloudHouseholdDashboard.fromJson(
          invalidBasis,
          expectedHomeId: homeId,
        ),
        throwsFormatException,
      );
    },
  );
}
