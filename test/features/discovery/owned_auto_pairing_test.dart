import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:energylens_mobile/core/cloud_api/cloud_hub_claim.dart';
import 'package:energylens_mobile/core/cloud_auth/cloud_auth.dart';
import 'package:energylens_mobile/features/discovery/discovery_api.dart';
import 'package:energylens_mobile/features/discovery/discovery_credentials.dart';
import 'package:flutter_test/flutter_test.dart';

const _config = CloudAuthConfig(
  issuer: 'https://issuer.example',
  audience: 'audience',
  clientId: 'client',
  redirectUrl: 'io.energylens.app://login-callback',
  apiUrl: 'https://api.example',
);
const _pin = 'aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa';

class _Tokens implements CloudTokenStore {
  int reads = 0;
  @override
  Future<CloudTokens?> read() async {
    reads++;
    return const CloudTokens(accessToken: 'owner-jwt');
  }

  @override
  Future<void> clear() async {}
  @override
  Future<void> save(CloudTokens tokens) async {}
}

class _Auth implements CloudAuthenticator {
  @override
  Future<CloudTokens> signIn(CloudAuthConfig config) async =>
      throw UnimplementedError();
  @override
  Future<CloudTokens> refresh(
    CloudAuthConfig config,
    String refreshToken,
  ) async => throw UnimplementedError();
}

class _Transport implements PairingTransport {
  final requests = <(String, String?)>[];
  bool badPin = false;
  String healthId = 'local-hub';
  Map<String, dynamic> overrides = {};
  Future<void> Function(String)? afterRequest;

  @override
  Future<PairingHttpResponse> send(
    String address,
    String path,
    String method, {
    Map<String, dynamic>? body,
    String? bearerToken,
  }) async {
    if (badPin) throw const HandshakeException('Pin mismatch');
    requests.add((path, bearerToken));
    await afterRequest?.call(path);
    return PairingHttpResponse(
      statusCode: 200,
      body: jsonEncode(
        path == '/healthz'
            ? {'hub_id': healthId}
            : {
                'hub_id': 'local-hub',
                'client_id': body!['client_id'],
                'ownership_epoch': 3,
                'token_type': 'Bearer',
                'token': 'paired-token',
                ...overrides,
              },
      ),
    );
  }
}

class _Store implements SecureKeyValueStore {
  final values = <String, String>{};
  Future<void> Function()? afterWrite;
  @override
  Future<String?> read(String key) async => values[key];
  @override
  Future<void> write(String key, String value) async {
    values[key] = value;
    await afterWrite?.call();
  }

  @override
  Future<void> delete(String key) async => values.remove(key);
}

HubOwnership _ownership({DateTime? expiry, int epoch = 3}) => HubOwnership(
  hubId: 'cloud-hub',
  localHubId: 'local-hub',
  homeId: 'home',
  ownershipEpoch: epoch,
  version: 1,
  connection: HubConnection(
    httpsOrigin: 'https://192.168.1.20:18787',
    certificateSha256: _pin,
    expiresAt: expiry ?? DateTime.now().toUtc().add(const Duration(minutes: 5)),
  ),
);

void main() {
  late _Transport transport;
  late _Tokens tokens;
  late CloudSession session;
  late bool current;
  late HubOwnerAuthorization owner;
  setUp(() {
    transport = _Transport();
    tokens = _Tokens();
    current = true;
    session = CloudSession(
      config: _config,
      store: tokens,
      authenticator: _Auth(),
    );
    owner = HubOwnerAuthorization(
      session: session,
      homeId: 'home',
      isCurrent: () => current,
    );
  });

  Future<PairingClaim> claim({HubOwnership? ownership}) =>
      DiscoveryApi(pairingTransport: transport).claimOwnedPairing(
        ownership ?? _ownership(),
        clientId: 'app:client',
        owner: owner,
      );

  test('pins and verifies identity before acquiring the Cloud JWT', () async {
    transport.afterRequest = (path) async {
      if (path == '/healthz') expect(tokens.reads, 0);
    };
    expect((await claim()).token, 'paired-token');
    expect(transport.requests, [
      ('/healthz', null),
      ('/v1/pairing/owner-claim', 'owner-jwt'),
    ]);
  });

  for (final failure in ['pin', 'identity', 'expired', 'scope', 'unclaimed']) {
    test(
      '$failure failure never acquires or transmits the owner JWT',
      () async {
        transport.badPin = failure == 'pin';
        if (failure == 'identity') transport.healthId = 'attacker';
        if (failure == 'scope') current = false;
        await expectLater(
          claim(
            ownership: _ownership(
              epoch: failure == 'unclaimed' ? 1 : 3,
              expiry: failure == 'expired'
                  ? DateTime.now().toUtc().subtract(const Duration(seconds: 1))
                  : null,
            ),
          ),
          throwsA(anything),
        );
        expect(tokens.reads, 0);
        expect(transport.requests.any((r) => r.$2 != null), isFalse);
      },
    );
  }

  for (final field in [
    'hub_id',
    'client_id',
    'ownership_epoch',
    'token_type',
    'token',
  ]) {
    test('rejects mismatched $field in owner claim response', () async {
      transport.overrides[field] = field == 'ownership_epoch'
          ? 4
          : field == 'token'
          ? ''
          : 'wrong';
      await expectLater(claim(), throwsStateError);
    });
  }

  test(
    'scope switch during pinned health check prevents JWT transmission',
    () async {
      transport.afterRequest = (_) async {
        current = false;
      };
      await expectLater(claim(), throwsStateError);
      expect(tokens.reads, 0);
    },
  );

  test(
    'session switch while claim is pending discards returned token',
    () async {
      transport.afterRequest = (path) async {
        if (path.endsWith('owner-claim'))
          await session.selectCredentialMethod('username_password');
      };
      await expectLater(claim(), throwsStateError);
    },
  );

  test('malformed directory metadata is never used as trust', () {
    final valid = {
      'https_origin': 'https://192.168.1.20:18787',
      'certificate_sha256': _pin,
      'expires_at': '2099-01-01T00:00:00Z',
    };
    expect(HubConnection.tryParse(valid), isNotNull);
    for (final origin in [
      'http://192.168.1.20:18787',
      'https://u:p@192.168.1.20:18787',
      'https://192.168.1.20:18787#sha256=$_pin',
      'https://192.168.1.20:18787/path',
      'https://192.168.1.20:18787?q=1',
    ]) {
      expect(
        HubConnection.tryParse({...valid, 'https_origin': origin}),
        isNull,
      );
    }
    expect(
      HubConnection.tryParse({...valid, 'certificate_sha256': 'bad'}),
      isNull,
    );
    expect(
      HubConnection.tryParse({...valid, 'expires_at': 'tomorrow'}),
      isNull,
    );
    expect(HubConnection.tryParse(null), isNull);
  });

  test(
    'stores direct scoped token and removes it on a concurrent scope switch',
    () async {
      final store = _Store();
      final credentials = DiscoveryCredentials(storage: store);
      final scope = OwnedPairingScope(
        origin: _config.apiUrl,
        profile: 'oidc',
        accountId: 'owner',
        homeId: 'home',
      );
      const pairing = StoredPairingCredential(
        address: 'https://192.168.1.20:18787#sha256=$_pin',
        hubId: 'local-hub',
        clientId: 'app:client',
        token: 'paired-token',
        ownershipEpoch: 3,
      );
      await credentials.storeOwnedPairing(
        scope,
        _ownership(),
        pairing,
        isCurrent: () => current,
      );
      expect(
        (await credentials.readOwnedPairing(scope, _ownership()))?.token,
        'paired-token',
      );
      expect(await credentials.readPairing(), isNull);
      expect(store.values.values.any((v) => v.contains('owner-jwt')), isFalse);
      store.afterWrite = () async {
        current = false;
      };
      await expectLater(
        credentials.storeOwnedPairing(
          scope,
          _ownership(),
          pairing,
          isCurrent: () => current,
        ),
        throwsStateError,
      );
      expect(await credentials.readOwnedPairing(scope, _ownership()), isNull);
    },
  );
}
