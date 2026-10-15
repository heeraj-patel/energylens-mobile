import 'dart:async';
import 'dart:convert';

import 'package:energylens_mobile/core/cloud_api/cloud_api_client.dart';
import 'package:energylens_mobile/core/cloud_api/cloud_home.dart';
import 'package:energylens_mobile/core/cloud_api/cloud_hub_claim_flow.dart';
import 'package:energylens_mobile/core/cloud_auth/cloud_auth.dart';
import 'package:energylens_mobile/features/discovery/discovery_api.dart';
import 'package:energylens_mobile/features/discovery/discovery_credentials.dart';
import 'package:energylens_mobile/features/identify/onboarding_draft_store.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

const home = CloudHome(
  id: '38d634c0-54c6-4c60-9523-0923dce8c040',
  name: 'Main home',
  timezone: 'America/Chicago',
  countryCode: 'US',
  postalCode: '60601',
);
const hubId = 'elhub_contractvector';
const address =
    'https://192.168.1.20:18787#sha256=aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa';
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
  Future<CloudTokens?> read() async =>
      const CloudTokens(accessToken: 'owner-token');
  @override
  Future<void> save(CloudTokens value) async {}
}

class _Auth implements CloudAuthenticator {
  @override
  Future<CloudTokens> refresh(
    CloudAuthConfig config,
    String refreshToken,
  ) async => const CloudTokens(accessToken: 'fresh-token');
  @override
  Future<CloudTokens> signIn(CloudAuthConfig config) async =>
      const CloudTokens(accessToken: 'owner-token');
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

class _PendingStore implements OnboardingDraftStorage {
  String? value;
  Completer<void>? holdWrite;
  final writeStarted = Completer<void>();
  int clears = 0;

  @override
  Future<String?> read() async => value;
  @override
  Future<void> write(String next) async {
    if (!writeStarted.isCompleted) writeStarted.complete();
    await holdWrite?.future;
    value = next;
  }

  @override
  Future<void> clear() async {
    clears++;
    value = null;
  }
}

Map<String, dynamic> _ownership() => {
  'hub_id': 'a2bcad23-1a7f-4b19-ab46-7f239992d331',
  'local_hub_id': hubId,
  'home_id': home.id,
  'ownership_epoch': 1,
  'version': 1,
};

Map<String, dynamic> _challenge() => {
  'claim_id': 'da17c425-d948-4d6b-8cc0-acf84da38c39',
  'hub_id': 'a2bcad23-1a7f-4b19-ab46-7f239992d331',
  'local_hub_id': hubId,
  'nonce': 'AgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgI',
  'expires_at': DateTime.now()
      .toUtc()
      .add(const Duration(minutes: 4))
      .toIso8601String(),
};

OwnedPairingScope _scope([String accountId = 'account-a']) => OwnedPairingScope(
  origin: config.apiUrl,
  profile: 'username_password',
  accountId: accountId,
  homeId: home.id,
);

CloudApiClient _cloud(http.Client client) => CloudApiClient(
  session: CloudSession(
    config: config,
    store: _Tokens(),
    authenticator: _Auth(),
  ),
  client: client,
);

class _HubTransport implements PairingTransport {
  final requests = <(String, String?, Map<String, dynamic>?)>[];
  @override
  Future<PairingHttpResponse> send(
    String address,
    String path,
    String method, {
    Map<String, dynamic>? body,
    String? bearerToken,
  }) async {
    requests.add((path, bearerToken, body));
    if (path == '/healthz') {
      return const PairingHttpResponse(
        statusCode: 200,
        body: '{"hub_id":"elhub_contractvector"}',
      );
    }
    return PairingHttpResponse(
      statusCode: 200,
      body: jsonEncode({
        'claim_id': body!['claim_id'],
        'local_hub_id': hubId,
        'possession_proof': 'AQEBAQEBAQEBAQEBAQEBAQEBAQEBAQEBAQEBAQEBAQE',
        'device_signature': 'signed-by-hub',
      }),
    );
  }
}

void main() {
  test('paired proof links selected owner home and uncertain finish retries unchanged', () async {
    final store = _Store();
    final credentials = DiscoveryCredentials(storage: store);
    await credentials.savePairing(
      address: address,
      hubId: hubId,
      clientId: 'phone',
      token: 'paired-token',
    );
    final transport = _HubTransport();
    final posts = <http.Request>[];
    final cloud = CloudApiClient(
      session: CloudSession(
        config: config,
        store: _Tokens(),
        authenticator: _Auth(),
      ),
      client: MockClient((request) async {
        posts.add(request);
        expect(request.headers['Authorization'], 'Bearer owner-token');
        if (request.url.path.endsWith('/hub-claims')) {
          return http.Response(
            jsonEncode({
              'claim_id': 'da17c425-d948-4d6b-8cc0-acf84da38c39',
              'hub_id': 'a2bcad23-1a7f-4b19-ab46-7f239992d331',
              'local_hub_id': hubId,
              'nonce': 'AgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgI',
              'expires_at': DateTime.now()
                  .toUtc()
                  .add(const Duration(minutes: 4))
                  .toIso8601String(),
            }),
            201,
          );
        }
        if (posts.where((item) => item.url.path == '/v1/hubs/claim').length ==
            1) {
          return http.Response('', 503);
        }
        return http.Response(
          jsonEncode({
            'hub_id': 'a2bcad23-1a7f-4b19-ab46-7f239992d331',
            'local_hub_id': hubId,
            'home_id': home.id,
            'ownership_epoch': 1,
            'version': 1,
          }),
          200,
        );
      }),
    );
    final flow = CloudHubClaimFlow(
      cloud: cloud,
      hub: DiscoveryApi(pairingTransport: transport),
      credentials: credentials,
    );
    await expectLater(flow.claim(home), throwsA(isA<CloudApiException>()));
    final result = await flow.claim(home);
    expect(result.homeId, home.id);
    expect(posts.map((request) => request.url.path), [
      '/v1/homes/${home.id}/hub-claims',
      '/v1/hubs/claim',
      '/v1/hubs/claim',
    ]);
    expect(
      posts[1].headers['Idempotency-Key'],
      posts[2].headers['Idempotency-Key'],
    );
    expect(posts[1].body, posts[2].body);
    expect(transport.requests.map((request) => request.$1), [
      '/healthz',
      '/v1/cloud/claim-proofs',
    ]);
    expect(transport.requests.last.$2, 'paired-token');
    expect(transport.requests.first.$2, isNull);
    expect(transport.requests.last.$3?['local_hub_id'], hubId);
    expect(posts[1].body, isNot(contains('paired-token')));
    cloud.close();
  });

  test(
    'cloud challenge for another hub never reaches local proof endpoint',
    () async {
      final store = _Store();
      final credentials = DiscoveryCredentials(storage: store);
      await credentials.savePairing(
        address: address,
        hubId: hubId,
        clientId: 'phone',
        token: 'paired-token',
      );
      final transport = _HubTransport();
      final cloud = CloudApiClient(
        session: CloudSession(
          config: config,
          store: _Tokens(),
          authenticator: _Auth(),
        ),
        client: MockClient(
          (_) async => http.Response(
            jsonEncode({
              'claim_id': 'da17c425-d948-4d6b-8cc0-acf84da38c39',
              'hub_id': 'a2bcad23-1a7f-4b19-ab46-7f239992d331',
              'local_hub_id': 'elhub_other',
              'nonce': 'AgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgI',
              'expires_at': DateTime.now()
                  .toUtc()
                  .add(const Duration(minutes: 4))
                  .toIso8601String(),
            }),
            201,
          ),
        ),
      );
      await expectLater(
        CloudHubClaimFlow(
          cloud: cloud,
          hub: DiscoveryApi(pairingTransport: transport),
          credentials: credentials,
        ).claim(home),
        throwsA(isA<PairingException>()),
      );
      expect(transport.requests, isEmpty);
      cloud.close();
    },
  );

  test(
    'scoped pending finish survives restart with its original key',
    () async {
      final credentials = DiscoveryCredentials(storage: _Store());
      await credentials.savePairing(
        address: address,
        hubId: hubId,
        clientId: 'phone',
        token: 'paired-token',
      );
      final pending = _PendingStore();
      final transport = _HubTransport();
      final requests = <http.Request>[];
      final cloud = _cloud(
        MockClient((request) async {
          requests.add(request);
          if (request.url.path.endsWith('/hubs')) {
            return http.Response('{"hubs":[]}', 200);
          }
          if (request.url.path.endsWith('/hub-claims')) {
            return http.Response(jsonEncode(_challenge()), 201);
          }
          if (requests
                  .where((item) => item.url.path == '/v1/hubs/claim')
                  .length ==
              1) {
            return http.Response('', 503);
          }
          return http.Response(jsonEncode(_ownership()), 200);
        }),
      );
      CloudHubClaimFlow flow() => CloudHubClaimFlow(
        cloud: cloud,
        hub: DiscoveryApi(pairingTransport: transport),
        credentials: credentials,
        scope: _scope(),
        pendingStorage: pending,
      );
      await expectLater(flow().claim(home), throwsA(isA<CloudApiException>()));
      final saved = pending.value;
      expect(saved, isNotNull);
      final result = await flow().claim(home);
      expect(result.homeId, home.id);
      final finishes = requests
          .where((request) => request.url.path == '/v1/hubs/claim')
          .toList();
      expect(finishes, hasLength(2));
      expect(
        finishes[0].headers['Idempotency-Key'],
        finishes[1].headers['Idempotency-Key'],
      );
      expect(finishes[0].body, finishes[1].body);
      expect(
        requests.where((request) => request.url.path.endsWith('/hub-claims')),
        hasLength(1),
      );
      expect(pending.value, isNull);
      cloud.close();
    },
  );

  test('ownership readback reconciles lost finish without replay', () async {
    final credentials = DiscoveryCredentials(storage: _Store());
    await credentials.savePairing(
      address: address,
      hubId: hubId,
      clientId: 'phone',
      token: 'paired-token',
    );
    final pending = _PendingStore();
    var owned = false;
    var finishes = 0;
    final cloud = _cloud(
      MockClient((request) async {
        if (request.url.path.endsWith('/hubs')) {
          return http.Response(
            jsonEncode({
              'hubs': owned ? [_ownership()] : [],
            }),
            200,
          );
        }
        if (request.url.path.endsWith('/hub-claims')) {
          return http.Response(jsonEncode(_challenge()), 201);
        }
        finishes++;
        owned = true;
        return http.Response('', 503);
      }),
    );
    CloudHubClaimFlow flow() => CloudHubClaimFlow(
      cloud: cloud,
      hub: DiscoveryApi(pairingTransport: _HubTransport()),
      credentials: credentials,
      scope: _scope(),
      pendingStorage: pending,
    );
    await expectLater(flow().claim(home), throwsA(isA<CloudApiException>()));
    expect((await flow().claim(home)).ownershipEpoch, 1);
    expect(finishes, 1);
    expect(pending.value, isNull);
    cloud.close();
  });

  test(
    'expired scoped claim reconciles first, then same instance can start over',
    () async {
      final credentials = DiscoveryCredentials(storage: _Store());
      await credentials.savePairing(
        address: address,
        hubId: hubId,
        clientId: 'phone',
        token: 'paired-token',
      );
      final pending = _PendingStore();
      pending.value = jsonEncode({
        'scope': _scope().identity,
        'home_id': home.id,
        'hub_id': hubId,
        'claim_id': 'da17c425-d948-4d6b-8cc0-acf84da38c39',
        'expires_at': DateTime.now()
            .toUtc()
            .subtract(const Duration(minutes: 1))
            .toIso8601String(),
        'operation_key': 'original-key',
        'proof': {
          'claim_id': 'da17c425-d948-4d6b-8cc0-acf84da38c39',
          'local_hub_id': hubId,
          'possession_proof': 'AQEBAQEBAQEBAQEBAQEBAQEBAQEBAQEBAQEBAQEBAQE',
          'device_signature': 'signed-by-hub',
        },
      });
      final paths = <String>[];
      final cloud = _cloud(
        MockClient((request) async {
          paths.add(request.url.path);
          if (request.url.path.endsWith('/hubs')) {
            return http.Response('{"hubs":[]}', 200);
          }
          if (request.url.path.endsWith('/hub-claims')) {
            return http.Response(jsonEncode(_challenge()), 201);
          }
          return http.Response(jsonEncode(_ownership()), 200);
        }),
      );
      final flow = CloudHubClaimFlow(
        cloud: cloud,
        hub: DiscoveryApi(pairingTransport: _HubTransport()),
        credentials: credentials,
        scope: _scope(),
        pendingStorage: pending,
      );
      await expectLater(flow.claim(home), throwsA(isA<StateError>()));
      expect(paths, ['/v1/homes/${home.id}/hubs']);
      expect(pending.value, isNull);
      expect((await flow.claim(home)).homeId, home.id);
      expect(paths.where((path) => path.endsWith('/hub-claims')), hasLength(1));
      cloud.close();
    },
  );

  test(
    'expired uncertain finish clears in-memory proof before retry',
    () async {
      final credentials = DiscoveryCredentials(storage: _Store());
      await credentials.savePairing(
        address: address,
        hubId: hubId,
        clientId: 'phone',
        token: 'paired-token',
      );
      final pending = _PendingStore();
      var finishes = 0;
      var challenges = 0;
      final cloud = _cloud(
        MockClient((request) async {
          if (request.url.path.endsWith('/hubs')) {
            return http.Response('{"hubs":[]}', 200);
          }
          if (request.url.path.endsWith('/hub-claims')) {
            challenges++;
            return http.Response(jsonEncode(_challenge()), 201);
          }
          finishes++;
          return finishes == 1
              ? http.Response('', 503)
              : http.Response(jsonEncode(_ownership()), 200);
        }),
      );
      final flow = CloudHubClaimFlow(
        cloud: cloud,
        hub: DiscoveryApi(pairingTransport: _HubTransport()),
        credentials: credentials,
        scope: _scope(),
        pendingStorage: pending,
      );
      await expectLater(flow.claim(home), throwsA(isA<CloudApiException>()));
      final saved = jsonDecode(pending.value!) as Map<String, dynamic>;
      saved['expires_at'] = DateTime.now()
          .toUtc()
          .subtract(const Duration(minutes: 1))
          .toIso8601String();
      pending.value = jsonEncode(saved);
      await expectLater(flow.claim(home), throwsA(isA<StateError>()));
      expect(finishes, 1);
      expect(pending.value, isNull);
      expect((await flow.claim(home)).homeId, home.id);
      expect(challenges, 2);
      expect(finishes, 2);
      cloud.close();
    },
  );

  test(
    'foreign account pending claim cannot start or replay a claim',
    () async {
      final credentials = DiscoveryCredentials(storage: _Store());
      await credentials.savePairing(
        address: address,
        hubId: hubId,
        clientId: 'phone',
        token: 'paired-token',
      );
      final pending = _PendingStore()
        ..value = jsonEncode({
          'scope': _scope('account-a').identity,
          'home_id': home.id,
          'hub_id': hubId,
          'expires_at': _challenge()['expires_at'],
          'operation_key': 'old-account-key',
          'proof': {
            'claim_id': 'da17c425-d948-4d6b-8cc0-acf84da38c39',
            'local_hub_id': hubId,
            'possession_proof': 'AQEBAQEBAQEBAQEBAQEBAQEBAQEBAQEBAQEBAQEBAQE',
            'device_signature': 'signed-by-hub',
          },
        });
      var requests = 0;
      final cloud = _cloud(
        MockClient((request) async {
          requests++;
          return http.Response('', 500);
        }),
      );
      await expectLater(
        CloudHubClaimFlow(
          cloud: cloud,
          hub: DiscoveryApi(pairingTransport: _HubTransport()),
          credentials: credentials,
          scope: _scope('account-b'),
          pendingStorage: pending,
        ).claim(home),
        throwsA(isA<StateError>()),
      );
      expect(requests, 0);
      expect(pending.value, isNull);
      cloud.close();
    },
  );

  test('scope invalidation clears a delayed pending proof write', () async {
    final credentials = DiscoveryCredentials(storage: _Store());
    await credentials.savePairing(
      address: address,
      hubId: hubId,
      clientId: 'phone',
      token: 'paired-token',
    );
    final pending = _PendingStore()..holdWrite = Completer<void>();
    final paths = <String>[];
    final cloud = _cloud(
      MockClient((request) async {
        paths.add(request.url.path);
        if (request.url.path.endsWith('/hubs')) {
          return http.Response('{"hubs":[]}', 200);
        }
        return http.Response(jsonEncode(_challenge()), 201);
      }),
    );
    final flow = CloudHubClaimFlow(
      cloud: cloud,
      hub: DiscoveryApi(pairingTransport: _HubTransport()),
      credentials: credentials,
      scope: _scope(),
      pendingStorage: pending,
    );
    final claim = flow.claim(home);
    await pending.writeStarted.future;
    final invalidation = CloudHubClaimFlow.invalidatePendingClaims(
      storage: pending,
    );
    pending.holdWrite!.complete();
    await expectLater(claim, throwsA(isA<StateError>()));
    await invalidation;
    expect(pending.value, isNull);
    expect(paths.where((path) => path == '/v1/hubs/claim'), isEmpty);
    cloud.close();
  });
}
