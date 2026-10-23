import 'dart:async';

import 'package:energylens_mobile/core/cloud_api/cloud_api_client.dart';
import 'package:energylens_mobile/core/cloud_auth/cloud_auth.dart';
import 'package:energylens_mobile/core/cloud_auth/cloud_entry_gate.dart';
import 'package:energylens_mobile/core/cloud_auth/cloud_local_auth.dart';
import 'package:energylens_mobile/features/identify/onboarding_draft_store.dart';
import 'package:energylens_mobile/core/cloud_auth/cloud_registration_screen.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter/services.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

const _config = CloudAuthConfig(
  issuer: 'https://issuer.example',
  audience: 'energylens-cloud',
  clientId: 'client',
  redirectUrl: 'io.energylens.app://login-callback',
  apiUrl: 'https://api.example',
);

class _DeferredRegistration implements CloudRegistrationService {
  final started = Completer<void>();
  final finish = Completer<void>();
  int requests = 0;
  @override
  Future<void> requestRegistration(String username, String password) async {
    requests++;
    started.complete();
    await finish.future;
  }

  @override
  Future<void> verifyEmail(String token) async {}
}

class _UsernameRegistration implements CloudRegistrationService {
  int requests = 0;
  String? lastUserId;
  Object? error;

  @override
  Future<void> requestRegistration(String username, String password) async {
    requests++;
    lastUserId = username;
    expect(password, 'correct long password');
    if (error != null) throw error!;
  }

  @override
  Future<void> verifyEmail(String token) async {}
}

class _Store implements CloudTokenStore {
  int saves = 0;
  CloudTokens? tokens;
  @override
  Future<void> clear() async => tokens = null;
  @override
  Future<CloudTokens?> read() async => tokens;
  @override
  Future<void> save(CloudTokens value) async {
    saves++;
    tokens = value;
  }
}

class _Auth implements CloudAuthenticator {
  @override
  Future<CloudTokens> signIn(CloudAuthConfig config) async =>
      const CloudTokens(accessToken: 'token');
  @override
  Future<CloudTokens> refresh(CloudAuthConfig config, String token) async =>
      const CloudTokens(accessToken: 'token');
}

class _DraftStorage implements OnboardingDraftStorage {
  String? value;
  @override
  Future<String?> read() async => value;
  @override
  Future<void> write(String data) async => value = data;
  @override
  Future<void> clear() async => value = null;
}

void main() {
  var clipboard = '';
  setUp(() {
    clipboard = '';
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(SystemChannels.platform, (call) async {
          if (call.method == 'Clipboard.setData') {
            clipboard = (call.arguments as Map)['text'] as String;
            return null;
          }
          if (call.method == 'Clipboard.getData') return {'text': clipboard};
          return null;
        });
  });
  tearDown(() {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(SystemChannels.platform, null);
  });

  testWidgets('registration is hidden without an injected capability', (
    tester,
  ) async {
    final store = _Store();
    final session = CloudSession(
      config: _config,
      store: store,
      authenticator: _Auth(),
    );
    final api = CloudApiClient(
      session: session,
      client: MockClient((_) async => http.Response('', 404)),
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
    expect(store.saves, 0);
    api.close();
  });

  testWidgets('email auth keeps login and recovery but exposes no signup', (
    tester,
  ) async {
    const config = CloudAuthConfig(
      issuer: '',
      audience: '',
      clientId: '',
      redirectUrl: '',
      apiUrl: 'https://api.example',
      localAuthEnabled: true,
    );
    final local = CloudLocalAuthClient(
      baseUrl: config.apiUrl,
      client: MockClient((_) async => http.Response('', 404)),
    );
    final session = CloudSession(
      config: config,
      store: _Store(),
      authenticator: _Auth(),
      localAuth: local,
    );
    final api = CloudApiClient(
      session: session,
      client: MockClient(
        (request) async => request.url.path == '/v1/auth/config'
            ? http.Response(
                '{"schema_version":1,"methods":["email_password"],'
                '"registration_enabled":true,"email_verification_required":false,'
                '"password_recovery_enabled":true,"session_logout_revokes_access":true}',
                200,
              )
            : http.Response('', 404),
      ),
    );
    await tester.pumpWidget(
      MaterialApp(
        home: CloudEntryGate(
          session: session,
          api: api,
          registrationService: _UsernameRegistration(),
          homeBuilder: (_, _, _, _) => const Text('Private Home'),
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.text('Email ID'), findsOneWidget);
    expect(find.text('Forgot password?'), findsOneWidget);
    expect(find.text('Create account'), findsNothing);
    api.close();
    local.close();
  });

  testWidgets(
    'User ID signup signs in only after registration and validates account',
    (tester) async {
      tester.view.physicalSize = const Size(390, 844);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      final registration = _UsernameRegistration();
      final store = _Store();
      final localAuth = CloudLocalAuthClient(
        baseUrl: 'https://api.example',
        client: MockClient((request) async {
          if (request.url.path != '/v1/auth/local/login') {
            return http.Response('', 404);
          }
          expect(request.body, contains('"username":"person"'));
          final expiry = DateTime.now().toUtc().add(
            const Duration(minutes: 15),
          );
          return http.Response(
            '{"token_type":"Bearer","access_token":"new-access",'
            '"refresh_token":"new-refresh",'
            '"access_expires_at":"${expiry.toIso8601String()}",'
            '"refresh_expires_at":"${expiry.add(const Duration(days: 30)).toIso8601String()}"}',
            200,
          );
        }),
      );
      final session = CloudSession(
        config: const CloudAuthConfig(
          issuer: '',
          audience: '',
          clientId: '',
          redirectUrl: '',
          apiUrl: 'https://api.example',
          localAuthEnabled: true,
        ),
        store: store,
        authenticator: _Auth(),
        localAuth: localAuth,
      );
      final api = CloudApiClient(
        session: session,
        client: MockClient((request) async {
          if (request.url.path == '/v1/auth/config') {
            return http.Response(
              '{"schema_version":1,"methods":["username_password"],'
              '"registration_enabled":true,"email_verification_required":false,'
              '"password_recovery_enabled":false,"session_logout_revokes_access":true}',
              200,
            );
          }
          if (request.url.path == '/v1/me') {
            expect(request.headers['Authorization'], 'Bearer new-access');
            return http.Response(
              '{"id":"aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa",'
              '"username":"person","email_verified":true,'
              '"auth_method":"username_password","display_name":null}',
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
            registrationService: registration,
            homeCreateStorage: _DraftStorage(),
            activeHomeStorage: _DraftStorage(),
            homeBuilder: (_, _, _, _) => const Text('Private Home'),
          ),
        ),
      );
      await tester.pumpAndSettle();
      await tester.tap(find.text('Create account'));
      await tester.pumpAndSettle();
      expect(
        find.widgetWithText(FilledButton, 'Create account'),
        findsOneWidget,
      );
      expect(
        tester
            .widget<TextField>(find.byKey(const Key('registrationPassword')))
            .obscureText,
        isTrue,
      );
      await tester.tap(find.widgetWithText(FilledButton, 'Create account'));
      await tester.pumpAndSettle();
      expect(registration.requests, 0);
      await tester.enterText(
        find.byKey(const Key('registrationUserId')),
        ' Person ',
      );
      await tester.enterText(
        find.byKey(const Key('registrationPassword')),
        'short',
      );
      await tester.enterText(
        find.byKey(const Key('registrationConfirm')),
        'short',
      );
      await tester.ensureVisible(
        find.widgetWithText(FilledButton, 'Create account'),
      );
      await tester.tap(find.widgetWithText(FilledButton, 'Create account'));
      await tester.pumpAndSettle();
      expect(registration.requests, 0);
      await tester.enterText(
        find.byKey(const Key('registrationPassword')),
        'correct long password',
      );
      await tester.enterText(
        find.byKey(const Key('registrationConfirm')),
        'correct long password',
      );
      await tester.tap(find.widgetWithText(FilledButton, 'Create account'));
      await tester.pumpAndSettle();
      expect(registration.requests, 1);
      expect(registration.lastUserId, 'person');
      expect(store.saves, 1);
      expect(store.tokens?.accessToken, 'new-access');
      expect(
        find.text('Set up your home'),
        findsOneWidget,
        reason: tester
            .widgetList<Text>(find.byType(Text))
            .map((item) => item.data)
            .toList()
            .toString(),
      );
      expect(find.text('Verify email'), findsNothing);
      api.close();
      localAuth.close();
    },
  );

  testWidgets('registration failure reveals no backend detail', (tester) async {
    final registration = _UsernameRegistration()
      ..error = StateError('private backend detail');
    await tester.pumpWidget(
      MaterialApp(home: CloudRegistrationScreen(service: registration)),
    );
    await tester.enterText(
      find.byKey(const Key('registrationUserId')),
      'person',
    );
    await tester.enterText(
      find.byKey(const Key('registrationPassword')),
      'correct long password',
    );
    await tester.enterText(
      find.byKey(const Key('registrationConfirm')),
      'correct long password',
    );
    await tester.ensureVisible(
      find.widgetWithText(FilledButton, 'Create account'),
    );
    await tester.tap(find.widgetWithText(FilledButton, 'Create account'));
    await tester.pumpAndSettle();
    expect(find.text('Internal Error, Try again later'), findsOneWidget);
    expect(find.textContaining('private backend detail'), findsNothing);
    expect(find.byKey(const Key('registrationUserId')), findsOneWidget);
    expect(
      tester
          .widget<TextField>(find.byKey(const Key('registrationPassword')))
          .controller!
          .text,
      isEmpty,
    );
  });

  testWidgets('ambiguous signup response cannot retry account creation', (
    tester,
  ) async {
    final registration = _UsernameRegistration()
      ..error = const CloudLocalAuthException(202);
    await tester.pumpWidget(
      MaterialApp(home: CloudRegistrationScreen(service: registration)),
    );
    await tester.enterText(
      find.byKey(const Key('registrationUserId')),
      'person',
    );
    await tester.enterText(
      find.byKey(const Key('registrationPassword')),
      'correct long password',
    );
    await tester.enterText(
      find.byKey(const Key('registrationConfirm')),
      'correct long password',
    );
    await tester.tap(find.widgetWithText(FilledButton, 'Create account'));
    await tester.pumpAndSettle();
    expect(registration.requests, 1);
    expect(
      tester
          .widget<TextField>(find.byKey(const Key('registrationUserId')))
          .controller!
          .text,
      'person',
    );
    expect(
      tester
          .widget<TextField>(find.byKey(const Key('registrationPassword')))
          .controller!
          .text,
      isEmpty,
    );
    expect(
      tester
          .widget<FilledButton>(
            find.widgetWithText(FilledButton, 'Create account'),
          )
          .onPressed,
      isNull,
    );
    expect(find.text('Verify email'), findsNothing);
  });

  testWidgets('duplicate after restart never signs in or retries', (
    tester,
  ) async {
    final service = _UsernameRegistration()
      ..error = const CloudLocalAuthException(202);
    var signIns = 0;
    Future<void> fillAndSubmit() async {
      await tester.enterText(
        find.byKey(const Key('registrationUserId')),
        'Alice',
      );
      await tester.enterText(
        find.byKey(const Key('registrationPassword')),
        'correct long password',
      );
      await tester.enterText(
        find.byKey(const Key('registrationConfirm')),
        'correct long password',
      );
      await tester.tap(find.widgetWithText(FilledButton, 'Create account'));
      await tester.pumpAndSettle();
    }

    Widget screen(Key key) => MaterialApp(
      key: key,
      home: CloudRegistrationScreen(
        service: service,
        onUsernameRegistered: (_, _) async {
          signIns++;
        },
      ),
    );
    await tester.pumpWidget(screen(const ValueKey('first')));
    await fillAndSubmit();
    expect(service.requests, 1);
    expect(signIns, 0);
    service.error = const CloudLocalAuthException(409);
    await tester.pumpWidget(screen(const ValueKey('restart')));
    await fillAndSubmit();
    expect(service.requests, 2);
    expect(signIns, 0);
    expect(
      tester
          .widget<FilledButton>(
            find.widgetWithText(FilledButton, 'Create account'),
          )
          .onPressed,
      isNull,
    );
  });

  testWidgets('double submit sends one registration and one login handoff', (
    tester,
  ) async {
    final service = _DeferredRegistration();
    var signIns = 0;
    await tester.pumpWidget(
      MaterialApp(
        home: CloudRegistrationScreen(
          service: service,
          onUsernameRegistered: (_, _) async {
            signIns++;
          },
        ),
      ),
    );
    await tester.enterText(
      find.byKey(const Key('registrationUserId')),
      'alice',
    );
    await tester.enterText(
      find.byKey(const Key('registrationPassword')),
      'correct long password',
    );
    await tester.enterText(
      find.byKey(const Key('registrationConfirm')),
      'correct long password',
    );
    final button = find.widgetWithText(FilledButton, 'Create account');
    await tester.tap(button);
    await tester.pump();
    await service.started.future;
    expect(tester.widget<FilledButton>(button).onPressed, isNull);
    await tester.tap(button);
    expect(service.requests, 1);
    service.finish.complete();
    await tester.pumpAndSettle();
    expect(signIns, 1);
  });

  testWidgets('canceled username signup never calls sign-in callback', (
    tester,
  ) async {
    final service = _DeferredRegistration();
    var signIns = 0;
    await tester.pumpWidget(
      MaterialApp(
        home: Builder(
          builder: (context) => Scaffold(
            body: TextButton(
              onPressed: () => Navigator.of(context).push(
                MaterialPageRoute<void>(
                  builder: (_) => CloudRegistrationScreen(
                    service: service,
                    onUsernameRegistered: (_, _) async {
                      signIns++;
                    },
                  ),
                ),
              ),
              child: const Text('Open'),
            ),
          ),
        ),
      ),
    );
    await tester.tap(find.text('Open'));
    await tester.pumpAndSettle();
    await tester.enterText(
      find.byKey(const Key('registrationUserId')),
      'alice',
    );
    await tester.enterText(
      find.byKey(const Key('registrationPassword')),
      'correct long password',
    );
    await tester.enterText(
      find.byKey(const Key('registrationConfirm')),
      'correct long password',
    );
    await tester.tap(find.widgetWithText(FilledButton, 'Create account'));
    await tester.pump();
    await service.started.future;
    await tester.pageBack();
    await tester.pumpAndSettle();
    service.finish.complete();
    await tester.pumpAndSettle();
    expect(signIns, 0);
  });
}
