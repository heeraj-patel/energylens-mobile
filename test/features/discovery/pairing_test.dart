import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:energylens_mobile/features/discovery/discovery_api.dart';
import 'package:energylens_mobile/features/discovery/discovery_credentials.dart';

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
  }) async {
    if (failPin) throw HandshakeException('Certificate pin mismatch');
    requests.add((method, path, body));
    if (path == '/healthz') {
      return PairingHttpResponse(
        statusCode: 200,
        body: jsonEncode({'status': 'ok', 'api_version': '1', 'hub_id': hubId}),
      );
    }
    return const PairingHttpResponse(
      statusCode: 200,
      body: '{"hub_id":"hub-1","client_id":"app:test","token":"client-token","token_type":"Bearer"}',
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
}
