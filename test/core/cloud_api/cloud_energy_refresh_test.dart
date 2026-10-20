import 'dart:convert';

import 'package:energylens_mobile/core/cloud_api/cloud_api_client.dart';
import 'package:energylens_mobile/core/cloud_api/cloud_question.dart';
import 'package:energylens_mobile/core/cloud_auth/cloud_auth.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

const _home = '11111111-1111-4111-8111-111111111111';
const _appliance = '22222222-2222-4222-8222-222222222222';
const _key = '33333333-3333-4333-8333-333333333333';

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
  Future<CloudTokens> refresh(CloudAuthConfig config, String token) async =>
      const CloudTokens(accessToken: 'owner-token');
}

CloudApiClient _api(MockClient client, {void Function()? onRejected}) {
  final api = CloudApiClient(
    session: CloudSession(
      config: const CloudAuthConfig(
        issuer: 'https://issuer.example',
        audience: 'energylens-cloud',
        clientId: 'client',
        redirectUrl: 'io.energylens.app://login-callback',
        apiUrl: 'https://cloud.example',
      ),
      store: _Store(),
      authenticator: _Auth(),
    ),
    client: client,
  );
  api.onSessionRejected = onRejected;
  return api;
}

http.Response _json(int status, Object body) => http.Response(
  jsonEncode(body),
  status,
  headers: {'content-type': 'application/json'},
);

Map<String, Object?> _question(Map<String, Object?> extra) => {
  'id': 'q',
  'version': 1,
  'purpose': 'onboarding',
  'appliance_id': _appliance,
  'identity_revision': 1,
  'prompt': 'p',
  'answer_kind': 'cycles_per_week',
  'unit': null,
  'optional': true,
  ...extra,
};

void main() {
  test('refresh posts with an idempotency key and parses queued_at', () async {
    late http.Request seen;
    final api = _api(
      MockClient((request) async {
        seen = request;
        return _json(202, {
          'appliance_id': _appliance,
          'reason': 'owner_refresh',
          'queued_at': '2026-10-20T10:00:00Z',
        });
      }),
    );
    final result = await api.refreshEnergyResolution(
      _home,
      _appliance,
      idempotencyKey: _key,
    );
    expect(seen.method, 'POST');
    expect(
      seen.url.path,
      '/v1/homes/$_home/appliances/$_appliance/energy-resolution/refresh',
    );
    expect(seen.headers['Idempotency-Key'], _key);
    expect(seen.body, isEmpty);
    expect(result.queuedAt, DateTime.utc(2026, 10, 20, 10));
    api.close();
  });

  test('refresh surfaces 429 retry_after_seconds', () async {
    final api = _api(
      MockClient(
        (_) async => _json(429, {
          'code': 'refresh_rate_limited',
          'details': {'retry_after_seconds': 420},
        }),
      ),
    );
    await expectLater(
      api.refreshEnergyResolution(_home, _appliance, idempotencyKey: _key),
      throwsA(
        isA<CloudApiException>()
            .having((e) => e.code, 'code', 'refresh_rate_limited')
            .having((e) => e.retryAfterSeconds, 'retry', 420),
      ),
    );
    api.close();
  });

  test('refresh signs out on 403 and rejects a changed appliance', () async {
    var rejected = 0;
    final denied = _api(
      MockClient((_) async => _json(403, {'code': 'forbidden'})),
      onRejected: () => rejected++,
    );
    await expectLater(
      denied.refreshEnergyResolution(_home, _appliance, idempotencyKey: _key),
      throwsA(isA<CloudApiException>()),
    );
    expect(rejected, 1);
    final wrong = _api(
      MockClient(
        (_) async => _json(202, {
          'appliance_id': _home,
          'reason': 'owner_refresh',
          'queued_at': '2026-10-20T10:00:00Z',
        }),
      ),
    );
    await expectLater(
      wrong.refreshEnergyResolution(_home, _appliance, idempotencyKey: _key),
      throwsFormatException,
    );
    await expectLater(
      wrong.refreshEnergyResolution(_home, _appliance, idempotencyKey: 'x'),
      throwsArgumentError,
    );
    denied.close();
    wrong.close();
  });

  test('question parses options and v2 fields', () {
    final q = CloudQuestion.fromJson(
      _question({
        'answer_kind': 'choice',
        'options': [
          {'key': 'light', 'value': 1.5},
          {'key': 'heavy', 'value': 4},
        ],
        'source_fact_id': _home,
        'cycle_definition': 'one load',
        'test_basis': 'DOE',
        'source_url': 'https://example.com/x',
      }),
    );
    expect(q.options!.map((o) => o.key), ['light', 'heavy']);
    expect(q.options!.last.value, 4);
    expect(q.cycleDefinition, 'one load');
    expect(q.sourceUrl, 'https://example.com/x');
    expect(CloudQuestion.fromJson(_question({})).options, isNull);
  });

  test('question rejects malformed options and unknown answer kind', () {
    for (final bad in [
      _question({'answer_kind': 'choice'}),
      _question({'options': []}),
      _question({
        'options': [
          {'key': 'a'},
        ],
      }),
      _question({
        'options': [
          {'key': 'a', 'value': 1, 'x': 2},
        ],
      }),
      _question({'answer_kind': 'other'}),
      _question({'cycle_definition': ''}),
    ]) {
      expect(() => CloudQuestion.fromJson(bad), throwsFormatException);
    }
  });
}
