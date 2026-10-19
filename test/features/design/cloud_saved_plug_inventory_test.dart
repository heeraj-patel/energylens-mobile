import 'dart:convert';

import 'package:energylens_mobile/core/cloud_api/cloud_api_client.dart';
import 'package:energylens_mobile/core/cloud_api/cloud_appliance.dart';
import 'package:energylens_mobile/core/cloud_api/cloud_hub_claim.dart';
import 'package:energylens_mobile/core/cloud_auth/cloud_auth.dart';
import 'package:energylens_mobile/features/design/cloud_saved_plug_inventory.dart';
import 'package:energylens_mobile/features/discovery/discovery_api.dart';
import 'package:energylens_mobile/features/discovery/discovery_credentials.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

const home = '11111111-1111-4111-8111-111111111111';
const otherHome = '22222222-2222-4222-8222-222222222222';
const hub = 'elhub_saved';
const otherHub = 'elhub_other';
const address =
    'https://192.168.1.20:18787#sha256=aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa';
const otherAddress =
    'https://192.168.1.21:18787#sha256=bbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb';
const config = CloudAuthConfig(
  issuer: 'https://issuer.example',
  audience: 'energylens-cloud',
  clientId: 'client',
  redirectUrl: 'io.energylens.app://login-callback',
  apiUrl: 'https://api.example',
);

class _Tokens implements CloudTokenStore {
  @override
  Future<void> clear() async {}
  @override
  Future<CloudTokens?> read() async => const CloudTokens(accessToken: 'token');
  @override
  Future<void> save(CloudTokens value) async {}
}

class _Auth implements CloudAuthenticator {
  @override
  Future<CloudTokens> refresh(CloudAuthConfig config, String token) async =>
      const CloudTokens(accessToken: 'token');
  @override
  Future<CloudTokens> signIn(CloudAuthConfig config) async =>
      const CloudTokens(accessToken: 'token');
}

class _Credentials extends DiscoveryCredentials {
  _Credentials(this.pairing);
  final StoredPairingCredential? pairing;
  final scopes = <String>[];
  @override
  Future<StoredPairingCredential?> readOwnedPairing(
    OwnedPairingScope scope,
    HubOwnership ownership,
  ) async {
    scopes.add(scope.identity);
    if (ownership.homeId != scope.homeId || scope.accountId != 'account-a') {
      return null;
    }
    return pairing;
  }
}

class _HubApi extends DiscoveryApi {
  HubOwnerAuthorization? authorization;
  bool verified = false;
  int reads = 0;
  void Function()? beforeRead;

  @override
  DiscoveryApi authorizedFor(HubOwnerAuthorization owner) {
    authorization = owner;
    return this;
  }

  @override
  Future<void> verifyStoredPairing(StoredHubIdentity pairing) async {
    expect(pairing.address, address);
    expect(pairing.hubId, hub);
    verified = true;
  }

  @override
  Future<List<SavedPlug>> saved(String baseUrl, String token) async {
    expect(verified, isTrue);
    expect(authorization?.homeId, home);
    expect(authorization?.isCurrent(), isTrue);
    beforeRead?.call();
    reads++;
    return const [
      SavedPlug(
        id: 'plug-8',
        ip: '192.168.1.8',
        model: 'KS8',
        name: 'Kitchehn Mixer Plug KS8',
        room: '',
        meterStatus: 'absent',
        lastVerifiedAt: 0,
      ),
    ];
  }
}

class _ReplacementHubApi extends _HubApi {
  @override
  Future<List<SavedPlug>> saved(String baseUrl, String token) async => const [
    SavedPlug(
      id: 'ks8-id',
      ip: '192.168.1.8',
      model: 'KP115',
      name: 'Kitchen Mixer Plug KS8',
      room: '',
      meterStatus: 'verified',
      lastVerifiedAt: 0,
    ),
    SavedPlug(
      id: 'ks19-id',
      ip: '192.168.1.19',
      model: 'HS103',
      name: 'Living Room Lamp KS19',
      room: '',
      meterStatus: 'absent',
      lastVerifiedAt: 0,
    ),
    SavedPlug(
      id: 'other-id',
      ip: '192.168.1.30',
      model: 'KP115',
      name: 'Other plug',
      room: '',
      meterStatus: 'verified',
      lastVerifiedAt: 0,
    ),
  ];
}

class _MultiCredentials extends DiscoveryCredentials {
  _MultiCredentials(this.pairings);
  final Map<String, StoredPairingCredential> pairings;

  @override
  Future<StoredPairingCredential?> readOwnedPairing(
    OwnedPairingScope scope,
    HubOwnership ownership,
  ) async => pairings[ownership.localHubId];
}

class _MultiHubApi extends DiscoveryApi {
  _MultiHubApi({required this.offlineAddress, required this.failOnSaved});
  final String offlineAddress;
  final bool failOnSaved;
  final verified = <String>{};
  void Function()? beforeFailure;

  @override
  DiscoveryApi authorizedFor(HubOwnerAuthorization owner) {
    expect(owner.homeId, home);
    expect(owner.isCurrent(), isTrue);
    return this;
  }

  @override
  Future<void> verifyStoredPairing(StoredHubIdentity pairing) async {
    if (!failOnSaved && pairing.address == offlineAddress) {
      throw const PairingException('Hub is offline');
    }
    verified.add(pairing.address);
  }

  @override
  Future<List<SavedPlug>> saved(String baseUrl, String token) async {
    expect(verified, contains(baseUrl));
    if (failOnSaved && baseUrl == offlineAddress) {
      beforeFailure?.call();
      throw StateError('Hub is offline');
    }
    return [
      SavedPlug(
        id: 'plug-8',
        ip: '192.168.1.8',
        model: 'KS8',
        name: 'Saved plug',
        room: '',
        meterStatus: 'absent',
        lastVerifiedAt: 0,
      ),
    ];
  }
}

CloudApiClient _cloud({String ownershipHome = home}) => CloudApiClient(
  session: CloudSession(
    config: config,
    store: _Tokens(),
    authenticator: _Auth(),
  ),
  client: MockClient(
    (_) async => http.Response(
      jsonEncode({
        'hubs': [
          {
            'hub_id': 'cloud-hub',
            'local_hub_id': hub,
            'home_id': ownershipHome,
            'ownership_epoch': 3,
            'version': 1,
          },
        ],
      }),
      200,
    ),
  ),
);

CloudApiClient _multiCloud() => CloudApiClient(
  session: CloudSession(
    config: config,
    store: _Tokens(),
    authenticator: _Auth(),
  ),
  client: MockClient(
    (_) async => http.Response(
      jsonEncode({
        'hubs': [
          for (final id in [hub, otherHub])
            {
              'hub_id': 'cloud-$id',
              'local_hub_id': id,
              'home_id': home,
              'ownership_epoch': 3,
              'version': 1,
            },
        ],
      }),
      200,
    ),
  ),
);

CloudApiClient _cloudWithAttachments() => CloudApiClient(
  session: CloudSession(
    config: config,
    store: _Tokens(),
    authenticator: _Auth(),
  ),
  client: MockClient((request) async {
    final path = request.url.path;
    if (path.endsWith('/hubs')) {
      return http.Response(
        jsonEncode({
          'hubs': [
            {
              'hub_id': 'cloud-hub',
              'local_hub_id': hub,
              'home_id': home,
              'ownership_epoch': 3,
              'version': 1,
            },
          ],
        }),
        200,
      );
    }
    if (path.endsWith('/attachments')) {
      return http.Response(
        jsonEncode({
          'attachments': [
            for (final (id, appliance, sensor) in [
              (
                'aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa',
                '11111111-aaaa-4aaa-8aaa-aaaaaaaaaaaa',
                '11111111-bbbb-4bbb-8bbb-bbbbbbbbbbbb',
              ),
              (
                'bbbbbbbb-bbbb-4bbb-8bbb-bbbbbbbbbbbb',
                '22222222-aaaa-4aaa-8aaa-aaaaaaaaaaaa',
                '22222222-bbbb-4bbb-8bbb-bbbbbbbbbbbb',
              ),
            ])
              {
                'id': id,
                'home_id': home,
                'appliance_id': appliance,
                'sensor_id': sensor,
                'started_at': '2026-10-17T00:00:00Z',
                'ended_at': null,
              },
          ],
        }),
        200,
      );
    }
    if (path.endsWith('/sensors')) {
      return http.Response(
        jsonEncode({
          'sensors': [
            for (final (id, local) in [
              ('11111111-bbbb-4bbb-8bbb-bbbbbbbbbbbb', 'ks8-id'),
              ('22222222-bbbb-4bbb-8bbb-bbbbbbbbbbbb', 'ks19-id'),
            ])
              {
                'id': id,
                'home_id': home,
                'hub_id': 'cloud-hub',
                'ownership_epoch': 3,
                'local_sensor_id': local,
                'kind': 'plug',
                'capabilities': ['power'],
                'version': 1,
              },
          ],
        }),
        200,
      );
    }
    return http.Response('{}', 404);
  }),
);

void main() {
  final pairing = StoredPairingCredential(
    address: address,
    hubId: hub,
    clientId: 'client',
    token: 'secret',
    ownershipEpoch: 3,
  );

  test('reads owner-scoped saved plugs even without a meter', () async {
    final credentials = _Credentials(pairing);
    final api = _HubApi();
    final rows =
        await CloudSavedPlugInventory(api: api, credentials: credentials).read(
          cloud: _cloud(),
          accountId: 'account-a',
          homeId: home,
          isCurrent: () => true,
        );
    expect(rows.single.id, '$hub|plug-8');
    expect(rows.single.name, 'Kitchehn Mixer Plug KS8');
    expect(
      credentials.scopes,
      everyElement('https://api.example|email_password|account-a|$home'),
    );
    expect(api.reads, 1);
  });

  test(
    'omits KS8 and KS19 plug rows when their replacements are attached',
    () async {
      const replacements = [
        CloudAppliance(
          id: '11111111-aaaa-4aaa-8aaa-aaaaaaaaaaaa',
          homeId: home,
          name: 'Dyson cool fan',
          category: 'fan',
          room: null,
          brand: 'Dyson',
          fullModel: '',
          fuel: 'electric',
          matchQuality: 'exact',
        ),
        CloudAppliance(
          id: '22222222-aaaa-4aaa-8aaa-aaaaaaaaaaaa',
          homeId: home,
          name: 'Philips Hue two-bulb lamp',
          category: 'lighting',
          room: null,
          brand: 'Philips Hue',
          fullModel: '',
          fuel: 'electric',
          matchQuality: 'exact',
        ),
      ];
      final rows =
          await CloudSavedPlugInventory(
            api: _ReplacementHubApi(),
            credentials: _Credentials(pairing),
          ).read(
            cloud: _cloudWithAttachments(),
            accountId: 'account-a',
            homeId: home,
            appliances: replacements,
            isCurrent: () => true,
          );
      expect(rows.map((row) => row.id), ['$hub|other-id']);
    },
  );

  test('drops a result when owner scope changes during the Hub read', () async {
    var current = true;
    final api = _HubApi()..beforeRead = () => current = false;
    final rows =
        await CloudSavedPlugInventory(
          api: api,
          credentials: _Credentials(pairing),
        ).read(
          cloud: _cloud(),
          accountId: 'account-a',
          homeId: home,
          isCurrent: () => current,
        );
    expect(rows, isEmpty);
  });

  test('rejects ownership from a different Cloud home', () async {
    final api = _HubApi();
    await expectLater(
      CloudSavedPlugInventory(
        api: api,
        credentials: _Credentials(pairing),
      ).read(
        cloud: _cloud(ownershipHome: otherHome),
        accountId: 'account-a',
        homeId: home,
        isCurrent: () => true,
      ),
      throwsFormatException,
    );
    expect(api.reads, 0);
  });

  test(
    'an offline Hub does not hide another owned Hub, in either order',
    () async {
      final credentials = _MultiCredentials({
        hub: pairing,
        otherHub: StoredPairingCredential(
          address: otherAddress,
          hubId: otherHub,
          clientId: 'other-client',
          token: 'other-secret',
          ownershipEpoch: 3,
        ),
      });
      for (final (offlineAddress, failOnSaved, expectedHub) in [
        (address, false, otherHub),
        (otherAddress, true, hub),
      ]) {
        final api = _MultiHubApi(
          offlineAddress: offlineAddress,
          failOnSaved: failOnSaved,
        );
        final rows =
            await CloudSavedPlugInventory(
              api: api,
              credentials: credentials,
            ).read(
              cloud: _multiCloud(),
              accountId: 'account-a',
              homeId: home,
              isCurrent: () => true,
            );
        expect(rows.map((row) => row.id), ['$expectedHub|plug-8']);
      }
    },
  );

  test(
    'a stale scope discards earlier results when a later Hub fails',
    () async {
      var current = true;
      final api = _MultiHubApi(offlineAddress: otherAddress, failOnSaved: true)
        ..beforeFailure = () => current = false;
      final rows =
          await CloudSavedPlugInventory(
            api: api,
            credentials: _MultiCredentials({
              hub: pairing,
              otherHub: StoredPairingCredential(
                address: otherAddress,
                hubId: otherHub,
                clientId: 'other-client',
                token: 'other-secret',
                ownershipEpoch: 3,
              ),
            }),
          ).read(
            cloud: _multiCloud(),
            accountId: 'account-a',
            homeId: home,
            isCurrent: () => current,
          );
      expect(rows, isEmpty);
    },
  );
}
