import 'package:energylens_mobile/core/cloud_api/cloud_api_client.dart';
import 'package:energylens_mobile/core/cloud_auth/cloud_auth.dart';
import 'package:energylens_mobile/core/cloud_auth/cloud_entry_gate.dart';
import 'package:flutter/material.dart';
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

void main() {
  testWidgets('required disclosure gates home creation until accepted', (
    tester,
  ) async {
    final session = CloudSession(
      config: config,
      store: Store(),
      authenticator: Auth(),
    );
    var homesRequests = 0;
    http.Request? acceptance;
    final api = CloudApiClient(
      session: session,
      client: MockClient((request) async {
        switch (request.url.path) {
          case '/v1/me':
            return http.Response(
              '{"id":"account-1","email":null,"email_verified":true}',
              200,
            );
          case '/v1/me/preferences':
            if (request.method == 'PATCH') {
              acceptance = request;
              return http.Response(
                '{"version":2,"schema_version":1,"email_reports_enabled":false,"history_disclosure_accepted_at":"2026-09-30T00:00:00Z"}',
                200,
                headers: {'etag': '"2"'},
              );
            }
            return http.Response(
              '{"version":1,"schema_version":1,"email_reports_enabled":false,"history_disclosure_accepted_at":null}',
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
          session: session,
          api: api,
          homeBuilder: (_, _, _, _) => const Text('Private Home'),
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.text('History disclosure'), findsOneWidget);
    expect(find.text('Create home'), findsNothing);
    expect(homesRequests, 0);
    expect(find.text('Accept history disclosure'), findsOneWidget);
    expect(
      tester
          .widget<FilledButton>(
            find.widgetWithText(FilledButton, 'Accept history disclosure'),
          )
          .onPressed,
      isNull,
    );
    await tester.tap(find.byKey(const Key('acceptHistoryDisclosure')));
    await tester.pump();
    expect(
      tester
          .widget<FilledButton>(
            find.widgetWithText(FilledButton, 'Accept history disclosure'),
          )
          .onPressed,
      isNotNull,
    );
    await tester.tap(find.text('Accept history disclosure'));
    await tester.pumpAndSettle();
    expect(acceptance?.headers['if-match'], '"1"');
    expect(acceptance?.headers['idempotency-key'], isNotEmpty);
    expect(homesRequests, 1);
    expect(find.text('Your cloud homes'), findsOneWidget);
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
          session: session,
          api: api,
          homeBuilder: (_, _, _, _) => const Text('Private Home'),
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.text('Private Home'), findsNothing);
    expect(
      find.text('Cloud account service is not available yet.'),
      findsOneWidget,
    );
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
        if (request.url.path == '/v1/me/preferences') {
          return http.Response(
            '{"version":1,"schema_version":1,"email_reports_enabled":false,"history_disclosure_accepted_at":"2026-09-30T00:00:00Z"}',
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
    expect(find.text('Sign in'), findsOneWidget);
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
        if (request.url.path == '/v1/me/preferences') {
          return http.Response(
            '{"version":1,"schema_version":1,"email_reports_enabled":false,"history_disclosure_accepted_at":"2026-09-30T00:00:00Z"}',
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
        if (request.url.path == '/v1/me/preferences') {
          return http.Response(
            '{"version":1,"schema_version":1,"email_reports_enabled":false,"history_disclosure_accepted_at":"2026-09-30T00:00:00Z"}',
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
    expect(
      find.text('Your cloud sign-in expired. Sign in again.'),
      findsOneWidget,
    );
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
        (_) async => http.Response(
          '{"id":"account-1","email":"a@example.com","email_verified":false}',
          200,
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
    expect(find.text('Private Home'), findsNothing);
    expect(
      find.text('Verify your email address before continuing.'),
      findsOneWidget,
    );
    api.close();
  });
}
