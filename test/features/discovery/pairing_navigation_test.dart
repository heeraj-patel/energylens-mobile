import 'dart:async';
import 'dart:convert';

import 'package:energylens_mobile/core/cloud_api/cloud_api_client.dart';
import 'package:energylens_mobile/core/cloud_api/cloud_home.dart';
import 'package:energylens_mobile/core/cloud_api/cloud_hub_claim.dart';
import 'package:energylens_mobile/core/cloud_api/cloud_hub_claim_flow.dart';
import 'package:energylens_mobile/core/cloud_auth/cloud_auth.dart';
import 'package:energylens_mobile/features/discovery/discovery_api.dart';
import 'package:energylens_mobile/features/discovery/discovery_credentials.dart';
import 'package:energylens_mobile/features/discovery/discovery_screen.dart';
import 'package:flutter/material.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

const _homeId = '11111111-1111-4111-8111-111111111111';
const _hubId = '22222222-2222-4222-8222-222222222222';
const _localHubId = 'elhub_test-hub';
const _home = CloudHome(
  id: _homeId,
  name: 'Selected home',
  timezone: 'America/Chicago',
  countryCode: 'US',
  postalCode: '60601',
);

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
  Future<CloudTokens> refresh(
    CloudAuthConfig config,
    String refreshToken,
  ) async => const CloudTokens(accessToken: 'token');
}

class _Store implements SecureKeyValueStore {
  final values = <String, String>{};
  @override
  Future<String?> read(String key) async => values[key];
  @override
  Future<void> write(String key, String value) async => values[key] = value;

  @override
  Future<void> delete(String key) async => values.remove(key);
}

class _Credentials extends DiscoveryCredentials {
  _Credentials(_Store store) : super(storage: store);
  int localClaims = 0;

  @override
  Future<PairingClaim> claimAndStore(
    PairingDetails details, {
    required String clientId,
    DiscoveryApi api = const DiscoveryApi(),
  }) async {
    localClaims++;
    await savePairing(
      address: details.address,
      hubId: details.hubId,
      clientId: clientId,
      token: 'issued-token',
    );
    return PairingClaim(
      hubId: details.hubId,
      clientId: clientId,
      token: 'issued-token',
    );
  }
}

class _Api extends DiscoveryApi {
  int scans = 0;
  int ownerClaims = 0;
  Completer<void>? scanGate;

  @override
  DiscoveryApi authorizedFor(HubOwnerAuthorization owner) => this;

  @override
  Future<void> verifyStoredPairing(StoredHubIdentity pairing) async {}

  @override
  Future<PairingClaim> claimOwnedPairing(
    HubOwnership ownership, {
    required String clientId,
    required HubOwnerAuthorization owner,
  }) async {
    ownerClaims++;
    return PairingClaim(
      hubId: ownership.localHubId,
      clientId: clientId,
      token: 'owned-token',
      ownershipEpoch: ownership.ownershipEpoch,
    );
  }

  @override
  Future<List<SavedPlug>> saved(String baseUrl, String token) async => const [];

  @override
  Future<bool> supportsNearbyDiscovery(String baseUrl, String token) async =>
      false;

  @override
  Future<List<DiscoveredPlug>> scan(String baseUrl, String token) async {
    scans++;
    await scanGate?.future;
    return const [];
  }

  @override
  Future<HubClaimProof> claimProof(
    HubClaimChallenge challenge, {
    required String address,
    required String hubId,
    required String token,
  }) async => HubClaimProof(
    claimId: challenge.claimId,
    localHubId: hubId,
    possessionProof: 'p' * 24,
    deviceSignature: 'signature',
  );
}

class _CloudHarness {
  _CloudHarness({this.finishResponse, this.connectionHintAfterHubLists = 0});
  final Completer<http.Response>? finishResponse;
  final int connectionHintAfterHubLists;
  final String homeId = _homeId;
  bool owned = false;
  int resolutions = 0;
  int hubLists = 0;
  late final cloud = CloudApiClient(
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
    client: MockClient((request) async {
      if (request.url.path == '/v1/homes/$homeId/hubs') {
        hubLists++;
        return http.Response(
          jsonEncode({
            'hubs': owned
                ? [
                    {
                      'hub_id': _hubId,
                      'local_hub_id': _localHubId,
                      'home_id': homeId,
                      'ownership_epoch': 2,
                      'version': 1,
                      if (hubLists > connectionHintAfterHubLists)
                        'connection': {
                          'https_origin': 'https://192.168.1.20:8787',
                          'certificate_sha256': 'a' * 64,
                          'expires_at': DateTime.now()
                              .toUtc()
                              .add(const Duration(minutes: 5))
                              .toIso8601String(),
                        },
                    },
                  ]
                : [],
          }),
          200,
        );
      }
      if (request.url.path == '/v1/homes/$homeId/hub-pairings/resolve') {
        resolutions++;
        return http.Response(
          jsonEncode({
            'hub_id': _hubId,
            'local_hub_id': _localHubId,
            'https_origin': 'https://192.168.1.20:8787',
            'certificate_sha256': 'a' * 64,
            'enrollment_secret': 'b' * 64,
            'expires_at': DateTime.now()
                .toUtc()
                .add(const Duration(minutes: 5))
                .toIso8601String(),
          }),
          200,
        );
      }
      if (request.url.path == '/v1/homes/$homeId/hub-claims') {
        return http.Response(
          jsonEncode({
            'claim_id': '44444444-4444-4444-8444-444444444444',
            'hub_id': _hubId,
            'local_hub_id': _localHubId,
            'nonce': 'nonce',
            'expires_at': DateTime.now()
                .toUtc()
                .add(const Duration(minutes: 5))
                .toIso8601String(),
          }),
          201,
        );
      }
      if (request.url.path == '/v1/hubs/claim') {
        final response = finishResponse == null
            ? http.Response(
                jsonEncode({
                  'hub_id': _hubId,
                  'local_hub_id': _localHubId,
                  'home_id': homeId,
                  'ownership_epoch': 2,
                  'version': 1,
                  'connection': {
                    'https_origin': 'https://192.168.1.20:8787',
                    'certificate_sha256': 'a' * 64,
                    'expires_at': DateTime.now()
                        .toUtc()
                        .add(const Duration(minutes: 5))
                        .toIso8601String(),
                  },
                }),
                200,
              )
            : await finishResponse!.future;
        if (response.statusCode == 200) owned = true;
        return response;
      }
      if (request.method == 'DELETE' &&
          request.url.path == '/v1/homes/$homeId/hubs/$_hubId') {
        owned = false;
        return http.Response('', 204);
      }
      return http.Response('{}', 404);
    }),
  );
}

Future<void> _pair(WidgetTester tester) async {
  await tester.tap(find.text('Pair with hub'));
  await tester.pumpAndSettle();
  expect(find.byKey(const Key('pairingCode')), findsOneWidget);
  await tester.enterText(find.byKey(const Key('pairingCode')), 'PQR234');
  await tester.tap(find.text('Verify and pair'));
  await tester.pumpAndSettle();
}

void main() {
  testWidgets('an automatic paired scan cannot start twice while active', (
    tester,
  ) async {
    final harness = _CloudHarness()..owned = true;
    final api = _Api()..scanGate = Completer<void>();
    addTearDown(harness.cloud.close);
    await tester.pumpWidget(
      MaterialApp(
        home: DiscoveryScreen(
          api: api,
          credentials: _Credentials(_Store()),
          autoScan: true,
          cloudHome: _home,
          cloudApi: harness.cloud,
          accountId: 'account-a',
        ),
      ),
    );
    for (var attempt = 0; attempt < 20 && api.scans == 0; attempt++) {
      await tester.pump(const Duration(milliseconds: 20));
    }
    expect(api.scans, 1);
    await tester.scrollUntilVisible(
      find.text('Scan for plugs'),
      250,
      scrollable: find.byType(Scrollable).first,
    );
    final scanButton = find.ancestor(
      of: find.text('Scan for plugs'),
      matching: find.byType(FilledButton),
    );
    expect(tester.widget<FilledButton>(scanButton).onPressed, isNull);
    await tester.pump();
    expect(api.scans, 1);
    api.scanGate!.complete();
    await tester.pumpAndSettle();
    expect(api.scans, 1);
  });

  test(
    'owned credential remains scoped to account and home and delete clears it',
    () async {
      final store = _Store();
      final credentials = _Credentials(store);
      final ownership = HubOwnership(
        hubId: _hubId,
        localHubId: _localHubId,
        homeId: _homeId,
        ownershipEpoch: 2,
        version: 1,
      );
      OwnedPairingScope scope(String account, String home) => OwnedPairingScope(
        origin: 'https://api.example',
        profile: 'email_password',
        accountId: account,
        homeId: home,
      );
      final selected = scope('account-a', _homeId);
      await credentials.storeOwnedPairing(
        selected,
        ownership,
        StoredPairingCredential(
          address: 'https://192.168.1.20:8787#sha256=${'a' * 64}',
          hubId: _localHubId,
          clientId: 'client',
          token: 'owned-token',
          ownershipEpoch: 2,
        ),
      );
      expect(
        await credentials.readOwnedPairing(selected, ownership),
        isNotNull,
      );
      expect(
        await credentials.readOwnedPairing(
          scope('account-b', _homeId),
          ownership,
        ),
        isNull,
      );
      expect(
        await credentials.readOwnedPairing(
          scope('account-a', 'other-home'),
          ownership,
        ),
        isNull,
      );
      await credentials.clearHubPairing(selected, ownership);
      expect(await credentials.readOwnedPairing(selected, ownership), isNull);
    },
  );

  testWidgets(
    'successful pairing routes by entry context and failures stay put',
    (tester) async {
      FlutterSecureStorage.setMockInitialValues({});
      await const FlutterSecureStorage().delete(key: 'hub_claim_pending_v1');

      final ordinary = _CloudHarness();
      final ordinaryApi = _Api();
      final ordinaryStore = _Store();
      final ordinaryCredentials = _Credentials(ordinaryStore);
      addTearDown(ordinary.cloud.close);
      await tester.pumpWidget(
        MaterialApp(
          home: DiscoveryScreen(
            api: ordinaryApi,
            credentials: ordinaryCredentials,
            cloudHome: _home,
            cloudApi: ordinary.cloud,
            accountId: 'account-a',
          ),
        ),
      );
      await tester.pumpAndSettle();
      await _pair(tester);
      for (var attempt = 0; attempt < 50 && !ordinary.owned; attempt++) {
        await tester.pump(const Duration(milliseconds: 20));
      }
      await tester.pumpAndSettle();
      expect(ordinaryCredentials.localClaims, 1);
      expect(ordinary.owned, isTrue);
      expect(ordinaryApi.scans, 1);
      expect(ordinaryApi.ownerClaims, 1);
      expect(await ordinaryCredentials.readPairing(), isNull);
      expect(
        ordinaryStore.values.keys.any((key) => key.contains('pairing.v2')),
        isTrue,
      );
      expect(find.byKey(const Key('pairingCode')), findsNothing);
      expect(find.text('Find a smart plug'), findsOneWidget);

      await tester.pumpWidget(const SizedBox.shrink());
      await tester.pumpAndSettle();
      final onboarding = _CloudHarness(connectionHintAfterHubLists: 3);
      final onboardingApi = _Api()..scanGate = Completer<void>();
      final onboardingStore = _Store();
      addTearDown(onboarding.cloud.close);
      var linked = false;
      await tester.pumpWidget(
        StatefulBuilder(
          builder: (context, setState) => MaterialApp(
            home: linked
                ? Builder(
                    builder: (dashboardContext) => Scaffold(
                      body: TextButton(
                        onPressed: () => Navigator.of(dashboardContext).push(
                          MaterialPageRoute<void>(
                            builder: (_) => DiscoveryScreen(
                              api: onboardingApi,
                              credentials: _Credentials(onboardingStore),
                              autoScan: true,
                              cloudHome: _home,
                              cloudApi: onboarding.cloud,
                              accountId: 'account-a',
                            ),
                          ),
                        ),
                        child: const Text('Add device'),
                      ),
                    ),
                  )
                : DiscoveryScreen(
                    api: onboardingApi,
                    credentials: _Credentials(onboardingStore),
                    cloudHome: _home,
                    cloudApi: onboarding.cloud,
                    accountId: 'account-a',
                    newHomeOnboarding: true,
                    onCloudHubLinked: () => setState(() => linked = true),
                  ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      await tester.tap(find.text('Pair with hub'));
      await tester.pumpAndSettle();
      await tester.enterText(find.byKey(const Key('pairingCode')), 'PQR234');
      await tester.tap(find.text('Verify and pair'));
      for (var attempt = 0; attempt < 20 && onboardingApi.scans == 0;
          attempt++) {
        await tester.pump(const Duration(seconds: 1));
      }
      expect(onboarding.owned, isTrue);
      expect(onboarding.hubLists, greaterThan(3));
      expect(onboardingApi.scans, 1);
      expect(linked, isFalse);
      onboardingApi.scanGate!.complete();
      await tester.pumpAndSettle();
      expect(linked, isTrue);
      expect(find.text('Add device'), findsOneWidget);
      await tester.tap(find.text('Add device'));
      await tester.pumpAndSettle();
      expect(find.text('Pair with hub'), findsNothing);
      expect(find.text('Scan for plugs'), findsOneWidget);
      expect(
        tester
            .widget<FilledButton>(
              find.ancestor(
                of: find.text('Scan for plugs'),
                matching: find.byType(FilledButton),
              ),
            )
            .onPressed,
        isNotNull,
      );
      expect(onboardingApi.scans, 2);
      expect(onboardingApi.ownerClaims, 1);

      await tester.pumpWidget(const SizedBox.shrink());
      await tester.pumpAndSettle();
      await tester.pumpWidget(
        MaterialApp(
          home: DiscoveryScreen(
            api: onboardingApi,
            credentials: _Credentials(onboardingStore),
            autoScan: true,
            cloudHome: _home,
            cloudApi: onboarding.cloud,
            accountId: 'account-a',
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(find.text('Scan for plugs'), findsOneWidget);
      expect(find.text('Pair with hub'), findsNothing);
      expect(onboardingApi.scans, 3);
      expect(onboardingApi.ownerClaims, 1);

      await tester.tap(find.byKey(const Key('deleteHubButton')));
      await tester.pumpAndSettle();
      expect(onboarding.owned, isFalse);
      expect(find.text('Scan for plugs'), findsNothing);
      expect(find.text('Pair with hub'), findsOneWidget);
      expect(
        onboardingStore.values.keys.any((key) => key.contains('pairing.v2')),
        isFalse,
      );

      await tester.pumpWidget(const SizedBox.shrink());
      await tester.pumpAndSettle();
      final settings = _CloudHarness();
      final settingsApi = _Api();
      addTearDown(settings.cloud.close);
      await tester.pumpWidget(
        MaterialApp(
          home: Builder(
            builder: (context) => Scaffold(
              body: TextButton(
                onPressed: () => Navigator.of(context).push(
                  MaterialPageRoute<void>(
                    builder: (_) => DiscoveryScreen(
                      api: settingsApi,
                      credentials: _Credentials(_Store()),
                      cloudHome: _home,
                      cloudApi: settings.cloud,
                      accountId: 'account-a',
                      returnToSettingsAfterPairing: true,
                    ),
                  ),
                ),
                child: const Text('Settings'),
              ),
            ),
          ),
        ),
      );
      await tester.tap(find.text('Settings'));
      await tester.pumpAndSettle();
      await _pair(tester);
      expect(settings.owned, isTrue);
      expect(settingsApi.scans, 0);
      expect(find.text('Settings'), findsOneWidget);
      expect(find.byType(DiscoveryScreen), findsNothing);

      await tester.pumpWidget(const SizedBox.shrink());
      await tester.pumpAndSettle();
      final finish = Completer<http.Response>()
        ..complete(http.Response('{"code":"claim_conflict"}', 409));
      final failed = _CloudHarness(finishResponse: finish);
      final failedApi = _Api();
      addTearDown(failed.cloud.close);
      await tester.pumpWidget(
        MaterialApp(
          home: DiscoveryScreen(
            api: failedApi,
            credentials: _Credentials(_Store()),
            cloudHome: _home,
            cloudApi: failed.cloud,
            accountId: 'account-a',
          ),
        ),
      );
      await tester.pumpAndSettle();
      await _pair(tester);
      expect(failed.owned, isFalse);
      expect(failedApi.scans, 0);
      expect(find.text('Find a smart plug'), findsOneWidget);
      expect(find.byKey(const Key('hubClaimMessage')), findsOneWidget);
    },
  );

  testWidgets('setup later cancels a pending connection hint retry', (
    tester,
  ) async {
    FlutterSecureStorage.setMockInitialValues({});
    await CloudHubClaimFlow.invalidatePendingClaims();
    final harness = _CloudHarness(connectionHintAfterHubLists: 999);
    final api = _Api();
    addTearDown(harness.cloud.close);
    var handoffs = 0;
    await tester.pumpWidget(
      MaterialApp(
        home: DiscoveryScreen(
          api: api,
          credentials: _Credentials(_Store()),
          cloudHome: _home,
          cloudApi: harness.cloud,
          accountId: 'account-skip-during-retry',
          newHomeOnboarding: true,
          onCloudHubLinked: () => handoffs++,
        ),
      ),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.text('Pair with hub'));
    await tester.pumpAndSettle();
    await tester.enterText(find.byKey(const Key('pairingCode')), 'PQR234');
    await tester.tap(find.text('Verify and pair'));
    for (var attempt = 0; attempt < 50 && harness.hubLists < 3; attempt++) {
      await tester.pump(const Duration(milliseconds: 20));
    }
    expect(harness.owned, isTrue);
    expect(harness.hubLists, greaterThanOrEqualTo(3));
    expect(api.scans, 0);
    await tester.pump(const Duration(milliseconds: 350));
    await tester.tap(
      find.descendant(
        of: find.byType(DiscoveryScreen),
        matching: find.text('Set up later'),
      ),
    );
    await tester.pump();
    expect(handoffs, 1);
    final listsAtSkip = harness.hubLists;
    await tester.pump(const Duration(seconds: 5));
    await tester.pumpAndSettle();
    expect(harness.hubLists, listsAtSkip);
    expect(api.scans, 0);
    expect(handoffs, 1);
    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pumpAndSettle();
    await CloudHubClaimFlow.invalidatePendingClaims();
  });
}
