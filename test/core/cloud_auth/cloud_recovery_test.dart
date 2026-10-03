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
      find.textContaining('invalid, expired, or already used'),
      findsOneWidget,
    );
    expect(find.textContaining('secret'), findsNothing);
    expect(find.text('Reset link ready.'), findsNothing);
    client.close();
  });
}
