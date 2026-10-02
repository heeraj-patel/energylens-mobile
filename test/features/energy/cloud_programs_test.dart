import 'dart:convert';

import 'package:energylens_mobile/core/cloud_api/cloud_api_client.dart';
import 'package:energylens_mobile/core/cloud_api/cloud_programs.dart';
import 'package:energylens_mobile/core/cloud_auth/cloud_auth.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

const home = '11111111-1111-4111-8111-111111111111';
const appliance = '22222222-2222-4222-8222-222222222222';
const foreign = '33333333-3333-4333-8333-333333333333';

Map<String, dynamic> program() => {
  'program_id': '44444444-4444-4444-8444-444444444444',
  'revision_id': '55555555-5555-4555-8555-555555555555',
  'title': 'Appliance program',
  'administrator_name': 'City utility',
  'benefit_kind': 'rebate',
  'status': 'unknown',
  'reasons': ['provider_unknown'],
  'source_url': 'https://utility.example/program',
  'source_sha256': 'a' * 64,
  'review_expires_at': '2026-11-01T12:00:00Z',
};
Map<String, dynamic> page([List<Map<String, dynamic>>? rows]) => {
  'programs': rows ?? [program()],
  'as_of': '2026-10-01T12:00:00Z',
};

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

void main() {
  test('accepts unknown source-cited results and location required', () {
    expect(
      CloudProgramPage.fromJson(page()).programs.single.title,
      'Appliance program',
    );
    expect(
      CloudProgramPage.fromJson({...page([]), 'reason': 'location_required'})
          .locationRequired,
      isTrue,
    );
  });

  test('rejects unsupported claims and malformed candidates', () {
    for (final bad in [
      {...program(), 'status': 'eligible'},
      {...program(), 'savings_amount': 100},
      {...program(), 'source_url': 'http://utility.example/program'},
      {...program(), 'source_sha256': 'bad'},
    ]) {
      expect(
        () => CloudProgramPage.fromJson(page([bad])),
        throwsFormatException,
      );
    }
    expect(
      () =>
          CloudProgramPage.fromJson({...page(), 'reason': 'location_required'}),
      throwsFormatException,
    );
    expect(
      () => CloudProgramPage.fromJson(page([program(), program()])),
      throwsFormatException,
    );
  });

  test('requests only selected owned appliance with bearer session', () async {
    final seen = <http.Request>[];
    final api = CloudApiClient(
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
      client: MockClient((request) async {
        seen.add(request);
        return http.Response(jsonEncode(page()), 200);
      }),
    );
    expect(
      (await api.programs(home, appliance, {appliance})).programs.single.title,
      'Appliance program',
    );
    expect(seen.single.url.path, '/v1/homes/$home/programs');
    expect(seen.single.url.queryParameters['appliance_id'], appliance);
    expect(seen.single.headers['authorization'], 'Bearer owner-token');
    await expectLater(
      api.programs(home, foreign, {appliance}),
      throwsArgumentError,
    );
    expect(seen.length, 1);
  });
}
