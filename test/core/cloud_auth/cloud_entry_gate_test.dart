import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:energylens_mobile/core/cloud_api/cloud_api_client.dart';
import 'package:energylens_mobile/core/cloud_api/cloud_home.dart';
import 'package:energylens_mobile/core/cloud_auth/cloud_auth.dart';
import 'package:energylens_mobile/core/cloud_auth/cloud_entry_gate.dart';
import 'package:energylens_mobile/core/cloud_auth/cloud_local_auth.dart';
import 'package:energylens_mobile/core/cloud_auth/cloud_auxiliary_domain_lifecycle.dart';
import 'package:energylens_mobile/features/design/design_context_coordinator.dart';
import 'package:energylens_mobile/features/design/report_preview_domain_repository.dart';
import 'package:energylens_mobile/features/design/report_delivery_domain_adapter.dart';
import 'package:energylens_mobile/features/identify/onboarding_draft_store.dart';
import 'package:energylens_mobile/features/identify/onboarding_persistence_repository.dart';
import 'package:flutter/material.dart';
import 'package:flutter_appauth/flutter_appauth.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

const config = CloudAuthConfig(
  issuer: 'https://issuer.example',
  audience: 'energylens-cloud',
  clientId: 'client',
  redirectUrl: 'io.energylens.app://login-callback',
  apiUrl: 'https://api.example',
);

class Store implements CloudTokenStore {
  CloudTokens? tokens = const CloudTokens(accessToken: 'token');
  @override
  Future<void> clear() async => tokens = null;
  @override
  Future<CloudTokens?> read() async => tokens;
  @override
  Future<void> save(CloudTokens value) async => tokens = value;
}

class Auth implements CloudAuthenticator {
  @override
  Future<CloudTokens> refresh(
    CloudAuthConfig config,
    String refreshToken,
  ) async => const CloudTokens(accessToken: 'token');
  @override
  Future<CloudTokens> signIn(CloudAuthConfig config) async =>
      const CloudTokens(accessToken: 'token');
}

class FailingAuth extends Auth {
  FailingAuth(this.error);
  final Object error;

  @override
  Future<CloudTokens> signIn(CloudAuthConfig config) async => throw error;
}

class RetryAuth extends Auth {
  RetryAuth({this.invalidGrant = false});
  final bool invalidGrant;
  int refreshCalls = 0;
  int signInCalls = 0;

  @override
  Future<CloudTokens> refresh(CloudAuthConfig config, String token) async {
    refreshCalls++;
    if (refreshCalls == 1) {
      if (invalidGrant) {
        throw FlutterAppAuthPlatformException(
          code: 'token_error',
          platformErrorDetails: FlutterAppAuthPlatformErrorDetails(
            error: FlutterAppAuthOAuthError.invalidGrant,
          ),
        );
      }
      throw const SocketException('offline');
    }
    return CloudTokens(
      accessToken: 'recovered',
      refreshToken: 'rotated',
      expiresAt: DateTime.now().add(const Duration(minutes: 15)),
    );
  }

  @override
  Future<CloudTokens> signIn(CloudAuthConfig config) async {
    signInCalls++;
    return const CloudTokens(accessToken: 'new-login');
  }
}

class RecordingDesignAdapters implements DesignContextAdapters {
  int clears = 0;
  @override
  void clear() => clears++;
  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class MemoryDraftStorage implements OnboardingDraftStorage {
  String? value;
  @override
  Future<String?> read() async => value;
  @override
  Future<void> write(String data) async => value = data;
  @override
  Future<void> clear() async => value = null;
}

const firstHomeId = '11111111-1111-1111-1111-111111111111';
const secondHomeId = '22222222-2222-2222-2222-222222222222';
const verifiedAccountId = 'aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa';
const acceptedPreferences =
    '{"version":1,"schema_version":1,"email_reports_enabled":false}';

String ownedHomes([String second = secondHomeId]) =>
    '{"homes":[{"id":"$firstHomeId","name":"First home","timezone":"America/Chicago","location":{"country_code":"US","postal_code":"60601"}},{"id":"$second","name":"Second home","timezone":"America/Chicago","location":{"country_code":"US","postal_code":"60601"}}]}';

String pendingFirstHomeDraft() => jsonEncode({
  'kind': 'home_create',
  'origin': 'https://api.example',
  'profile': 'oidc',
  'account_id': verifiedAccountId,
  'operation_key': '33333333-3333-4333-8333-333333333333',
  'input': {
    'name': 'Pending home',
    'timezone': 'America/Chicago',
    'location': {
      'country_code': 'US',
      'postal_code': '60601',
      'city': null,
      'county': null,
      'precision': 'postal_code',
      'source': 'user_entered',
    },
  },
});

void main() {
  testWidgets('contradictory signup capabilities keep email sign-in usable', (
    tester,
  ) async {
    const localConfig = CloudAuthConfig(
      issuer: '',
      audience: '',
      clientId: '',
      redirectUrl: '',
      apiUrl: 'https://api.example',
      localAuthEnabled: true,
    );
    var logins = 0;
    final local = CloudLocalAuthClient(
      baseUrl: localConfig.apiUrl,
      client: MockClient((request) async {
        if (request.url.path == '/v1/auth/local/login') {
          logins++;
          final expiry = DateTime.now().toUtc().add(
            const Duration(minutes: 15),
          );
          return http.Response(
            '{"token_type":"Bearer","access_token":"signed-in","refresh_token":"refresh",'
            '"access_expires_at":"${expiry.toIso8601String()}",'
            '"refresh_expires_at":"${expiry.add(const Duration(days: 30)).toIso8601String()}"}',
            200,
          );
        }
        return http.Response('', 404);
      }),
    );
    final store = Store()..tokens = null;
    final session = CloudSession(
      config: localConfig,
      store: store,
      authenticator: Auth(),
      localAuth: local,
    );
    final api = CloudApiClient(
      session: session,
      client: MockClient((request) async {
        if (request.url.path == '/v1/auth/config') {
          return http.Response(
            '{"schema_version":1,"methods":["email_password"],'
            '"registration_enabled":true,"email_verification_required":true,'
            '"password_recovery_enabled":true,"session_logout_revokes_access":true}',
            200,
          );
        }
        if (request.url.path == '/v1/me') {
          return http.Response(
            '{"id":"$verifiedAccountId","email":"person@example.com",'
            '"email_verified":false,"auth_method":"email_password",'
            '"display_name":"Alex"}',
            200,
          );
        }
        if (request.url.path == '/v1/homes') {
          return http.Response('{"homes":[]}', 200);
        }
        return http.Response('', 404);
      }),
    );
    await tester.pumpWidget(
      MaterialApp(
        home: CloudEntryGate(
          homeCreateStorage: MemoryDraftStorage(),
          activeHomeStorage: MemoryDraftStorage(),
          session: session,
          api: api,
          homeBuilder: (_, _, _, _) => const Text('Private Home'),
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.text('Email ID'), findsOneWidget);
    expect(find.text('Create account'), findsNothing);
    expect(find.text('Forgot password?'), findsOneWidget);
    await tester.enterText(find.byType(TextField).first, 'person@example.com');
    await tester.enterText(
      find.byType(TextField).last,
      'correct long password',
    );
    await tester.tap(find.text('Submit'));
    await tester.pumpAndSettle();
    expect(logins, 1);
    expect(find.text('Set up your home'), findsOneWidget);
    api.close();
    local.close();
  });

  testWidgets('local Submit recovers saved session without password login', (
    tester,
  ) async {
    const localConfig = CloudAuthConfig(
      issuer: '',
      audience: '',
      clientId: '',
      redirectUrl: '',
      apiUrl: 'https://api.example',
      localAuthEnabled: true,
    );
    var refreshCalls = 0;
    var loginCalls = 0;
    final local = CloudLocalAuthClient(
      baseUrl: localConfig.apiUrl,
      client: MockClient((request) async {
        if (request.url.path.endsWith('/login')) {
          loginCalls++;
          return http.Response('', 401);
        }
        refreshCalls++;
        if (refreshCalls == 1) return http.Response('', 503);
        final expiry = DateTime.now().toUtc().add(const Duration(minutes: 15));
        return http.Response(
          '{"token_type":"Bearer","access_token":"recovered","refresh_token":"rotated",'
          '"access_expires_at":"${expiry.toIso8601String()}",'
          '"refresh_expires_at":"${expiry.add(const Duration(days: 30)).toIso8601String()}"}',
          200,
        );
      }),
    );
    final store = Store()
      ..tokens = CloudTokens(
        accessToken: 'expired',
        refreshToken: 'valid-refresh',
        expiresAt: DateTime.now().subtract(const Duration(minutes: 1)),
        refreshExpiresAt: DateTime.now().add(const Duration(days: 30)),
        provider: 'local',
      );
    final session = CloudSession(
      config: localConfig,
      store: store,
      authenticator: Auth(),
      localAuth: local,
    );
    final api = CloudApiClient(
      session: session,
      client: MockClient((request) async {
        if (request.url.path == '/v1/auth/config') {
          return http.Response(
            '{"schema_version":1,"methods":["username_password"],'
            '"registration_enabled":false,"email_verification_required":false,'
            '"password_recovery_enabled":false,"session_logout_revokes_access":true}',
            200,
          );
        }
        if (request.url.path == '/v1/me') {
          return http.Response(
            '{"id":"$verifiedAccountId","username":"dev",'
            '"email_verified":true,"auth_method":"username_password"}',
            200,
          );
        }
        if (request.url.path == '/v1/me/preferences') {
          return http.Response(
            acceptedPreferences,
            200,
            headers: {'etag': '"1"'},
          );
        }
        return http.Response(ownedHomes(), 200);
      }),
    );
    await tester.pumpWidget(
      MaterialApp(
        home: CloudEntryGate(
          session: session,
          api: api,
          homeCreateStorage: MemoryDraftStorage(),
          activeHomeStorage: MemoryDraftStorage(),
          homeBuilder: (_, _, _, _) => const Text('Private Home'),
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.text('Submit'), findsOneWidget);
    expect(store.tokens?.refreshToken, 'valid-refresh');
    await tester.tap(find.text('Submit'));
    await tester.pumpAndSettle();
    expect(find.text('First home'), findsOneWidget);
    expect(refreshCalls, 2);
    expect(loginCalls, 0);
    expect(store.tokens?.refreshToken, 'rotated');
    api.close();
    local.close();
  });

  testWidgets(
    'Submit retries a stored session after transient restore failure',
    (tester) async {
      final store = Store()
        ..tokens = CloudTokens(
          accessToken: 'expired',
          refreshToken: 'valid-refresh',
          expiresAt: DateTime.now().subtract(const Duration(minutes: 1)),
        );
      final auth = RetryAuth();
      final session = CloudSession(
        config: config,
        store: store,
        authenticator: auth,
      );
      final api = CloudApiClient(
        session: session,
        client: MockClient((request) async {
          if (request.url.path == '/v1/auth/config') {
            return http.Response('', 404);
          }
          if (request.url.path == '/v1/me') {
            return http.Response(
              '{"id":"$verifiedAccountId","email":null,"email_verified":true}',
              200,
            );
          }
          if (request.url.path == '/v1/me/preferences') {
            return http.Response(
              acceptedPreferences,
              200,
              headers: {'etag': '"1"'},
            );
          }
          return http.Response(ownedHomes(), 200);
        }),
      );
      await tester.pumpWidget(
        MaterialApp(
          home: CloudEntryGate(
            session: session,
            api: api,
            homeCreateStorage: MemoryDraftStorage(),
            activeHomeStorage: MemoryDraftStorage(),
            homeBuilder: (_, _, _, _) => const Text('Private Home'),
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(find.text('Submit'), findsOneWidget);
      expect(store.tokens?.refreshToken, 'valid-refresh');
      await tester.tap(find.text('Submit'));
      await tester.pumpAndSettle();
      expect(find.text('First home'), findsOneWidget);
      expect(auth.refreshCalls, 2);
      expect(auth.signInCalls, 0);
      expect(store.tokens?.refreshToken, 'rotated');
      api.close();
    },
  );

  testWidgets('rejected stored refresh permits a new sign-in', (tester) async {
    final store = Store()
      ..tokens = CloudTokens(
        accessToken: 'expired',
        refreshToken: 'revoked',
        expiresAt: DateTime.now().subtract(const Duration(minutes: 1)),
      );
    final auth = RetryAuth(invalidGrant: true);
    final session = CloudSession(
      config: config,
      store: store,
      authenticator: auth,
    );
    final api = CloudApiClient(
      session: session,
      client: MockClient((request) async {
        if (request.url.path == '/v1/auth/config') {
          return http.Response('', 404);
        }
        if (request.url.path == '/v1/me') {
          return http.Response(
            '{"id":"$verifiedAccountId","email":null,"email_verified":true}',
            200,
          );
        }
        if (request.url.path == '/v1/me/preferences') {
          return http.Response(
            acceptedPreferences,
            200,
            headers: {'etag': '"1"'},
          );
        }
        return http.Response(ownedHomes(), 200);
      }),
    );
    await tester.pumpWidget(
      MaterialApp(
        home: CloudEntryGate(
          session: session,
          api: api,
          homeCreateStorage: MemoryDraftStorage(),
          activeHomeStorage: MemoryDraftStorage(),
          homeBuilder: (_, _, _, _) => const Text('Private Home'),
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(store.tokens, isNull);
    await tester.tap(find.text('Submit'));
    await tester.pumpAndSettle();
    expect(find.text('First home'), findsOneWidget);
    expect(auth.refreshCalls, 1);
    expect(auth.signInCalls, 1);
    api.close();
  });

  testWidgets('default gate renders the form with missing build config', (
    tester,
  ) async {
    expect(CloudAuthConfig.fromEnvironment().hasCloudSignIn, isFalse);
    await tester.pumpWidget(
      MaterialApp(
        home: CloudEntryGate(
          homeBuilder: (_, _, _, _) => const Text('Private Home'),
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
    expect(find.text('Email ID'), findsOneWidget);
    expect(find.text('Password'), findsOneWidget);
    expect(find.text('Submit'), findsOneWidget);
    await tester.tap(find.text('Submit'));
    await tester.pumpAndSettle();
    expect(find.text('Internal Error, Try again later'), findsOneWidget);
  });

  testWidgets('invalid development pin cannot start a request', (tester) async {
    const invalidPin = CloudAuthConfig(
      issuer: '',
      audience: '',
      clientId: '',
      redirectUrl: '',
      apiUrl: 'https://api.example',
      localAuthEnabled: true,
      devCertificateSha256: 'invalid-pin',
    );
    final session = CloudSession(
      config: invalidPin,
      store: Store()..tokens = null,
      authenticator: Auth(),
    );
    await tester.pumpWidget(
      MaterialApp(
        home: CloudEntryGate(
          session: session,
          homeBuilder: (_, _, _, _) => const Text('Private Home'),
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
    expect(find.text('Email ID'), findsOneWidget);
    await tester.tap(find.text('Submit'));
    await tester.pumpAndSettle();
    expect(find.text('Internal Error, Try again later'), findsOneWidget);
  });

  testWidgets(
    'missing Cloud config keeps the form and fails locally on Submit',
    (tester) async {
      const missing = CloudAuthConfig(
        issuer: '',
        audience: '',
        clientId: '',
        redirectUrl: '',
        apiUrl: '',
      );
      final session = CloudSession(
        config: missing,
        store: Store()..tokens = null,
        authenticator: Auth(),
      );
      var requests = 0;
      final api = CloudApiClient(
        session: session,
        client: MockClient((_) async {
          requests++;
          return http.Response('', 500);
        }),
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
      expect(find.text('Email ID'), findsOneWidget);
      expect(find.text('Password'), findsOneWidget);
      expect(find.text('Submit'), findsOneWidget);
      expect(find.text('Internal Error, Try again later'), findsNothing);
      await tester.tap(find.text('Submit'));
      await tester.pumpAndSettle();
      expect(find.text('Internal Error, Try again later'), findsOneWidget);
      expect(requests, 0);
      api.close();
    },
  );

  testWidgets(
    'capability outage shows the internal error and retries on Submit',
    (tester) async {
      const localConfig = CloudAuthConfig(
        issuer: '',
        audience: '',
        clientId: '',
        redirectUrl: '',
        apiUrl: 'https://api.example',
        localAuthEnabled: true,
      );
      final local = CloudLocalAuthClient(
        baseUrl: localConfig.apiUrl,
        client: MockClient((_) async => http.Response('', 401)),
      );
      final session = CloudSession(
        config: localConfig,
        store: Store()..tokens = null,
        authenticator: Auth(),
        localAuth: local,
      );
      var capabilities = 0;
      final api = CloudApiClient(
        session: session,
        client: MockClient((request) async {
          if (request.url.path == '/v1/auth/config') {
            capabilities++;
            throw const SocketException('offline');
          }
          return http.Response('', 500);
        }),
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
      expect(capabilities, 1);
      expect(find.text('Email ID'), findsOneWidget);
      expect(find.text('Internal Error, Try again later'), findsOneWidget);
      await tester.tap(find.text('Submit'));
      await tester.pumpAndSettle();
      expect(capabilities, 2);
      final error = tester.widget<Text>(
        find.text('Internal Error, Try again later'),
      );
      expect(
        error.style?.color,
        Theme.of(tester.element(find.text('Submit'))).colorScheme.error,
      );
      expect(
        error.style?.fontSize,
        Theme.of(tester.element(find.text('Submit')))
            .textTheme
            .bodySmall
            ?.fontSize,
      );
      await tester.enterText(find.byKey(const Key('localSignInEmail')), 'nik');
      await tester.pump();
      expect(find.text('Internal Error, Try again later'), findsNothing);
      api.close();
      local.close();
    },
  );

  testWidgets('recovered username capability keeps the entered identity', (
    tester,
  ) async {
    const localConfig = CloudAuthConfig(
      issuer: '',
      audience: '',
      clientId: '',
      redirectUrl: '',
      apiUrl: 'https://api.example',
      localAuthEnabled: true,
    );
    http.Request? login;
    final local = CloudLocalAuthClient(
      baseUrl: localConfig.apiUrl,
      client: MockClient((request) async {
        login = request;
        return http.Response('', 401);
      }),
    );
    final session = CloudSession(
      config: localConfig,
      store: Store()..tokens = null,
      authenticator: Auth(),
      localAuth: local,
    );
    var capabilities = 0;
    final api = CloudApiClient(
      session: session,
      client: MockClient((request) async {
        if (request.url.path == '/v1/auth/config') {
          capabilities++;
          return capabilities == 1
              ? http.Response('', 500)
              : http.Response(
                  '{"schema_version":1,"methods":["username_password"],"registration_enabled":false,"email_verification_required":false,"password_recovery_enabled":true,"session_logout_revokes_access":true}',
                  200,
                );
        }
        return http.Response('', 500);
      }),
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
    await tester.enterText(find.byKey(const Key('localSignInEmail')), 'nik');
    await tester.enterText(
      find.byKey(const Key('localSignInPassword')),
      'wrong',
    );
    final loginPassword = find.byKey(const Key('localSignInPassword'));
    final loginToggle = find.descendant(
      of: loginPassword,
      matching: find.byType(IconButton),
    );
    expect(tester.widget<TextField>(loginPassword).obscureText, isTrue);
    expect(tester.widget<IconButton>(loginToggle).tooltip, 'Show password');
    expect(tester.getSize(loginToggle).width, greaterThanOrEqualTo(44));
    final passwordController = tester
        .widget<TextField>(loginPassword)
        .controller!;
    final beforeToggle = passwordController.value;
    final focusBeforeToggle = FocusManager.instance.primaryFocus;
    await tester.tap(loginToggle);
    await tester.pump();
    expect(tester.widget<TextField>(loginPassword).obscureText, isFalse);
    expect(tester.widget<IconButton>(loginToggle).tooltip, 'Hide password');
    expect(passwordController.value, beforeToggle);
    expect(FocusManager.instance.primaryFocus, focusBeforeToggle);
    await tester.tap(loginToggle);
    await tester.pump();
    expect(tester.widget<TextField>(loginPassword).obscureText, isTrue);
    await tester.tap(find.text('Submit'));
    await tester.pumpAndSettle();
    expect(capabilities, 2);
    expect(session.credentialMethod, 'username_password');
    expect(find.text('Forgot password?'), findsOneWidget);
    expect(login?.body, contains('"username":"nik"'));
    expect(find.text('Invalid username or password.'), findsOneWidget);
    expect(
      tester
          .widget<TextField>(find.byKey(const Key('localSignInEmail')))
          .controller
          ?.text,
      'nik',
    );
    await tester.tap(find.text('Forgot password?'));
    await tester.pumpAndSettle();
    expect(find.text('User ID'), findsOneWidget);
    expect(find.text('Request reset link'), findsNothing);
    expect(find.byKey(const Key('recoveryUserId')), findsOneWidget);
    expect(
      tester
          .widget<TextField>(find.byKey(const Key('recoveryUserId')))
          .controller
          ?.text,
      'nik',
    );
    api.close();
    local.close();
  });

  testWidgets('User ID reset 204 signs in and leaves recovery route', (
    tester,
  ) async {
    const localConfig = CloudAuthConfig(
      issuer: '',
      audience: '',
      clientId: '',
      redirectUrl: '',
      apiUrl: 'https://api.example',
      localAuthEnabled: true,
    );
    var resets = 0;
    var logins = 0;
    final recoveryEvents = <String>[];
    final local = CloudLocalAuthClient(
      baseUrl: localConfig.apiUrl,
      client: MockClient((request) async {
        if (request.url.path == '/v1/auth/local/reset-password') {
          resets++;
          expect(jsonDecode(request.body), {
            'username': 'alice',
            'password': 'replacement password 123',
          });
          return http.Response('', 204);
        }
        if (request.url.path == '/v1/auth/local/login') {
          logins++;
          expect(jsonDecode(request.body), {
            'username': 'alice',
            'password': 'replacement password 123',
          });
          final expiry = DateTime.now().toUtc().add(
            const Duration(minutes: 15),
          );
          return http.Response(
            '{"token_type":"Bearer","access_token":"reset-access",'
            '"refresh_token":"reset-refresh",'
            '"access_expires_at":"${expiry.toIso8601String()}",'
            '"refresh_expires_at":"${expiry.add(const Duration(days: 30)).toIso8601String()}"}',
            200,
          );
        }
        return http.Response('', 404);
      }),
    );
    final store = Store()..tokens = null;
    final session = CloudSession(
      config: localConfig,
      store: store,
      authenticator: Auth(),
      localAuth: local,
    );
    final api = CloudApiClient(
      session: session,
      client: MockClient((request) async {
        if (request.url.path == '/v1/auth/config') {
          return http.Response(
            '{"schema_version":1,"methods":["username_password"],'
            '"registration_enabled":false,"email_verification_required":false,'
            '"password_recovery_enabled":true,"session_logout_revokes_access":true}',
            200,
          );
        }
        if (request.url.path == '/v1/me') {
          expect(request.headers['Authorization'], 'Bearer reset-access');
          return http.Response(
            '{"id":"$verifiedAccountId","username":"alice",'
            '"email_verified":true,"auth_method":"username_password",'
            '"display_name":"Alice"}',
            200,
          );
        }
        if (request.url.path == '/v1/homes') {
          return http.Response('{"homes":[]}', 200);
        }
        return http.Response('', 404);
      }),
    );
    await tester.pumpWidget(
      MaterialApp(
        home: CloudEntryGate(
          session: session,
          api: api,
          homeCreateStorage: MemoryDraftStorage(),
          activeHomeStorage: MemoryDraftStorage(),
          recoveryDiagnosticSink: recoveryEvents.add,
          homeBuilder: (_, _, _, _) => const Text('Private Home'),
        ),
      ),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.text('Forgot password?'));
    await tester.pumpAndSettle();
    await tester.enterText(find.byKey(const Key('recoveryUserId')), ' ALICE ');
    await tester.enterText(
      find.byKey(const Key('resetPassword')),
      'replacement password 123',
    );
    await tester.enterText(
      find.byKey(const Key('resetConfirm')),
      'replacement password 123',
    );
    await tester.ensureVisible(find.byKey(const Key('submitPasswordReset')));
    await tester.tap(find.byKey(const Key('submitPasswordReset')));
    await tester.pumpAndSettle();
    expect(resets, 1);
    expect(logins, 1);
    expect(store.tokens?.accessToken, 'reset-access');
    expect(find.byKey(const Key('recoveryUserId')), findsNothing);
    expect(find.text('Set up your home'), findsOneWidget);
    expect(
      recoveryEvents,
      containsAllInOrder([
        'reset_post_start',
        'reset_post_204',
        'reset_handoff_start',
        'handoff_login_start',
        'handoff_login_200',
        'handoff_validation_success',
        'handoff_route_pop',
      ]),
    );
    api.close();
    local.close();
  });

  for (final (label, status, body, invalidCredentials) in [
    ('401', 401, '', true),
    (
      'exact username 400',
      400,
      '{"code":"invalid_request","message":"invalid username or password"}',
      true,
    ),
    (
      'unrelated 400',
      400,
      '{"code":"invalid_request","message":"invalid JSON"}',
      false,
    ),
    ('500', 500, '', false),
    ('transport failure', null, '', false),
  ]) {
    testWidgets(
      'reset 204 with login $label records handoff failure and pops',
      (tester) async {
        const localConfig = CloudAuthConfig(
          issuer: '',
          audience: '',
          clientId: '',
          redirectUrl: '',
          apiUrl: 'https://api.example',
          localAuthEnabled: true,
        );
        final events = <String>[];
        var resets = 0;
        var logins = 0;
        final local = CloudLocalAuthClient(
          baseUrl: localConfig.apiUrl,
          client: MockClient((request) async {
            if (request.url.path == '/v1/auth/local/reset-password') {
              resets++;
              return http.Response('', 204);
            }
            if (request.url.path == '/v1/auth/local/login') {
              logins++;
              if (status == null) throw StateError('network unavailable');
              return http.Response(body, status);
            }
            return http.Response('', 404);
          }),
        );
        final session = CloudSession(
          config: localConfig,
          store: Store()..tokens = null,
          authenticator: Auth(),
          localAuth: local,
        );
        final api = CloudApiClient(
          session: session,
          client: MockClient((request) async {
            if (request.url.path == '/v1/auth/config') {
              return http.Response(
                '{"schema_version":1,"methods":["username_password"],'
                '"registration_enabled":false,"email_verification_required":false,'
                '"password_recovery_enabled":true,"session_logout_revokes_access":true}',
                200,
              );
            }
            return http.Response('', 404);
          }),
        );
        await tester.pumpWidget(
          MaterialApp(
            home: CloudEntryGate(
              session: session,
              api: api,
              homeCreateStorage: MemoryDraftStorage(),
              activeHomeStorage: MemoryDraftStorage(),
              recoveryDiagnosticSink: events.add,
              homeBuilder: (_, _, _, _) => const Text('Private Home'),
            ),
          ),
        );
        await tester.pumpAndSettle();
        await tester.tap(find.text('Forgot password?'));
        await tester.pumpAndSettle();
        await tester.enterText(
          find.byKey(const Key('recoveryUserId')),
          'alice',
        );
        await tester.enterText(
          find.byKey(const Key('resetPassword')),
          'replacement password 123',
        );
        await tester.enterText(
          find.byKey(const Key('resetConfirm')),
          'replacement password 123',
        );
        await tester.ensureVisible(
          find.byKey(const Key('submitPasswordReset')),
        );
        await tester.tap(find.byKey(const Key('submitPasswordReset')));
        await tester.pumpAndSettle();
        expect(resets, 1);
        expect(logins, 1);
        expect(find.byKey(const Key('recoveryUserId')), findsNothing);
        expect(
          find.text(
            invalidCredentials
                ? 'Invalid username or password.'
                : 'Internal Error, Try again later',
          ),
          findsOneWidget,
        );
        expect(
          events,
          containsAllInOrder([
            'reset_post_start',
            'reset_post_204',
            'handoff_login_start',
            status == null ? 'handoff_failure' : 'handoff_login_http_$status',
            'handoff_route_pop',
          ]),
        );
        expect(events.join(' '), isNot(contains('alice')));
        expect(events.join(' '), isNot(contains('replacement')));
        api.close();
        local.close();
      },
    );
  }
  testWidgets('native design builder receives gate-owned verified lifecycle', (
    tester,
  ) async {
    final session = CloudSession(
      config: config,
      store: Store(),
      authenticator: Auth(),
    );
    final coordinator = DesignContextCoordinator(RecordingDesignAdapters());
    final api = CloudApiClient(
      session: session,
      client: MockClient((request) async {
        if (request.url.path == '/v1/auth/config') {
          return http.Response('', 404);
        }
        if (request.url.path == '/v1/me') {
          return http.Response(
            '{"id":"$verifiedAccountId","email":null,"email_verified":true}',
            200,
          );
        }
        if (request.url.path == '/v1/me/preferences') {
          return http.Response(
            acceptedPreferences,
            200,
            headers: {'etag': '"1"'},
          );
        }
        return http.Response(ownedHomes(), 200);
      }),
    );
    final auxiliary = CloudAuxiliaryDomainLifecycle(
      drafts: DurableOnboardingDrafts(
        MemoryDraftStorage(),
        OnboardingPersistenceRepository(CloudOnboardingPersistenceSource(api)),
      ),
      reports: ReportPreviewDomainRepository(
        CloudReportPreviewDomainSource(api),
      ),
      deliveries: ReportDeliveryDomainAdapter(
        CloudReportDeliveryDomainSource(api),
      ),
    );
    final seenHomes = <(String, String)>[];
    await tester.pumpWidget(
      MaterialApp(
        home: CloudEntryGate(
          homeCreateStorage: MemoryDraftStorage(),
          activeHomeStorage: MemoryDraftStorage(),
          session: session,
          api: api,
          designContextCoordinator: coordinator,
          auxiliaryDomainLifecycle: auxiliary,
          homeBuilder: (_, _, _, _) => const Text('Preview home'),
          verifiedDesignHomeBuilder:
              (
                home,
                signOut,
                changeHome,
                receivedApi,
                lifecycle,
                receivedCoordinator,
              ) {
                expect(identical(receivedApi, api), isTrue);
                expect(identical(receivedCoordinator, coordinator), isTrue);
                expect(
                  receivedCoordinator.context?.accountId,
                  verifiedAccountId,
                );
                expect(receivedCoordinator.context?.homeId, home.id);
                expect(
                  lifecycle.isVerifiedScope(verifiedAccountId, home.id),
                  isTrue,
                );
                seenHomes.add((home.id, home.name));
                return Scaffold(
                  body: Column(
                    children: [
                      TextButton(
                        onPressed: changeHome,
                        child: const Text('Change selected home'),
                      ),
                      TextButton(
                        onPressed: signOut,
                        child: const Text('Sign out selected home'),
                      ),
                    ],
                  ),
                );
              },
          newHomeBuilder: (_, _, _, _) =>
              const Text('Unexpected new-home onboarding'),
        ),
      ),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.text('First home'));
    await tester.pumpAndSettle();
    expect(seenHomes, contains((firstHomeId, 'First home')));
    expect(find.text('Unexpected new-home onboarding'), findsNothing);
    await tester.tap(find.text('Change selected home'));
    expect(coordinator.context, isNull);
    await tester.pumpAndSettle();
    await tester.tap(find.text('Second home'));
    await tester.pumpAndSettle();
    expect(seenHomes, contains((secondHomeId, 'Second home')));
    expect(find.text('Unexpected new-home onboarding'), findsNothing);
    await tester.tap(find.text('Sign out selected home'));
    expect(coordinator.context, isNull);
    await tester.pumpAndSettle();
    expect(find.text('Submit'), findsOneWidget);
    api.close();
  });

  testWidgets('sign-in leaves cancellation quiet and reports failures', (
    tester,
  ) async {
    final failures = <(Object, String?)>[
      (
        FlutterAppAuthUserCancelledException(
          code: 'user_cancelled',
          platformErrorDetails: FlutterAppAuthPlatformErrorDetails(),
        ),
        null,
      ),
      (
        FlutterAppAuthPlatformException(
          code: 'discovery_failed',
          platformErrorDetails: FlutterAppAuthPlatformErrorDetails(),
        ),
        'Internal Error, Try again later',
      ),
      (StateError('unavailable'), 'Internal Error, Try again later'),
    ];
    for (final (failure, message) in failures) {
      final store = Store()..tokens = null;
      final session = CloudSession(
        config: config,
        store: store,
        authenticator: FailingAuth(failure),
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
            homeCreateStorage: MemoryDraftStorage(),
            activeHomeStorage: MemoryDraftStorage(),
            session: session,
            api: api,
            homeBuilder: (_, _, _, _) => const Text('Private Home'),
          ),
        ),
      );
      await tester.pumpAndSettle();
      await tester.tap(find.text('Submit'));
      await tester.pumpAndSettle();
      expect(
        find.text('Internal Error, Try again later'),
        message == null ? findsNothing : findsOneWidget,
      );
      expect(store.tokens, isNull);
      api.close();
      await tester.pumpWidget(const SizedBox.shrink());
    }
  });

  testWidgets('home entry proceeds without any disclosure step', (
    tester,
  ) async {
    final session = CloudSession(
      config: config,
      store: Store(),
      authenticator: Auth(),
    );
    var homesRequests = 0;
    final api = CloudApiClient(
      session: session,
      client: MockClient((request) async {
        switch (request.url.path) {
          case '/v1/auth/config':
            return http.Response('', 404);
          case '/v1/me':
            return http.Response(
              '{"id":"account-1","email":null,"email_verified":true}',
              200,
            );
          case '/v1/me/preferences':
            return http.Response(
              '{"version":1,"schema_version":1,"email_reports_enabled":false}',
              200,
              headers: {'etag': '"1"'},
            );
          case '/v1/homes':
            homesRequests++;
            return http.Response('{"homes":[]}', 200);
        }
        return http.Response('', 404);
      }),
    );
    await tester.pumpWidget(
      MaterialApp(
        home: CloudEntryGate(
          homeCreateStorage: MemoryDraftStorage(),
          activeHomeStorage: MemoryDraftStorage(),
          session: session,
          api: api,
          homeBuilder: (_, _, _, _) => const Text('Private Home'),
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.text('Set up your home'), findsOneWidget);
    expect(homesRequests, 1);
    api.close();
  });

  testWidgets('restart with owned home discards pending first-home draft', (
    tester,
  ) async {
    final drafts = MemoryDraftStorage()..value = pendingFirstHomeDraft();
    final session = CloudSession(
      config: config,
      store: Store(),
      authenticator: Auth(),
    );
    var homeCreates = 0;
    final api = CloudApiClient(
      session: session,
      client: MockClient((request) async {
        if (request.url.path == '/v1/auth/config') {
          return http.Response('', 404);
        }
        if (request.url.path == '/v1/me') {
          return http.Response(
            '{"id":"$verifiedAccountId","email":null,"email_verified":true,"display_name":"Alex"}',
            200,
          );
        }
        if (request.url.path == '/v1/homes' && request.method == 'GET') {
          return http.Response(ownedHomes(), 200);
        }
        if (request.url.path == '/v1/homes' && request.method == 'POST') {
          homeCreates++;
          return http.Response('', 500);
        }
        return http.Response('', 404);
      }),
    );
    await tester.pumpWidget(
      MaterialApp(
        home: CloudEntryGate(
          homeCreateStorage: drafts,
          activeHomeStorage: MemoryDraftStorage(),
          session: session,
          api: api,
          homeBuilder: (_, _, _, _) => const Text('Private Home'),
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(homeCreates, 0);
    expect(drafts.value, isNull);
    expect(find.text('First home'), findsOneWidget);
    api.close();
  });

  testWidgets('restart with no owned home retries pending first-home draft', (
    tester,
  ) async {
    final drafts = MemoryDraftStorage()..value = pendingFirstHomeDraft();
    final session = CloudSession(
      config: config,
      store: Store(),
      authenticator: Auth(),
    );
    const pendingHome =
        '{"id":"$firstHomeId","name":"Pending home","timezone":"America/Chicago","location":{"country_code":"US","postal_code":"60601"}}';
    var homeCreates = 0;
    final api = CloudApiClient(
      session: session,
      client: MockClient((request) async {
        if (request.url.path == '/v1/auth/config') {
          return http.Response('', 404);
        }
        if (request.url.path == '/v1/me') {
          return http.Response(
            '{"id":"$verifiedAccountId","email":null,"email_verified":true,"display_name":"Alex"}',
            200,
          );
        }
        if (request.url.path == '/v1/homes' && request.method == 'GET') {
          return http.Response(
            '{"homes":${homeCreates == 0 ? '[]' : '[$pendingHome]'}}',
            200,
          );
        }
        if (request.url.path == '/v1/homes' && request.method == 'POST') {
          homeCreates++;
          expect(
            request.headers['idempotency-key'],
            '33333333-3333-4333-8333-333333333333',
          );
          return http.Response(pendingHome, 201);
        }
        return http.Response('', 404);
      }),
    );
    await tester.pumpWidget(
      MaterialApp(
        home: CloudEntryGate(
          homeCreateStorage: drafts,
          activeHomeStorage: MemoryDraftStorage(),
          session: session,
          api: api,
          homeBuilder: (_, _, _, _) => const Text('Private Home'),
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(homeCreates, 1);
    expect(drafts.value, isNull);
    expect(find.text('Pending home'), findsOneWidget);
    api.close();
  });

  testWidgets('first-home route commits versioned profile before home', (
    tester,
  ) async {
    tester.binding.platformDispatcher.localeTestValue = const Locale(
      'en',
      'US',
    );
    addTearDown(tester.binding.platformDispatcher.clearLocaleTestValue);
    tester.view.physicalSize = const Size(800, 1400);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final session = CloudSession(
      config: config,
      store: Store(),
      authenticator: Auth(),
    );
    var profileAttempts = 0;
    var homeCreates = 0;
    var homesReads = 0;
    var ownerSaved = false;
    String profileBody() =>
        '{"id":"$verifiedAccountId","email":null,'
        '"email_verified":true,"display_name":${ownerSaved ? '"Alex"' : 'null'}}';
    final homeBody =
        '{"id":"$firstHomeId","name":"New home",'
        '"timezone":"America/Chicago",'
        '"location":{"country_code":"US","postal_code":"60601"}}';
    final api = CloudApiClient(
      session: session,
      client: MockClient((request) async {
        if (request.url.path == '/v1/auth/config') {
          return http.Response('', 404);
        }
        if (request.url.path == '/v1/me' && request.method == 'GET') {
          return http.Response(profileBody(), 200, headers: {'etag': '"1"'});
        }
        if (request.url.path == '/v1/me/profile') {
          expect(request.headers['if-match'], '"1"');
          expect(request.headers['idempotency-key'], isNotEmpty);
          profileAttempts++;
          if (profileAttempts == 1) return http.Response('', 503);
          ownerSaved = true;
          return http.Response(profileBody(), 200, headers: {'etag': '"2"'});
        }
        if (request.url.path == '/v1/homes' && request.method == 'GET') {
          homesReads++;
          return http.Response(
            '{"homes":${homeCreates == 0 ? '[]' : '[$homeBody]'}}',
            200,
          );
        }
        if (request.url.path == '/v1/homes' && request.method == 'POST') {
          expect(ownerSaved, isTrue);
          homeCreates++;
          return http.Response(homeBody, 201);
        }
        return http.Response('', 404);
      }),
    );
    final auxiliary = CloudAuxiliaryDomainLifecycle(
      drafts: DurableOnboardingDrafts(
        MemoryDraftStorage(),
        OnboardingPersistenceRepository(CloudOnboardingPersistenceSource(api)),
      ),
      reports: ReportPreviewDomainRepository(
        CloudReportPreviewDomainSource(api),
      ),
      deliveries: ReportDeliveryDomainAdapter(
        CloudReportDeliveryDomainSource(api),
      ),
    );
    VoidCallback? finishNewHome;
    await tester.pumpWidget(
      MaterialApp(
        home: CloudEntryGate(
          homeCreateStorage: MemoryDraftStorage(),
          activeHomeStorage: MemoryDraftStorage(),
          auxiliaryDomainLifecycle: auxiliary,
          session: session,
          api: api,
          homeBuilder: (home, _, _, _) => Text('Verified ${home?.name}'),
          newHomeBuilder: (home, receivedApi, lifecycle, onLinked) {
            expect(home.id, firstHomeId);
            expect(identical(receivedApi, api), isTrue);
            expect(
              lifecycle.isVerifiedScope(verifiedAccountId, home.id),
              isTrue,
            );
            finishNewHome = onLinked;
            return const Text('Hub discovery');
          },
        ),
      ),
    );
    await tester.pumpAndSettle();
    await tester.enterText(find.byKey(const Key('setupOwnerName')), 'Alex');
    await tester.enterText(find.byKey(const Key('setupHomeName')), 'New home');
    await tester.enterText(find.byKey(const Key('setupPostalCode')), 'bad');
    await tester.tap(find.text('Continue'));
    await tester.pumpAndSettle();
    await tester.enterText(find.byKey(const Key('setupCountry')), 'US');
    await tester.enterText(find.byKey(const Key('setupPostalCode')), '60601');
    await tester.ensureVisible(find.text('Continue'));
    await tester.tap(find.text('Continue'));
    await tester.pumpAndSettle();
    expect(profileAttempts, 1);
    expect(homeCreates, 0);
    await tester.tap(find.text('Continue'));
    await tester.pumpAndSettle();
    expect(profileAttempts, 2);
    expect(homeCreates, 1);
    expect(homesReads, greaterThanOrEqualTo(2));
    await tester.pump(const Duration(milliseconds: 100));
    await tester.pumpAndSettle();
    expect(find.text('Hub discovery'), findsOneWidget);
    expect(find.text('Verified New home'), findsNothing);
    finishNewHome!();
    await tester.pumpAndSettle();
    expect(find.text('Verified New home'), findsOneWidget);
    api.close();
  });

  testWidgets('404 account route keeps Home closed', (tester) async {
    final session = CloudSession(
      config: config,
      store: Store(),
      authenticator: Auth(),
    );
    final api = CloudApiClient(
      session: session,
      client: MockClient((_) async => http.Response('', 404)),
    );
    await tester.pumpWidget(
      MaterialApp(
        home: CloudEntryGate(
          homeCreateStorage: MemoryDraftStorage(),
          activeHomeStorage: MemoryDraftStorage(),
          session: session,
          api: api,
          homeBuilder: (_, _, _, _) => const Text('Private Home'),
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.text('Private Home'), findsNothing);
    expect(find.text('User ID'), findsOneWidget);
    expect(find.text('Password'), findsOneWidget);
    expect(find.text('Submit'), findsOneWidget);
    expect(find.text('Internal Error, Try again later'), findsOneWidget);
    api.close();
  });

  testWidgets('verified account opens Home and sign-out closes it', (
    tester,
  ) async {
    final store = Store();
    final session = CloudSession(
      config: config,
      store: store,
      authenticator: Auth(),
    );
    final api = CloudApiClient(
      session: session,
      client: MockClient((request) async {
        if (request.url.path == '/v1/auth/config') {
          return http.Response('', 404);
        }
        if (request.url.path == '/v1/me/preferences') {
          return http.Response(
            '{"version":1,"schema_version":1,"email_reports_enabled":false}',
            200,
            headers: {'etag': '"1"'},
          );
        }
        if (request.url.path == '/v1/me') {
          return http.Response(
            '{"id":"account-1","email":null,"email_verified":true}',
            200,
          );
        }
        return http.Response(
          '{"homes":[{"id":"home-1","name":"Main home","timezone":"America/Chicago","location":{"country_code":"US","postal_code":"60601"}}]}',
          200,
        );
      }),
    );
    await tester.pumpWidget(
      MaterialApp(
        home: CloudEntryGate(
          homeCreateStorage: MemoryDraftStorage(),
          activeHomeStorage: MemoryDraftStorage(),
          session: session,
          api: api,
          homeBuilder: (_, signOut, _, _) => Scaffold(
            body: TextButton(
              onPressed: signOut,
              child: const Text('Private Home'),
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.text('Private Home'), findsNothing);
    expect(find.text('Main home'), findsOneWidget);
    await tester.tap(find.text('Main home'));
    await tester.pumpAndSettle();
    expect(find.text('Private Home'), findsOneWidget);
    await tester.tap(find.text('Private Home'));
    await tester.pumpAndSettle();
    expect(store.tokens, isNull);
    expect(find.text('Submit'), findsOneWidget);
    api.close();
  });

  testWidgets('remembered home opens dashboard without new-home onboarding', (
    tester,
  ) async {
    final active = MemoryDraftStorage();
    final preference = ActiveHomePreference(active);
    await preference.selectScope(
      Uri.parse(config.apiUrl).origin,
      verifiedAccountId,
    );
    await preference.remember(
      const CloudHome(
        id: firstHomeId,
        name: 'First home',
        timezone: 'America/Chicago',
        countryCode: 'US',
        postalCode: '60601',
      ),
    );
    final session = CloudSession(
      config: config,
      store: Store(),
      authenticator: Auth(),
    );
    final api = CloudApiClient(
      session: session,
      client: MockClient((request) async {
        if (request.url.path == '/v1/auth/config') {
          return http.Response('', 404);
        }
        if (request.url.path == '/v1/me') {
          return http.Response(
            '{"id":"$verifiedAccountId","email":null,"email_verified":true}',
            200,
          );
        }
        if (request.url.path == '/v1/homes') {
          return http.Response(ownedHomes(), 200);
        }
        return http.Response('', 404);
      }),
    );
    final auxiliary = CloudAuxiliaryDomainLifecycle(
      drafts: DurableOnboardingDrafts(
        MemoryDraftStorage(),
        OnboardingPersistenceRepository(CloudOnboardingPersistenceSource(api)),
      ),
      reports: ReportPreviewDomainRepository(
        CloudReportPreviewDomainSource(api),
      ),
      deliveries: ReportDeliveryDomainAdapter(
        CloudReportDeliveryDomainSource(api),
      ),
    );
    await tester.pumpWidget(
      MaterialApp(
        home: CloudEntryGate(
          homeCreateStorage: MemoryDraftStorage(),
          activeHomeStorage: active,
          session: session,
          api: api,
          auxiliaryDomainLifecycle: auxiliary,
          homeBuilder: (home, _, _, _) => Text('Dashboard ${home?.name}'),
          newHomeBuilder: (_, _, _, _) =>
              const Text('Unexpected new-home onboarding'),
        ),
      ),
    );
    for (var i = 0; i < 20; i++) {
      await tester.pump(const Duration(milliseconds: 100));
      if (find.text('Dashboard First home').evaluate().isNotEmpty) break;
    }
    expect(
      find.text('Dashboard First home'),
      findsOneWidget,
      reason:
          '${active.value} ${tester.widgetList<Text>(find.byType(Text, skipOffstage: false)).map((text) => text.data).toList()}',
    );
    expect(find.text('Unexpected new-home onboarding'), findsNothing);
    api.close();
  });

  testWidgets('homes outage keeps local Home closed and offers refresh', (
    tester,
  ) async {
    final session = CloudSession(
      config: config,
      store: Store(),
      authenticator: Auth(),
    );
    final api = CloudApiClient(
      session: session,
      client: MockClient((request) async {
        if (request.url.path == '/v1/auth/config') {
          return http.Response('', 404);
        }
        if (request.url.path == '/v1/me/preferences') {
          return http.Response(
            '{"version":1,"schema_version":1,"email_reports_enabled":false}',
            200,
            headers: {'etag': '"1"'},
          );
        }
        if (request.url.path == '/v1/me') {
          return http.Response(
            '{"id":"account-1","email":null,"email_verified":true}',
            200,
          );
        }
        return http.Response('', 503);
      }),
    );
    await tester.pumpWidget(
      MaterialApp(
        home: CloudEntryGate(
          homeCreateStorage: MemoryDraftStorage(),
          activeHomeStorage: MemoryDraftStorage(),
          session: session,
          api: api,
          homeBuilder: (_, _, _, _) => const Text('Private Home'),
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.text('Private Home'), findsNothing);
    expect(find.byKey(const Key('homeListError')), findsOneWidget);
    expect(find.text('Refresh homes'), findsOneWidget);
    api.close();
  });

  testWidgets('a rejected homes refresh clears the account home list', (
    tester,
  ) async {
    final store = Store();
    var homesRequests = 0;
    final session = CloudSession(
      config: config,
      store: store,
      authenticator: Auth(),
    );
    final api = CloudApiClient(
      session: session,
      client: MockClient((request) async {
        if (request.url.path == '/v1/auth/config') {
          return http.Response('', 404);
        }
        if (request.url.path == '/v1/me/preferences') {
          return http.Response(
            '{"version":1,"schema_version":1,"email_reports_enabled":false}',
            200,
            headers: {'etag': '"1"'},
          );
        }
        if (request.url.path == '/v1/me') {
          return http.Response(
            '{"id":"account-1","email":null,"email_verified":true}',
            200,
          );
        }
        homesRequests++;
        return homesRequests == 1
            ? http.Response(
                '{"homes":[{"id":"home-1","name":"Main home","timezone":"America/Chicago","location":{"country_code":"US","postal_code":"60601"}}]}',
                200,
              )
            : http.Response('', 403);
      }),
    );
    await tester.pumpWidget(
      MaterialApp(
        home: CloudEntryGate(
          homeCreateStorage: MemoryDraftStorage(),
          activeHomeStorage: MemoryDraftStorage(),
          session: session,
          api: api,
          homeBuilder: (_, _, _, _) => const Text('Private Home'),
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.text('Main home'), findsOneWidget);
    await tester.tap(find.text('Refresh homes'));
    await tester.pumpAndSettle();
    expect(store.tokens, isNull);
    expect(find.text('Main home'), findsNothing);
    expect(find.text('Private Home'), findsNothing);
    expect(find.text('Your sign-in expired. Sign in again.'), findsOneWidget);
    api.close();
  });

  testWidgets('unverified account remains at the sign-in gate', (tester) async {
    final session = CloudSession(
      config: config,
      store: Store(),
      authenticator: Auth(),
    );
    final api = CloudApiClient(
      session: session,
      client: MockClient(
        (request) async => request.url.path == '/v1/auth/config'
            ? http.Response('', 404)
            : http.Response(
                '{"id":"account-1","email":"a@example.com","email_verified":false}',
                200,
              ),
      ),
    );
    await tester.pumpWidget(
      MaterialApp(
        home: CloudEntryGate(
          homeCreateStorage: MemoryDraftStorage(),
          activeHomeStorage: MemoryDraftStorage(),
          session: session,
          api: api,
          homeBuilder: (_, _, _, _) => const Text('Private Home'),
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.text('Private Home'), findsNothing);
    expect(
      find.text('Verify your email address before continuing.'),
      findsOneWidget,
    );
    api.close();
  });

  testWidgets('verified owned home binds; switch and sign-out clear context', (
    tester,
  ) async {
    final store = Store();
    final session = CloudSession(
      config: config,
      store: store,
      authenticator: Auth(),
    );
    final adapters = RecordingDesignAdapters();
    final coordinator = DesignContextCoordinator(adapters);
    final api = CloudApiClient(
      session: session,
      client: MockClient((request) async {
        if (request.url.path == '/v1/auth/config') {
          return http.Response('', 404);
        }
        if (request.url.path == '/v1/me') {
          return http.Response(
            '{"id":"$verifiedAccountId","email":null,"email_verified":true}',
            200,
          );
        }
        if (request.url.path == '/v1/me/preferences') {
          return http.Response(
            acceptedPreferences,
            200,
            headers: {'etag': '"1"'},
          );
        }
        return http.Response(ownedHomes(), 200);
      }),
    );
    final draftStorage = MemoryDraftStorage();
    final auxiliary = CloudAuxiliaryDomainLifecycle(
      drafts: DurableOnboardingDrafts(
        draftStorage,
        OnboardingPersistenceRepository(CloudOnboardingPersistenceSource(api)),
      ),
      reports: ReportPreviewDomainRepository(
        CloudReportPreviewDomainSource(api),
      ),
      deliveries: ReportDeliveryDomainAdapter(
        CloudReportDeliveryDomainSource(api),
      ),
    );
    await tester.pumpWidget(
      MaterialApp(
        home: CloudEntryGate(
          homeCreateStorage: MemoryDraftStorage(),
          activeHomeStorage: MemoryDraftStorage(),
          session: session,
          api: api,
          designContextCoordinator: coordinator,
          auxiliaryDomainLifecycle: auxiliary,
          homeBuilder: (_, signOut, changeHome, _) => Scaffold(
            body: Column(
              children: [
                TextButton(
                  onPressed: changeHome,
                  child: const Text('Switch home'),
                ),
                TextButton(onPressed: signOut, child: const Text('Leave home')),
              ],
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(coordinator.context, isNull);
    await tester.tap(find.text('First home'));
    await tester.pumpAndSettle();
    expect(coordinator.context?.accountId, verifiedAccountId);
    expect(coordinator.context?.homeId, firstHomeId);
    expect(
      coordinator.context?.dataPolicy,
      DesignDataPolicy.sameHomeDemoFallback,
    );
    expect(auxiliary.verifiedHomeId, firstHomeId);
    await auxiliary.drafts.stage(
      const OnboardingDraft(
        name: 'Fridge',
        category: 'refrigerator',
        brand: 'Acme',
        fullModel: 'A123',
        fuel: 'electricity',
      ),
    );
    await tester.tap(find.text('Switch home'));
    await tester.pumpAndSettle();
    expect(coordinator.context, isNull);
    expect(auxiliary.verifiedHomeId, isNull);
    await tester.tap(find.text('Second home'));
    await tester.pumpAndSettle();
    expect(coordinator.context?.homeId, secondHomeId);
    expect(auxiliary.verifiedHomeId, secondHomeId);
    expect(await auxiliary.drafts.restore(), isNull);
    await tester.tap(find.text('Leave home'));
    await tester.pumpAndSettle();
    expect(coordinator.context, isNull);
    expect(auxiliary.verifiedHomeId, isNull);
    expect(draftStorage.value, isNull);
    expect(store.tokens, isNull);
    expect(adapters.clears, greaterThanOrEqualTo(4));
    api.close();
  });

  testWidgets('late owned homes response cannot bind after sign-out', (
    tester,
  ) async {
    final delayedHomes = Completer<http.Response>();
    final session = CloudSession(
      config: config,
      store: Store(),
      authenticator: Auth(),
    );
    final coordinator = DesignContextCoordinator(RecordingDesignAdapters());
    final api = CloudApiClient(
      session: session,
      client: MockClient((request) async {
        if (request.url.path == '/v1/auth/config') {
          return http.Response('', 404);
        }
        if (request.url.path == '/v1/me') {
          return http.Response(
            '{"id":"account-1","email":null,"email_verified":true}',
            200,
          );
        }
        if (request.url.path == '/v1/me/preferences') {
          return http.Response(
            acceptedPreferences,
            200,
            headers: {'etag': '"1"'},
          );
        }
        return delayedHomes.future;
      }),
    );
    await tester.pumpWidget(
      MaterialApp(
        home: CloudEntryGate(
          homeCreateStorage: MemoryDraftStorage(),
          activeHomeStorage: MemoryDraftStorage(),
          session: session,
          api: api,
          designContextCoordinator: coordinator,
          homeBuilder: (_, _, _, _) => const Text('Private Home'),
        ),
      ),
    );
    await tester.pump();
    await tester.pump();
    await tester.tap(find.byTooltip('Sign out'));
    await tester.pump();
    delayedHomes.complete(http.Response(ownedHomes(), 200));
    await tester.pumpAndSettle();
    expect(coordinator.context, isNull);
    expect(find.text('First home'), findsNothing);
    api.close();
  });

  testWidgets('malformed or unowned home IDs never enter design context', (
    tester,
  ) async {
    final session = CloudSession(
      config: config,
      store: Store(),
      authenticator: Auth(),
    );
    final coordinator = DesignContextCoordinator(RecordingDesignAdapters());
    final api = CloudApiClient(
      session: session,
      client: MockClient((request) async {
        if (request.url.path == '/v1/auth/config') {
          return http.Response('', 404);
        }
        if (request.url.path == '/v1/me') {
          return http.Response(
            '{"id":"account-1","email":null,"email_verified":true}',
            200,
          );
        }
        if (request.url.path == '/v1/me/preferences') {
          return http.Response(
            acceptedPreferences,
            200,
            headers: {'etag': '"1"'},
          );
        }
        return http.Response(ownedHomes('not-a-uuid'), 200);
      }),
    );
    await tester.pumpWidget(
      MaterialApp(
        home: CloudEntryGate(
          homeCreateStorage: MemoryDraftStorage(),
          activeHomeStorage: MemoryDraftStorage(),
          session: session,
          api: api,
          designContextCoordinator: coordinator,
          homeBuilder: (_, _, _, _) => const Text('Private Home'),
        ),
      ),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.text('Second home'));
    await tester.pumpAndSettle();
    expect(coordinator.context, isNull);
    api.close();
  });
}
