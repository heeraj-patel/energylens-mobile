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

class _Store implements CloudTokenStore {
  @override
  Future<void> clear() async {}
  @override
  Future<CloudTokens?> read() async => const CloudTokens(accessToken: 'owner');
  @override
  Future<void> save(CloudTokens value) async {}
}

class _Auth implements CloudAuthenticator {
  @override
  Future<CloudTokens> signIn(CloudAuthConfig config) async =>
      const CloudTokens(accessToken: 'owner');
  @override
  Future<CloudTokens> refresh(CloudAuthConfig config, String token) async =>
      const CloudTokens(accessToken: 'owner');
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

void main() {
  test('rejects another home’s electricity tariff', () async {
    final api = _api(
      MockClient(
        (_) async => http.Response(
          jsonEncode({
            'tariffs': [
              {
                'id': '22222222-2222-4222-8222-222222222222',
                'home_id': '33333333-3333-4333-8333-333333333333',
                'revision': 1,
                'fuel': 'electricity',
                'rate': '0.15',
                'rate_unit': 'kWh',
                'currency': 'USD',
                'rate_kind': 'user_tariff',
                'source_ref': 'bill',
                'source_as_of': '2026-10-01T00:00:00Z',
                'is_fallback': false,
                'effective_from': '2026-10-01T00:00:00Z',
              },
            ],
          }),
          200,
        ),
      ),
    );
    await expectLater(api.electricityTariffs(home.id), throwsFormatException);
    api.close();
  });

  test('gas tariffs accept only selected-home therm revisions', () async {
    Map<String, dynamic> gasRow({
      String fuel = 'natural_gas',
      String unit = 'therm',
      String? homeId,
    }) => {
      'id': '22222222-2222-4222-8222-222222222222',
      'home_id': homeId ?? home.id,
      'revision': 1,
      'fuel': fuel,
      'rate': '1.25',
      'rate_unit': unit,
      'currency': 'USD',
      'rate_kind': 'user_tariff',
      'source_ref': 'Customer-entered natural gas bill',
      'source_as_of': '2026-10-01T00:00:00Z',
      'is_fallback': false,
      'effective_from': '2026-10-01T00:00:00Z',
    };

    for (final badRow in [
      gasRow(unit: 'kWh'),
      gasRow(homeId: '33333333-3333-4333-8333-333333333333'),
    ]) {
      final api = _api(
        MockClient(
          (_) async => http.Response(
            jsonEncode({
              'tariffs': [badRow],
            }),
            200,
          ),
        ),
      );
      await expectLater(api.gasTariffs(home.id), throwsFormatException);
      api.close();
    }
    final api = _api(
      MockClient(
        (_) async => http.Response(
          jsonEncode({
            'tariffs': [gasRow(), gasRow(fuel: 'electricity', unit: 'kWh')],
          }),
          200,
        ),
      ),
    );
    final rows = await api.gasTariffs(home.id);
    expect(rows, hasLength(1));
    expect(rows.single.rate, '1.25');
    api.close();
  });
}
