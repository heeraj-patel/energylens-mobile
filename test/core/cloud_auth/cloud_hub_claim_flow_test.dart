import 'dart:convert';

import 'package:energylens_mobile/core/cloud_api/cloud_api_client.dart';
import 'package:energylens_mobile/core/cloud_api/cloud_home.dart';
import 'package:energylens_mobile/core/cloud_api/cloud_hub_claim_flow.dart';
import 'package:energylens_mobile/core/cloud_auth/cloud_auth.dart';
import 'package:energylens_mobile/features/discovery/discovery_api.dart';
import 'package:energylens_mobile/features/discovery/discovery_credentials.dart';
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
}
