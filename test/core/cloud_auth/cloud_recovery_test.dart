import 'dart:async';
import 'dart:convert';

import 'package:energylens_mobile/core/cloud_auth/cloud_auth_link.dart';
import 'package:energylens_mobile/core/cloud_auth/cloud_local_auth.dart';
import 'package:energylens_mobile/core/cloud_auth/cloud_recovery_screen.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

const _token = 'AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA';
const _origin = 'https://account.example';

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

  testWidgets('blank and invalid User ID errors stay visible with keyboard', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(390, 650);
    tester.view.devicePixelRatio = 1;
    tester.view.viewInsets = const FakeViewPadding(bottom: 260);
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    addTearDown(tester.view.resetViewInsets);
    var requests = 0;
    final client = CloudLocalAuthClient(
      baseUrl: 'https://api.example',
      client: MockClient((_) async {
        requests++;
        return http.Response('', 204);
      }),
    )..credentialMethod = 'username_password';
    for (final identity in ['', 'alice@example.com']) {
      await tester.pumpWidget(
        MaterialApp(
          key: ValueKey(identity),
          home: CloudRecoveryScreen(service: client, usernameMode: true),
        ),
      );
      if (identity.isNotEmpty) {
        await tester.enterText(
          find.byKey(const Key('recoveryUserId')),
          identity,
        );
      }
      await tester.enterText(
        find.byKey(const Key('resetPassword')),
        'replacement password 123',
      );
      await tester.enterText(
        find.byKey(const Key('resetConfirm')),
        'replacement password 123',
      );
      await tester.testTextInput.receiveAction(TextInputAction.done);
      await tester.pumpAndSettle();
      final error = find.byKey(const Key('recoveryError'));
      final submit = find.byKey(const Key('submitPasswordReset'));
      expect(requests, 0);
      expect(
        find.text('Could not reset the password. Try again later.'),
        findsOneWidget,
      );
      final semantics = tester.ensureSemantics();
      expect(tester.getSemantics(error).flagsCollection.isLiveRegion, isTrue);
      semantics.dispose();
      expect(
        tester.getBottomLeft(error).dy,
        lessThan(tester.getTopLeft(submit).dy),
      );
      expect(tester.getBottomLeft(error).dy, lessThan(390));
    }
    client.close();
  });

  testWidgets('short and mismatched passwords show visible errors', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(390, 650);
    tester.view.devicePixelRatio = 1;
    tester.view.viewInsets = const FakeViewPadding(bottom: 260);
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    addTearDown(tester.view.resetViewInsets);
    var requests = 0;
    final client = CloudLocalAuthClient(
      baseUrl: 'https://api.example',
      client: MockClient((_) async {
        requests++;
        return http.Response('', 204);
      }),
    )..credentialMethod = 'username_password';
    for (final password in ['short', 'replacement password 123']) {
      await tester.pumpWidget(
        MaterialApp(
          key: ValueKey(password),
          home: CloudRecoveryScreen(service: client, usernameMode: true),
        ),
      );
      await tester.enterText(find.byKey(const Key('recoveryUserId')), 'alice');
      await tester.enterText(find.byKey(const Key('resetPassword')), password);
      await tester.enterText(
        find.byKey(const Key('resetConfirm')),
        password == 'short' ? 'short' : 'different long password',
      );
      await tester.ensureVisible(find.byKey(const Key('submitPasswordReset')));
      await tester.tap(find.byKey(const Key('submitPasswordReset')));
      await tester.pumpAndSettle();
      final error = find.byKey(const Key('recoveryError'));
      expect(requests, 0);
      expect(
        find.text('Enter a matching new password of at least 12 characters.'),
        findsOneWidget,
      );
      expect(tester.getBottomLeft(error).dy, lessThan(390));
    }
    client.close();
  });

  testWidgets('reset 400 and timeout errors remain visible', (tester) async {
    tester.view.physicalSize = const Size(390, 650);
    tester.view.devicePixelRatio = 1;
    tester.view.viewInsets = const FakeViewPadding(bottom: 260);
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    addTearDown(tester.view.resetViewInsets);
    for (final status in [400, 408]) {
      final client = CloudLocalAuthClient(
        baseUrl: 'https://api.example',
        client: MockClient((_) async {
          if (status == 408) throw TimeoutException('slow');
          return http.Response('', status);
        }),
      )..credentialMethod = 'username_password';
      await tester.pumpWidget(
        MaterialApp(
          key: ValueKey(status),
          home: CloudRecoveryScreen(service: client, usernameMode: true),
        ),
      );
      await tester.enterText(find.byKey(const Key('recoveryUserId')), 'alice');
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
      final error = find.byKey(const Key('recoveryError'));
      expect(
        find.text(
          status == 400
              ? 'Could not reset the password. Try again later.'
              : 'Internal Error, Try again later',
        ),
        findsOneWidget,
      );
      expect(tester.getBottomLeft(error).dy, lessThan(390));
      client.close();
    }
  });

  testWidgets('busy reset prevents duplicate submit through login handoff', (
    tester,
  ) async {
    final response = Completer<http.Response>();
    final loginHandoff = Completer<void>();
    var requests = 0;
    var handoffs = 0;
    final client = CloudLocalAuthClient(
      baseUrl: 'https://api.example',
      client: MockClient((_) {
        requests++;
        return response.future;
      }),
    )..credentialMethod = 'username_password';
    await tester.pumpWidget(
      MaterialApp(
        home: CloudRecoveryScreen(
          service: client,
          usernameMode: true,
          onResetSuccess: (_, _) {
            handoffs++;
            return loginHandoff.future;
          },
        ),
      ),
    );
    await tester.enterText(find.byKey(const Key('recoveryUserId')), 'alice');
    await tester.enterText(
      find.byKey(const Key('resetPassword')),
      'replacement password 123',
    );
    await tester.enterText(
      find.byKey(const Key('resetConfirm')),
      'replacement password 123',
    );
    final submit = find.byKey(const Key('submitPasswordReset'));
    await tester.ensureVisible(submit);
    await tester.tap(submit);
    await tester.pump();
    expect(requests, 1);
    expect(tester.widget<FilledButton>(submit).onPressed, isNull);
    expect(find.byType(CircularProgressIndicator), findsOneWidget);
    await tester.tap(submit);
    expect(requests, 1);
    response.complete(http.Response('', 204));
    await tester.pump();
    expect(handoffs, 1);
    expect(find.byType(CircularProgressIndicator), findsOneWidget);
    loginHandoff.complete();
    await tester.pumpAndSettle();
    expect(find.byType(CircularProgressIndicator), findsNothing);
    client.close();
  });

  testWidgets('confirmation keyboard Done submits reset once', (tester) async {
    final response = Completer<http.Response>();
    var requests = 0;
    final client = CloudLocalAuthClient(
      baseUrl: 'https://api.example',
      client: MockClient((_) {
        requests++;
        return response.future;
      }),
    )..credentialMethod = 'username_password';
    await tester.pumpWidget(
      MaterialApp(
        home: CloudRecoveryScreen(service: client, usernameMode: true),
      ),
    );
    await tester.enterText(find.byKey(const Key('recoveryUserId')), 'alice');
    await tester.enterText(
      find.byKey(const Key('resetPassword')),
      'replacement password 123',
    );
    await tester.enterText(
      find.byKey(const Key('resetConfirm')),
      'replacement password 123',
    );
    expect(
      tester
          .widget<TextField>(find.byKey(const Key('resetConfirm')))
          .textInputAction,
      TextInputAction.done,
    );
    await tester.testTextInput.receiveAction(TextInputAction.done);
    await tester.pump();
    expect(requests, 1);
    expect(find.byType(CircularProgressIndicator), findsOneWidget);
    await tester.testTextInput.receiveAction(TextInputAction.done);
    expect(requests, 1);
    response.complete(http.Response('', 204));
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('recoveryCompleted')), findsOneWidget);
    client.close();
  });

  test('handoff accepts only exact trusted fragment and expected purpose', () {
    expect(
      CloudAuthLink.capture(
        '$_origin/reset-password#token=$_token',
        path: '/reset-password',
        trustedOrigin: _origin,
      ),
      _token,
    );
    expect(
      CloudAuthLink.capture(_token, path: '/reset-password', trustedOrigin: ''),
      _token,
    );
    for (final link in [
      'http://account.example/reset-password#token=$_token',
      'https://other.example/reset-password#token=$_token',
      '$_origin/verify-email#token=$_token',
      '$_origin/reset-password?x=1#token=$_token',
      '$_origin/reset-password#other=$_token',
      '$_origin/reset-password#token=short',
    ]) {
      expect(
        CloudAuthLink.capture(
          link,
          path: '/reset-password',
          trustedOrigin: _origin,
        ),
        isNull,
      );
    }
    expect(
      CloudAuthLink.capture(
        '$_origin/reset-password#token=$_token',
        path: '/reset-password',
        trustedOrigin: '',
      ),
      isNull,
    );
  });

  testWidgets('User ID reset uses no email challenge and hands off to login', (
    tester,
  ) async {
    var requests = 0;
    final client = CloudLocalAuthClient(
      baseUrl: 'https://api.example',
      client: MockClient((request) async {
        requests++;
        expect(request.url.path, '/v1/auth/local/reset-password');
        expect(jsonDecode(request.body), {
          'username': 'alice',
          'password': 'replacement password 123',
        });
        return http.Response('', 204);
      }),
    )..credentialMethod = 'username_password';
    String? loginUserId;
    await tester.pumpWidget(
      MaterialApp(
        home: CloudRecoveryScreen(
          service: client,
          usernameMode: true,
          onResetSuccess: (identity, _) async {
            loginUserId = identity;
          },
        ),
      ),
    );
    expect(find.text('User ID'), findsOneWidget);
    expect(find.byKey(const Key('recoveryEmail')), findsNothing);
    expect(find.text('Request reset link'), findsNothing);
    expect(find.byKey(const Key('pasteResetLink')), findsNothing);
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
    expect(requests, 1);
    expect(loginUserId, 'alice');
    expect(
      tester
          .widget<TextField>(find.byKey(const Key('resetPassword')))
          .controller!
          .text,
      isEmpty,
    );
    client.close();
  });

  testWidgets('User ID reset hides unknown and rate-limited account details', (
    tester,
  ) async {
    for (final status in [404, 429]) {
      final client = CloudLocalAuthClient(
        baseUrl: 'https://api.example',
        client: MockClient(
          (_) async => http.Response('{"secret":"private"}', status),
        ),
      )..credentialMethod = 'username_password';
      await tester.pumpWidget(
        MaterialApp(
          key: ValueKey(status),
          home: CloudRecoveryScreen(service: client, usernameMode: true),
        ),
      );
      await tester.enterText(find.byKey(const Key('recoveryUserId')), 'alice');
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
      expect(find.textContaining('private'), findsNothing);
      expect(find.byKey(const Key('recoveryCompleted')), findsNothing);
      expect(find.byKey(const Key('recoveryError')), findsOneWidget);
      client.close();
    }
  });

  testWidgets(
    'recovery accepts generically and clears copied link after reset',
    (tester) async {
      final paths = <String>[];
      final client = CloudLocalAuthClient(
        baseUrl: 'https://api.example',
        client: MockClient((request) async {
          paths.add(request.url.path);
          final body = jsonDecode(request.body) as Map<String, dynamic>;
          if (request.url.path.endsWith('/recovery')) {
            expect(body, {'email': 'person@example.com'});
            return http.Response('{"accepted":true}', 202);
          }
          expect(body, {
            'token': _token,
            'password': 'replacement password 123',
          });
          return http.Response('', 204);
        }),
      );
      await tester.pumpWidget(
        MaterialApp(
          home: CloudRecoveryScreen(service: client, linkOrigin: _origin),
        ),
      );
      await tester.enterText(
        find.byKey(const Key('recoveryEmail')),
        'person@example.com',
      );
      await tester.tap(find.text('Request reset link'));
      await tester.pumpAndSettle();
      expect(find.byKey(const Key('recoveryAccepted')), findsOneWidget);
      await Clipboard.setData(
        const ClipboardData(text: '$_origin/reset-password#token=$_token'),
      );
      await tester.tap(find.byKey(const Key('pasteResetLink')));
      await tester.pumpAndSettle();
      expect((await Clipboard.getData('text/plain'))?.text, isEmpty);
      expect(find.text('Reset link ready.'), findsOneWidget);
      await tester.enterText(
        find.byKey(const Key('resetPassword')),
        'replacement password 123',
      );
      await tester.enterText(
        find.byKey(const Key('resetConfirm')),
        'replacement password 123',
      );
      await tester.scrollUntilVisible(
        find.byKey(const Key('submitPasswordReset')),
        200,
        scrollable: find.byType(Scrollable).first,
      );
      await tester.ensureVisible(find.byKey(const Key('submitPasswordReset')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('submitPasswordReset')));
      await tester.pumpAndSettle();
      expect(find.byKey(const Key('recoveryCompleted')), findsOneWidget);
      expect(paths, [
        '/v1/auth/local/recovery',
        '/v1/auth/local/reset-password',
      ]);
      client.close();
    },
  );

  testWidgets('successful reset hands credentials to normal sign-in', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(800, 1400);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final client = CloudLocalAuthClient(
      baseUrl: 'https://api.example',
      client: MockClient((request) async {
        expect(request.url.path, '/v1/auth/local/reset-password');
        return http.Response('', 204);
      }),
    );
    String? signedInEmail;
    String? signedInPassword;
    await tester.pumpWidget(
      MaterialApp(
        home: CloudRecoveryScreen(
          service: client,
          initialEmail: 'person@example.com',
          onResetSuccess: (email, password) async {
            signedInEmail = email;
            signedInPassword = password;
          },
        ),
      ),
    );
    expect(
      tester
          .widget<TextField>(find.byKey(const Key('recoveryEmail')))
          .controller!
          .text,
      'person@example.com',
    );
    await tester.tap(find.text('I have a reset link'));
    await tester.pumpAndSettle();
    await Clipboard.setData(const ClipboardData(text: _token));
    await tester.tap(find.byKey(const Key('pasteResetLink')));
    await tester.pumpAndSettle();
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
    expect(signedInEmail, 'person@example.com');
    expect(signedInPassword, 'replacement password 123');
    expect(
      tester
          .widget<TextField>(find.byKey(const Key('resetPassword')))
          .controller!
          .text,
      isEmpty,
    );
    expect(find.byKey(const Key('recoveryCompleted')), findsNothing);
    client.close();
  });

  testWidgets('used reset link reports expiry without exposing backend text', (
    tester,
  ) async {
    final client = CloudLocalAuthClient(
      baseUrl: 'https://api.example',
      client: MockClient(
        (_) async => http.Response('{"private":"secret"}', 401),
      ),
    );
    await tester.pumpWidget(
      MaterialApp(
        home: CloudRecoveryScreen(service: client, linkOrigin: _origin),
      ),
    );
    await tester.tap(find.text('I have a reset link'));
    await tester.pumpAndSettle();
    await Clipboard.setData(const ClipboardData(text: _token));
    await tester.tap(find.byKey(const Key('pasteResetLink')));
    await tester.pumpAndSettle();
    await tester.enterText(
      find.byKey(const Key('resetPassword')),
      'replacement password 123',
    );
    await tester.enterText(
      find.byKey(const Key('resetConfirm')),
      'replacement password 123',
    );
    await tester.scrollUntilVisible(
      find.byKey(const Key('submitPasswordReset')),
      200,
      scrollable: find.byType(Scrollable).first,
    );
    await tester.ensureVisible(find.byKey(const Key('submitPasswordReset')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('submitPasswordReset')));
    await tester.pumpAndSettle();
    expect(
      find.text(
        'This reset link has expired or was already used. Request a new link.',
      ),
      findsOneWidget,
    );
    expect(find.textContaining('secret'), findsNothing);
    expect(find.text('Reset link ready.'), findsNothing);
    client.close();
  });
}
