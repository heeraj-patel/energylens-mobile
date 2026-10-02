import 'package:energylens_mobile/core/cloud_api/cloud_api_client.dart';
import 'package:energylens_mobile/core/cloud_auth/cloud_auth.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

const config = CloudAuthConfig(
  issuer: 'https://issuer.example',
  audience: 'energylens-cloud',
  clientId: 'mobile-client',
  redirectUrl: 'io.energylens.app://login-callback',
  apiUrl: 'https://api.example',
);

class MemoryStore implements CloudTokenStore {
  CloudTokens? tokens;
  @override
  Future<void> clear() async => tokens = null;
  @override
  Future<CloudTokens?> read() async => tokens;
  @override
  Future<void> save(CloudTokens value) async => tokens = value;
}

class FakeAuthenticator implements CloudAuthenticator {
  int refreshCalls = 0;
  @override
  Future<CloudTokens> signIn(CloudAuthConfig config) async =>
      const CloudTokens(accessToken: 'new', refreshToken: 'refresh');
  @override
  Future<CloudTokens> refresh(
    CloudAuthConfig config,
    String refreshToken,
  ) async {
    refreshCalls++;
    return const CloudTokens(accessToken: 'renewed', refreshToken: 'rotated');
  }
}

void main() {
  test(
    'configuration fails closed for missing or mismatched callback and HTTP',
    () {
      expect(CloudAuthConfig.fromEnvironment().isConfigured, isFalse);
      expect(config.isConfigured, isTrue);
      expect(
        CloudAuthConfig(
          issuer: config.issuer,
          audience: config.audience,
          clientId: config.clientId,
          redirectUrl: 'other.app://login-callback',
          apiUrl: config.apiUrl,
        ).isConfigured,
        isFalse,
      );
      expect(
        CloudAuthConfig(
          issuer: config.issuer,
          audience: config.audience,
          clientId: config.clientId,
          redirectUrl: config.redirectUrl,
          apiUrl: 'http://api.example',
        ).isConfigured,
        isFalse,
      );
    },
  );

  test('placeholder issuer and API hosts cannot start cloud sign-in', () async {
    for (final placeholder in [
      'https://invalid',
      'https://auth.example.invalid',
    ]) {
      for (final invalidIssuer in [true, false]) {
        final candidate = CloudAuthConfig(
          issuer: invalidIssuer ? placeholder : config.issuer,
          audience: config.audience,
          clientId: config.clientId,
          redirectUrl: config.redirectUrl,
          apiUrl: invalidIssuer ? config.apiUrl : placeholder,
        );
        expect(candidate.hasPlaceholderEndpoint, isTrue);
        expect(candidate.isConfigured, isFalse);
        final session = CloudSession(
          config: candidate,
          store: MemoryStore(),
          authenticator: FakeAuthenticator(),
        );
        await expectLater(session.signIn(), throwsStateError);
      }
    }
    expect(config.hasPlaceholderEndpoint, isFalse);
  });

  test(
    'expired access token refreshes once and persists rotated token',
    () async {
      final store = MemoryStore()
        ..tokens = CloudTokens(
          accessToken: 'expired',
          refreshToken: 'refresh',
          expiresAt: DateTime.now().subtract(const Duration(minutes: 1)),
        );
      final auth = FakeAuthenticator();
      final session = CloudSession(
        config: config,
        store: store,
        authenticator: auth,
      );
      expect(await session.accessToken(), 'renewed');
      expect(store.tokens?.refreshToken, 'rotated');
      expect(auth.refreshCalls, 1);
    },
  );

  test(
    'cloud client retries a 401 once with new bearer and parses account',
    () async {
      final store = MemoryStore()
        ..tokens = const CloudTokens(
          accessToken: 'old',
          refreshToken: 'refresh',
        );
      final auth = FakeAuthenticator();
      final session = CloudSession(
        config: config,
        store: store,
        authenticator: auth,
      );
      final seen = <String?>[];
      final client = CloudApiClient(
        session: session,
        client: MockClient((request) async {
          expect(request.url.toString(), 'https://api.example/v1/me');
          seen.add(request.headers['Authorization']);
          if (seen.length == 1) return http.Response('', 401);
          return http.Response(
            '{"id":"account-1","email":"a@example.com","email_verified":true}',
            200,
          );
        }),
      );
      final account = await client.me();
      expect(account.id, 'account-1');
      expect(seen, ['Bearer old', 'Bearer renewed']);
      expect(auth.refreshCalls, 1);
      client.close();
    },
  );

  test('unavailable account route cannot establish a session', () async {
    final store = MemoryStore()..tokens = const CloudTokens(accessToken: 'old');
    final session = CloudSession(
      config: config,
      store: store,
      authenticator: FakeAuthenticator(),
    );
    final client = CloudApiClient(
      session: session,
      client: MockClient((_) async => http.Response('', 404)),
    );
    await expectLater(
      client.me(),
      throwsA(
        isA<CloudApiException>().having((e) => e.statusCode, 'status', 404),
      ),
    );
    client.close();
  });
}
