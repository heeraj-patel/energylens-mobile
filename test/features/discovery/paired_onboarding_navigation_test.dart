import 'dart:convert';

import 'package:energylens_mobile/core/cloud_api/cloud_api_client.dart';
import 'package:energylens_mobile/core/cloud_api/cloud_home.dart';
import 'package:energylens_mobile/core/cloud_api/cloud_hub_claim.dart';
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

class _Credentials extends DiscoveryCredentials {
  StoredPairingCredential? pairing;
  int localClaims = 0;

  @override
  Future<StoredPairingCredential?> readPairing() async => pairing;

  @override
  Future<PairingClaim> claimAndStore(
    PairingDetails details, {
    required String clientId,
    DiscoveryApi api = const DiscoveryApi(),
  }) async {
    localClaims++;
    pairing = StoredPairingCredential(
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

  @override
  Future<StoredPairingCredential?> readOwnedPairing(
    OwnedPairingScope scope,
    HubOwnership ownership,
  ) async {
    final current = pairing;
    if (current == null) return null;
    return StoredPairingCredential(
      address: current.address,
      hubId: current.hubId,
      clientId: current.clientId,
      token: current.token,
      ownershipEpoch: ownership.ownershipEpoch,
    );
  }
}

class _Api extends DiscoveryApi {
  int scans = 0;

  @override
  DiscoveryApi authorizedFor(HubOwnerAuthorization owner) => this;

  @override
  Future<void> verifyStoredPairing(StoredHubIdentity pairing) async {}

  @override
  Future<List<SavedPlug>> saved(String baseUrl, String token) async => const [];

  @override
  Future<bool> supportsNearbyDiscovery(String baseUrl, String token) async =>
      false;

  @override
  Future<List<DiscoveredPlug>> scan(String baseUrl, String token) async {
    scans++;
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
  bool owned = false;
  int resolutions = 0;
  int claimRequests = 0;
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
      if (request.url.path == '/v1/homes/$_homeId/hubs') {
        return http.Response(
          jsonEncode({
            'hubs': owned
                ? [
                    {
                      'hub_id': _hubId,
                      'local_hub_id': _localHubId,
                      'home_id': _homeId,
                      'ownership_epoch': 2,
                      'version': 1,
                    },
                  ]
                : [],
          }),
          200,
        );
      }
      if (request.url.path == '/v1/homes/$_homeId/hub-pairings/resolve') {
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
      if (request.url.path == '/v1/homes/$_homeId/hub-claims') {
        claimRequests++;
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
        final response = http.Response(
          jsonEncode({
            'hub_id': _hubId,
            'local_hub_id': _localHubId,
            'home_id': _homeId,
            'ownership_epoch': 2,
            'version': 1,
          }),
          200,
        );
        if (response.statusCode == 200) owned = true;
        return response;
      }
      return http.Response('{}', 404);
    }),
  );
}

void main() {
  testWidgets('onboarding can reach Dashboard before entering a pairing code', (
    tester,
  ) async {
    final cloud = _CloudHarness();
    addTearDown(cloud.cloud.close);
    var linked = false;
    await tester.pumpWidget(
      StatefulBuilder(
        builder: (context, setState) => MaterialApp(
          home: linked
              ? const Scaffold(body: Text('Dashboard'))
              : DiscoveryScreen(
                  api: _Api(),
                  credentials: _Credentials(),
                  cloudHome: _home,
                  cloudApi: cloud.cloud,
                  accountId: 'account-onboarding-skip',
                  newHomeOnboarding: true,
                  onCloudHubLinked: () => setState(() => linked = true),
                ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.text('Pair with hub'));
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('pairingCode')), findsOneWidget);
    await tester.tap(find.text('Set up later'));
    await tester.pumpAndSettle();
    expect(cloud.claimRequests, 0);
    expect(find.text('Dashboard'), findsOneWidget);
  });

  testWidgets(
    'paired onboarding action opens code before claim and reaches Dashboard',
    (tester) async {
      FlutterSecureStorage.setMockInitialValues({});
      await const FlutterSecureStorage().delete(key: 'hub_claim_pending_v1');
      final cloud = _CloudHarness();
      final api = _Api();
      addTearDown(cloud.cloud.close);
      final credentials = _Credentials()
        ..pairing = const StoredPairingCredential(
          address: 'https://192.168.1.20:8787#sha256=aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa',
          hubId: _localHubId,
          clientId: 'client-1',
          token: 'old-token',
        );
      var linked = false;
      await tester.pumpWidget(
        StatefulBuilder(
          builder: (context, setState) => MaterialApp(
            home: linked
                ? const Scaffold(body: Text('Dashboard'))
                : DiscoveryScreen(
                    api: api,
                    credentials: credentials,
                    cloudHome: _home,
                    cloudApi: cloud.cloud,
                    accountId: 'account-onboarding-paired',
                    newHomeOnboarding: true,
                    onCloudHubLinked: () => setState(() => linked = true),
                  ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(find.text('Pair with hub'), findsOneWidget);
      expect(find.text('Link paired hub to home'), findsNothing);
      expect(cloud.claimRequests, 0);
      await tester.tap(find.text('Pair with hub'));
      await tester.pumpAndSettle();
      expect(find.byKey(const Key('pairingCode')), findsOneWidget);
      expect(cloud.claimRequests, 0);
      await tester.enterText(find.byKey(const Key('pairingCode')), 'PQR234');
      await tester.tap(find.text('Verify and pair'));
      await tester.pumpAndSettle();
      // Confirm the code flow completed before checking the Cloud claim.
      expect(find.byKey(const Key('pairingCode')), findsNothing);
      expect(credentials.localClaims, 1);
      expect(cloud.claimRequests, 1);
      expect(api.scans, 1);
      expect(linked, isTrue);
      expect(find.text('Dashboard'), findsOneWidget);
    },
  );
}
