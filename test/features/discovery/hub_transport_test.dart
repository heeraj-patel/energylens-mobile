import 'dart:convert';
import 'dart:io';

import 'package:energylens_mobile/features/discovery/discovery_api.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  const fingerprint =
      'ba7816bf8f01cfea414140de5dae2223b00361a396177a9cb410ff61f20015ad';

  test('accepts HTTPS LAN and Tailscale addresses and strips the pin', () {
    final lan = HubEndpoint.parse('https://192.168.1.20:18787');
    expect(lan.uri.toString(), 'https://192.168.1.20:18787');
    expect(lan.pin, isNull);

    final tailnet = HubEndpoint.parse(
      'https://100.115.133.73:18787#sha256=$fingerprint',
    );
    expect(tailnet.uri.toString(), 'https://100.115.133.73:18787');
    expect(tailnet.pin, fingerprint);
  });

  test('rejects plaintext, public hosts, and malformed certificate pins', () {
    for (final address in [
      'http://192.168.1.20:18787',
      'https://8.8.8.8:18787',
      'https://192.168.1.20:18787#',
      'https://192.168.1.20:18787#sha256=1234',
      'https://192.168.1.20:18787#sha256=${fingerprint.toUpperCase()}',
      'https://192.168.1.20:18787#sha256=$fingerprint&other=1',
      'https://192.168.1.20:18787/path#sha256=$fingerprint',
      'https://user@192.168.1.20:18787#sha256=$fingerprint',
    ]) {
      expect(
        () => HubEndpoint.parse(address),
        throwsFormatException,
        reason: address,
      );
    }
  });

  test('certificate pin matches only the expected DER bytes', () {
    expect(matchesHubCertificatePin(utf8.encode('abc'), fingerprint), isTrue);
    expect(matchesHubCertificatePin(utf8.encode('abd'), fingerprint), isFalse);
  });

  test(
    'self-signed hub gets bearer token only with matching leaf pin',
    () async {
      final context = SecurityContext()
        ..useCertificateChain('test/fixtures/hub_tls_test_cert.pem')
        ..usePrivateKey('test/fixtures/hub_tls_test_key.pem');
      final server = await HttpServer.bindSecure(
        InternetAddress.loopbackIPv4,
        0,
        context,
      );
      final receivedTokens = <String?>[];
      server.listen((request) async {
        receivedTokens.add(
          request.headers.value(HttpHeaders.authorizationHeader),
        );
        request.response.headers.contentType = ContentType.json;
        request.response.write('[]');
        await request.response.close();
      });
      try {
        final base = 'https://127.0.0.1:${server.port}';
        const certificatePin =
            '50c731cdfd5802849c6e68983836566463b7cf40f95ae5e0c6575c81772251e9';
        final api = DiscoveryApi();

        expect(
          await api.saved('$base#sha256=$certificatePin', 'secret'),
          isEmpty,
        );
        expect(receivedTokens, ['Bearer secret']);

        await expectLater(
          api.saved('$base#sha256=${'0' * 64}', 'secret'),
          throwsA(isA<Exception>()),
        );
        await expectLater(api.saved(base, 'secret'), throwsA(isA<Exception>()));
        expect(receivedTokens, ['Bearer secret']);
      } finally {
        await server.close(force: true);
      }
    },
  );

  test('baseline coverage uses authenticated device endpoint', () async {
    final context = SecurityContext()
      ..useCertificateChain('test/fixtures/hub_tls_test_cert.pem')
      ..usePrivateKey('test/fixtures/hub_tls_test_key.pem');
    final server = await HttpServer.bindSecure(
      InternetAddress.loopbackIPv4,
      0,
      context,
    );
    HttpRequest? receivedRequest;
    server.listen((request) async {
      receivedRequest = request;
      request.response.headers.contentType = ContentType.json;
      request.response.write('''{
        "device_id":"meter/office","appliance_id":42,
        "window_start":"2026-09-22T12:00:00Z",
        "window_end":"2026-09-29T12:00:00Z",
        "latest_sample_at":null,"sample_count":0,"covered_secs":0,
        "coverage_fraction":0,"covered_days":0,"required_days":5,
        "status":"unavailable","reason":"stale_meter_stream"
      }''');
      await request.response.close();
    });
    try {
      const certificatePin =
          '50c731cdfd5802849c6e68983836566463b7cf40f95ae5e0c6575c81772251e9';
      final result = await DiscoveryApi().deviceBaselineCoverage(
        'https://127.0.0.1:${server.port}#sha256=$certificatePin',
        'secret',
        'meter/office',
      );
      expect(
        receivedRequest?.uri.toString(),
        contains('/v1/devices/meter%2Foffice/baseline-coverage'),
      );
      expect(
        receivedRequest?.headers.value(HttpHeaders.authorizationHeader),
        'Bearer secret',
      );
      expect(result.deviceId, 'meter/office');
      expect(result.latestSampleAt, isNull);
      expect(result.status, 'unavailable');
      expect(result.reason, 'stale_meter_stream');
    } finally {
      await server.close(force: true);
    }
  });

  test(
    'status refresh posts to the saved plug endpoint and parses status',
    () async {
      final context = SecurityContext()
        ..useCertificateChain('test/fixtures/hub_tls_test_cert.pem')
        ..usePrivateKey('test/fixtures/hub_tls_test_key.pem');
      final server = await HttpServer.bindSecure(
        InternetAddress.loopbackIPv4,
        0,
        context,
      );
      String? path;
      String? method;
      String? authorization;
      server.listen((request) async {
        path = request.uri.toString();
        method = request.method;
        authorization = request.headers.value(HttpHeaders.authorizationHeader);
        request.response.headers.contentType = ContentType.json;
        request.response.write('''{
        "id":"plug/1","ip":"192.168.1.42","model":"HS103",
        "name":"Lamp plug","room":"Living room","meter_status":"absent",
        "last_verified_at":100,"connection_status":"disconnected",
        "status_checked_at":200,"connected_appliance":null
      }''');
        await request.response.close();
      });
      try {
        const certificatePin =
            '50c731cdfd5802849c6e68983836566463b7cf40f95ae5e0c6575c81772251e9';
        final plug = await DiscoveryApi().refreshPlugStatus(
          'https://127.0.0.1:${server.port}#sha256=$certificatePin',
          'secret',
          'plug/1',
        );
        expect(method, 'POST');
        expect(path, '/v1/devices/plug%2F1/status/refresh');
        expect(authorization, 'Bearer secret');
        expect(plug.connectionStatus, 'disconnected');
        expect(plug.statusCheckedAt, 200);
        expect(plug.meterStatus, 'absent');
      } finally {
        await server.close(force: true);
      }
    },
  );
}
