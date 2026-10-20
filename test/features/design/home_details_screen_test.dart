import 'dart:convert';

import 'package:energylens_mobile/core/cloud_api/cloud_api_client.dart';
import 'package:energylens_mobile/core/cloud_auth/cloud_auth.dart';
import 'package:energylens_mobile/features/design/home_details_screen.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

const _homeId = '11111111-1111-4111-8111-111111111111';

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

void main() {
  testWidgets(
    'home form saves through selected-home versioned API and readback',
    (tester) async {
      var name = 'Original Home';
      var version = 1;
      var writes = 0;
      final client = MockClient((request) async {
        expect(request.headers['authorization'], 'Bearer owner-token');
        final path = request.url.path;
        if (path == '/v1/me') {
          return http.Response(
            jsonEncode({
              'id': 'owner',
              'email': 'owner@example.com',
              'email_verified': true,
            }),
            200,
          );
        }
        Map<String, Object?> home() => {
          'id': _homeId,
          'name': name,
          'timezone': 'America/Chicago',
          'location': {'country_code': 'US', 'postal_code': '60601'},
          'version': version,
        };
        if (path == '/v1/homes' && request.method == 'GET') {
          return http.Response(
            jsonEncode({
              'homes': [home()],
            }),
            200,
          );
        }
        if (path == '/v1/me/preferences') {
          return http.Response(
            jsonEncode({
              'schema_version': 1,
              'version': 1,
              'email_reports_enabled': false,
            }),
            200,
            headers: {'etag': '"1"'},
          );
        }
        if (path == '/v1/homes/$_homeId/preferences') {
          return http.Response(
            jsonEncode({
              'schema_version': 1,
              'version': 1,
              'goal': 'unspecified',
              'comfort_priority': 'unknown',
            }),
            200,
            headers: {'etag': '"1"'},
          );
        }
        if (path == '/v1/homes/$_homeId/appliances') {
          return http.Response(jsonEncode({'appliances': []}), 200);
        }
        if (path == '/v1/homes/$_homeId' && request.method == 'PATCH') {
          writes++;
          expect(request.headers['if-match'], '"1"');
          expect(
            request.headers['idempotency-key'],
            matches(
              RegExp(
                r'^[0-9a-f]{8}-[0-9a-f]{4}-4[0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$',
              ),
            ),
          );
          final patch = jsonDecode(request.body) as Map<String, dynamic>;
          expect(patch, {'name': 'Updated Home'});
          name = patch['name'] as String;
          version++;
          return http.Response(
            jsonEncode(home()),
            200,
            headers: {'etag': '"2"'},
          );
        }
        if (path == '/v1/homes/$_homeId' && request.method == 'GET') {
          return http.Response(
            jsonEncode(home()),
            200,
            headers: {'etag': '"$version"'},
          );
        }
        fail('Unexpected ${request.method} $path');
      });
      bool? result;
      await tester.pumpWidget(
        MaterialApp(
          home: Builder(
            builder: (context) => TextButton(
              onPressed: () async {
                result = await Navigator.of(context).push<bool>(
                  MaterialPageRoute(
                    builder: (_) => HomeDetailsScreen(
                      api: _api(client),
                      homeId: _homeId,
                      isCurrentHome: () => true,
                    ),
                  ),
                );
              },
              child: const Text('Open'),
            ),
          ),
        ),
      );
      await tester.tap(find.text('Open'));
      await tester.pumpAndSettle();
      expect(find.text('Home details'), findsOneWidget);
      expect(find.text('Original Home'), findsOneWidget);
      await tester.enterText(
        find.widgetWithText(TextField, 'Home name'),
        'Updated Home',
      );
      await tester.tap(find.text('Save changes'));
      await tester.pumpAndSettle();
      expect(writes, 1);
      expect(result, true);
      expect(find.text('Open'), findsOneWidget);
    },
  );
}
