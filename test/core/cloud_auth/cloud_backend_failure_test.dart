import 'dart:async';
import 'dart:io';

import 'package:energylens_mobile/core/backend_error.dart';
import 'package:energylens_mobile/core/cloud_api/cloud_api_client.dart';
import 'package:energylens_mobile/core/cloud_auth/cloud_auth.dart';
import 'package:energylens_mobile/core/cloud_auth/cloud_entry_gate.dart';
import 'package:energylens_mobile/core/cloud_auth/cloud_local_auth.dart';
import 'package:energylens_mobile/core/cloud_auth/cloud_recovery_screen.dart';
import 'package:energylens_mobile/core/cloud_auth/cloud_registration_screen.dart';
import 'package:energylens_mobile/features/identify/onboarding_draft_store.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

const _config = CloudAuthConfig(
  issuer: 'https://issuer.example',
  audience: 'energylens-cloud',
  clientId: 'client',
  redirectUrl: 'io.energylens.app://login-callback',
  apiUrl: 'https://api.example',
);
const _homeId = '11111111-1111-4111-8111-111111111111';
const _homeJson =
    '{"id":"$_homeId","name":"Main home","timezone":"America/Chicago","location":{"country_code":"US","postal_code":"60601"}}';
const _expired = 'Your cloud sign-in expired. Sign in again.';

class _Store implements CloudTokenStore {
  CloudTokens? tokens = const CloudTokens(accessToken: 'token');
  @override
  Future<void> clear() async => tokens = null;
  @override
  Future<CloudTokens?> read() async => tokens;
  @override
  Future<void> save(CloudTokens value) async => tokens = value;
}

class _Auth implements CloudAuthenticator {
  @override
  Future<CloudTokens> refresh(CloudAuthConfig config, String token) async =>
      const CloudTokens(accessToken: 'token');
  @override
  Future<CloudTokens> signIn(CloudAuthConfig config) async =>
      const CloudTokens(accessToken: 'token');
}

class _Drafts implements OnboardingDraftStorage {
  String? value;
  @override
  Future<String?> read() async => value;
  @override
  Future<void> write(String data) async => value = data;
  @override
  Future<void> clear() async => value = null;
}

CloudApiClient _client(
  _Store store,
  Future<http.Response> Function(http.Request) handler,
) => CloudApiClient(
  session: CloudSession(config: _config, store: store, authenticator: _Auth()),
  client: MockClient(handler),
);

Future<http.Response> Function(http.Request) _cloud({
  required Future<http.Response> Function(http.Request) homes,
  Future<http.Response> Function(http.Request)? other,
}) => (request) async {
  switch (request.url.path) {
    case '/v1/auth/config':
      return http.Response('', 404);
    case '/v1/me':
      return http.Response(
        '{"id":"account-1","email":null,"email_verified":true}',
        200,
      );
    case '/v1/homes':
      return homes(request);
  }
  return other == null ? http.Response('', 404) : other(request);
};

Future<http.Response> _homesOk(http.Request _) async =>
    http.Response('{"homes":[$_homeJson]}', 200);

class _Registration implements CloudRegistrationService {
  Object? error;
  @override
  Future<void> requestRegistration(String email, String password) async {
    if (error != null) throw error!;
  }

  @override
  Future<void> verifyEmail(String token) async {}
}

class _Recovery implements LocalCloudAuthService {
  Object? error;
  @override
  Future<void> requestRecovery(String email) async {
    if (error != null) throw error!;
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

void main() {
  test('shared message is the owner-approved text', () {
    expect(internalErrorMessage, 'Internal Error, Try again later');
  });

  group('session rejection', () {
    for (final status in [401, 403]) {
      test('$status signals the session owner once', () async {
        var rejected = 0;
        final api = _client(_Store(), (_) async => http.Response('', status))
          ..onSessionRejected = () => rejected++;
        await expectLater(
          api.me(),
          throwsA(
            isA<CloudApiException>().having(
              (e) => e.statusCode,
              'status',
              status,
            ),
          ),
        );
        expect(rejected, 1);
        api.close();
      });
    }

    for (final status in [400, 404, 409, 422, 500, 503]) {
      test('$status does not end the session', () async {
        var rejected = 0;
        final api = _client(_Store(), (_) async => http.Response('', status))
          ..onSessionRejected = () => rejected++;
        await expectLater(api.me(), throwsA(isA<CloudApiException>()));
        expect(rejected, 0);
        api.close();
      });
    }

    test('network failures do not end the session', () async {
      var rejected = 0;
      final api = _client(
        _Store(),
        (_) async => throw const SocketException('offline'),
      )..onSessionRejected = () => rejected++;
      await expectLater(api.me(), throwsA(isA<SocketException>()));
      expect(rejected, 0);
      api.close();
    });

    test('a missing token ends the session', () async {
      var rejected = 0;
      final store = _Store()..tokens = null;
      final api = _client(store, (_) async => http.Response('{}', 200))
        ..onSessionRejected = () => rejected++;
      await expectLater(
        api.me(),
        throwsA(
          isA<CloudApiException>().having((e) => e.statusCode, 'status', 401),
        ),
      );
      expect(rejected, 1);
      api.close();
    });

    test('a rejection after sign-out is ignored', () async {
      var rejected = 0;
      final store = _Store();
      late CloudApiClient api;
      final release = Completer<void>();
      api = _client(store, (_) async {
        await release.future;
        return http.Response('', 403);
      })..onSessionRejected = () => rejected++;
      final pending = api.me();
      await Future<void>.delayed(Duration.zero);
      await api.session.signOut();
      release.complete();
      await expectLater(pending, throwsA(isA<CloudApiException>()));
      expect(rejected, 0);
      api.close();
    });

    test('a missing home is not verifiable and ends the session', () async {
      var rejected = 0;
      final api = _client(_Store(), (_) async => http.Response('', 404))
        ..onSessionRejected = () => rejected++;
      await expectLater(api.home(_homeId), throwsA(isA<CloudApiException>()));
      expect(rejected, 1);
      api.close();
    });

    test('a home answering for another ID ends the session', () async {
      var rejected = 0;
      final api = _client(
        _Store(),
        (_) async => http.Response(
          _homeJson.replaceFirst(
            _homeId,
            '22222222-2222-4222-8222-222222222222',
          ),
          200,
          headers: {'etag': '"1"'},
        ),
      )..onSessionRejected = () => rejected++;
      await expectLater(api.home(_homeId), throwsFormatException);
      expect(rejected, 1);
      api.close();
    });
  });

  group('gate', () {
    Future<CloudApiClient> openHome(
      WidgetTester tester,
      _Store store,
      Future<http.Response> Function(http.Request) other,
    ) async {
      final api = _client(store, _cloud(homes: _homesOk, other: other));
      await tester.pumpWidget(
        MaterialApp(
          home: CloudEntryGate(
            homeCreateStorage: _Drafts(),
            activeHomeStorage: _Drafts(),
            session: api.session,
            api: api,
            homeBuilder: (_, _, _, _) => const Text('Private Home'),
          ),
        ),
      );
      await tester.pumpAndSettle();
      await tester.tap(find.text('Main home'));
      await tester.pumpAndSettle();
      expect(find.text('Private Home'), findsOneWidget);
      return api;
    }

    for (final status in [401, 403]) {
      testWidgets('$status from any Cloud call signs the user out', (
        tester,
      ) async {
        final store = _Store();
        final api = await openHome(
          tester,
          store,
          (_) async => http.Response('', status),
        );
        await expectLater(
          api.get('/v1/homes/$_homeId/dashboard'),
          throwsA(isA<CloudApiException>()),
        );
        await tester.pumpAndSettle();
        expect(store.tokens, isNull);
        expect(find.text('Private Home'), findsNothing);
        expect(find.text('Submit'), findsOneWidget);
        expect(find.text(_expired), findsOneWidget);
        expect(find.text(internalErrorMessage), findsNothing);
        api.close();
      });
    }

    testWidgets('an unverifiable selected home signs the user out', (
      tester,
    ) async {
      final store = _Store();
      final api = await openHome(tester, store, (_) async {
        return http.Response('', 404);
      });
      await expectLater(api.home(_homeId), throwsA(isA<CloudApiException>()));
      await tester.pumpAndSettle();
      expect(store.tokens, isNull);
      expect(find.text('Private Home'), findsNothing);
      expect(find.text('Submit'), findsOneWidget);
      api.close();
    });

    for (final status in [500, 502, 503]) {
      testWidgets('$status keeps the session and is not disclosed', (
        tester,
      ) async {
        final store = _Store();
        final api = await openHome(
          tester,
          store,
          (_) async => http.Response('{"code":"db_down"}', status),
        );
        await expectLater(
          api.get('/v1/homes/$_homeId/dashboard'),
          throwsA(isA<CloudApiException>()),
        );
        await tester.pumpAndSettle();
        expect(store.tokens, isNotNull);
        expect(find.text('Private Home'), findsOneWidget);
        api.close();
      });
    }

    for (final status in [500, 503, 404]) {
      testWidgets('homes $status shows only the internal error', (
        tester,
      ) async {
        final store = _Store();
        final api = _client(
          store,
          _cloud(homes: (_) async => http.Response('{"code":"x"}', status)),
        );
        await tester.pumpWidget(
          MaterialApp(
            home: CloudEntryGate(
              homeCreateStorage: _Drafts(),
              activeHomeStorage: _Drafts(),
              session: api.session,
              api: api,
              homeBuilder: (_, _, _, _) => const Text('Private Home'),
            ),
          ),
        );
        await tester.pumpAndSettle();
        expect(find.text(internalErrorMessage), findsOneWidget);
        expect(find.textContaining('x)'), findsNothing);
        expect(find.textContaining('Could not'), findsNothing);
        expect(store.tokens, isNotNull);
        api.close();
      });
    }

    for (final error in <Object>[
      const SocketException('offline'),
      TimeoutException('slow'),
      const FormatException('bad json'),
    ]) {
      testWidgets('homes ${error.runtimeType} shows only the internal error', (
        tester,
      ) async {
        final api = _client(_Store(), _cloud(homes: (_) async => throw error));
        await tester.pumpWidget(
          MaterialApp(
            home: CloudEntryGate(
              homeCreateStorage: _Drafts(),
              activeHomeStorage: _Drafts(),
              session: api.session,
              api: api,
              homeBuilder: (_, _, _, _) => const Text('Private Home'),
            ),
          ),
        );
        await tester.pumpAndSettle();
        expect(find.text(internalErrorMessage), findsOneWidget);
        expect(find.textContaining('Could not'), findsNothing);
        api.close();
      });
    }

    testWidgets('account read failing with 5xx shows the internal error', (
      tester,
    ) async {
      final api = _client(
        _Store(),
        (request) async => request.url.path == '/v1/auth/config'
            ? http.Response('', 404)
            : http.Response('', 503),
      );
      await tester.pumpWidget(
        MaterialApp(
          home: CloudEntryGate(
            homeCreateStorage: _Drafts(),
            activeHomeStorage: _Drafts(),
            session: api.session,
            api: api,
            homeBuilder: (_, _, _, _) => const Text('Private Home'),
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(find.text('Private Home'), findsNothing);
      expect(find.text('Submit'), findsOneWidget);
      expect(find.text(internalErrorMessage), findsOneWidget);
      api.close();
    });

    testWidgets('account read rejected with 403 returns to sign-in', (
      tester,
    ) async {
      final store = _Store();
      final api = _client(
        store,
        (request) async => request.url.path == '/v1/auth/config'
            ? http.Response('', 404)
            : http.Response('', 403),
      );
      await tester.pumpWidget(
        MaterialApp(
          home: CloudEntryGate(
            homeCreateStorage: _Drafts(),
            activeHomeStorage: _Drafts(),
            session: api.session,
            api: api,
            homeBuilder: (_, _, _, _) => const Text('Private Home'),
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(store.tokens, isNull);
      expect(find.text('Submit'), findsOneWidget);
      expect(find.text(internalErrorMessage), findsNothing);
      api.close();
    });
  });

  group('account screens', () {
    Future<void> register(WidgetTester tester, _Registration service) async {
      await tester.pumpWidget(
        MaterialApp(home: CloudRegistrationScreen(service: service)),
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
    }

    for (final error in <Object>[
      const CloudLocalAuthException(500),
      const CloudLocalAuthException(503),
      const CloudLocalAuthException(404),
      const SocketException('offline'),
      TimeoutException('slow'),
    ]) {
      testWidgets('registration ${error.runtimeType} shows internal error', (
        tester,
      ) async {
        await register(tester, _Registration()..error = error);
        expect(find.text(internalErrorMessage), findsOneWidget);
      });
    }

    testWidgets('registration keeps the validation message for 422', (
      tester,
    ) async {
      await register(
        tester,
        _Registration()..error = const CloudLocalAuthException(422),
      );
      expect(
        find.text('Could not submit the request. Try again.'),
        findsOneWidget,
      );
      expect(find.text(internalErrorMessage), findsNothing);
    });

    Future<void> recover(WidgetTester tester, _Recovery service) async {
      await tester.pumpWidget(
        MaterialApp(home: CloudRecoveryScreen(service: service)),
      );
      await tester.enterText(
        find.byKey(const Key('recoveryEmail')),
        'person@example.com',
      );
      await tester.tap(find.text('Request reset link'));
      await tester.pumpAndSettle();
    }

    for (final error in <Object>[
      const CloudLocalAuthException(502),
      const CloudLocalAuthException(404),
      const SocketException('offline'),
    ]) {
      testWidgets('recovery ${error.runtimeType} shows internal error', (
        tester,
      ) async {
        await recover(tester, _Recovery()..error = error);
        expect(find.text(internalErrorMessage), findsOneWidget);
      });
    }

    testWidgets('recovery keeps the validation message for 400', (
      tester,
    ) async {
      await recover(
        tester,
        _Recovery()..error = const CloudLocalAuthException(400),
      );
      expect(
        find.text('Could not submit the request. Try again later.'),
        findsOneWidget,
      );
    });
  });
}
