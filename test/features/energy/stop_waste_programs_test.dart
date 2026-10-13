import 'dart:convert';

import 'package:energylens_mobile/core/cloud_api/cloud_api_client.dart';
import 'package:energylens_mobile/core/cloud_api/cloud_home.dart';
import 'package:energylens_mobile/core/cloud_auth/cloud_auth.dart';
import 'package:energylens_mobile/features/energy/stop_waste_programs.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:url_launcher_platform_interface/url_launcher_platform_interface.dart';
import 'package:url_launcher_platform_interface/link.dart';

const _homeId = '11111111-1111-4111-8111-111111111111';
const _home = CloudHome(
  id: _homeId,
  name: 'Home',
  timezone: 'America/Chicago',
  countryCode: 'US',
  postalCode: '60601',
);

class _Store implements CloudTokenStore {
  @override
  Future<void> clear() async {}
  @override
  Future<CloudTokens?> read() async => const CloudTokens(accessToken: 'token');
  @override
  Future<void> save(CloudTokens tokens) async {}
}

class _Auth implements CloudAuthenticator {
  @override
  Future<CloudTokens> signIn(CloudAuthConfig config) async =>
      const CloudTokens(accessToken: 'token');
  @override
  Future<CloudTokens> refresh(CloudAuthConfig config, String token) async =>
      const CloudTokens(accessToken: 'token');
}

class _Launcher extends UrlLauncherPlatform {
  String? openedUrl;
  PreferredLaunchMode? mode;

  @override
  LinkDelegate? get linkDelegate => null;

  @override
  Future<bool> launchUrl(String url, LaunchOptions options) async {
    openedUrl = url;
    mode = options.mode;
    return true;
  }
}

Map<String, dynamic> _program(
  String id,
  String kind, {
  String availability = 'open',
  String expires = '2099-01-01T00:00:00Z',
  String? availabilityExpires,
}) => {
  'program_id': id,
  'revision_id': '88888888-8888-4888-8888-888888888888',
  'title': '$kind offer',
  'administrator_name': '$kind source',
  'administrator_kind': kind,
  'benefit_kind': 'rebate',
  'benefit_display': '$kind benefit',
  'benefit_terms': {},
  'eligibility_terms': {},
  'stacking_terms': {},
  'availability_status': availability,
  'status': 'unknown',
  'reasons': ['provider_unknown'],
  'source_url': 'https://example.org/$kind',
  'source_sha256': 'a' * 64,
  'review_expires_at': expires,
  'availability_expires_at': ?availabilityExpires,
};

void main() {
  testWidgets('shows current home programs without saved appliances', (
    tester,
  ) async {
    final previousLauncher = UrlLauncherPlatform.instance;
    final launcher = _Launcher();
    UrlLauncherPlatform.instance = launcher;
    addTearDown(() => UrlLauncherPlatform.instance = previousLauncher);
    const localId = '44444444-4444-4444-8444-444444444444';
    const federalId = '55555555-5555-4555-8555-555555555555';
    const makerId = '66666666-6666-4666-8666-666666666666';
    final requested = <Uri>[];
    final api = CloudApiClient(
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
      client: MockClient((request) async {
        requested.add(request.url);
        final rows = [
          _program(localId, 'city'),
          _program(federalId, 'federal'),
          _program(makerId, 'manufacturer'),
          _program(
            '77777777-7777-4777-8777-777777777777',
            'county',
            availability: 'closed',
          ),
          _program(
            '99999999-9999-4999-8999-999999999999',
            'state',
            expires: '2020-01-01T00:00:00Z',
          ),
        ];
        return http.Response(
          jsonEncode({
            'programs': rows,
            'as_of': '2026-10-01T00:00:00Z',
            'coverage': null,
          }),
          200,
        );
      }),
    );
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: SingleChildScrollView(
            child: StopWastePrograms(
              api: api,
              home: _home,
              now: () => DateTime.utc(2026, 10, 13, 12),
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(requested, hasLength(1));
    expect(requested.single.path, '/v1/homes/$_homeId/programs');
    expect(requested.single.query, isEmpty);
    expect(find.text('Programs'), findsOneWidget);
    expect(find.byKey(const Key('stopWasteProgram-$localId')), findsOneWidget);
    expect(
      find.byKey(const Key('stopWasteProgram-$federalId')),
      findsOneWidget,
    );
    expect(find.byKey(const Key('stopWasteProgram-$makerId')), findsOneWidget);
    expect(find.text('Local'), findsOneWidget);
    expect(find.text('Federal'), findsOneWidget);
    expect(find.text('Manufacturers'), findsOneWidget);
    expect(find.text('city benefit'), findsOneWidget);
    expect(find.text('city source'), findsOneWidget);
    expect(find.text('https://example.org/city'), findsOneWidget);
    expect(find.text('county offer'), findsNothing);
    expect(find.text('state offer'), findsNothing);
    await tester.tap(find.byKey(const Key('stopWasteProgram-$localId')));
    await tester.pump();
    expect(launcher.openedUrl, 'https://example.org/city');
    expect(launcher.mode, PreferredLaunchMode.externalApplication);
    api.close();
  });

  testWidgets('cached promotion disappears at expiry boundary and after', (
    tester,
  ) async {
    final expiry = DateTime.utc(2026, 10, 13, 12);
    var now = expiry.subtract(const Duration(seconds: 1));
    final api = CloudApiClient(
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
      client: MockClient(
        (_) async => http.Response(
          jsonEncode({
            'programs': [
              _program(
                '44444444-4444-4444-8444-444444444444',
                'city',
                expires: expiry.toIso8601String(),
              ),
              _program('55555555-5555-4555-8555-555555555555', 'federal'),
              _program(
                '66666666-6666-4666-8666-666666666666',
                'manufacturer',
                availabilityExpires: expiry.toIso8601String(),
              ),
            ],
            'as_of': '2026-10-01T00:00:00Z',
            'coverage': null,
          }),
          200,
        ),
      ),
    );
    Future<void> render() async {
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: StopWastePrograms(api: api, home: _home, now: () => now),
          ),
        ),
      );
      await tester.pumpAndSettle();
    }

    await render();
    expect(find.text('city offer'), findsOneWidget);
    expect(find.text('federal offer'), findsOneWidget);
    expect(find.text('manufacturer offer'), findsOneWidget);
    now = expiry;
    await tester.pump(const Duration(seconds: 1));
    expect(find.text('city offer'), findsNothing);
    expect(find.text('federal offer'), findsOneWidget);
    expect(find.text('manufacturer offer'), findsNothing);
    now = expiry.add(const Duration(microseconds: 1));
    await tester.pump();
    expect(find.text('city offer'), findsNothing);
    expect(find.text('federal offer'), findsOneWidget);
    expect(find.text('manufacturer offer'), findsNothing);
    api.close();
  });
}
