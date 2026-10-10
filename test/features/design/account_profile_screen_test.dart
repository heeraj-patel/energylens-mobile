import 'dart:convert';

import 'package:energylens_mobile/core/cloud_api/cloud_api_client.dart';
import 'package:energylens_mobile/core/cloud_auth/cloud_auth.dart';
import 'package:energylens_mobile/core/cloud_auth/cloud_local_auth.dart';
import 'package:energylens_mobile/features/design/account_profile_screen.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

class _Store implements CloudTokenStore {
  @override
  Future<CloudTokens?> read() async => CloudTokens(
    accessToken: 'local-token',
    provider: 'local',
    expiresAt: DateTime.now().add(const Duration(hours: 1)),
    refreshExpiresAt: DateTime.now().add(const Duration(days: 1)),
  );
  @override
  Future<void> clear() async {}
  @override
  Future<void> save(CloudTokens value) async {}
}

class _Auth implements CloudAuthenticator {
  @override
  Future<CloudTokens> signIn(CloudAuthConfig config) async =>
      const CloudTokens(accessToken: 'local-token', provider: 'local');
  @override
  Future<CloudTokens> refresh(
    CloudAuthConfig config,
    String refreshToken,
  ) async => const CloudTokens(accessToken: 'local-token', provider: 'local');
}

CloudApiClient _api(MockClient client) => CloudApiClient(
  session: CloudSession(
    config: const CloudAuthConfig(
      issuer: 'https://issuer.example',
      audience: 'energylens-cloud',
      clientId: 'client',
      redirectUrl: 'io.energylens.app://login-callback',
      apiUrl: 'https://api.example',
      localAuthEnabled: true,
    ),
    store: _Store(),
    authenticator: _Auth(),
    localAuth: CloudLocalAuthClient(
      baseUrl: 'https://api.example',
      client: client,
    ),
  ),
  client: client,
);

void main() {
  test(
    'email and password mutations use the local credential routes',
    () async {
      final calls = <String>[];
      final api = _api(
        MockClient((request) async {
          calls.add(request.url.path);
          expect(request.headers['authorization'], 'Bearer local-token');
          if (request.url.path.endsWith('/change-email')) {
            expect(request.headers['if-match'], '"3"');
            expect(jsonDecode(request.body), {
              'new_email': 'next@example.com',
              'current_password': 'current-secret',
            });
            return http.Response(
              jsonEncode({
                'id': 'owner',
                'email': 'next@example.com',
                'email_verified': true,
                'display_name': 'Owner',
                'profile_version': 4,
              }),
              200,
              headers: {'etag': '"4"'},
            );
          }
          expect(request.url.path, '/v1/auth/local/change-password');
          expect(jsonDecode(request.body), {
            'current_password': 'current-secret',
            'new_password': 'new-long-secret',
          });
          return http.Response('', 204);
        }),
      );
      final changed = await api.changeLocalEmail(
        'next@example.com',
        'current-secret',
        ifMatch: '"3"',
        idempotencyKey: '11111111-1111-4111-8111-111111111111',
      );
      expect(changed.value.email, 'next@example.com');
      expect(changed.etag, '"4"');
      await api.changeLocalPassword('current-secret', 'new-long-secret');
      expect(calls, [
        '/v1/auth/local/change-email',
        '/v1/auth/local/change-password',
      ]);
      api.close();
    },
  );

  testWidgets('account owner form sends versioned write and returns success', (
    tester,
  ) async {
    var wrote = false;
    final api = _api(
      MockClient((request) async {
        expect(request.headers['authorization'], 'Bearer local-token');
        if (request.url.path == '/v1/me' && request.method == 'GET') {
          return http.Response(
            jsonEncode({
              'id': 'owner',
              'email': 'owner@example.com',
              'email_verified': true,
              'display_name': 'Old Name',
              'profile_version': 1,
            }),
            200,
            headers: {'etag': '"1"'},
          );
        }
        expect(request.url.path, '/v1/me/profile');
        expect(request.method, 'PATCH');
        expect(request.headers['if-match'], '"1"');
        expect(jsonDecode(request.body), {'display_name': 'New Name'});
        wrote = true;
        return http.Response(
          jsonEncode({
            'id': 'owner',
            'email': 'owner@example.com',
            'email_verified': true,
            'display_name': 'New Name',
            'profile_version': 2,
          }),
          200,
          headers: {'etag': '"2"'},
        );
      }),
    );
    expect((await api.accountProfile()).etag, '"1"');
    bool? result;
    await tester.pumpWidget(
      MaterialApp(
        home: Builder(
          builder: (context) => Scaffold(
            body: TextButton(
              onPressed: () async {
                result = await Navigator.of(context).push<bool>(
                  MaterialPageRoute(
                    builder: (_) => AccountProfileScreen(
                      api: api,
                      field: AccountProfileField.owner,
                      isCurrentAccount: () => true,
                    ),
                  ),
                );
              },
              child: const Text('Open'),
            ),
          ),
        ),
      ),
    );
    await tester.tap(find.text('Open'));
    await tester.pumpAndSettle();
    expect(find.byIcon(Icons.error_outline), findsNothing);
    expect(
      tester.widget<FilledButton>(find.byType(FilledButton)).onPressed,
      isNotNull,
    );
    await tester.enterText(find.byType(TextField), 'New Name');
    await tester.tap(find.text('Save changes'));
    await tester.pumpAndSettle();
    expect(wrote, true);
    expect(result, true);
  });
}
