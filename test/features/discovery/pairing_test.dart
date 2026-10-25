import 'dart:convert';
import 'dart:io';
import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:flutter/material.dart';
import 'package:energylens_mobile/features/discovery/discovery_api.dart';
import 'package:energylens_mobile/features/discovery/discovery_credentials.dart';
import 'package:energylens_mobile/features/discovery/hub_pairing_screen.dart';
import 'package:energylens_mobile/core/cloud_api/cloud_hub_claim.dart';
import 'package:energylens_mobile/core/cloud_api/cloud_api_client.dart';
import 'package:energylens_mobile/core/cloud_auth/cloud_auth.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

const _homeId = '11111111-1111-4111-8111-111111111111';
const _hubCloudId = '22222222-2222-4222-8222-222222222222';
const _localHubId = 'elhub_test-hub';

class _Tokens implements CloudTokenStore {
  @override
  Future<void> clear() async {}
  @override
  Future<CloudTokens?> read() async => const CloudTokens(accessToken: 'token');
  @override
  Future<void> save(CloudTokens tokens) async {}
}

class _Auth implements CloudAuthenticator {
  @override
  Future<CloudTokens> signIn(CloudAuthConfig config) async =>
      const CloudTokens(accessToken: 'token');
  @override
  Future<CloudTokens> refresh(CloudAuthConfig config, String token) async =>
      const CloudTokens(accessToken: 'token');
}

CloudApiClient _cloud(Future<http.Response> Function(http.Request) send) =>
    CloudApiClient(
      session: CloudSession(
        config: const CloudAuthConfig(
          issuer: 'https://issuer.example',
          audience: 'audience',
          clientId: 'client',
          redirectUrl: 'io.energylens.app://login-callback',
          apiUrl: 'https://api.example',
        ),
        store: _Tokens(),
        authenticator: _Auth(),
      ),
      client: MockClient(send),
    );

http.Response _resolution() => http.Response(
  jsonEncode({
    'hub_id': _hubCloudId,
    'local_hub_id': _localHubId,
    'https_origin': 'https://192.168.1.20:18787',
    'certificate_sha256': 'a' * 64,
    'enrollment_secret': 'b' * 64,
    'expires_at': DateTime.now()
        .toUtc()
        .add(const Duration(minutes: 5))
        .toIso8601String(),
  }),
  200,
);

const _address =
    'https://192.168.1.20:18787#sha256=aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa';

class _FakePairingTransport implements PairingTransport {
  _FakePairingTransport({this.hubId = 'hub-1', this.failPin = false});

  final String hubId;
  final bool failPin;
  final List<(String, String, Map<String, dynamic>?)> requests = [];

  @override
  Future<PairingHttpResponse> send(
    String address,
    String path,
    String method, {
    Map<String, dynamic>? body,
    String? bearerToken,
  }) async {
    if (failPin) throw HandshakeException('Certificate pin mismatch');
    requests.add((method, path, body));
    if (path == '/healthz') {
      return PairingHttpResponse(
        statusCode: 200,
        body: jsonEncode({'status': 'ok', 'api_version': '1', 'hub_id': hubId}),
      );
    }
    return PairingHttpResponse(
      statusCode: 200,
      body: jsonEncode({
        'hub_id': hubId,
        'client_id': body?['client_id'] ?? 'app:test',
        'token': 'client-token',
        'token_type': 'Bearer',
      }),
    );
  }
}

class _MemorySecureStore implements SecureKeyValueStore {
  final values = <String, String>{};

  @override
  Future<String?> read(String key) async => values[key];

  @override
  Future<void> write(String key, String value) async => values[key] = value;

  @override
  Future<void> delete(String key) async => values.remove(key);
}

PairingDetails _details() => PairingDetails.fromJson({
  'version': 1,
  'address': _address,
  'hub_id': 'hub-1',
  'enrollment_secret': 'one-time-secret',
});

void main() {
  testWidgets('setup later is available throughout onboarding pairing', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(800, 1200);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    var dashboardRequested = false;
    final transport = _FakePairingTransport(hubId: 'wrong-hub');
    final cloud = _cloud((_) async => _resolution());
    addTearDown(cloud.close);
    await tester.pumpWidget(
      MaterialApp(
        home: HubPairingScreen(
          api: DiscoveryApi(pairingTransport: transport),
          credentials: DiscoveryCredentials(storage: _MemorySecureStore()),
          cloudApi: cloud,
          homeId: _homeId,
          onSetUpLater: () => dashboardRequested = true,
        ),
      ),
    );
    expect(find.text('Set up later'), findsOneWidget);
    await tester.tap(find.text('Set up later'));
    expect(dashboardRequested, isTrue);
    dashboardRequested = false;
    expect(find.byType(TextField), findsOneWidget);
    expect(find.byKey(const Key('pairingAddress')), findsNothing);
    expect(find.byKey(const Key('pairingSecret')), findsNothing);
    await tester.enterText(find.byKey(const Key('pairingCode')), ' pqr234 ');
    await tester.ensureVisible(find.text('Verify and pair'));
    await tester.tap(find.text('Verify and pair'));
    await tester.pumpAndSettle();
    expect(find.text('Set up later'), findsOneWidget);
    expect(find.text('Verify and pair'), findsOneWidget);
    await tester.tap(find.text('Set up later'));
    expect(dashboardRequested, isTrue);
  });

  testWidgets('invalid code stays local and keeps one field', (tester) async {
    var requests = 0;
    final cloud = _cloud((_) async {
      requests++;
      return _resolution();
    });
    addTearDown(cloud.close);
    await tester.pumpWidget(
      MaterialApp(
        home: HubPairingScreen(cloudApi: cloud, homeId: _homeId),
      ),
    );
    expect(find.text('Pair with your hub'), findsOneWidget);
    expect(find.text('Pairing code'), findsOneWidget);
    expect(find.byType(TextField), findsOneWidget);
    await tester.enterText(find.byKey(const Key('pairingCode')), 'abci12');
    await tester.tap(find.text('Verify and pair'));
    await tester.pump();
    expect(requests, 0);
    expect(
      find.text('Enter the 6-character code from your hub.'),
      findsNWidgets(2),
    );
  });

  testWidgets('resolver failure never contacts Hub and allows setup later', (
    tester,
  ) async {
    final transport = _FakePairingTransport(hubId: _localHubId);
    final cloud = _cloud(
      (_) async => http.Response('{"code":"pairing_unavailable"}', 404),
    );
    addTearDown(cloud.close);
    await tester.pumpWidget(
      MaterialApp(
        home: HubPairingScreen(
          api: DiscoveryApi(pairingTransport: transport),
          cloudApi: cloud,
          homeId: _homeId,
          onSetUpLater: () {},
        ),
      ),
    );
    await tester.enterText(find.byKey(const Key('pairingCode')), 'PQR234');
    await tester.tap(find.text('Verify and pair'));
    await tester.pumpAndSettle();
    expect(transport.requests, isEmpty);
    expect(find.text('Set up later'), findsOneWidget);
    expect(find.text('Internal Error, Try again later'), findsOneWidget);
  });

  testWidgets('expired Cloud capability never contacts Hub', (tester) async {
    final transport = _FakePairingTransport(hubId: _localHubId);
    final cloud = _cloud(
      (_) async => http.Response(
        jsonEncode({
          'hub_id': _hubCloudId,
          'local_hub_id': _localHubId,
          'https_origin': 'https://192.168.1.20:18787',
          'certificate_sha256': 'a' * 64,
          'enrollment_secret': 'b' * 64,
          'expires_at': DateTime.now()
              .toUtc()
              .subtract(const Duration(minutes: 1))
              .toIso8601String(),
        }),
        200,
      ),
    );
    addTearDown(cloud.close);
    await tester.pumpWidget(
      MaterialApp(
        home: HubPairingScreen(
          api: DiscoveryApi(pairingTransport: transport),
          cloudApi: cloud,
          homeId: _homeId,
        ),
      ),
    );
    await tester.enterText(find.byKey(const Key('pairingCode')), 'PQR234');
    await tester.tap(find.text('Verify and pair'));
    await tester.pumpAndSettle();
    expect(transport.requests, isEmpty);
    expect(find.text('Internal Error, Try again later'), findsOneWidget);
  });

  testWidgets('verify action stays disabled while resolver runs', (
    tester,
  ) async {
    final pending = Completer<http.Response>();
    final cloud = _cloud((_) => pending.future);
    addTearDown(cloud.close);
    await tester.pumpWidget(
      MaterialApp(
        home: HubPairingScreen(cloudApi: cloud, homeId: _homeId),
      ),
    );
    await tester.enterText(find.byKey(const Key('pairingCode')), 'PQR234');
    await tester.tap(find.text('Verify and pair'));
    await tester.pump();
    expect(find.text('Pairing…'), findsOneWidget);
    expect(find.text('Wait 20 to 30 seconds to pair.'), findsOneWidget);
    expect(find.byKey(const Key('pairingProgressIndicator')), findsOneWidget);
    expect(
      tester.widget<FilledButton>(find.byType(FilledButton)).onPressed,
      isNull,
    );
    pending.complete(http.Response('{"code":"pairing_unavailable"}', 404));
    await tester.pumpAndSettle();
    expect(
      tester.widget<FilledButton>(find.byType(FilledButton)).onPressed,
      isNotNull,
    );
    expect(find.text('Pairing…'), findsNothing);
    expect(find.text('Wait 20 to 30 seconds to pair.'), findsNothing);
    expect(find.byKey(const Key('pairingProgressIndicator')), findsNothing);
  });

  test('owned pairing requires matching owner, hub and epoch', () async {
    final store = _MemorySecureStore();
    final credentials = DiscoveryCredentials(storage: store);
    await credentials.savePairing(
      address: _address,
      hubId: 'hub-1',
      clientId: 'app:test',
      token: 'claimed-token',
      ownershipEpoch: 3,
    );
    final scope = OwnedPairingScope(
      origin: 'https://api.example/',
      profile: 'username_password',
      accountId: 'account-a',
      homeId: 'home-a',
    );
    const owner = HubOwnership(
      hubId: 'cloud-hub',
      localHubId: 'hub-1',
      homeId: 'home-a',
      ownershipEpoch: 3,
      version: 1,
    );
    expect(await credentials.saveOwnedPairing(scope, owner), isTrue);
    expect(
      (await credentials.readOwnedPairing(scope, owner))?.token,
      'claimed-token',
    );
    expect(await credentials.readPairing(), isNull);
    expect(
      await credentials.readOwnedPairing(
        OwnedPairingScope(
          origin: 'https://api.example',
          profile: 'username_password',
          accountId: 'account-b',
          homeId: 'home-a',
        ),
        owner,
      ),
      isNull,
    );
    expect(
      await credentials.readOwnedPairing(
        scope,
        const HubOwnership(
          hubId: 'cloud-hub',
          localHubId: 'hub-1',
          homeId: 'home-a',
          ownershipEpoch: 4,
          version: 2,
        ),
      ),
      isNull,
    );
  });

  test('household preferences stay within verified owner and home', () async {
    final credentials = DiscoveryCredentials(storage: _MemorySecureStore());
    final first = OwnedPairingScope(
      origin: 'https://api.example',
      profile: 'username_password',
      accountId: 'account-a',
      homeId: 'home-a',
    );
    final second = OwnedPairingScope(
      origin: 'https://api.example',
      profile: 'username_password',
      accountId: 'account-b',
      homeId: 'home-b',
    );
    await credentials.savePostalCode('60601', scope: first);
    await credentials.dismissZipPrompt(scope: first);
    expect(await credentials.readPostalCode(scope: first), '60601');
    expect(await credentials.readPostalCode(scope: second), isNull);
    expect(await credentials.readPostalCode(), isNull);
    expect(await credentials.readZipPromptDismissed(scope: second), isFalse);
  });

  test('parses operator JSON and manual pairing fields', () {
    final details = _details();
    expect(details.address, _address);
    expect(details.hubId, 'hub-1');
    expect(details.enrollmentSecret, 'one-time-secret');
    expect(
      PairingDetails.fromManualFields(
        address: _address,
        hubId: 'hub-1',
        enrollmentSecret: 'one-time-secret',
      ).hubId,
      'hub-1',
    );
    expect(
      () => PairingDetails.fromManualFields(
        address: 'https://192.168.1.20:18787',
        hubId: 'hub-1',
        enrollmentSecret: 'secret',
      ),
      throwsFormatException,
    );
  });

  test('hub ID mismatch never sends the enrollment secret or replaces pairing', () async {
    final transport = _FakePairingTransport(hubId: 'different-hub');
    final store = _MemorySecureStore()
      ..values['energylens.hub.pairing'] =
          '{"address":"old","hub_id":"old-hub","client_id":"old-client","token":"old-token"}';
    final credentials = DiscoveryCredentials(storage: store);

    await expectLater(
      credentials.claimAndStore(
        _details(),
        clientId: 'app:test',
        api: DiscoveryApi(pairingTransport: transport),
      ),
      throwsA(isA<PairingException>()),
    );

    expect(transport.requests.map((request) => request.$2), ['/healthz']);
    expect(
      transport.requests.any(
        (request) => request.$3?.containsKey('enrollment_secret') ?? false,
      ),
      isFalse,
    );
    expect(
      jsonDecode(store.values['energylens.hub.pairing']!)['token'],
      'old-token',
    );
  });

  test(
    'successful claim stores address, hub, client ID, and token only',
    () async {
      final transport = _FakePairingTransport();
      final store = _MemorySecureStore();
      final claim = await DiscoveryCredentials(storage: store).claimAndStore(
        _details(),
        clientId: 'app:test',
        api: DiscoveryApi(pairingTransport: transport),
      );

      expect(transport.requests.map((request) => request.$2), [
        '/healthz',
        '/v1/pairing/claim',
      ]);
      expect(transport.requests.last.$3, {
        'hub_id': 'hub-1',
        'enrollment_secret': 'one-time-secret',
        'client_id': 'app:test',
      });
      expect(claim.token, 'client-token');
      final stored = jsonDecode(store.values['energylens.hub.pairing']!);
      expect(stored, {
        'address': _address,
        'hub_id': 'hub-1',
        'client_id': 'app:test',
        'token': 'client-token',
      });
      expect(store.values.values.join(), isNot(contains('one-time-secret')));
      expect(await DiscoveryCredentials(storage: store).read(), (
        _address,
        'client-token',
      ));
    },
  );

  test('bad certificate pin stops before health response and claim', () async {
    final transport = _FakePairingTransport(failPin: true);
    final store = _MemorySecureStore()
      ..values['energylens.hub.pairing'] =
          '{"address":"old","hub_id":"old-hub","client_id":"old-client","token":"old-token"}';

    await expectLater(
      DiscoveryCredentials(storage: store).claimAndStore(
        _details(),
        clientId: 'app:test',
        api: DiscoveryApi(pairingTransport: transport),
      ),
      throwsA(isA<HandshakeException>()),
    );
    expect(transport.requests, isEmpty);
    expect(
      jsonDecode(store.values['energylens.hub.pairing']!)['token'],
      'old-token',
    );
  });

  test('stored pairing checks the pinned hub identity on restart', () async {
    final transport = _FakePairingTransport(hubId: 'different-hub');
    await expectLater(
      DiscoveryApi(pairingTransport: transport).verifyStoredPairing(
        const StoredHubIdentity(address: _address, hubId: 'hub-1'),
      ),
      throwsA(isA<PairingException>()),
    );
    expect(transport.requests.map((request) => request.$2), ['/healthz']);
  });

  testWidgets('short code resolves and stores only the issued token', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(800, 1200);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    final store = _MemorySecureStore();
    final transport = _FakePairingTransport(hubId: _localHubId);
    http.Request? resolveRequest;
    final cloud = _cloud((request) async {
      resolveRequest = request;
      return _resolution();
    });
    addTearDown(cloud.close);
    await tester.pumpWidget(
      MaterialApp(
        home: HubPairingScreen(
          api: DiscoveryApi(pairingTransport: transport),
          credentials: DiscoveryCredentials(storage: store),
          cloudApi: cloud,
          homeId: _homeId,
        ),
      ),
    );
    expect(find.byType(TextField), findsOneWidget);
    await tester.enterText(find.byKey(const Key('pairingCode')), ' pqr234 ');
    await tester.ensureVisible(find.text('Verify and pair'));
    await tester.tap(find.text('Verify and pair'));
    await tester.pumpAndSettle();
    expect(transport.requests.map((request) => request.$2), [
      '/healthz',
      '/v1/pairing/claim',
    ]);
    expect(resolveRequest?.url.path, '/v1/homes/$_homeId/hub-pairings/resolve');
    expect(jsonDecode(resolveRequest!.body)['code'], 'PQR234');
    expect(resolveRequest!.headers['Authorization'], 'Bearer token');
    expect(resolveRequest!.headers['Idempotency-Key'], isNotEmpty);
    expect(
      transport.requests.last.$3?['client_id'],
      jsonDecode(resolveRequest!.body)['client_id'],
    );
    expect(
      store.values['energylens.hub.pairing'],
      contains('client-token'),
      reason: tester
          .widgetList<Text>(find.byType(Text))
          .map((widget) => widget.data)
          .join(' | '),
    );
    expect(store.values.values.join(), isNot(contains('b' * 64)));
  });
}
