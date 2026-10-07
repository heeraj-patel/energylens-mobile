import 'dart:convert';

import 'package:energylens_mobile/core/cloud_api/cloud_api_client.dart';
import 'package:energylens_mobile/core/cloud_api/cloud_appliance_list.dart';
import 'package:energylens_mobile/core/cloud_api/cloud_home.dart';
import 'package:energylens_mobile/core/cloud_api/cloud_metered_summary.dart';
import 'package:energylens_mobile/core/cloud_auth/cloud_auth.dart';
import 'package:energylens_mobile/features/energy/cloud_metered_summary_screen.dart';
import 'package:flutter/material.dart';
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

Map<String, dynamic> _gapRow(int day) => {
  ..._row('coverage_gap'),
  'bucket_start': '2026-10-${day.toString().padLeft(2, '0')}T00:00:00Z',
  'gap_overlap_count': 1,
  'dropped_count_started': 0,
};

http.Response _page(int day, String? next) => http.Response(
  jsonEncode({
    'granularity': 'day',
    'summaries': [_gapRow(day)],
    'next_cursor': next,
  }),
  200,
);

http.Response _conflict() =>
    http.Response(jsonEncode({'code': 'evidence_changed'}), 409);

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

  testWidgets(
    'daily and hourly rows retain distinct meanings and cursor scope',
    (tester) async {
      tester.view.physicalSize = const Size(900, 1800);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      final requests = <http.Request>[];
      final api = _api(
        MockClient((request) async {
          requests.add(request);
          expect(request.headers['authorization'], 'Bearer owner-token');
          expect(request.url.path, '/v1/homes/${home.id}/metered-summaries');
          expect(request.url.queryParameters['limit'], '50');
          final hourly = request.url.queryParameters['granularity'] == 'hour';
          final cursor = request.url.queryParameters['cursor'];
          if (cursor != null) {
            expect(cursor, 'next');
            expect(
              request.url.queryParameters.containsKey('granularity'),
              isFalse,
            );
          }
          return http.Response(
            jsonEncode({
              'granularity': hourly ? 'hour' : 'day',
              'summaries': hourly
                  ? [
                      {
                        ..._row('energy'),
                        'attachment_id': attachment,
                        'energy_wh': 2.3,
                        'covered_seconds': 59.5,
                        'interval_count': 1,
                        'status': 'complete',
                        'allocation_method': 'duration_proportional',
                      },
                      {
                        ..._row('power_sample_stats'),
                        'sample_count': 2,
                        'min_watts': 90,
                        'max_watts': 120,
                        'mean_watts': 105,
                      },
                    ]
                  : cursor != null
                  ? [
                      {
                        ..._row('coverage_gap'),
                        'gap_overlap_count': 1,
                        'dropped_count_started': 2,
                      },
                    ]
                  : [],
              'next_cursor': hourly
                  ? null
                  : cursor == null
                  ? 'next'
                  : null,
            }),
            200,
          );
        }),
      );
      await tester.pumpWidget(
        MaterialApp(
          home: CloudMeteredSummaryScreen(api: api, home: home),
        ),
      );
      await tester.pumpAndSettle();
      await tester.ensureVisible(find.byKey(const Key('moreMeteredSummaries')));
      await tester.tap(find.byKey(const Key('moreMeteredSummaries')));
      await tester.pumpAndSettle();
      expect(find.textContaining('Missing sensor coverage'), findsOneWidget);
      await tester.tap(find.text('Hourly'));
      await tester.pumpAndSettle();
      expect(find.textContaining('2.30 measured Wh'), findsOneWidget);
      expect(find.textContaining('59.50 covered seconds'), findsOneWidget);
      expect(find.textContaining('sample statistics only'), findsOneWidget);
      expect(find.textContaining('Quality: complete'), findsOneWidget);
      expect(find.textContaining('source references'), findsNWidgets(2));
      expect(find.textContaining('home or appliance totals'), findsOneWidget);
      expect(requests, hasLength(3));
      api.close();
    },
  );

  testWidgets('evidence conflict restarts once without mixing pages', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(900, 1800);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final requests = <http.Request>[];
    final api = _api(
      MockClient((request) async {
        requests.add(request);
        return switch (requests.length) {
          1 => _page(1, 'before-correction'),
          2 => _conflict(),
          3 => _page(2, 'after-correction'),
          _ => _page(3, null),
        };
      }),
    );
    await tester.pumpWidget(
      MaterialApp(
        home: CloudMeteredSummaryScreen(api: api, home: home),
      ),
    );
    await tester.pumpAndSettle();
    await tester.ensureVisible(find.byKey(const Key('moreMeteredSummaries')));
    await tester.tap(find.byKey(const Key('moreMeteredSummaries')));
    await tester.pumpAndSettle();
    expect(requests, hasLength(3));
    expect(requests[1].url.queryParameters['cursor'], 'before-correction');
    expect(requests[2].url.queryParameters.containsKey('cursor'), isFalse);
    expect(find.textContaining('Could not load'), findsNothing);
    expect(find.byKey(const Key('moreMeteredSummaries')), findsOneWidget);
    await tester.ensureVisible(find.byKey(const Key('moreMeteredSummaries')));
    await tester.tap(find.byKey(const Key('moreMeteredSummaries')));
    await tester.pumpAndSettle();
    expect(requests[3].url.queryParameters['cursor'], 'after-correction');
    expect(find.text('UTC bucket: 2026-10-01T00:00:00.000Z'), findsNothing);
    expect(find.text('UTC bucket: 2026-10-02T00:00:00.000Z'), findsOneWidget);
    expect(find.text('UTC bucket: 2026-10-03T00:00:00.000Z'), findsOneWidget);
    api.close();
  });

  testWidgets('repeated evidence conflict stops after one restart', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(900, 1800);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    var calls = 0;
    final api = _api(
      MockClient((request) async {
        calls++;
        if (calls == 1) return _page(1, 'first');
        if (calls == 2) return _conflict();
        if (calls == 3) return _page(2, 'second');
        return _conflict();
      }),
    );
    await tester.pumpWidget(
      MaterialApp(
        home: CloudMeteredSummaryScreen(api: api, home: home),
      ),
    );
    await tester.pumpAndSettle();
    await tester.ensureVisible(find.byKey(const Key('moreMeteredSummaries')));
    await tester.tap(find.byKey(const Key('moreMeteredSummaries')));
    await tester.pumpAndSettle();
    await tester.ensureVisible(find.byKey(const Key('moreMeteredSummaries')));
    await tester.tap(find.byKey(const Key('moreMeteredSummaries')));
    await tester.pumpAndSettle();
    expect(calls, 4);
    expect(find.byKey(const Key('meteredSummaryError')), findsOneWidget);
    expect(find.text('UTC bucket: 2026-10-02T00:00:00.000Z'), findsOneWidget);
    api.close();
  });

  testWidgets('home and granularity changes start a fresh query', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(900, 1800);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    const otherHome = CloudHome(
      id: 'aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa',
      name: 'Other home',
      timezone: 'UTC',
      countryCode: 'US',
      postalCode: '10001',
    );
    final requests = <http.Request>[];
    final api = _api(
      MockClient((request) async {
        requests.add(request);
        final day = requests.length;
        final granularity = request.url.queryParameters['granularity'];
        return http.Response(
          jsonEncode({
            'granularity': granularity ?? 'day',
            'summaries': [_gapRow(day)],
            'next_cursor': 'next',
          }),
          200,
        );
      }),
    );
    await tester.pumpWidget(
      MaterialApp(
        home: CloudMeteredSummaryScreen(api: api, home: home),
      ),
    );
    await tester.pumpAndSettle();
    await tester.ensureVisible(find.text('Hourly'));
    await tester.tap(find.text('Hourly'));
    await tester.pumpAndSettle();
    expect(requests.last.url.queryParameters['granularity'], 'hour');
    await tester.pumpWidget(
      MaterialApp(
        home: CloudMeteredSummaryScreen(api: api, home: otherHome),
      ),
    );
    await tester.pumpAndSettle();
    expect(requests.last.url.path, contains(otherHome.id));
    expect(requests.last.url.queryParameters['granularity'], 'hour');
    expect(find.text('Other home'), findsOneWidget);
    api.close();
  });

  testWidgets('authentication and server errors remain visible', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(900, 1800);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    for (final status in [401, 500]) {
      final api = _api(
        MockClient((request) async {
          if (request.url.queryParameters.containsKey('cursor')) {
            return http.Response('{}', status);
          }
          return _page(1, 'next');
        }),
      );
      await tester.pumpWidget(
        MaterialApp(
          home: CloudMeteredSummaryScreen(api: api, home: home),
        ),
      );
      await tester.pumpAndSettle();
      await tester.ensureVisible(find.byKey(const Key('moreMeteredSummaries')));
      await tester.tap(find.byKey(const Key('moreMeteredSummaries')));
      await tester.pumpAndSettle();
      expect(find.byKey(const Key('meteredSummaryError')), findsOneWidget);
      expect(find.text('UTC bucket: 2026-10-01T00:00:00.000Z'), findsOneWidget);
      api.close();
    }
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
