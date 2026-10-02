import 'dart:convert';
import 'dart:io';

import 'package:energylens_mobile/core/cloud_api/cloud_api_client.dart';
import 'package:energylens_mobile/core/cloud_api/cloud_home.dart';
import 'package:energylens_mobile/core/cloud_auth/cloud_auth.dart';
import 'package:energylens_mobile/features/energy/cloud_report_preview_screen.dart';
import 'package:flutter/material.dart';
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
const applianceId = '22222222-2222-4222-8222-222222222222';
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

Map<String, Object?> _preview() {
  final now = DateTime.now().toUtc();
  return {
    'id': previewId,
    'snapshot_sha256': 'a' * 64,
    'home_id': home.id,
    'schema_version': 'manual-preview/v1',
    'created_at': now.subtract(const Duration(minutes: 1)).toIso8601String(),
    'expires_at': now.add(const Duration(hours: 23)).toIso8601String(),
    'scope': 'selected_appliances',
    'home_total_status': 'unavailable_incomplete_scope',
    'measured_status': 'not_included',
    'recommendations_status': 'not_included',
    'assumptions': ['Only selected appliances are included.'],
    'items': [
      {
        'appliance_id': applianceId,
        'category': 'washer',
        'explanation': 'No current estimate is available.',
        'estimate': null,
      },
    ],
    'stale': false,
  };
}

void main() {
  testWidgets('explicit approval safely retries a pending report request', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(900, 1800);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final deliveryPosts = <http.Request>[];
    final api = _api(
      MockClient((request) async {
        expect(request.headers['authorization'], 'Bearer owner-token');
        if (request.url.path == '/v1/homes') {
          return http.Response(
            jsonEncode({
              'homes': [
                {
                  'id': home.id,
                  'name': home.name,
                  'timezone': home.timezone,
                  'location': {
                    'country_code': home.countryCode,
                    'postal_code': home.postalCode,
                  },
                },
              ],
            }),
            200,
          );
        }
        if (request.url.path.endsWith('/appliances')) {
          return http.Response(
            jsonEncode({
              'appliances': [
                {
                  'id': applianceId,
                  'home_id': home.id,
                  'name': 'Washer',
                  'category': 'washer',
                  'identity': {
                    'brand': 'LG',
                    'full_model': 'WM3070HWA',
                    'fuel': 'electricity',
                    'match_quality': 'confirmed_exact',
                  },
                },
              ],
            }),
            200,
          );
        }
        if (request.url.path.endsWith('/reports/preview') ||
            request.url.path.endsWith('/reports/previews/$previewId')) {
          return http.Response(
            jsonEncode(_preview()),
            request.method == 'POST' ? 201 : 200,
          );
        }
        expect(
          request.url.path,
          '/v1/homes/${home.id}/reports/previews/$previewId/deliveries',
        );
        deliveryPosts.add(request);
        if (deliveryPosts.length == 1) throw const SocketException('uncertain');
        return http.Response(
          jsonEncode({
            'id': deliveryId,
            'preview_id': previewId,
            'recipients': ['a@example.com'],
            'state': 'pending',
            'created_at': DateTime.now().toUtc().toIso8601String(),
          }),
          201,
        );
      }),
    );
    await tester.pumpWidget(
      MaterialApp(
        home: CloudReportPreviewScreen(api: api, home: home),
      ),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('reportAppliance-$applianceId')));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Create private preview'));
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('reportStatus')), findsOneWidget);
    expect(deliveryPosts, isEmpty);
    await tester.ensureVisible(find.byKey(const Key('reportRecipients')));
    await tester.enterText(
      find.byKey(const Key('reportRecipients')),
      'A@Example.com',
    );
    expect(
      tester
          .widget<FilledButton>(find.byKey(const Key('requestReportDelivery')))
          .onPressed,
      isNull,
    );
    await tester.ensureVisible(find.byKey(const Key('reportApproval')));
    await tester.tap(find.byKey(const Key('reportApproval')));
    await tester.pumpAndSettle();
    await tester.ensureVisible(find.byKey(const Key('requestReportDelivery')));
    await tester.tap(find.byKey(const Key('requestReportDelivery')));
    await tester.pumpAndSettle();
    expect(find.textContaining('Retry unchanged'), findsOneWidget);
    expect(deliveryPosts, hasLength(1));
    expect(jsonDecode(deliveryPosts.single.body), {
      'approved_snapshot_sha256': 'a' * 64,
      'recipients': ['a@example.com'],
      'approved': true,
    });
    await tester.tap(find.byKey(const Key('requestReportDelivery')));
    await tester.pumpAndSettle();
    expect(deliveryPosts, hasLength(2));
    expect(deliveryPosts[1].body, deliveryPosts[0].body);
    expect(
      deliveryPosts[1].headers['idempotency-key'],
      deliveryPosts[0].headers['idempotency-key'],
    );
    expect(
      find.text('Report request queued · delivery pending'),
      findsOneWidget,
    );
    expect(
      find.textContaining('availability and completion are unknown'),
      findsOneWidget,
    );
    expect(find.byKey(const Key('requestReportDelivery')), findsNothing);
    api.close();
  });
}
