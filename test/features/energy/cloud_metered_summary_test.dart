import 'dart:convert';

import 'package:energylens_mobile/core/cloud_api/cloud_api_client.dart';
import 'package:energylens_mobile/core/cloud_api/cloud_appliance_list.dart';
import 'package:energylens_mobile/core/cloud_api/cloud_home.dart';
import 'package:energylens_mobile/core/cloud_api/cloud_metered_summary.dart';
import 'package:energylens_mobile/core/cloud_auth/cloud_auth.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

const home = CloudHome(
  id: '11111111-1111-4111-8111-111111111111',
  name: 'Home',
  timezone: 'America/Chicago',
  countryCode: 'US',
  postalCode: '60601',
);
const sensor = '22222222-2222-4222-8222-222222222222';
const hub = '33333333-3333-4333-8333-333333333333';
const attachment = '44444444-4444-4444-8444-444444444444';

class _Store implements CloudTokenStore {
  @override
  Future<void> clear() async {}
  @override
  Future<CloudTokens?> read() async =>
      const CloudTokens(accessToken: 'owner-token');
  @override
  Future<void> save(CloudTokens value) async {}
}

class _Auth implements CloudAuthenticator {
  @override
  Future<CloudTokens> signIn(CloudAuthConfig config) async =>
      const CloudTokens(accessToken: 'owner-token');
  @override
  Future<CloudTokens> refresh(
    CloudAuthConfig config,
    String refreshToken,
  ) async => const CloudTokens(accessToken: 'owner-token');
}

CloudApiClient _api(MockClient client) => CloudApiClient(
  session: CloudSession(
    config: const CloudAuthConfig(
      issuer: 'https://issuer.example',
      audience: 'energylens-cloud',
      clientId: 'client',
      redirectUrl: 'io.energylens.app://login-callback',
      apiUrl: 'https://api.example',
    ),
    store: _Store(),
    authenticator: _Auth(),
  ),
  client: client,
);

Map<String, dynamic> _row(String kind) => {
  'kind': kind,
  'bucket_start': '2026-10-01T00:00:00Z',
  'computed_at': '2026-10-01T01:00:00Z',
  'sensor_id': sensor,
  'hub_id': hub,
  'ownership_epoch': 2,
  'source_refs': [
    {'event_id': '55555555-5555-4555-8555-555555555555', 'revision': 1},
  ],
};

void main() {
  test('metered page retains paired sample response provenance', () async {
    final api = _api(
      MockClient(
        (_) async => http.Response(
          jsonEncode({
            'granularity': 'day',
            'summaries': [],
            'next_cursor': null,
          }),
          200,
          headers: {
            'X-EnergyLens-Data-Mode': 'sample',
            'X-EnergyLens-Fixture-Revision': 'synthetic-household-v1',
          },
        ),
      ),
    );
    final page = await api.meteredSummaries(home.id, granularity: 'day');
    expect(page.dataMode, CloudApplianceDataMode.sample);
    expect(page.fixtureRevision, 'synthetic-household-v1');
    api.close();
  });

  test('metered page accepts optional opaque evidence revision', () async {
    for (final revision in <String?>[null, 'v1-42', 'A' * 128]) {
      final api = _api(
        MockClient(
          (_) async => http.Response(
            jsonEncode({
              'granularity': 'day',
              'summaries': [],
              'next_cursor': null,
            }),
            200,
            headers: revision == null
                ? const {}
                : {'X-EnergyLens-Evidence-Revision': revision},
          ),
        ),
      );
      final page = await api.meteredSummaries(home.id, granularity: 'day');
      expect(page.evidenceRevision, revision);
      expect(page.dataMode, CloudApplianceDataMode.household);
      api.close();
    }
  });

  test('metered page rejects malformed evidence revision', () async {
    for (final revision in <String>[
      '',
      ' bad',
      'bad revision',
      'a/b',
      'A' * 129,
    ]) {
      final api = _api(
        MockClient(
          (_) async => http.Response(
            jsonEncode({
              'granularity': 'day',
              'summaries': [],
              'next_cursor': null,
            }),
            200,
            headers: {'X-EnergyLens-Evidence-Revision': revision},
          ),
        ),
      );
      await expectLater(
        api.meteredSummaries(home.id, granularity: 'day'),
        throwsFormatException,
      );
      api.close();
    }
  });

  test('metered page rejects malformed provenance pairs', () async {
    for (final headers in <Map<String, String>>[
      {'x-energylens-data-mode': 'sample'},
      {'x-energylens-fixture-revision': 'synthetic-household-v1'},
      {
        'x-energylens-data-mode': 'household',
        'x-energylens-fixture-revision': 'synthetic-household-v1',
      },
      {
        'x-energylens-data-mode': 'sample',
        'x-energylens-fixture-revision': 'bad revision',
      },
    ]) {
      final api = _api(
        MockClient(
          (_) async => http.Response(
            jsonEncode({
              'granularity': 'day',
              'summaries': [],
              'next_cursor': null,
            }),
            200,
            headers: headers,
          ),
        ),
      );
      await expectLater(
        api.meteredSummaries(home.id, granularity: 'day'),
        throwsFormatException,
      );
      api.close();
    }
  });

  test('authorization failure never becomes a sample page', () async {
    final api = _api(
      MockClient(
        (_) async => http.Response(
          jsonEncode({'code': 'forbidden'}),
          403,
          headers: {
            'x-energylens-data-mode': 'sample',
            'x-energylens-fixture-revision': 'synthetic-household-v1',
          },
        ),
      ),
    );
    await expectLater(
      api.meteredSummaries(home.id, granularity: 'day'),
      throwsA(
        isA<CloudApiException>().having((e) => e.statusCode, 'statusCode', 403),
      ),
    );
    api.close();
  });

  test('rejects unknown summary kind and mismatched granularity', () async {
    final api = _api(
      MockClient(
        (request) async => http.Response(
          jsonEncode({
            'granularity': 'day',
            'summaries': [_row('future_kind')],
            'next_cursor': null,
          }),
          200,
        ),
      ),
    );
    await expectLater(
      api.meteredSummaries(home.id, granularity: 'day'),
      throwsFormatException,
    );
    api.close();

    final mismatch = _api(
      MockClient(
        (request) async => http.Response(
          jsonEncode({
            'granularity': 'hour',
            'summaries': [],
            'next_cursor': null,
          }),
          200,
        ),
      ),
    );
    await expectLater(
      mismatch.meteredSummaries(home.id, granularity: 'day'),
      throwsFormatException,
    );
    mismatch.close();
  });

  test('zero sample bucket retains unknown power statistics', () {
    final row = CloudMeteredSummary.fromJson({
      ..._row('power_sample_stats'),
      'sample_count': 0,
      'min_watts': null,
      'max_watts': null,
      'mean_watts': null,
    });
    expect(row.sampleCount, 0);
    expect(row.meanWatts, isNull);

    expect(
      () => CloudMeteredSummary.fromJson({
        ..._row('power_sample_stats'),
        'sample_count': 0,
        'min_watts': 0,
        'max_watts': null,
        'mean_watts': null,
      }),
      throwsFormatException,
    );
  });
}
