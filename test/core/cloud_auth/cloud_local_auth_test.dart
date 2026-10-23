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
  test('auth capability selection prefers email and suppresses contradictory signup', () {
    const config = CloudAuthConfig(
      issuer: '',
      audience: '',
      clientId: '',
      redirectUrl: '',
      apiUrl: 'https://api.example',
      localAuthEnabled: true,
    );
    final data = <String, dynamic>{
      'schema_version': 1,
      'methods': ['username_password', 'email_password'],
      'registration_enabled': true,
      'email_verification_required': false,
      'password_recovery_enabled': true,
      'session_logout_revokes_access': true,
    };
    expect(
      CloudAuthCapabilities.fromJson(data, config).method,
      'email_password',
    );
    final contradictory = CloudAuthCapabilities.fromJson({
      ...data,
      'email_verification_required': true,
    }, config);
    expect(contradictory.method, 'email_password');
    expect(contradictory.registrationEnabled, isFalse);
    expect(contradictory.registrationConfigurationError, isTrue);
    expect(contradictory.passwordRecoveryEnabled, isTrue);
    expect(
      CloudAuthCapabilities.fromJson(
        {
          ...data,
          'methods': ['username_password'],
          'password_recovery_enabled': false,
        },
        const CloudAuthConfig(
          issuer: '',
          audience: '',
          clientId: '',
          redirectUrl: '',
          apiUrl: 'https://api.example',
          devAuthEnabled: true,
          appEnvironment: 'dev',
        ),
      ).method,
      'username_password',
    );
  });

  test('generic or malformed signup response never stores a session', () async {
    for (final response in [
      http.Response('{"status":"accepted"}', 202),
      http.Response('{"token_type":"Bearer"}', 201),
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
        session.registerLocal(
          client,
          'person@example.com',
          'long password 123',
        ),
        throwsA(anything),
      );
      expect(store.tokens, isNull);
      expect(await session.accessToken(), isNull);
      client.close();
    }
  });

  test(
    'transient refresh failures retain the session for a later retry',
    () async {
      var attempts = 0;
      final client = CloudLocalAuthClient(
        baseUrl: _config.apiUrl,
        client: MockClient((request) async {
          expect(request.url.path, '/v1/auth/local/refresh');
          attempts++;
          if (attempts == 1) return http.Response('', 503);
          if (attempts == 2) throw http.ClientException('offline');
          final expiry = DateTime.now().toUtc().add(
            const Duration(minutes: 15),
          );
          return http.Response(
            jsonEncode({
              'token_type': 'Bearer',
              'access_token': 'recovered-access',
              'refresh_token': 'rotated-refresh',
              'access_expires_at': expiry.toIso8601String(),
              'refresh_expires_at': expiry
                  .add(const Duration(days: 30))
                  .toIso8601String(),
            }),
            200,
          );
        }),
      );
      final store = _Store()
        ..tokens = CloudTokens(
          accessToken: 'expired-access',
          refreshToken: 'original-refresh',
          expiresAt: DateTime.now().subtract(const Duration(minutes: 1)),
          refreshExpiresAt: DateTime.now().add(const Duration(days: 30)),
          provider: 'local',
        );
      final session = CloudSession(
        config: _config,
        store: store,
        authenticator: _Oidc(),
        localAuth: client,
      );
      await expectLater(
        session.accessToken(),
        throwsA(isA<CloudLocalAuthException>()),
      );
      expect(store.tokens?.refreshToken, 'original-refresh');
      await expectLater(
        session.accessToken(),
        throwsA(isA<http.ClientException>()),
      );
      expect(store.tokens?.refreshToken, 'original-refresh');
      expect(await session.accessToken(), 'recovered-access');
      expect(store.tokens?.refreshToken, 'rotated-refresh');
      expect(attempts, 3);
      client.close();
    },
  );

  test('rejected refresh credential clears the persisted session', () async {
    final client = CloudLocalAuthClient(
      baseUrl: _config.apiUrl,
      client: MockClient((_) async => http.Response('', 401)),
    );
    final store = _Store()
      ..tokens = CloudTokens(
        accessToken: 'expired-access',
        refreshToken: 'revoked-refresh',
        expiresAt: DateTime.now().subtract(const Duration(minutes: 1)),
        refreshExpiresAt: DateTime.now().add(const Duration(days: 30)),
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
    client.close();
  });

  test(
    'API 401 with unavailable refresh keeps credentials for retry',
    () async {
      final client = CloudLocalAuthClient(
        baseUrl: _config.apiUrl,
        client: MockClient((_) async => http.Response('', 503)),
      );
      final store = _Store()
        ..tokens = CloudTokens(
          accessToken: 'still-stored-access',
          refreshToken: 'still-stored-refresh',
          expiresAt: DateTime.now().add(const Duration(minutes: 5)),
          refreshExpiresAt: DateTime.now().add(const Duration(days: 30)),
          provider: 'local',
        );
      final session = CloudSession(
        config: _config,
        store: store,
        authenticator: _Oidc(),
        localAuth: client,
      );
      final api = CloudApiClient(
        session: session,
        client: MockClient((_) async => http.Response('', 401)),
      );
      await expectLater(api.me(), throwsA(isA<CloudLocalAuthException>()));
      expect(store.tokens?.refreshToken, 'still-stored-refresh');
      api.close();
      client.close();
    },
  );

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
            path.endsWith('/registration') ? 201 : 200,
          );
        }),
      );
      final store = _Store();
      final session = CloudSession(
        config: _config,
        store: store,
        authenticator: _Oidc(),
        localAuth: client,
      );
      await session.registerLocal(
        client,
        'person@example.com',
        'long password 123',
      );
      expect(store.tokens?.accessToken, 'rotated-access');
      await session.signInLocal('person@example.com', 'long password 123');
      expect(await session.accessToken(), 'first-access');
      expect(store.tokens?.provider, 'local');
      expect(await session.refreshAccessToken(), 'rotated-access');
      expect(store.tokens?.refreshToken, 'rotated-refresh');
      await session.signOut();
      expect(store.tokens, isNull);
      expect(calls, [
        '/v1/auth/local/registration',
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
    expect(find.text('Submit'), findsOneWidget);
    expect(find.text('Create account'), findsNothing);
    await tester.enterText(
      find.byKey(const Key('localSignInEmail')),
      'person@example.com',
    );
    await tester.enterText(
      find.byKey(const Key('localSignInPassword')),
      'long password 123',
    );
    await tester.tap(find.text('Submit'));
    await tester.pumpAndSettle();
    expect(find.text('Internal Error, Try again later'), findsOneWidget);
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
    await tester.tap(find.text('Submit'));
    await tester.pumpAndSettle();
    expect(find.text('Invalid username or password.'), findsOneWidget);
    expect(find.textContaining('secret'), findsNothing);
    expect(find.text('Private Home'), findsNothing);
    api.close();
    client.close();
  });
}
