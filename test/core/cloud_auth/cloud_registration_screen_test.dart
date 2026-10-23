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

class _Registration
    implements CloudRegistrationService, AuthenticatedCloudRegistrationService {
  int requests = 0;
  int verifications = 0;
  bool fail = false;

  @override
  Future<void> requestRegistration(String email, String password) async {
    requests++;
    expect(email, 'person@example.com');
    expect(password, 'correct long password');
    if (fail) throw StateError('private backend detail');
  }

  @override
  Future<void> verifyEmail(String token) async {
    verifications++;
    expect(token, 'AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA');
  }

  @override
  Future<CloudTokens> registerSession(String email, String password) async {
    await requestRegistration(email, password);
    return CloudTokens(
      accessToken: 'new-access',
      refreshToken: 'new-refresh',
      expiresAt: DateTime.now().add(const Duration(minutes: 15)),
      refreshExpiresAt: DateTime.now().add(const Duration(days: 30)),
      provider: 'local',
    );
  }
}

class _DeferredRegistration implements CloudRegistrationService {
  final started = Completer<void>();
  final finish = Completer<void>();
  @override
  Future<void> requestRegistration(String username, String password) async {
    started.complete();
    await finish.future;
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

  testWidgets('email signup stores a session and validates account', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(390, 844);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final registration = _Registration();
    final store = _Store();
    final localAuth = CloudLocalAuthClient(
      baseUrl: 'https://api.example',
      client: MockClient((_) async => http.Response('', 404)),
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
            '{"schema_version":1,"methods":["email_password"],'
            '"registration_enabled":true,"email_verification_required":false,'
            '"password_recovery_enabled":false,"session_logout_revokes_access":true}',
            200,
          );
        }
        if (request.url.path == '/v1/me') {
          expect(request.headers['Authorization'], 'Bearer new-access');
          return http.Response(
            '{"id":"aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa",'
            '"email":"person@example.com","email_verified":false,'
            '"auth_method":"email_password","display_name":null}',
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
    expect(find.widgetWithText(FilledButton, 'Create account'), findsOneWidget);
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
      find.byKey(const Key('registrationEmail')),
      'person@example.com',
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
  });

  testWidgets('registration failure reveals no backend detail', (tester) async {
    final registration = _Registration()..fail = true;
    await tester.pumpWidget(
      MaterialApp(
        home: CloudRegistrationScreen(
          service: registration,
          onEmailRegister: (email, password) =>
              registration.registerSession(email, password).then((_) {}),
        ),
      ),
    );
    await tester.enterText(
      find.byKey(const Key('registrationEmail')),
      'person@example.com',
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
    expect(find.byKey(const Key('registrationEmail')), findsOneWidget);
    expect(
      tester
          .widget<TextField>(find.byKey(const Key('registrationPassword')))
          .controller!
          .text,
      isEmpty,
    );
  });

  testWidgets('generic accepted response cannot retry account creation', (
    tester,
  ) async {
    var attempts = 0;
    await tester.pumpWidget(
      MaterialApp(
        home: CloudRegistrationScreen(
          service: _Registration(),
          onEmailRegister: (_, _) async {
            attempts++;
            throw const CloudLocalAuthException(202);
          },
        ),
      ),
    );
    await tester.enterText(
      find.byKey(const Key('registrationEmail')),
      'person@example.com',
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
    expect(attempts, 1);
    expect(
      tester
          .widget<TextField>(find.byKey(const Key('registrationEmail')))
          .controller!
          .text,
      'person@example.com',
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
                    usernameMode: true,
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
    await tester.enterText(find.byKey(const Key('registrationEmail')), 'alice');
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
