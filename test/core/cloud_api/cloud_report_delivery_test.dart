import 'dart:convert';

import 'package:energylens_mobile/core/cloud_api/cloud_api_client.dart';
import 'package:energylens_mobile/core/cloud_api/cloud_report_delivery.dart';
import 'package:energylens_mobile/core/cloud_auth/cloud_auth.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:flutter_test/flutter_test.dart';

const previewId = '55555555-5555-4555-8555-555555555555';
const deliveryId = '66666666-6666-4666-8666-666666666666';

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
  Future<CloudTokens> refresh(
    CloudAuthConfig config,
    String refreshToken,
  ) async => const CloudTokens(accessToken: 'fresh-token');
  @override
  Future<CloudTokens> signIn(CloudAuthConfig config) async =>
      const CloudTokens(accessToken: 'owner-token');
}

void main() {
  test(
    'approval POST binds exact digest, recipients and stable caller key',
    () async {
      final requests = <http.Request>[];
      final client = CloudApiClient(
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
          requests.add(request);
          return http.Response(
            jsonEncode({
              'id': deliveryId,
              'preview_id': previewId,
              'recipients': ['a@example.com'],
              'state': 'pending',
              'created_at': '2026-10-02T12:00:00Z',
            }),
            201,
          );
        }),
      );
      const homeId = '11111111-1111-4111-8111-111111111111';
      const key = '77777777-7777-4777-8777-777777777777';
      final delivery = await client.queueReportDelivery(
        homeId,
        previewId,
        'a' * 64,
        ['a@example.com'],
        idempotencyKey: key,
      );
      expect(delivery.state, 'pending');
      expect(requests.single.method, 'POST');
      expect(
        requests.single.url.path,
        '/v1/homes/$homeId/reports/previews/$previewId/deliveries',
      );
      expect(requests.single.headers['Idempotency-Key'], key);
      expect(requests.single.headers['Authorization'], 'Bearer owner-token');
      expect(jsonDecode(requests.single.body), {
        'approved_snapshot_sha256': 'a' * 64,
        'recipients': ['a@example.com'],
        'approved': true,
      });
      client.close();
    },
  );

  test('recipient validation matches server limits and canonical ordering', () {
    expect(validatedReportRecipients(' B@Example.com, a@example.com\n'), [
      'a@example.com',
      'b@example.com',
    ]);
    expect(validatedReportRecipients(''), isNull);
    expect(validatedReportRecipients('a@example.com,'), isNull);
    expect(validatedReportRecipients('a@example.com,A@example.com'), isNull);
    expect(validatedReportRecipients('a@-example.com'), isNull);
    expect(
      validatedReportRecipients(
        'a@example.com,b@example.com,c@example.com,d@example.com,e@example.com,f@example.com',
      ),
      isNull,
    );
  });

  test('delivery receipt must be pending and bound to approved preview', () {
    final payload = {
      'id': deliveryId,
      'preview_id': previewId,
      'recipients': ['a@example.com'],
      'state': 'pending',
      'created_at': '2026-10-02T12:00:00Z',
    };
    expect(CloudReportDelivery.fromJson(payload, previewId).state, 'pending');
    expect(
      () => CloudReportDelivery.fromJson({
        ...payload,
        'state': 'delivered',
      }, previewId),
      throwsFormatException,
    );
    expect(
      () => CloudReportDelivery.fromJson(payload, deliveryId),
      throwsFormatException,
    );
  });
}
