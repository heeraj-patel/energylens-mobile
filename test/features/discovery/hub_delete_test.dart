import 'dart:async';
import 'dart:convert';

import 'package:energylens_mobile/core/cloud_api/cloud_api_client.dart';
import 'package:energylens_mobile/core/cloud_api/cloud_home.dart';
import 'package:energylens_mobile/core/cloud_api/cloud_hub_claim.dart';
import 'package:energylens_mobile/core/cloud_auth/cloud_auth.dart';
import 'package:energylens_mobile/features/discovery/discovery_credentials.dart';
import 'package:energylens_mobile/features/discovery/discovery_screen.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

const homeId = '11111111-1111-4111-8111-111111111111';
const hubId = '22222222-2222-4222-8222-222222222222';
const localHubId = 'elhub_test';
const config = CloudAuthConfig(
  issuer: 'https://issuer.example',
  audience: 'audience',
  clientId: 'client',
  redirectUrl: 'io.energylens.app://login-callback',
  apiUrl: 'https://api.example',
);
const home = CloudHome(
  id: homeId,
  name: 'Home',
  timezone: 'America/Chicago',
  countryCode: 'US',
  postalCode: '60601',
);

class TokenStore implements CloudTokenStore {
  @override
  Future<void> clear() async {}
  @override
  Future<CloudTokens?> read() async => const CloudTokens(accessToken: 'token');
  @override
  Future<void> save(CloudTokens tokens) async {}
}

class Authenticator implements CloudAuthenticator {
  @override
  Future<CloudTokens> signIn(CloudAuthConfig config) async =>
      const CloudTokens(accessToken: 'token');
  @override
  Future<CloudTokens> refresh(CloudAuthConfig config, String token) async =>
      const CloudTokens(accessToken: 'token');
}

class MemoryStore implements SecureKeyValueStore {
  final values = <String, String>{};
  @override
  Future<String?> read(String key) async => values[key];
  @override
  Future<void> write(String key, String value) async => values[key] = value;
  @override
  Future<void> delete(String key) async {
    values.remove(key);
  }
}

Map<String, Object> ownership() => {
  'hub_id': hubId,
  'local_hub_id': localHubId,
  'home_id': homeId,
  'ownership_epoch': 3,
  'version': 4,
};

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUp(() => FlutterSecureStorage.setMockInitialValues({}));

  testWidgets(
    'Delete requires concrete selected Cloud ownership and prevents double submit',
    (tester) async {
      tester.view.physicalSize = const Size(800, 1200);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      final pending = Completer<http.Response>();
      final requests = <http.Request>[];
      var listed = true;
      final cloud = CloudApiClient(
        session: CloudSession(
          config: config,
          store: TokenStore(),
          authenticator: Authenticator(),
        ),
        client: MockClient((request) async {
          requests.add(request);
          if (request.method == 'GET') {
            return http.Response(
              jsonEncode({
                'hubs': listed ? [ownership()] : [],
              }),
              200,
            );
          }
          return pending.future;
        }),
      );
      final store = MemoryStore();
      final credentials = DiscoveryCredentials(storage: store);
      final scope = OwnedPairingScope(
        origin: config.apiUrl,
        profile: cloud.session.credentialMethod,
        accountId: 'account-a',
        homeId: homeId,
      );
      final ownedKey = scope.keyFor(HubOwnership.fromJson(ownership()));
      store.values[ownedKey] = 'cached';
      store.values['$ownedKey.client_id'] = 'client';
      await tester.pumpWidget(
        MaterialApp(
          home: DiscoveryScreen(
            cloudHome: home,
            cloudApi: cloud,
            accountId: 'account-a',
            credentials: credentials,
          ),
        ),
      );
      await tester.pumpAndSettle();
      final button = find.byKey(const Key('deleteHubButton'));
      expect(
        find.text(
          'Removes this hub from your EnergyLens home. It does not erase the physical hub.',
        ),
        findsOneWidget,
      );
      expect(
        tester.getTopLeft(button).dy,
        lessThan(tester.getTopLeft(find.text('Detected plugs')).dy),
      );
      expect(tester.widget<TextButton>(button).onPressed, isNotNull);
      await tester.tap(button);
      await tester.pump();
      expect(tester.widget<TextButton>(button).onPressed, isNull);
      expect(
        requests.where((request) => request.method == 'DELETE'),
        hasLength(1),
      );
      final request = requests.last;
      expect(request.url.path, '/v1/homes/$homeId/hubs/$hubId');
      expect(request.headers['Authorization'], 'Bearer token');
      expect(request.headers['If-Match'], '"4"');
      expect(
        request.headers['Idempotency-Key'],
        matches(RegExp(r'^[0-9a-f-]{36}$')),
      );
      listed = false;
      pending.complete(http.Response('', 204));
      await tester.pumpAndSettle();
      expect(tester.widget<TextButton>(button).onPressed, isNull);
      expect(store.values.containsKey(ownedKey), isFalse);
      expect(store.values.containsKey('$ownedKey.client_id'), isFalse);
      expect(
        requests.where((request) => request.method == 'DELETE'),
        hasLength(1),
      );
    },
  );

  testWidgets(
    'Delete stays disabled without an association or account context',
    (tester) async {
      final cloud = CloudApiClient(
        session: CloudSession(
          config: config,
          store: TokenStore(),
          authenticator: Authenticator(),
        ),
        client: MockClient((_) async => http.Response('{"hubs":[]}', 200)),
      );
      await tester.pumpWidget(
        MaterialApp(
          home: DiscoveryScreen(
            cloudHome: home,
            cloudApi: cloud,
            accountId: 'account-a',
            credentials: DiscoveryCredentials(storage: MemoryStore()),
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(
        tester
            .widget<TextButton>(find.byKey(const Key('deleteHubButton')))
            .onPressed,
        isNull,
      );
      await tester.pumpWidget(
        MaterialApp(
          home: DiscoveryScreen(
            cloudHome: home,
            cloudApi: cloud,
            credentials: DiscoveryCredentials(storage: MemoryStore()),
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(
        tester
            .widget<TextButton>(find.byKey(const Key('deleteHubButton')))
            .onPressed,
        isNull,
      );
    },
  );

  for (final status in [404, 409, 500]) {
    testWidgets(
      'Delete $status preserves association when Cloud still lists it',
      (tester) async {
        var deletes = 0;
        final store = MemoryStore();
        final cloud = CloudApiClient(
          session: CloudSession(
            config: config,
            store: TokenStore(),
            authenticator: Authenticator(),
          ),
          client: MockClient((request) async {
            if (request.method == 'GET') {
              return http.Response(
                jsonEncode({
                  'hubs': [ownership()],
                }),
                200,
              );
            }
            deletes++;
            return http.Response(
              jsonEncode({
                'code': status == 409 ? 'version_conflict' : 'not_found',
              }),
              status,
            );
          }),
        );
        await tester.pumpWidget(
          MaterialApp(
            home: DiscoveryScreen(
              cloudHome: home,
              cloudApi: cloud,
              accountId: 'account-a',
              credentials: DiscoveryCredentials(storage: store),
            ),
          ),
        );
        await tester.pumpAndSettle();
        final button = find.byKey(const Key('deleteHubButton'));
        await tester.tap(button);
        await tester.pumpAndSettle();
        expect(deletes, 1);
        expect(tester.widget<TextButton>(button).onPressed, isNotNull);
        expect(find.text('Delete'), findsOneWidget);
        expect(find.text('Internal Error, Try again later'), findsOneWidget);
      },
    );
  }

  testWidgets('404 with confirmed Cloud absence clears association', (
    tester,
  ) async {
    var listed = true;
    final cloud = CloudApiClient(
      session: CloudSession(
        config: config,
        store: TokenStore(),
        authenticator: Authenticator(),
      ),
      client: MockClient((request) async {
        if (request.method == 'GET') {
          return http.Response(
            jsonEncode({
              'hubs': listed ? [ownership()] : [],
            }),
            200,
          );
        }
        listed = false;
        return http.Response('{"code":"not_found"}', 404);
      }),
    );
    await tester.pumpWidget(
      MaterialApp(
        home: DiscoveryScreen(
          cloudHome: home,
          cloudApi: cloud,
          accountId: 'account-a',
          credentials: DiscoveryCredentials(storage: MemoryStore()),
        ),
      ),
    );
    await tester.pumpAndSettle();
    final button = find.byKey(const Key('deleteHubButton'));
    await tester.tap(button);
    await tester.pumpAndSettle();
    expect(tester.widget<TextButton>(button).onPressed, isNull);
  });
}
