import 'dart:convert';

import 'package:energylens_mobile/core/cloud_api/cloud_api_client.dart';
import 'package:energylens_mobile/core/cloud_api/cloud_home.dart';
import 'package:energylens_mobile/core/cloud_auth/cloud_auth.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

const home = CloudHome(
  id: '11111111-1111-4111-8111-111111111111',
  name: 'Home',
  timezone: 'America/Chicago',
  countryCode: 'US',
  postalCode: '60601',
);
const sensor = '22222222-2222-4222-8222-222222222222';
const appliance = '33333333-3333-4333-8333-333333333333';
const attachment = '44444444-4444-4444-8444-444444444444';

class _Store implements CloudTokenStore {
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
  Future<CloudTokens> signIn(CloudAuthConfig config) async =>
      const CloudTokens(accessToken: 'owner-token');
  @override
  Future<CloudTokens> refresh(
    CloudAuthConfig config,
    String refreshToken,
  ) async => const CloudTokens(accessToken: 'owner-token');
}

CloudApiClient _api(MockClient client) => CloudApiClient(
  session: CloudSession(
    config: const CloudAuthConfig(
      issuer: 'https://issuer.example',
      audience: 'energylens-cloud',
      clientId: 'client',
      redirectUrl: 'io.energylens.app://login-callback',
      apiUrl: 'https://api.example',
    ),
    store: _Store(),
    authenticator: _Auth(),
  ),
  client: client,
);

Map<String, dynamic> _page(List<Map<String, dynamic>> events, String? next) => {
  'events': events,
  'as_of': '2026-10-01T12:00:00Z',
  'as_of_cursor': 7,
  'next_cursor': next,
};

void main() {
  test(
    'rejects an unknown event kind rather than treating it as energy',
    () async {
      final api = _api(
        MockClient(
          (request) async => http.Response(
            jsonEncode(
              _page([
                {'kind': 'future_energy_kind', 'sensor_id': sensor},
              ], null),
            ),
            200,
          ),
        ),
      );
      await expectLater(api.meteredHistory(home.id), throwsFormatException);
      api.close();
    },
  );
}
