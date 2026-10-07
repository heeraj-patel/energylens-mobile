import 'dart:convert';

import 'package:energylens_mobile/core/cloud_api/cloud_api_client.dart';
import 'package:energylens_mobile/core/cloud_api/cloud_appliance_list.dart';
import 'package:energylens_mobile/core/cloud_auth/cloud_auth.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

const _homeId = '11111111-1111-4111-8111-111111111111';
const _config = CloudAuthConfig(
  issuer: 'https://issuer.example',
  audience: 'energylens-cloud',
  clientId: 'client',
  redirectUrl: 'io.energylens.app://login-callback',
  apiUrl: 'https://api.example',
);

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

CloudApiClient _api(Future<http.Response> Function(http.Request) handler) =>
    CloudApiClient(
      session: CloudSession(
        config: _config,
        store: _Store(),
        authenticator: _Auth(),
      ),
      client: MockClient(handler),
    );

Map<String, Object?> _appliance() => {
  'id': '22222222-2222-4222-8222-222222222222',
  'home_id': _homeId,
  'name': 'Washer',
  'category': 'other',
  'identity': {
    'brand': 'LG',
    'full_model': 'WM3070HWA',
    'fuel': 'electricity',
    'match_quality': 'confirmed_exact',
  },
};

http.Response _response({
  Object? body,
  Map<String, String> headers = const {},
  int status = 200,
}) => http.Response(
  jsonEncode(
    body ??
        {
          'appliances': [_appliance()],
        },
  ),
  status,
  headers: headers,
);

void main() {
  test('defaults responses without provenance headers to household', () async {
    final api = _api((_) async => _response());
    final result = await api.applianceList(_homeId);
    expect(result.dataMode, CloudApplianceDataMode.household);
    expect(result.fixtureRevision, isNull);
    expect(result.appliances.single.homeId, _homeId);
    api.close();
  });

  test('preserves valid same-route sample provenance', () async {
    final api = _api(
      (_) async => _response(
        headers: {
          'X-EnergyLens-Data-Mode': 'sample',
          'X-EnergyLens-Fixture-Revision': 'synthetic-household-v1',
        },
      ),
    );
    final result = await api.applianceList(_homeId);
    expect(result.dataMode, CloudApplianceDataMode.sample);
    expect(result.isSample, isTrue);
    expect(result.fixtureRevision, 'synthetic-household-v1');
    api.close();
  });

  test('legacy appliances caller still receives the appliance list', () async {
    final api = _api((_) async => _response());
    final rows = await api.appliances(_homeId);
    expect(rows.single.name, 'Washer');
    api.close();
  });

  test('rejects incomplete and invalid provenance headers', () async {
    final cases = <Map<String, String>>[
      {'X-EnergyLens-Data-Mode': 'sample'},
      {'X-EnergyLens-Fixture-Revision': 'synthetic-household-v1'},
      {
        'X-EnergyLens-Data-Mode': 'household',
        'X-EnergyLens-Fixture-Revision': 'synthetic-household-v1',
      },
      {
        'X-EnergyLens-Data-Mode': 'unknown',
        'X-EnergyLens-Fixture-Revision': 'synthetic-household-v1',
      },
      {
        'X-EnergyLens-Data-Mode': 'sample',
        'X-EnergyLens-Fixture-Revision': 'bad revision',
      },
    ];
    for (final headers in cases) {
      final api = _api((_) async => _response(headers: headers));
      await expectLater(api.applianceList(_homeId), throwsFormatException);
      api.close();
    }
  });

  test('rejects malformed body and appliances from another home', () async {
    final malformed = _api(
      (_) async => _response(
        body: {
          'appliances': [3],
        },
      ),
    );
    await expectLater(malformed.applianceList(_homeId), throwsFormatException);
    malformed.close();

    final otherHome = _api((_) async {
      final row = _appliance()
        ..['home_id'] = '33333333-3333-4333-8333-333333333333';
      return _response(
        body: {
          'appliances': [row],
        },
      );
    });
    await expectLater(otherHome.applianceList(_homeId), throwsFormatException);
    otherHome.close();
  });

  test('auth and server errors remain errors', () async {
    final unauthorized = _api(
      (_) async => http.Response('{"code":"not_authenticated"}', 403),
    );
    await expectLater(
      unauthorized.applianceList(_homeId),
      throwsA(
        isA<CloudApiException>()
            .having((error) => error.statusCode, 'statusCode', 403)
            .having((error) => error.code, 'code', 'not_authenticated'),
      ),
    );
    unauthorized.close();

    final serverError = _api((_) async => http.Response('{}', 500));
    await expectLater(
      serverError.applianceList(_homeId),
      throwsA(
        isA<CloudApiException>().having(
          (error) => error.statusCode,
          'statusCode',
          500,
        ),
      ),
    );
    serverError.close();
  });
}
