import 'dart:convert';
import 'dart:io';
import 'dart:async';

import 'package:energylens_mobile/core/cloud_api/cloud_api_client.dart';
import 'package:energylens_mobile/core/cloud_api/cloud_home.dart';
import 'package:energylens_mobile/core/cloud_auth/cloud_auth.dart';
import 'package:energylens_mobile/core/cloud_auth/cloud_auxiliary_domain_lifecycle.dart';
import 'package:energylens_mobile/features/design/report_preview_domain_repository.dart';
import 'package:energylens_mobile/features/design/report_delivery_domain_adapter.dart';
import 'package:energylens_mobile/features/identify/onboarding_draft_store.dart';
import 'package:energylens_mobile/features/identify/onboarding_persistence_repository.dart';
import 'package:energylens_mobile/features/energy/cloud_report_preview_screen.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:printing/printing.dart';

const home = CloudHome(
  id: '11111111-1111-4111-8111-111111111111',
  name: 'Home',
  timezone: 'America/Chicago',
  countryCode: 'US',
  postalCode: '60601',
);
const applianceId = '22222222-2222-4222-8222-222222222222';
const seededId = '839e2376-d211-5137-b5fb-09486a7d978a';
const previewId = '55555555-5555-4555-8555-555555555555';
const deliveryId = '66666666-6666-4666-8666-666666666666';
const accountA = 'aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa';
const accountB = 'bbbbbbbb-bbbb-4bbb-8bbb-bbbbbbbbbbbb';

class _DraftStorage implements OnboardingDraftStorage {
  @override
  Future<String?> read() async => null;
  @override
  Future<void> write(String data) async {}
  @override
  Future<void> clear() async {}
}

class _DraftSource implements OnboardingPersistenceSource {
  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

CloudAuxiliaryDomainLifecycle _lifecycle(
  CloudApiClient api,
) => CloudAuxiliaryDomainLifecycle(
  drafts: DurableOnboardingDrafts(
    _DraftStorage(),
    OnboardingPersistenceRepository(_DraftSource()),
  ),
  reports: ReportPreviewDomainRepository(CloudReportPreviewDomainSource(api)),
  deliveries: ReportDeliveryDomainAdapter(CloudReportDeliveryDomainSource(api)),
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
  testWidgets('seeded inventory UUID and persisted UUID reach v2 POST and GET', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(900, 1800);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final posted = <String>[];
    var reads = 0;
    final response = {
      ..._preview(),
      'schema_version': 'manual-preview/v2',
      'measured_status': 'unavailable',
      'recommendations_status': 'unavailable',
      'items': [
        {
          'appliance_id': seededId,
          'category': 'other',
          'estimate': null,
          'explanation': 'No current reviewed monthly estimate is available for this appliance.',
        },
        {
          'appliance_id': applianceId,
          'category': 'washer',
          'estimate': null,
          'explanation': 'No current reviewed monthly estimate is available for this appliance.',
        },
      ],
    };
    final api = _api(
      MockClient((request) async {
        if (request.url.path.endsWith('/appliances')) {
          return http.Response(
            jsonEncode({
              'appliances': [
                {
                  'id': seededId,
                  'demo_device_id': 'demo-device-01',
                  'home_id': home.id,
                  'name': 'Study Desktop & Rig',
                  'category': '',
                  'identity': {
                    'brand': '',
                    'full_model': '',
                    'fuel': '',
                    'match_quality': 'unresolved',
                  },
                  'version': 1,
                  'archived_at': null,
                },
                {
                  'id': applianceId,
                  'home_id': home.id,
                  'name': 'Washer',
                  'category': 'washer',
                  'identity': {
                    'brand': '',
                    'full_model': '',
                    'fuel': 'electricity',
                    'match_quality': 'unresolved',
                  },
                },
              ],
            }),
            200,
          );
        }
        if (request.url.path.endsWith('/reports/preview')) {
          posted.addAll(
            (jsonDecode(request.body) as Map<String, dynamic>)['appliance_ids']
                .cast<String>(),
          );
          return http.Response(jsonEncode(response), 201);
        }
        if (request.url.path.endsWith('/reports/previews/$previewId')) {
          reads++;
          return http.Response(jsonEncode(response), 200);
        }
        fail('Unexpected request: ${request.url.path}');
      }),
    );
    await tester.pumpWidget(
      MaterialApp(
        home: CloudReportPreviewScreen(api: api, home: home),
      ),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('reportAppliance-$seededId')));
    await tester.tap(find.byKey(const Key('reportAppliance-$applianceId')));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Create private preview'));
    await tester.pumpAndSettle();
    expect(posted, [applianceId, seededId]);
    expect(reads, 1);
    expect(find.byKey(const Key('reportStatus')), findsOneWidget);
    expect(
      find.text(
        'No current reviewed monthly estimate is available for this appliance.',
      ),
      findsNWidgets(2),
    );
    api.close();
  });

  testWidgets('direct send requires sent confirmation for terminal status', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(900, 1800);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final deliveryPosts = <http.Request>[];
    String? deliveryReadbackState;
    var staleReadback = false;
    var previewReads = 0;
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
          if (request.method == 'GET') previewReads++;
          final body = _preview();
          body['stale'] = staleReadback;
          if (request.method == 'GET' && deliveryReadbackState != null) {
            body['latest_delivery'] = {
              'id': deliveryId,
              'state': deliveryReadbackState,
              'created_at': DateTime.now().toUtc().toIso8601String(),
              'sent_at': deliveryReadbackState == 'sent'
                  ? DateTime.now().toUtc().toIso8601String()
                  : null,
            };
          }
          return http.Response(
            jsonEncode(body),
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
            'state': 'sent',
            'created_at': DateTime.now().toUtc().toIso8601String(),
            'sent_at': DateTime.now().toUtc().toIso8601String(),
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
    expect(find.text('Internal Error, Try again later'), findsOneWidget);
    expect(deliveryPosts, hasLength(1));
    expect(jsonDecode(deliveryPosts.single.body), {
      'approved_snapshot_sha256': 'a' * 64,
      'recipients': ['a@example.com'],
      'approved': true,
      'send_now': true,
    });
    await tester.tap(find.byKey(const Key('requestReportDelivery')));
    await tester.pumpAndSettle();
    expect(deliveryPosts, hasLength(2));
    expect(deliveryPosts[1].body, deliveryPosts[0].body);
    expect(
      deliveryPosts[1].headers['idempotency-key'],
      deliveryPosts[0].headers['idempotency-key'],
    );
    expect(find.byKey(const Key('reportDeliveryStatus')), findsOneWidget);
    expect(find.text('Email sent'), findsOneWidget);
    expect(find.byKey(const Key('requestReportDelivery')), findsNothing);
    deliveryReadbackState = 'sent';
    await tester.pump(const Duration(seconds: 10));
    await tester.pumpAndSettle();
    expect(find.text('Email sent'), findsOneWidget);
    staleReadback = true;
    deliveryReadbackState = 'canceled';
    await tester.tap(find.text('Check preview status'));
    await tester.pumpAndSettle();
    expect(find.text('Internal Error, Try again later'), findsOneWidget);
    api.close();
  });

  testWidgets('verified scope queues through lifecycle revalidation', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(900, 1800);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    var previewReads = 0;
    var deliveries = 0;
    final api = _api(
      MockClient((request) async {
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
        if (request.url.path.endsWith('/reports/preview')) {
          return http.Response(jsonEncode(_preview()), 201);
        }
        if (request.url.path.endsWith('/reports/previews/$previewId')) {
          previewReads++;
          return http.Response(jsonEncode(_preview()), 200);
        }
        if (request.url.path.endsWith('/deliveries')) {
          deliveries++;
          expect(previewReads, 3);
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
        }
        fail('Unexpected request: ${request.url.path}');
      }),
    );
    final lifecycle = _lifecycle(api);
    await lifecycle.selectVerifiedHome(accountA, home.id);
    await tester.pumpWidget(
      MaterialApp(
        home: CloudReportPreviewScreen(
          api: api,
          home: home,
          lifecycle: lifecycle,
          accountId: accountA,
        ),
      ),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('reportAppliance-$applianceId')));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Create private preview'));
    await tester.pumpAndSettle();
    await tester.ensureVisible(find.byKey(const Key('reportRecipients')));
    await tester.enterText(
      find.byKey(const Key('reportRecipients')),
      'a@example.com',
    );
    await tester.ensureVisible(find.byKey(const Key('reportApproval')));
    await tester.tap(find.byKey(const Key('reportApproval')));
    await tester.pumpAndSettle();
    await tester.ensureVisible(find.byKey(const Key('requestReportDelivery')));
    await tester.tap(find.byKey(const Key('requestReportDelivery')));
    await tester.pumpAndSettle();
    expect(deliveries, 1);
    expect(find.byKey(const Key('reportDeliveryStatus')), findsNothing);
    api.close();
  });

  testWidgets(
    'late recipient-free preview read is hidden after account switch',
    (tester) async {
      final pendingRead = Completer<http.Response>();
      var reads = 0;
      final api = _api(
        MockClient((request) async {
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
          if (request.url.path.endsWith('/reports/preview')) {
            return http.Response(jsonEncode(_preview()), 201);
          }
          if (request.url.path.endsWith('/reports/previews/$previewId')) {
            reads++;
            return pendingRead.future;
          }
          fail('Unexpected request: ${request.url.path}');
        }),
      );
      final lifecycle = _lifecycle(api);
      await lifecycle.selectVerifiedHome(accountA, home.id);
      await tester.pumpWidget(
        MaterialApp(
          home: CloudReportPreviewScreen(
            api: api,
            home: home,
            lifecycle: lifecycle,
            accountId: accountA,
          ),
        ),
      );
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('reportAppliance-$applianceId')));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Create private preview'));
      await tester.pump();
      expect(reads, 1);
      await lifecycle.selectVerifiedHome(accountB, home.id);
      pendingRead.complete(
        http.Response(
          jsonEncode({
            ..._preview(),
            'latest_delivery': {
              'id': deliveryId,
              'state': 'pending',
              'created_at': DateTime.now().toUtc().toIso8601String(),
              'sent_at': null,
            },
          }),
          200,
        ),
      );
      await tester.pump();
      expect(find.byKey(const Key('reportStatus')), findsNothing);
      expect(lifecycle.isVerifiedScope(accountA, home.id), isFalse);
      api.close();
    },
  );

  test(
    'report PDF download sends owner digest and rejects non-PDF bytes',
    () async {
      var valid = true;
      final api = _api(
        MockClient((request) async {
          expect(request.method, 'GET');
          expect(
            request.url.path,
            '/v1/homes/${home.id}/reports/previews/$previewId/pdf',
          );
          expect(request.headers['authorization'], 'Bearer owner-token');
          expect(request.headers['x-report-snapshot-sha256'], 'a' * 64);
          return http.Response(
            valid ? '%PDF-test' : 'not a PDF',
            200,
            headers: {'content-type': 'application/pdf'},
          );
        }),
      );
      expect(await api.reportPDF(home.id, previewId, 'a' * 64), hasLength(9));
      valid = false;
      await expectLater(
        api.reportPDF(home.id, previewId, 'a' * 64),
        throwsA(isA<FormatException>()),
      );
      api.close();
    },
  );

  testWidgets('PDF action uses approved progress and error copy', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(900, 1800);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    var pendingPDF = Completer<http.Response>();
    final api = _api(
      MockClient((request) async {
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
        if (request.url.path.endsWith('/reports/preview')) {
          return http.Response(jsonEncode(_preview()), 201);
        }
        if (request.url.path.endsWith('/reports/previews/$previewId')) {
          return http.Response(jsonEncode(_preview()), 200);
        }
        if (request.url.path.endsWith('/reports/previews/$previewId/pdf')) {
          return pendingPDF.future;
        }
        fail('Unexpected request: ${request.url.path}');
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
    expect(find.text('View PDF'), findsOneWidget);
    expect(find.text('Save or share PDF'), findsOneWidget);
    await tester.ensureVisible(find.byKey(const Key('viewReportPDF')));
    await tester.tap(find.byKey(const Key('viewReportPDF')));
    await tester.pump();
    expect(find.text('Preparing PDF…'), findsOneWidget);
    pendingPDF.complete(http.Response('{"code":"preview_stale"}', 409));
    await tester.pumpAndSettle();
    expect(find.text('Couldn’t prepare the PDF. Try again.'), findsOneWidget);
    expect(find.text('✉ Email Report Now'), findsOneWidget);
    pendingPDF = Completer<http.Response>();
    await tester.ensureVisible(find.byKey(const Key('viewReportPDF')));
    await tester.tap(find.byKey(const Key('viewReportPDF')));
    await tester.pump();
    pendingPDF.complete(
      http.Response(
        '%PDF-test',
        200,
        headers: {'content-type': 'application/pdf'},
      ),
    );
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));
    expect(find.byType(PdfPreview), findsOneWidget);
    final signOut = api.session.signOut();
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));
    expect(find.byType(PdfPreview), findsNothing);
    await signOut;
    api.close();
  });
}
