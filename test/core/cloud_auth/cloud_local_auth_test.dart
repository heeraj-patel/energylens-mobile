import 'dart:convert';

import 'package:energylens_mobile/core/cloud_auth/cloud_auth.dart';
import 'package:energylens_mobile/core/cloud_auth/cloud_local_auth.dart';
import 'package:energylens_mobile/core/cloud_auth/cloud_entry_gate.dart';
import 'package:energylens_mobile/core/cloud_api/cloud_api_client.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

class _Store implements CloudTokenStore {
  CloudTokens? tokens;
  @override
  Future<void> clear() async => tokens = null;
  @override
  Future<CloudTokens?> read() async => tokens;
  @override
  Future<void> save(CloudTokens value) async => tokens = value;
}

class _Oidc implements CloudAuthenticator {
  @override
  Future<CloudTokens> signIn(CloudAuthConfig config) async =>
      throw StateError('OIDC should not be used');
  @override
  Future<CloudTokens> refresh(CloudAuthConfig config, String token) async =>
      throw StateError('OIDC should not be used');
}

const _config = CloudAuthConfig(
  issuer: '',
  audience: '',
  clientId: '',
  redirectUrl: '',
  apiUrl: 'https://api.example',
  localAuthEnabled: true,
);

void main() {
  test('local auth requires explicit enablement and a real HTTPS origin', () {
    expect(_config.isConfigured, isFalse);
    expect(_config.isLocalAuthConfigured, isTrue);
    for (final url in [
      'http://api.example',
      'https://api.invalid',
      'https://api.example/path',
    ]) {
      expect(
        CloudAuthConfig(
          issuer: '',
          audience: '',
          clientId: '',
          redirectUrl: '',
          apiUrl: url,
          localAuthEnabled: true,
        ).isLocalAuthConfigured,
        isFalse,
      );
      expect(() => CloudLocalAuthClient(baseUrl: url), throwsArgumentError);
    }
    expect(
      const CloudAuthConfig(
        issuer: '',
        audience: '',
        clientId: '',
        redirectUrl: '',
        apiUrl: 'https://api.example',
      ).isLocalAuthConfigured,
      isFalse,
    );
  });

  test(
    'registration, verification, login, rotation and logout use guarded routes',
    () async {
      final calls = <String>[];
      final client = CloudLocalAuthClient(
        baseUrl: _config.apiUrl,
        client: MockClient((request) async {
          expect(request.method, 'POST');
          expect(request.headers['Content-Type'], 'application/json');
          expect(request.headers.containsKey('Authorization'), isFalse);
          final path = request.url.path;
          calls.add(path);
          final body = jsonDecode(request.body) as Map<String, dynamic>;
          if (path.endsWith('/registration')) {
            expect(body, {
              'email': 'person@example.com',
              'password': 'long password 123',
            });
            return http.Response('{"accepted":true}', 202);
          }
          if (path.endsWith('/verify-email')) {
            expect(body, {'token': 'opaque-token'});
            return http.Response('', 204);
          }
          if (path.endsWith('/login')) {
            expect(body, {
              'email': 'person@example.com',
              'password': 'long password 123',
            });
          } else if (path.endsWith('/refresh') || path.endsWith('/logout')) {
            expect(
              body['refresh_token'],
              path.endsWith('/refresh') ? 'first-refresh' : 'rotated-refresh',
            );
          }
          if (path.endsWith('/logout')) return http.Response('', 204);
          final expiry = DateTime.now().toUtc().add(
            const Duration(minutes: 15),
          );
          return http.Response(
            jsonEncode({
              'access_token': path.endsWith('/login')
                  ? 'first-access'
                  : 'rotated-access',
              'token_type': 'Bearer',
              'access_expires_at': expiry.toIso8601String(),
              'refresh_token': path.endsWith('/login')
                  ? 'first-refresh'
                  : 'rotated-refresh',
              'refresh_expires_at': expiry
                  .add(const Duration(days: 30))
                  .toIso8601String(),
            }),
            200,
          );
        }),
      );
      await client.requestRegistration(
        'person@example.com',
        'long password 123',
      );
      await client.verifyEmail('opaque-token');
      final store = _Store();
      final session = CloudSession(
        config: _config,
        store: store,
        authenticator: _Oidc(),
        localAuth: client,
      );
      await session.signInLocal('person@example.com', 'long password 123');
      expect(await session.accessToken(), 'first-access');
      expect(store.tokens?.provider, 'local');
      expect(await session.refreshAccessToken(), 'rotated-access');
      expect(store.tokens?.refreshToken, 'rotated-refresh');
      await session.signOut();
      expect(store.tokens, isNull);
      expect(calls, [
        '/v1/auth/local/registration',
        '/v1/auth/local/verify-email',
        '/v1/auth/local/login',
        '/v1/auth/local/refresh',
        '/v1/auth/local/logout',
      ]);
      client.close();
    },
  );

  test(
    'disabled routes and malformed tokens cannot create a session',
    () async {
      for (final response in [
        http.Response('', 404),
        http.Response('{"access_token":"x","token_type":"Bearer"}', 200),
      ]) {
        final client = CloudLocalAuthClient(
          baseUrl: _config.apiUrl,
          client: MockClient((_) async => response),
        );
        final store = _Store();
        final session = CloudSession(
          config: _config,
          store: store,
          authenticator: _Oidc(),
          localAuth: client,
        );
        await expectLater(
          session.signInLocal('person@example.com', 'password'),
          throwsA(anything),
        );
        expect(store.tokens, isNull);
        client.close();
      }
    },
  );

  test(
    'expired local refresh token clears session without a request',
    () async {
      var calls = 0;
      final client = CloudLocalAuthClient(
        baseUrl: _config.apiUrl,
        client: MockClient((_) async {
          calls++;
          return http.Response('', 500);
        }),
      );
      final store = _Store()
        ..tokens = CloudTokens(
          accessToken: 'expired-access',
          refreshToken: 'expired-refresh',
          expiresAt: DateTime.now().subtract(const Duration(minutes: 1)),
          refreshExpiresAt: DateTime.now().subtract(const Duration(seconds: 1)),
          provider: 'local',
        );
      final session = CloudSession(
        config: _config,
        store: store,
        authenticator: _Oidc(),
        localAuth: client,
      );
      expect(await session.accessToken(), isNull);
      expect(store.tokens, isNull);
      expect(calls, 0);
      client.close();
    },
  );

  testWidgets('enabled email sign-in shows unavailable state for gated 404', (
    tester,
  ) async {
    final client = CloudLocalAuthClient(
      baseUrl: _config.apiUrl,
      client: MockClient((_) async => http.Response('', 404)),
    );
    final session = CloudSession(
      config: _config,
      store: _Store(),
      authenticator: _Oidc(),
      localAuth: client,
    );
    final api = CloudApiClient(
      session: session,
      client: MockClient(
        (request) async => http.Response(
          '',
          request.url.path == '/v1/auth/config' ? 404 : 500,
        ),
      ),
    );
    await tester.pumpWidget(
      MaterialApp(
        home: CloudEntryGate(
          session: session,
          api: api,
          homeBuilder: (_, _, _, _) => const Text('Private Home'),
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.text('Sign in with email'), findsOneWidget);
    expect(find.text('Create account'), findsOneWidget);
    await tester.enterText(
      find.byKey(const Key('localSignInEmail')),
      'person@example.com',
    );
    await tester.enterText(
      find.byKey(const Key('localSignInPassword')),
      'long password 123',
    );
    await tester.tap(find.text('Sign in with email'));
    await tester.pumpAndSettle();
    expect(
      find.text('Email sign-in is not available on this Cloud server.'),
      findsOneWidget,
    );
    expect(find.text('Private Home'), findsNothing);
    api.close();
    client.close();
  });

  testWidgets('401 keeps credential failure generic and closes Home', (
    tester,
  ) async {
    final client = CloudLocalAuthClient(
      baseUrl: _config.apiUrl,
      client: MockClient(
        (_) async => http.Response(
          '{"code":"invalid_credential","private":"secret"}',
          401,
        ),
      ),
    );
    final session = CloudSession(
      config: _config,
      store: _Store(),
      authenticator: _Oidc(),
      localAuth: client,
    );
    final api = CloudApiClient(
      session: session,
      client: MockClient(
        (request) async => http.Response(
          '',
          request.url.path == '/v1/auth/config' ? 404 : 500,
        ),
      ),
    );
    await tester.pumpWidget(
      MaterialApp(
        home: CloudEntryGate(
          session: session,
          api: api,
          homeBuilder: (_, _, _, _) => const Text('Private Home'),
        ),
      ),
    );
    await tester.pumpAndSettle();
    await tester.enterText(
      find.byKey(const Key('localSignInEmail')),
      'person@example.com',
    );
    await tester.enterText(
      find.byKey(const Key('localSignInPassword')),
      'wrong password',
    );
    await tester.tap(find.text('Sign in with email'));
    await tester.pumpAndSettle();
    expect(
      find.text('Could not sign in. Check your details and try again.'),
      findsOneWidget,
    );
    expect(find.textContaining('secret'), findsNothing);
    expect(find.text('Private Home'), findsNothing);
    api.close();
    client.close();
  });
}
