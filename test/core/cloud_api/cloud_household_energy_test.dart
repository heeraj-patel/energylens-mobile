import 'dart:convert';

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
          return http.Response(jsonEncode(_trends(sample: true)), 200);
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
      expect(
        result.buckets.single.allocation.cost!.amount,
        '2.4680000000000000002',
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
