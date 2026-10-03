import 'package:energylens_mobile/core/cloud_api/cloud_api_client.dart';
import 'package:energylens_mobile/core/cloud_auth/cloud_auth.dart';
import 'package:energylens_mobile/core/cloud_auth/cloud_entry_gate.dart';
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

class _Registration implements CloudRegistrationService {
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
}

class _Store implements CloudTokenStore {
  int saves = 0;
  @override
  Future<void> clear() async {}
  @override
  Future<CloudTokens?> read() async => null;
  @override
  Future<void> save(CloudTokens tokens) async => saves++;
}

class _Auth implements CloudAuthenticator {
  @override
  Future<CloudTokens> signIn(CloudAuthConfig config) async =>
      const CloudTokens(accessToken: 'token');
  @override
  Future<CloudTokens> refresh(CloudAuthConfig config, String token) async =>
      const CloudTokens(accessToken: 'token');
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
      client: MockClient((_) async => http.Response('', 500)),
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
    expect(find.text('Sign in'), findsOneWidget);
    expect(find.text('Create account'), findsNothing);
    expect(store.saves, 0);
    api.close();
  });

  testWidgets('injected flow validates and accepts without signing in', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(390, 844);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final registration = _Registration();
    final store = _Store();
    final session = CloudSession(
      config: _config,
      store: store,
      authenticator: _Auth(),
    );
    final api = CloudApiClient(
      session: session,
      client: MockClient((_) async => http.Response('', 500)),
    );
    await tester.pumpWidget(
      MaterialApp(
        home: CloudEntryGate(
          session: session,
          api: api,
          registrationService: registration,
          homeBuilder: (_, _, _, _) => const Text('Private Home'),
        ),
      ),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.text('Create account'));
    await tester.pumpAndSettle();
    expect(find.text('Request account'), findsOneWidget);
    expect(
      tester
          .widget<TextField>(find.byKey(const Key('registrationPassword')))
          .obscureText,
      isTrue,
    );
    await tester.tap(find.text('Request account'));
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
    await tester.ensureVisible(find.text('Request account'));
    await tester.tap(find.text('Request account'));
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
    await tester.tap(find.text('Request account'));
    await tester.pumpAndSettle();
    expect(registration.requests, 1);
    expect(find.byKey(const Key('registrationAccepted')), findsOneWidget);
    expect(
      find.textContaining('The request does not sign you in'),
      findsOneWidget,
    );
    expect(store.saves, 0);
    expect(find.text('Private Home'), findsNothing);
    await tester.tap(find.text('Verify email'));
    await tester.pumpAndSettle();
    expect(registration.verifications, 0);
    await Clipboard.setData(
      const ClipboardData(text: 'AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA'),
    );
    await tester.tap(find.byKey(const Key('pasteVerificationLink')));
    await tester.pumpAndSettle();
    expect((await Clipboard.getData('text/plain'))?.text, isEmpty);
    await tester.tap(find.text('Verify email'));
    await tester.pumpAndSettle();
    expect(registration.verifications, 1);
    expect(
      find.byKey(const Key('registrationVerificationSubmitted')),
      findsOneWidget,
    );
    expect(store.saves, 0);
    api.close();
  });

  testWidgets('registration failure reveals no backend detail', (tester) async {
    final registration = _Registration()..fail = true;
    await tester.pumpWidget(
      MaterialApp(home: CloudRegistrationScreen(service: registration)),
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
    await tester.ensureVisible(find.text('Request account'));
    await tester.tap(find.text('Request account'));
    await tester.pumpAndSettle();
    expect(
      find.text('Could not submit the request. Try again.'),
      findsOneWidget,
    );
    expect(find.textContaining('private backend detail'), findsNothing);
    expect(find.byKey(const Key('registrationAccepted')), findsNothing);
  });
}
