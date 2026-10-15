import 'dart:async';

import 'package:energylens_mobile/core/cloud_api/cloud_api_client.dart';
import 'package:energylens_mobile/core/cloud_auth/cloud_auth.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
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

class BlockingReadStore extends MemoryStore {
  final entered = Completer<void>();
  final release = Completer<void>();
  @override
  Future<CloudTokens?> read() async {
    final captured = tokens;
    if (!entered.isCompleted) entered.complete();
    await release.future;
    return captured;
  }
}

class BlockingSaveStore extends MemoryStore {
  final entered = Completer<void>();
  final release = Completer<void>();
  @override
  Future<void> save(CloudTokens value) async {
    if (!entered.isCompleted) entered.complete();
    await release.future;
    tokens = value;
  }
}

class FailedAuthenticator extends FakeAuthenticator {
  @override
  Future<CloudTokens> signIn(CloudAuthConfig config) async =>
      throw StateError('login failed');
}

class BlockingSecureStorage extends FlutterSecureStorage {
  final values = <String, String>{};
  final entered = Completer<void>();
  final release = Completer<void>();
  bool block = false;
  @override
  Future<String?> read({
    required String key,
    dynamic iOptions,
    dynamic aOptions,
    dynamic lOptions,
    dynamic webOptions,
    dynamic mOptions,
    dynamic wOptions,
  }) async {
    final captured = values[key];
    if (block && key.startsWith('energylens.cloud.session.v2.')) {
      if (!entered.isCompleted) entered.complete();
      await release.future;
    }
    return captured;
  }

  @override
  Future<void> write({
    required String key,
    required String? value,
    dynamic iOptions,
    dynamic aOptions,
    dynamic lOptions,
    dynamic webOptions,
    dynamic mOptions,
    dynamic wOptions,
  }) async {
    if (value == null)
      values.remove(key);
    else
      values[key] = value;
  }

  @override
  Future<void> delete({
    required String key,
    dynamic iOptions,
    dynamic aOptions,
    dynamic lOptions,
    dynamic webOptions,
    dynamic mOptions,
    dynamic wOptions,
  }) async {
    values.remove(key);
  }
}

void main() {
  test('corrupt old-profile read cannot remove another profile', () async {
    final storage = BlockingSecureStorage();
    final old = SecureCloudTokenStore(
      origin: config.apiUrl,
      profile: 'email_password',
      storage: storage,
    );
    final newer = SecureCloudTokenStore(
      origin: config.apiUrl,
      profile: 'username_password',
      storage: storage,
    );
    await old.save(const CloudTokens(accessToken: 'old'));
    await newer.save(const CloudTokens(accessToken: 'new'));
    final oldKey = storage.values.keys.firstWhere(
      (key) => storage.values[key]!.contains('"access":"old"'),
    );
    storage.values[oldKey] = '{bad json';
    storage.block = true;
    final pending = old.read();
    await storage.entered.future;
    final change = old.selectProfile('username_password');
    storage.release.complete();
    expect(await pending, isNull);
    await change;
    expect((await old.read())?.accessToken, 'new');
  });

  test('delayed login save cannot restore access after sign-out', () async {
    final store = BlockingSaveStore();
    final session = CloudSession(
      config: config,
      store: store,
      authenticator: FakeAuthenticator(),
    );
    final login = session.signIn();
    await store.entered.future;
    final logout = session.signOut();
    expect(await session.accessToken(), isNull);
    store.release.complete();
    await expectLater(login, throwsStateError);
    await logout;
    expect(store.tokens, isNull);
  });

  test('failed replacement login clears old persisted bearer', () async {
    final store = MemoryStore()
      ..tokens = const CloudTokens(accessToken: 'account-a');
    final session = CloudSession(
      config: config,
      store: store,
      authenticator: FailedAuthenticator(),
    );
    await expectLater(session.signIn(), throwsStateError);
    expect(store.tokens, isNull);
    expect(await session.accessToken(), isNull);
  });

  test('sign-out invalidates a token read already in progress', () async {
    final store = BlockingReadStore()
      ..tokens = const CloudTokens(accessToken: 'old');
    final session = CloudSession(
      config: config,
      store: store,
      authenticator: FakeAuthenticator(),
    );
    final pending = session.accessToken();
    await store.entered.future;
    final signOut = session.signOut();
    expect(await session.accessToken(), isNull);
    store.release.complete();
    expect(await pending, isNull);
    await signOut;
    expect(store.tokens, isNull);
  });

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
