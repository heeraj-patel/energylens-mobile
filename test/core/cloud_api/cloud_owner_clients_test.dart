import 'dart:convert';

import 'package:energylens_mobile/core/cloud_api/cloud_api_client.dart';
import 'package:energylens_mobile/core/cloud_api/cloud_appliance.dart';
import 'package:energylens_mobile/core/cloud_api/cloud_home.dart';
import 'package:energylens_mobile/core/cloud_api/cloud_sensor.dart';
import 'package:energylens_mobile/core/cloud_auth/cloud_auth.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

const homeId = '11111111-1111-4111-8111-111111111111';
const applianceId = '22222222-2222-4222-8222-222222222222';
const sensorId = '33333333-3333-4333-8333-333333333333';
const attachmentId = '44444444-4444-4444-8444-444444444444';
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

Map<String, dynamic> home() => {
  'id': homeId,
  'name': 'Home',
  'timezone': 'America/Chicago',
  'location': {'country_code': 'US', 'postal_code': '60601'},
  'version': 2,
  'created_at': '2026-01-01T00:00:00Z',
  'updated_at': '2026-01-02T00:00:00Z',
};
Map<String, dynamic> appliance() => {
  'id': applianceId,
  'home_id': homeId,
  'name': 'Washer',
  'category': 'washer',
  'room': 'Laundry',
  'identity': {
    'brand': 'LG',
    'full_model': 'A1',
    'fuel': 'electricity',
    'match_quality': 'user_typed',
  },
  'version': 3,
  'created_at': '2026-01-01T00:00:00Z',
  'updated_at': '2026-01-02T00:00:00Z',
  'archived_at': null,
};
Map<String, dynamic> sensor() => {
  'id': sensorId,
  'home_id': homeId,
  'kind': 'plug',
  'capabilities': ['power', 'energy'],
  'hub_id': '66666666-6666-4666-8666-666666666666',
  'ownership_epoch': 1,
  'local_sensor_id': 'plug-1',
  'version': 1,
  'parent_sensor_id': null,
};
Map<String, dynamic> attachment() => {
  'id': attachmentId,
  'home_id': homeId,
  'sensor_id': sensorId,
  'appliance_id': applianceId,
  'started_at': '2026-09-01T00:00:00Z',
  'ended_at': null,
  'identity_revision': 3,
  'version': 1,
  'created_at': '2026-09-01T00:00:00Z',
  'updated_at': '2026-09-01T00:00:00Z',
};

void main() {
  test(
    'home and appliance reads are owner scoped, typed and expose ETags',
    () async {
      final seen = <http.Request>[];
      final client = api(
        MockClient((request) async {
          seen.add(request);
          final body = request.url.path.endsWith('/$homeId')
              ? home()
              : appliance();
          return http.Response(
            jsonEncode(body),
            200,
            headers: {'etag': '"v2"'},
          );
        }),
      );
      final h = await client.home(homeId);
      final a = await client.appliance(homeId, applianceId);
      expect(h.value.version, 2);
      expect(h.etag, '"v2"');
      expect(a.value.brand, 'LG');
      expect(seen.map((request) => request.url.path), [
        '/v1/homes/$homeId',
        '/v1/homes/$homeId/appliances/$applianceId',
      ]);
      expect(
        seen.every(
          (request) => request.headers['authorization'] == 'Bearer token',
        ),
        isTrue,
      );
      client.close();
    },
  );

  test(
    'patch requests carry If-Match and idempotency and parse versioned replies',
    () async {
      final seen = <http.Request>[];
      final client = api(
        MockClient((request) async {
          seen.add(request);
          return http.Response(
            jsonEncode(
              request.url.path == '/v1/homes/$homeId' ? home() : appliance(),
            ),
            200,
            headers: {'etag': '"v4"'},
          );
        }),
      );
      expect(
        (await client.updateHome(
          homeId,
          const CloudHomePatch(name: 'Updated'),
          ifMatch: '"v2"',
          idempotencyKey: key,
        )).etag,
        '"v4"',
      );
      await client.updateAppliance(
        homeId,
        applianceId,
        const CloudAppliancePatch(name: 'New name'),
        ifMatch: '"v3"',
        idempotencyKey: key,
      );
      expect(seen[0].headers['if-match'], '"v2"');
      expect(seen[0].headers['idempotency-key'], key);
      expect(jsonDecode(seen[0].body), {'name': 'Updated'});
      expect(seen[1].headers['if-match'], '"v3"');
      expect(jsonDecode(seen[1].body), {'name': 'New name'});
      client.close();
    },
  );

  test('home and appliance edits surface backend version conflicts', () async {
    final client = api(
      MockClient(
        (_) async => http.Response('{"code":"version_conflict"}', 409),
      ),
    );
    await expectLater(
      client.updateHome(
        homeId,
        const CloudHomePatch(name: 'x'),
        ifMatch: '"v1"',
        idempotencyKey: key,
      ),
      throwsA(
        isA<CloudApiException>().having((e) => e.statusCode, 'statusCode', 409),
      ),
    );
    await expectLater(
      client.updateAppliance(
        homeId,
        applianceId,
        const CloudAppliancePatch(name: 'x'),
        ifMatch: '"v1"',
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
    client.close();
  });

  test(
    'sensor list/create and attachment attach/close send typed owner requests',
    () async {
      final seen = <http.Request>[];
      final client = api(
        MockClient((request) async {
          seen.add(request);
          if (request.url.path.endsWith('/sensors') &&
              request.method == 'GET') {
            return http.Response(
              jsonEncode({
                'sensors': [sensor()],
              }),
              200,
            );
          }
          if (request.url.path.endsWith('/sensors')) {
            return http.Response(jsonEncode(sensor()), 201);
          }
          final result = attachment();
          if (request.method == 'PATCH') {
            result['ended_at'] = '2026-10-01T00:00:00Z';
          }
          return http.Response(
            jsonEncode(result),
            request.method == 'POST' ? 201 : 200,
          );
        }),
      );
      expect((await client.sensors(homeId)).single.id, sensorId);
      expect(
        (await client.createSensor(
          homeId,
          const CloudSensorCreate(
            kind: 'plug',
            capabilities: ['power'],
            hubId: '66666666-6666-4666-8666-666666666666',
            ownershipEpoch: 1,
            localSensorId: 'plug-1',
          ),
          idempotencyKey: key,
        )).homeId,
        homeId,
      );
      await client.createAttachment(
        homeId,
        CloudAttachmentCreate(
          sensorId: sensorId,
          applianceId: applianceId,
          startedAt: DateTime.utc(2026, 9, 1),
          identityRevision: 3,
        ),
        ifMatch: '"sensor-v1"',
        idempotencyKey: key,
      );
      expect(
        (await client.closeAttachment(
          homeId,
          attachmentId,
          CloudAttachmentClose(DateTime.utc(2026, 10, 1)),
          ifMatch: '"sensor-v2"',
          idempotencyKey: key,
        )).endedAt,
        isNotNull,
      );
      expect(seen.map((r) => r.url.path), [
        '/v1/homes/$homeId/sensors',
        '/v1/homes/$homeId/sensors',
        '/v1/homes/$homeId/attachments',
        '/v1/homes/$homeId/attachments/$attachmentId',
      ]);
      expect(seen[2].headers['if-match'], '"sensor-v1"');
      expect(seen[3].headers['if-match'], '"sensor-v2"');
      expect(
        seen.skip(1).every((r) => r.headers['idempotency-key'] == key),
        isTrue,
      );
      client.close();
    },
  );

  test(
    'requires resource ETag and rejects cross-home typed responses',
    () async {
      final noTag = api(
        MockClient((_) async => http.Response(jsonEncode(home()), 200)),
      );
      await expectLater(noTag.home(homeId), throwsFormatException);
      noTag.close();
      final wrongOwner = api(
        MockClient(
          (_) async => http.Response(
            jsonEncode({
              ...appliance(),
              'home_id': '77777777-7777-4777-8777-777777777777',
            }),
            200,
            headers: {'etag': '"v1"'},
          ),
        ),
      );
      await expectLater(
        wrongOwner.appliance(homeId, applianceId),
        throwsFormatException,
      );
      wrongOwner.close();
    },
  );
}
