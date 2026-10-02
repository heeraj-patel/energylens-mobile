import 'dart:convert';

import 'package:energylens_mobile/core/cloud_api/cloud_api_client.dart';
import 'package:energylens_mobile/core/cloud_api/cloud_home.dart';
import 'package:energylens_mobile/core/cloud_auth/cloud_auth.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

const config = CloudAuthConfig(
  issuer: 'https://issuer.example',
  audience: 'energylens-cloud',
  clientId: 'client',
  redirectUrl: 'io.energylens.app://login-callback',
  apiUrl: 'https://api.example',
);

class Store implements CloudTokenStore {
  @override
  Future<void> clear() async {}
  @override
  Future<CloudTokens?> read() async =>
      const CloudTokens(accessToken: 'owner-token', refreshToken: 'refresh');
  @override
  Future<void> save(CloudTokens value) async {}
}

class Auth implements CloudAuthenticator {
  @override
  Future<CloudTokens> refresh(
    CloudAuthConfig config,
    String refreshToken,
  ) async => const CloudTokens(accessToken: 'fresh-token');
  @override
  Future<CloudTokens> signIn(CloudAuthConfig config) async =>
      const CloudTokens(accessToken: 'owner-token');
}

void main() {
  test('home fields normalize and validate before cloud submission', () {
    final input = CloudHomeCreate.validate(
      name: ' My home ',
      timezone: 'America/Chicago',
      countryCode: 'us',
      postalCode: '60601',
    );
    expect(input?.toJson(), {
      'name': 'My home',
      'timezone': 'America/Chicago',
      'location': {
        'country_code': 'US',
        'postal_code': '60601',
        'city': null,
        'county': null,
        'precision': 'postal_code',
        'source': 'user_entered',
      },
    });
    expect(
      CloudHomeCreate.validate(
        name: '',
        timezone: 'America/Chicago',
        countryCode: 'US',
        postalCode: '60601',
      ),
      isNull,
    );
    expect(
      CloudHomeCreate.validate(
        name: 'Home',
        timezone: 'Invalid/Zone',
        countryCode: 'US',
        postalCode: '60601',
      ),
      isNull,
    );
    expect(
      CloudHomeCreate.validate(
        name: 'Home',
        timezone: 'EST',
        countryCode: 'US',
        postalCode: '60601',
      ),
      isNull,
    );
    expect(
      CloudHomeCreate.validate(
        name: 'Home',
        timezone: 'America/Chicago',
        countryCode: 'US',
        postalCode: '123',
      ),
      isNull,
    );
    expect(
      newCloudIdempotencyKey(),
      matches(
        RegExp(
          r'^[0-9a-f]{8}-[0-9a-f]{4}-4[0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$',
        ),
      ),
    );
  });

  test('list and create use bearer, UUID idempotency key, and preserve POST on 401 retry', () async {
    final seen = <http.Request>[];
    final client = CloudApiClient(
      session: CloudSession(
        config: config,
        store: Store(),
        authenticator: Auth(),
      ),
      client: MockClient((request) async {
        seen.add(request);
        if (request.method == 'GET') {
          return http.Response(
            '{"homes":[{"id":"home-1","name":"Main","timezone":"America/Chicago","location":{"country_code":"US","postal_code":"60601"}}]}',
            200,
          );
        }
        if (seen.where((item) => item.method == 'POST').length == 1) {
          return http.Response('', 401);
        }
        return http.Response(
          '{"id":"home-2","name":"New","timezone":"America/Chicago","location":{"country_code":"US","postal_code":"60601"}}',
          201,
        );
      }),
    );
    final homes = await client.homes();
    expect(homes.single.name, 'Main');
    final key = newCloudIdempotencyKey();
    final created = await client.createHome(
      CloudHomeCreate.validate(
        name: 'New',
        timezone: 'America/Chicago',
        countryCode: 'US',
        postalCode: '60601',
      )!,
      idempotencyKey: key,
    );
    expect(created.id, 'home-2');
    final posts = seen.where((item) => item.method == 'POST').toList();
    expect(posts.length, 2);
    expect(
      posts.every(
        (item) =>
            item.url.path == '/v1/homes' &&
            item.headers['Idempotency-Key'] == key,
      ),
      isTrue,
    );
    expect(posts.map((item) => item.body).toSet().length, 1);
    expect(posts.map((item) => item.headers['Authorization']).toList(), [
      'Bearer owner-token',
      'Bearer fresh-token',
    ]);
    expect(
      jsonDecode(posts.first.body)['location']['precision'],
      'postal_code',
    );
    client.close();
  });
}
