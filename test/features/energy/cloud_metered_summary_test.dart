import 'dart:convert';

import 'package:energylens_mobile/core/cloud_api/cloud_api_client.dart';
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

void main() {
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
