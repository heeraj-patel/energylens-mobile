import 'dart:io';

import 'package:energylens_mobile/core/cloud_auth/cloud_auth.dart';
import 'package:energylens_mobile/core/cloud_auth/cloud_dev_tls.dart';
import 'package:energylens_mobile/core/cloud_auth/cloud_local_auth.dart';
import 'package:energylens_mobile/core/cloud_api/cloud_api_client.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;

class _Store implements CloudTokenStore {
  _Store(this.tokens);
  CloudTokens? tokens;
  @override
  Future<CloudTokens?> read() async => tokens;
  @override
  Future<void> save(CloudTokens value) async => tokens = value;
  @override
  Future<void> clear() async => tokens = null;
}

class _NoOidc implements CloudAuthenticator {
  @override
  Future<CloudTokens> signIn(CloudAuthConfig config) async =>
      throw StateError('OIDC disabled');
  @override
  Future<CloudTokens> refresh(CloudAuthConfig config, String token) async =>
      throw StateError('OIDC disabled');
}

void main() {
  const pin =
      '50c731cdfd5802849c6e68983836566463b7cf40f95ae5e0c6575c81772251e9';

  CloudAuthConfig config(
    String url, {
    String fingerprint = pin,
    String environment = 'dev',
  }) => CloudAuthConfig(
    issuer: '',
    audience: '',
    clientId: '',
    redirectUrl: '',
    apiUrl: url,
    devAuthEnabled: true,
    appEnvironment: environment,
    devCertificateSha256: fingerprint,
  );

  test('development pin is rejected outside dev and for malformed digest', () {
    const url = 'https://api.example';
    expect(config(url, environment: 'staging').isLocalAuthConfigured, isFalse);
    expect(
      () => cloudHttpClient(config(url, environment: 'staging')),
      throwsStateError,
    );
    expect(
      () => cloudHttpClient(config(url, fingerprint: 'bad')),
      throwsStateError,
    );
  });

  test(
    'exact pinned self-signed Cloud certificate serves local login',
    () async {
      final context = SecurityContext()
        ..useCertificateChain('test/fixtures/hub_tls_test_cert.pem')
        ..usePrivateKey('test/fixtures/hub_tls_test_key.pem');
      final server = await HttpServer.bindSecure(
        InternetAddress.loopbackIPv4,
        0,
        context,
      );
      server.listen((request) async {
        await utf8Response(request);
      });
      final url = 'https://127.0.0.1:${server.port}';
      try {
        final auth = CloudLocalAuthClient(baseUrl: url, config: config(url));
        final tokens = await auth.login('owner@example.test', 'secret');
        expect(tokens.accessToken, 'dev-access');
        final client = cloudHttpClient(config(url));
        expect((await client.get(Uri.parse('$url/v1/me'))).statusCode, 200);
        client.close();
        final api = CloudApiClient(
          session: CloudSession(
            config: config(url),
            store: _Store(tokens),
            authenticator: _NoOidc(),
            localAuth: auth,
          ),
        );
        expect((await api.me()).emailVerified, isTrue);
        api.close();
        auth.close();
        final wrong = cloudHttpClient(config(url, fingerprint: '0' * 64));
        await expectLater(
          wrong.get(Uri.parse('$url/v1/me')),
          throwsA(isA<Exception>()),
        );
        wrong.close();
        await expectLater(
          http.get(Uri.parse('$url/v1/me')),
          throwsA(isA<Exception>()),
        );
      } finally {
        await server.close(force: true);
      }
    },
  );
}

Future<void> utf8Response(HttpRequest request) async {
  request.response.headers.contentType = ContentType.json;
  final now = DateTime.now().toUtc();
  if (request.uri.path.endsWith('/login')) {
    request.response.write(
      '{"token_type":"Bearer","access_token":"dev-access",'
      '"refresh_token":"dev-refresh","access_expires_at":"${now.add(const Duration(hours: 1)).toIso8601String()}",'
      '"refresh_expires_at":"${now.add(const Duration(days: 30)).toIso8601String()}"}',
    );
  } else {
    request.response.write(
      '{"id":"11111111-1111-4111-8111-111111111111","email":"owner@example.test","email_verified":true}',
    );
  }
  await request.response.close();
}
