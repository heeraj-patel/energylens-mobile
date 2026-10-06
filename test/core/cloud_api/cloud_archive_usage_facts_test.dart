import 'dart:convert';

import 'package:energylens_mobile/core/cloud_api/cloud_api_client.dart';
import 'package:energylens_mobile/core/cloud_api/cloud_usage_facts.dart';
import 'package:energylens_mobile/core/cloud_auth/cloud_auth.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

const homeId = '11111111-1111-4111-8111-111111111111';
const applianceId = '22222222-2222-4222-8222-222222222222';
const key = '55555555-5555-4555-8555-555555555555';
const config = CloudAuthConfig(
  issuer: 'https://issuer.example',
  audience: 'a',
  clientId: 'c',
  redirectUrl: 'io.energylens.app://login-callback',
  apiUrl: 'https://api.example',
);

class Store implements CloudTokenStore {
  @override
  Future<void> clear() async {}
  @override
  Future<CloudTokens?> read() async => const CloudTokens(accessToken: 'token');
  @override
  Future<void> save(CloudTokens value) async {}
}

class Auth implements CloudAuthenticator {
  @override
  Future<CloudTokens> signIn(CloudAuthConfig config) async =>
      const CloudTokens(accessToken: 'token');
  @override
  Future<CloudTokens> refresh(
    CloudAuthConfig config,
    String refreshToken,
  ) async => const CloudTokens(accessToken: 'token');
}

CloudApiClient api(MockClient client) => CloudApiClient(
  session: CloudSession(config: config, store: Store(), authenticator: Auth()),
  client: client,
);

const scope = CloudUsageFactScope(
  category: 'washer',
  manufacturer: 'LG',
  model: 'WM3070HWA',
  fuel: 'electricity',
  variant: 'US-120V',
);

Map<String, dynamic> fact() => {
  'id': '33333333-3333-4333-8333-333333333333',
  'measurement_kind': 'cycle_energy',
  'value': '0.42',
  'unit': 'kWh/cycle',
  'test_basis': 'DOE Normal Cycle',
  'cycle_definition': 'Normal Cycle',
  'operation_mode': null,
  'included_energy': {
    'components': ['appliance_electricity'],
    'evidence_text': 'Appliance electricity only',
    'status': 'documented',
  },
  'source_kind': 'oem_pdf',
  'source_url': 'https://example.test/manual.pdf',
  'source_sha256': 'a' * 64,
  'source_page_index': 1,
  'dataset_id': null,
  'row_identifier': null,
  'field_name': null,
  'metadata_sha256': null,
  'review_sha256': 'b' * 64,
  'reviewed_at': '2026-09-28T00:00:00Z',
  'publication_sha256': 'c' * 64,
};

Map<String, dynamic> response({
  Map<String, dynamic>? factOverride,
  Map<String, dynamic>? scopeOverride,
  List<dynamic>? facts,
}) => {
  'schema': 'energylens.reviewed-usage-facts',
  'schema_version': 1,
  'scope': scopeOverride ?? scope.toQueryParameters(),
  'facts': facts ?? [factOverride ?? fact()],
};

void main() {
  test(
    'archives appliance with bearer auth, strong ETag and idempotency key',
    () async {
      http.Request? seen;
      final client = api(
        MockClient((request) async {
          seen = request;
          return http.Response('', 204);
        }),
      );
      await client.archiveAppliance(
        homeId,
        applianceId,
        ifMatch: '"3"',
        idempotencyKey: key,
      );
      expect(seen!.method, 'DELETE');
      expect(seen!.url.path, '/v1/homes/$homeId/appliances/$applianceId');
      expect(seen!.headers['authorization'], 'Bearer token');
      expect(seen!.headers['if-match'], '"3"');
      expect(seen!.headers['idempotency-key'], key);
      expect(seen!.body, isEmpty);
      client.close();
    },
  );

  test('archive surfaces stale version and idempotency errors', () async {
    final client = api(
      MockClient((request) async {
        if (request.headers['if-match'] == '"2"') {
          return http.Response('{"code":"version_conflict"}', 409);
        }
        return http.Response('{"code":"idempotency_key_reuse"}', 409);
      }),
    );
    await expectLater(
      client.archiveAppliance(
        homeId,
        applianceId,
        ifMatch: '"2"',
        idempotencyKey: key,
      ),
      throwsA(
        isA<CloudApiException>().having(
          (e) => e.code,
          'code',
          'version_conflict',
        ),
      ),
    );
    await expectLater(
      client.archiveAppliance(
        homeId,
        applianceId,
        ifMatch: '"3"',
        idempotencyKey: key,
      ),
      throwsA(
        isA<CloudApiException>().having(
          (e) => e.code,
          'code',
          'idempotency_key_reuse',
        ),
      ),
    );
    client.close();
  });

  test(
    'archive rejects non-version ETags and malformed idempotency keys locally',
    () async {
      var requests = 0;
      final client = api(
        MockClient((_) async {
          requests++;
          return http.Response('', 204);
        }),
      );
      await expectLater(
        client.archiveAppliance(
          homeId,
          applianceId,
          ifMatch: 'W/"3"',
          idempotencyKey: key,
        ),
        throwsArgumentError,
      );
      await expectLater(
        client.archiveAppliance(
          homeId,
          applianceId,
          ifMatch: '"3"',
          idempotencyKey: 'not-a-uuid',
        ),
        throwsArgumentError,
      );
      expect(requests, 0);
      client.close();
    },
  );

  test(
    'usage facts requests exact query with bearer auth and parses evidence',
    () async {
      http.Request? seen;
      final client = api(
        MockClient((request) async {
          seen = request;
          return http.Response(jsonEncode(response()), 200);
        }),
      );
      final value = await client.usageFacts(scope);
      expect(seen!.method, 'GET');
      expect(seen!.url.path, '/v1/usage-facts');
      expect(seen!.url.queryParameters, scope.toQueryParameters());
      expect(seen!.headers['authorization'], 'Bearer token');
      expect(value.scope.model, 'WM3070HWA');
      expect(value.facts.single.value, '0.42');
      expect(value.facts.single.includedEnergy.components, [
        'appliance_electricity',
      ]);
      expect(value.facts.single.publicationSha256, 'c' * 64);
      client.close();
    },
  );

  test('usage facts accepts empty exact-scope response and optional provenance fields', () async {
    final emptyClient = api(
      MockClient(
        (_) async => http.Response(jsonEncode(response(facts: [])), 200),
      ),
    );
    expect((await emptyClient.usageFacts(scope)).facts, isEmpty);
    emptyClient.close();

    final optional = fact()
      ..remove('cycle_definition')
      ..remove('operation_mode')
      ..remove('source_page_index')
      ..remove('dataset_id')
      ..remove('row_identifier')
      ..remove('field_name')
      ..remove('metadata_sha256');
    final optionalClient = api(
      MockClient(
        (_) async =>
            http.Response(jsonEncode(response(factOverride: optional)), 200),
      ),
    );
    final parsed = (await optionalClient.usageFacts(scope)).facts.single;
    expect(parsed.cycleDefinition, isNull);
    expect(parsed.sourcePageIndex, isNull);
    optionalClient.close();
  });

  test(
    'usage facts rejects mismatched scope, malformed and overfull response',
    () async {
      final mismatch = api(
        MockClient(
          (_) async => http.Response(
            jsonEncode(
              response(
                scopeOverride: {...scope.toQueryParameters(), 'model': 'other'},
              ),
            ),
            200,
          ),
        ),
      );
      await expectLater(mismatch.usageFacts(scope), throwsFormatException);
      mismatch.close();

      final malformed = api(
        MockClient((_) async => http.Response('{"schema":"unknown"}', 200)),
      );
      await expectLater(malformed.usageFacts(scope), throwsFormatException);
      malformed.close();

      final overfull = api(
        MockClient(
          (_) async => http.Response(
            jsonEncode(response(facts: [fact(), fact(), fact()])),
            200,
          ),
        ),
      );
      await expectLater(overfull.usageFacts(scope), throwsFormatException);
      overfull.close();
    },
  );

  test('usage facts validates exact scope and surfaces API errors', () async {
    var requests = 0;
    final client = api(
      MockClient((_) async {
        requests++;
        return http.Response('{"code":"invalid_request"}', 400);
      }),
    );
    await expectLater(
      client.usageFacts(
        const CloudUsageFactScope(
          category: 'dryer',
          manufacturer: 'LG',
          model: 'D1',
          fuel: 'natural_gas',
          variant: 'US',
        ),
      ),
      throwsA(
        isA<CloudApiException>().having(
          (e) => e.code,
          'code',
          'invalid_request',
        ),
      ),
    );
    await expectLater(
      client.usageFacts(
        const CloudUsageFactScope(
          category: 'washer',
          manufacturer: 'LG',
          model: 'W1',
          fuel: 'natural_gas',
          variant: 'US',
        ),
      ),
      throwsArgumentError,
    );
    expect(requests, 1);
    client.close();
  });
}
