import 'dart:convert';

import 'package:energylens_mobile/core/cloud_api/cloud_api_client.dart';
import 'package:energylens_mobile/core/cloud_api/cloud_home.dart';
import 'package:energylens_mobile/core/cloud_auth/cloud_auth.dart';
import 'package:energylens_mobile/features/energy/cloud_metered_history_screen.dart';
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
const appliance = '33333333-3333-4333-8333-333333333333';
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

Map<String, dynamic> _page(List<Map<String, dynamic>> events, String? next) => {
  'events': events,
  'as_of': '2026-10-01T12:00:00Z',
  'as_of_cursor': 7,
  'next_cursor': next,
};

void main() {
  testWidgets(
    'renders separate point, interval, and gap with bounded cursor paging',
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
          expect(request.url.path, '/v1/homes/${home.id}/metered-history');
          expect(request.url.queryParameters['limit'], '50');
          if (requests.length == 1) {
            return http.Response(
              jsonEncode(
                _page([
                  {
                    'kind': 'power_point',
                    'sensor_id': sensor,
                    'timestamp': '2026-10-01T11:00:00Z',
                    'watts': 1200,
                    'kwh_cumulative': 1234,
                  },
                  {
                    'kind': 'energy_interval',
                    'sensor_id': sensor,
                    'start': '2026-10-01T10:00:00Z',
                    'end': '2026-10-01T10:15:00Z',
                    'energy_wh': 250,
                    'covered_seconds': 840,
                    'appliance_id': appliance,
                    'attachment_id': attachment,
                    'fuel': 'electricity',
                    'quality': 'metered',
                    'source': 'verified_driver',
                  },
                ], 'page-two'),
              ),
              200,
            );
          }
          expect(request.url.queryParameters['cursor'], 'page-two');
          expect(request.url.queryParameters.containsKey('from'), isFalse);
          expect(request.url.queryParameters.containsKey('to'), isFalse);
          return http.Response(
            jsonEncode(
              _page([
                {
                  'kind': 'coverage_gap',
                  'sensor_id': sensor,
                  'first_timestamp': '2026-10-01T09:00:00Z',
                  'last_timestamp': '2026-10-01T09:10:00Z',
                  'reason': 'offline',
                  'dropped_count': 3,
                },
              ], null),
            ),
            200,
          );
        }),
      );
      await tester.pumpWidget(
        MaterialApp(
          home: CloudMeteredHistoryScreen(api: api, home: home),
        ),
      );
      await tester.pumpAndSettle();
      expect(find.textContaining('1200.0 W at'), findsOneWidget);
      expect(find.text('250.00 measured Wh'), findsOneWidget);
      expect(find.text('Coverage: 840 seconds · electricity'), findsOneWidget);
      expect(
        find.textContaining('Attached appliance $appliance'),
        findsOneWidget,
      );
      expect(find.textContaining('kWh'), findsNothing);
      await tester.ensureVisible(find.byKey(const Key('moreMeteredHistory')));
      await tester.tap(find.byKey(const Key('moreMeteredHistory')));
      await tester.pumpAndSettle();
      expect(find.text('Missing data: offline'), findsOneWidget);
      expect(find.textContaining('3 dropped events'), findsOneWidget);
      expect(find.byKey(const Key('moreMeteredHistory')), findsNothing);
      expect(requests, hasLength(2));
      api.close();
    },
  );

  test(
    'rejects an unknown event kind rather than treating it as energy',
    () async {
      final api = _api(
        MockClient(
          (request) async => http.Response(
            jsonEncode(
              _page([
                {'kind': 'future_energy_kind', 'sensor_id': sensor},
              ], null),
            ),
            200,
          ),
        ),
      );
      await expectLater(api.meteredHistory(home.id), throwsFormatException);
      api.close();
    },
  );
}
