import 'dart:convert';

import 'package:energylens_mobile/core/cloud_api/cloud_api_client.dart';
import 'package:energylens_mobile/core/cloud_api/cloud_appliance_list.dart';
import 'package:energylens_mobile/core/cloud_auth/cloud_auth.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

const _homeId = '11111111-1111-4111-8111-111111111111';
const _applianceId = '22222222-2222-4222-8222-222222222222';
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

Map<String, Object?> _body({String home = _homeId, String id = _applianceId}) => {
  'id': id,
  'home_id': home,
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
  Map<String, String> headers = const {'etag': '"1"'},
  int status = 200,
}) => http.Response(jsonEncode(body ?? _body()), status, headers: headers);

void main() {
  test('preserves paired sample provenance and strong ETag', () async {
    final api = _api(
      (_) async => _response(
        headers: {
          'etag': '"1"',
          'X-EnergyLens-Data-Mode': 'sample',
          'X-EnergyLens-Fixture-Revision': 'synthetic_household_v1',
          'cache-control': 'no-store',
        },
      ),
    );
    final detail = await api.applianceDetail(_homeId, _applianceId);
    expect(detail.appliance.id, _applianceId);
    expect(detail.etag, '"1"');
    expect(detail.dataMode, CloudApplianceDataMode.sample);
    expect(detail.fixtureRevision, 'synthetic_household_v1');
    expect(detail.isSample, isTrue);
    api.close();
  });

  test('header absent and explicit household responses are household', () async {
    for (final headers in [
      {'etag': '"2"'},
      {'etag': '"2"', 'X-EnergyLens-Data-Mode': 'household'},
    ]) {
      final api = _api((_) async => _response(headers: headers));
      final detail = await api.applianceDetail(_homeId, _applianceId);
      expect(detail.dataMode, CloudApplianceDataMode.household);
      expect(detail.fixtureRevision, isNull);
      api.close();
    }
  });

  test('validates route identity and malformed or unpaired provenance', () async {
    for (final body in [
      _body(home: '33333333-3333-4333-8333-333333333333'),
      _body(id: '33333333-3333-4333-8333-333333333333'),
    ]) {
      final api = _api((_) async => _response(body: body));
      await expectLater(
        api.applianceDetail(_homeId, _applianceId),
        throwsFormatException,
      );
      api.close();
    }
    final cases = [
      {'etag': '"1"', 'X-EnergyLens-Data-Mode': 'sample'},
      {
        'etag': '"1"',
        'X-EnergyLens-Fixture-Revision': 'synthetic_household_v1',
      },
      {
        'etag': '"1"',
        'X-EnergyLens-Data-Mode': 'household',
        'X-EnergyLens-Fixture-Revision': 'synthetic_household_v1',
      },
      {
        'etag': '"1"',
        'X-EnergyLens-Data-Mode': 'sample',
        'X-EnergyLens-Fixture-Revision': 'bad revision',
      },
    ];
    for (final headers in cases) {
      final api = _api((_) async => _response(headers: headers));
      await expectLater(
        api.applianceDetail(_homeId, _applianceId),
        throwsFormatException,
      );
      api.close();
    }
    final noEtag = _api((_) async => _response(headers: const {}));
    await expectLater(
      noEtag.applianceDetail(_homeId, _applianceId),
      throwsFormatException,
    );
    noEtag.close();

    final malformed = _api((_) async => http.Response('not-json', 200));
    await expectLater(
      malformed.applianceDetail(_homeId, _applianceId),
      throwsFormatException,
    );
    malformed.close();
  });

  test('auth and server failures remain CloudApiException errors', () async {
    for (final status in [401, 500]) {
      final api = _api(
        (_) async => http.Response('{"code":"request_failed"}', status),
      );
      await expectLater(
        api.applianceDetail(_homeId, _applianceId),
        throwsA(isA<CloudApiException>().having(
          (error) => error.statusCode,
          'statusCode',
          status,
        )),
      );
      api.close();
    }
  });

  test('legacy appliance keeps its versioned return contract', () async {
    final api = _api((_) async => _response());
    final result = await api.appliance(_homeId, _applianceId);
    expect(result.value.id, _applianceId);
    expect(result.etag, '"1"');
    api.close();
  });
}
