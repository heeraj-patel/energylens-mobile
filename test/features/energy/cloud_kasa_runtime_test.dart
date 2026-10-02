import 'dart:convert';

import 'package:energylens_mobile/core/cloud_api/cloud_api_client.dart';
import 'package:energylens_mobile/core/cloud_api/cloud_home.dart';
import 'package:energylens_mobile/core/cloud_auth/cloud_auth.dart';
import 'package:energylens_mobile/features/energy/cloud_kasa_runtime_screen.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

const home = CloudHome(
  id: '11111111-1111-4111-8111-111111111111',
  name: 'Selected home',
  timezone: 'America/Chicago',
  countryCode: 'US',
  postalCode: '60601',
);

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

Map<String, dynamic> _row(
  String id,
  String label,
  int? minutes, {
  String? homeId,
}) => {
  'snapshot_id': id,
  'hub_id': '33333333-3333-4333-8333-333333333333',
  'ownership_epoch': 2,
  'home_id': homeId ?? home.id,
  'sensor_id': '22222222-2222-4222-8222-222222222222',
  'scope': 'single_plug',
  'window_label': label,
  'native_unit': 'minutes',
  'native_minutes': minutes,
  'duration_seconds': minutes == null ? null : minutes * 60,
  'reported_start': null,
  'reported_end': null,
  'device_clock_valid': false,
  'observed_at': '2026-10-01T11:00:00Z',
  'method': 'get_device_usage',
  'transport': 'kasa_http_klap',
  'quality': minutes == null
      ? 'unavailable'
      : 'protocol_reported_clock_unverified',
};

Map<String, dynamic> _page(List<Map<String, dynamic>> rows, String? next) => {
  'snapshots': rows,
  'from': '2026-09-01T12:00:00Z',
  'to': '2026-10-01T12:00:00Z',
  'next_cursor': next,
};

void main() {
  testWidgets('selected-home runtime is paged and never shown as energy', (
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
        expect(request.headers['authorization'], 'Bearer owner-token');
        expect(request.url.path, '/v1/homes/${home.id}/kasa-runtime');
        expect(request.url.queryParameters['limit'], '50');
        if (requests.length == 1) {
          expect(request.url.queryParameters.containsKey('cursor'), isFalse);
          return http.Response(
            jsonEncode(
              _page([
                _row('aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa', 'today', 0),
                _row('bbbbbbbb-bbbb-4bbb-8bbb-bbbbbbbbbbbb', 'past7', 45),
              ], 'page-two'),
            ),
            200,
          );
        }
        expect(request.url.queryParameters['cursor'], 'page-two');
        return http.Response(
          jsonEncode(
            _page([
              _row('cccccccc-cccc-4ccc-8ccc-cccccccccccc', 'past30', 90),
            ], null),
          ),
          200,
        );
      }),
    );
    await tester.pumpWidget(
      MaterialApp(
        home: CloudKasaRuntimeScreen(api: api, home: home),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.text('Selected home'), findsOneWidget);
    expect(find.text('Today'), findsOneWidget);
    expect(find.text('Past 7 days'), findsOneWidget);
    expect(find.text('0 reported relay-on minutes'), findsOneWidget);
    expect(find.text('45 reported relay-on minutes'), findsOneWidget);
    expect(find.textContaining('Device clock unverified'), findsWidgets);
    expect(find.textContaining('Source: Kasa device usage'), findsWidgets);
    expect(find.textContaining('kWh'), findsNothing);
    expect(find.textContaining('cost'), findsNothing);
    expect(find.textContaining('waste'), findsNothing);
    await tester.ensureVisible(find.byKey(const Key('moreKasaRuntime')));
    await tester.tap(find.byKey(const Key('moreKasaRuntime')));
    await tester.pumpAndSettle();
    expect(find.text('Past 30 days'), findsOneWidget);
    expect(find.text('90 reported relay-on minutes'), findsOneWidget);
    expect(requests, hasLength(2));
    api.close();
  });

  test('unavailable and wrong-home rows fail closed', () async {
    for (final row in [
      _row('aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa', 'today', null),
      _row(
        'aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa',
        'today',
        1,
        homeId: '99999999-9999-4999-8999-999999999999',
      ),
    ]) {
      final api = _api(
        MockClient(
          (_) async => http.Response(jsonEncode(_page([row], null)), 200),
        ),
      );
      await expectLater(api.kasaRuntimeHistory(home.id), throwsFormatException);
      api.close();
    }
  });
}
