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
}
