import 'dart:convert';
import 'dart:io';

import 'package:energylens_mobile/core/cloud_api/cloud_api_client.dart';
import 'package:energylens_mobile/core/cloud_api/cloud_appliance_facts.dart';
import 'package:energylens_mobile/core/cloud_auth/cloud_auth.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

const _home = '00000000-0000-4000-8000-000000000001';
const _appliance = '00000000-0000-4000-8000-000000000003';

List<Map<String, dynamic>> _fixtures() {
  final file = File(
    '../energylens-common-contracts/api/testdata/appliance-facts.json',
  );
  final rows = (jsonDecode(file.readAsStringSync()) as Map)['valid'] as List;
  return [for (final row in rows) Map<String, dynamic>.from(row as Map)];
}

Map<String, dynamic> _fixture(String name) => Map<String, dynamic>.from(
  _fixtures().firstWhere((row) => row['name'] == name)['value'] as Map,
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
  Future<CloudTokens> refresh(CloudAuthConfig config, String token) async =>
      const CloudTokens(accessToken: 'owner-token');
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
  test('parses every contract example payload', () {
    final rows = _fixtures();
    expect(rows, isNotEmpty);
    for (final row in rows) {
      final facts = CloudApplianceFacts.fromJson(
        Map<String, dynamic>.from(row['value'] as Map),
      );
      expect(facts.applianceVersion, 1, reason: row['name'] as String);
    }
  });

  test('electric metered washer sections', () {
    final facts = CloudApplianceFacts.fromJson(
      _fixture('electric_metered_washer'),
    );
    expect(facts.identity.value!.id, _appliance);
    expect(facts.catalogFacts.isOk, isTrue);
    expect(facts.estimate.isOk, isTrue);
    expect(facts.efficiency.isOk, isTrue);
    expect(
      facts.programs.value!.items.single.title,
      'Reviewed appliance program',
    );
    expect(facts.programs.value!.total, 4);
    expect(facts.tips.value!.items, hasLength(1));
    expect(facts.care.value!.items, hasLength(1));
    expect(
      facts.usageAnswers.value!.single.questionId,
      'washer.cycles_per_week',
    );
  });

  test('gas furnace keeps statuses and reasons', () {
    final facts = CloudApplianceFacts.fromJson(_fixture('gas_furnace'));
    expect(facts.catalogFacts.status, 'error');
    expect(facts.catalogFacts.reason, 'resolution_read_failed');
    expect(facts.estimate.status, 'unavailable');
    expect(facts.programs.isEmpty, isTrue);
    expect(facts.programs.value!.items, isEmpty);
    expect(facts.usageAnswers.isEmpty, isTrue);
  });

  test('efficiency not built and location reason', () {
    final facts = CloudApplianceFacts.fromJson(
      _fixture('efficiency_not_built'),
    );
    expect(facts.efficiency.status, 'unavailable');
    expect(facts.efficiency.reason, 'measured_efficiency_not_built');
    expect(facts.programs.reason, 'location_required');
  });

  test('a malformed section body only fails that section', () {
    final json = _fixture('electric_metered_washer');
    (json['programs'] as Map)['items'] = [
      {'program_id': 'bad'},
    ];
    final facts = CloudApplianceFacts.fromJson(json);
    expect(facts.programs.status, 'error');
    expect(facts.estimate.isOk, isTrue);
  });

  test('a malformed envelope throws', () {
    final json = _fixture('gas_furnace')..remove('generated_at');
    expect(() => CloudApplianceFacts.fromJson(json), throwsFormatException);
  });

  test('sends capability and ETag, reuses the cached body on 304', () async {
    final seen = <http.Request>[];
    final api = _api(
      MockClient((request) async {
        seen.add(request);
        if (request.headers['If-None-Match'] == '"abc"') {
          return http.Response('', 304, headers: {'etag': '"abc"'});
        }
        return http.Response(
          jsonEncode(_fixture('electric_metered_washer')),
          200,
          headers: {'etag': '"abc"'},
        );
      }),
    );
    addTearDown(api.close);
    final first = await api.applianceFacts(_home, _appliance);
    final second = await api.applianceFacts(_home, _appliance);
    expect(identical(first, second), isTrue);
    expect(seen, hasLength(2));
    expect(seen[0].headers.containsKey('If-None-Match'), isFalse);
    expect(seen[1].headers['If-None-Match'], '"abc"');
    expect(
      seen[0].url.queryParameters['capability'],
      'gas_appliance_recommendations_v1',
    );
    expect(seen[0].url.path, '/v1/homes/$_home/appliances/$_appliance/facts');
  });

  test('a changed body replaces the cached entry', () async {
    var n = 0;
    final api = _api(
      MockClient((request) async {
        n++;
        final body = _fixture('electric_metered_washer');
        body['appliance_version'] = n;
        return http.Response(jsonEncode(body), 200, headers: {'etag': '"v$n"'});
      }),
    );
    addTearDown(api.close);
    await api.applianceFacts(_home, _appliance);
    final second = await api.applianceFacts(_home, _appliance);
    expect(second.applianceVersion, 2);
  });
}
