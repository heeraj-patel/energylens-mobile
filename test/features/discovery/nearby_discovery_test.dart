import 'dart:io';
import 'dart:convert';

import 'package:energylens_mobile/features/discovery/discovery_api.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('shared protocol v2 fixture decodes into Mobile discovery models', () {
    // Run from energylens-mobile in the sibling-repository workspace layout.
    final fixture = jsonDecode(
      File(
        '../energylens-common-contracts/api/testdata/protocol-v2-hub-routes.json',
      ).readAsStringSync(),
    ) as Map<String, dynamic>;
    final scan = NearbyScan.fromJson(fixture['scan'] as Map<String, dynamic>);
    expect(scan.state, 'partial');
    expect(scan.isTerminal, isTrue);
    expect(scan.candidates.single.id, 'cand_1');
    expect(scan.candidates.single.addresses.single.kind, 'ipv4');
    expect(scan.candidates.single.capabilities.last.supportState, 'unknown');

    final inventory = (fixture['inventory_response'] as List<dynamic>)
        .map(
          (value) => NearbySavedDevice.fromJson(value as Map<String, dynamic>),
        )
        .toList();
    expect(inventory.single.endpoints.single.measurementScope, 'device');
    expect(inventory.single.bindings.single.nativeDeviceId, 'shelly-1');
  });

  const candidateJson = <String, dynamic>{
    'candidate_id': 'scope:scan:tv',
    'scan_id': 'scope:scan',
    'expires_at_ms': 4102444800000,
    'manufacturer': null,
    'model': null,
    'category': null,
    'addresses': [
      {'kind': 'service_id', 'value': 'urn:example:tv', 'interface': null},
    ],
    'sources': ['ssdp'],
    'capabilities': [
      {'name': 'energy', 'support_state': 'unknown'},
    ],
    'requires_action': true,
    'reason_code': 'needs_credentials',
  };

  test(
    'generic candidate keeps partial identity and has no plug assumptions',
    () {
      final candidate = NearbyDeviceCandidate.fromJson(candidateJson);
      expect(candidate.displayName, 'Unnamed device');
      expect(candidate.addresses.single.kind, 'service_id');
      expect(candidate.capabilities.single.supportState, 'unknown');
      expect(candidate.canAdopt, isFalse);
      expect(candidate.reasonCode, 'needs_credentials');
      expect(
        NearbyDeviceCandidate.fromJson({...candidateJson, 'name': 'Den TV'})
            .displayName,
        'Den TV',
      );
    },
  );

  test('scan identity and saved state decode with older Hub fallback', () {
    final old = NearbyDeviceCandidate.fromJson(candidateJson);
    expect(old.alreadySaved, isFalse);
    expect(old.stableIdentity, isNull);
    final saved = NearbyDeviceCandidate.fromJson({
      ...candidateJson,
      'already_saved': true,
      'stable_identity': {'source': 'ssdp', 'value': 'uuid:tv-one'},
    });
    expect(saved.alreadySaved, isTrue);
    expect(
      saved.stableIdentity!.matches(
        const NearbyStableIdentity('ssdp', 'uuid:tv-one'),
      ),
      isTrue,
    );
    expect(
      saved.stableIdentity!.matches(
        const NearbyStableIdentity('ssdp', 'uuid:tv-two'),
      ),
      isFalse,
    );
  });

  test('generic inventory preserves endpoint scope and binding identity', () {
    final device = NearbySavedDevice.fromJson({
      'id': 'device-1',
      'name': 'Meter',
      'room': '',
      'endpoints': [
        {
          'id': 'ep-2',
          'component_id': '2',
          'measurement_scope': 'outlet',
          'parent_endpoint_id': null,
          'capabilities': [
            {'name': 'energy', 'support_state': 'verified'},
          ],
        },
      ],
      'bindings': [
        {
          'id': 'binding-1',
          'protocol': 'shelly_gen2',
          'adapter_instance_id': 'local',
          'security_domain_id': 'home',
          'native_device_id': 'meter-1',
        },
      ],
    });
    expect(device.endpoints.single.measurementScope, 'outlet');
    expect(
      device.endpoints.single.capabilities.single.supportState,
      'verified',
    );
    expect(device.bindings.single.nativeDeviceId, 'meter-1');
  });

  test(
    'older Hub 404 selects v1 fallback, while other failure stays visible',
    () async {
      final context = SecurityContext()
        ..useCertificateChain('test/fixtures/hub_tls_test_cert.pem')
        ..usePrivateKey('test/fixtures/hub_tls_test_key.pem');
      final server = await HttpServer.bindSecure(
        InternetAddress.loopbackIPv4,
        0,
        context,
      );
      var status = 404;
      server.listen((request) async {
        request.response.statusCode = status;
        request.response.headers.contentType = ContentType.json;
        request.response.write('{"error":{"message":"unavailable"}}');
        await request.response.close();
      });
      try {
        const pin =
            '50c731cdfd5802849c6e68983836566463b7cf40f95ae5e0c6575c81772251e9';
        final base = 'https://127.0.0.1:${server.port}#sha256=$pin';
        const api = DiscoveryApi();
        expect(await api.supportsNearbyDiscovery(base, 'token'), isFalse);
        status = 503;
        await expectLater(
          api.supportsNearbyDiscovery(base, 'token'),
          throwsA(isA<StateError>()),
        );
      } finally {
        await server.close(force: true);
      }
    },
  );

  test('cancel sends a scoped POST to the Hub scan route', () async {
    final context = SecurityContext()
      ..useCertificateChain('test/fixtures/hub_tls_test_cert.pem')
      ..usePrivateKey('test/fixtures/hub_tls_test_key.pem');
    final server = await HttpServer.bindSecure(
      InternetAddress.loopbackIPv4,
      0,
      context,
    );
    String? method;
    String? path;
    String? authorization;
    server.listen((request) async {
      method = request.method;
      path = request.uri.path;
      authorization = request.headers.value(HttpHeaders.authorizationHeader);
      request.response.headers.contentType = ContentType.json;
      request.response.write(
        '{"scan_id":"scan-1","state":"cancelled","expires_at_ms":4102444800000,"candidates":[]}',
      );
      await request.response.close();
    });
    try {
      const pin =
          '50c731cdfd5802849c6e68983836566463b7cf40f95ae5e0c6575c81772251e9';
      final scan = await const DiscoveryApi().cancelNearbyScan(
        'https://127.0.0.1:${server.port}#sha256=$pin',
        'client-token',
        'scan-1',
      );
      expect(scan.state, 'cancelled');
      expect(method, 'POST');
      expect(path, '/v2/discovery/scans/scan-1/cancel');
      expect(authorization, 'Bearer client-token');
    } finally {
      await server.close(force: true);
    }
  });
}
