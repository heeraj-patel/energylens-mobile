import 'dart:async';
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
  _CloudHarness({this.finishResponse});
  final Completer<http.Response>? finishResponse;
  bool owned = false;
  int resolutions = 0;
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
                  'home_id': _homeId,
                  'ownership_epoch': 2,
                  'version': 1,
                }),
                200,
              )
            : await finishResponse!.future;
        if (response.statusCode == 200) owned = true;
        return response;
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
  testWidgets(
    'successful pairing routes by entry context and failures stay put',
    (tester) async {
      FlutterSecureStorage.setMockInitialValues({});

      final ordinary = _CloudHarness();
      final ordinaryApi = _Api();
      final ordinaryCredentials = _Credentials();
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
      expect(ordinaryCredentials.localClaims, 1);
      expect(ordinary.owned, isTrue);
      expect(ordinaryApi.scans, 1);
      expect(find.byKey(const Key('pairingCode')), findsNothing);
      expect(find.text('Find a smart plug'), findsOneWidget);

      await tester.pumpWidget(const SizedBox.shrink());
      await tester.pumpAndSettle();
      final onboarding = _CloudHarness();
      final onboardingApi = _Api();
      addTearDown(onboarding.cloud.close);
      var linked = false;
      await tester.pumpWidget(
        StatefulBuilder(
          builder: (context, setState) => MaterialApp(
            home: linked
                ? const Scaffold(body: Text('Dashboard'))
                : DiscoveryScreen(
                    api: onboardingApi,
                    credentials: _Credentials(),
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
      await _pair(tester);
      expect(linked, isTrue);
      expect(onboarding.owned, isTrue);
      expect(onboardingApi.scans, 0);
      expect(find.text('Dashboard'), findsOneWidget);

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
                      credentials: _Credentials(),
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
            credentials: _Credentials(),
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
}
