import 'dart:convert';

import 'package:energylens_mobile/core/cloud_api/cloud_api_client.dart';
import 'package:energylens_mobile/core/cloud_api/cloud_cycle_comparison.dart';
import 'package:energylens_mobile/core/cloud_api/cloud_home.dart';
import 'package:energylens_mobile/core/cloud_auth/cloud_auth.dart';
import 'package:energylens_mobile/features/energy/cloud_cycle_comparison_screen.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

const homeId = '11111111-1111-4111-8111-111111111111';
const applianceId = '22222222-2222-4222-8222-222222222222';
const attachmentId = '33333333-3333-4333-8333-333333333333';
const factId = '44444444-4444-4444-8444-444444444444';
const evidenceId = '55555555-5555-4555-8555-555555555555';
const home = CloudHome(
  id: homeId,
  name: 'Home',
  timezone: 'America/Chicago',
  countryCode: 'US',
  postalCode: '78701',
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
      audience: 'cloud',
      clientId: 'client',
      redirectUrl: 'io.energylens.app://login-callback',
      apiUrl: 'https://api.example',
    ),
    store: _Store(),
    authenticator: _Auth(),
  ),
  client: client,
);

Map<String, dynamic> reference() => {
  'status': 'available',
  'fact': {
    'id': factId,
    'value_kwh_per_cycle': 0.7,
    'test_basis': 'DOE Normal',
    'cycle_definition': 'Normal with heated dry',
    'source_kind': 'oem_pdf',
    'source_url': 'https://example.test/manual.pdf',
    'reviewed_at': '2026-09-29T00:00:00Z',
  },
};

void main() {
  test(
    'comparison parser rejects numeric claims when evidence is unavailable',
    () {
      final option = CloudCycleReferenceOption.fromJson(reference());
      final now = DateTime.now().toUtc();
      final request = CloudCycleComparisonRequest(
        start: now.subtract(const Duration(hours: 2)),
        end: now.subtract(const Duration(hours: 1)),
        attachmentId: attachmentId,
        reference: option.fact!,
        dedicatedNoOtherLoads: true,
      );
      expect(
        () => CloudCycleComparisonResult.fromJson({
          'status': 'unavailable',
          'reason': 'coverage_gap_reported',
          'start': request.start.toIso8601String(),
          'end': request.end.toIso8601String(),
          'measured_kwh': 0.8,
          'interpretation': cycleComparisonInterpretation,
        }, request),
        throwsFormatException,
      );
      expect(
        () => CloudCycleReferenceOption.fromJson({
          'status': 'unavailable',
          'reason': 'missing',
          'fact': reference()['fact'],
        }),
        throwsFormatException,
      );
    },
  );

  test(
    'saved evidence rejects changed owner scope and invalidated numbers',
    () {
      final option = CloudCycleReferenceOption.fromJson(reference());
      final now = DateTime.now().toUtc();
      final request = CloudCycleComparisonRequest(
        start: now.subtract(const Duration(hours: 2)),
        end: now.subtract(const Duration(hours: 1)),
        attachmentId: attachmentId,
        reference: option.fact!,
        dedicatedNoOtherLoads: true,
      );
      final saved = <String, dynamic>{
        'id': evidenceId,
        'status': 'invalidated',
        'reason': 'meter_evidence_changed',
        'home_id': homeId,
        'appliance_id': applianceId,
        'appliance_version': 1,
        'attachment_id': attachmentId,
        'start': request.start.toIso8601String(),
        'end': request.end.toIso8601String(),
        'fact_id': factId,
        'confirmed_test_basis': 'DOE Normal',
        'confirmed_cycle_definition': 'Normal with heated dry',
        'dedicated_no_other_loads': true,
        'created_at': now.toIso8601String(),
        'interpretation': cycleComparisonInterpretation,
      };
      expect(
        CloudSavedCycleEvidence.fromJson(
          saved,
          homeId: homeId,
          applianceId: applianceId,
          request: request,
        ).measuredKWh,
        isNull,
      );
      expect(
        () => CloudSavedCycleEvidence.fromJson(
          {...saved, 'measured_kwh': 0.8},
          homeId: homeId,
          applianceId: applianceId,
          request: request,
        ),
        throwsFormatException,
      );
      expect(
        () => CloudSavedCycleEvidence.fromJson(
          {...saved, 'home_id': attachmentId},
          homeId: homeId,
          applianceId: applianceId,
          request: request,
        ),
        throwsFormatException,
      );
    },
  );

  testWidgets(
    'tagged cycle shows only a neutral measured/reference comparison',
    (tester) async {
      Map<String, dynamic>? submitted;
      var savedFetches = 0;
      var saveAttempts = 0;
      String? saveKey;
      final api = _api(
        MockClient((request) async {
          expect(request.headers['authorization'], 'Bearer owner-token');
          if (request.url.path == '/v1/me/preferences') {
            return http.Response(
              '{"version":2,"schema_version":1,"email_reports_enabled":false}',
              200,
              headers: {'etag': '"2"'},
            );
          }
          if (request.url.path == '/v1/homes/$homeId/appliances') {
            return http.Response(
              jsonEncode({
                'appliances': [
                  {
                    'id': applianceId,
                    'home_id': homeId,
                    'name': 'Dishwasher',
                    'category': 'dishwasher',
                    'room': null,
                    'identity': {
                      'brand': 'Acme',
                      'full_model': 'DW123',
                      'variant': 'US-120V',
                      'fuel': 'electricity',
                      'match_quality': 'confirmed_exact',
                    },
                  },
                ],
              }),
              200,
            );
          }
          if (request.url.path == '/v1/homes/$homeId/attachments') {
            return http.Response(
              jsonEncode({
                'attachments': [
                  {
                    'id': attachmentId,
                    'home_id': homeId,
                    'appliance_id': applianceId,
                    'started_at': DateTime.now()
                        .toUtc()
                        .subtract(const Duration(days: 3))
                        .toIso8601String(),
                    'ended_at': null,
                  },
                ],
              }),
              200,
            );
          }
          if (request.url.path.endsWith('/cycle-comparison/reference')) {
            return http.Response(jsonEncode(reference()), 200);
          }
          if (request.url.path.endsWith('/cycle-comparison/evidence')) {
            expect(request.method, 'POST');
            saveAttempts++;
            saveKey ??= request.headers['idempotency-key'];
            expect(request.headers['idempotency-key'], saveKey);
            expect(jsonDecode(request.body), submitted);
            if (saveAttempts == 1) {
              return http.Response('{"code":"internal_error"}', 500);
            }
            return http.Response(
              jsonEncode({
                'id': evidenceId,
                'status': 'available',
                'home_id': homeId,
                'appliance_id': applianceId,
                'appliance_version': 2,
                'attachment_id': attachmentId,
                'start': submitted!['start'],
                'end': submitted!['end'],
                'fact_id': factId,
                'confirmed_test_basis': 'DOE Normal',
                'confirmed_cycle_definition': 'Normal with heated dry',
                'dedicated_no_other_loads': true,
                'measured_kwh': 0.8,
                'lab_reference_kwh_per_cycle': 0.7,
                'difference_kwh': 0.1,
                'created_at': DateTime.now().toUtc().toIso8601String(),
                'interpretation': cycleComparisonInterpretation,
              }),
              201,
            );
          }
          if (request.url.path.endsWith(
            '/cycle-comparison/evidence/$evidenceId',
          )) {
            expect(request.method, 'GET');
            savedFetches++;
            return http.Response(
              jsonEncode({
                'id': evidenceId,
                'status': 'invalidated',
                'reason': 'coverage_changed',
                'home_id': homeId,
                'appliance_id': applianceId,
                'appliance_version': 2,
                'attachment_id': attachmentId,
                'start': submitted!['start'],
                'end': submitted!['end'],
                'fact_id': factId,
                'confirmed_test_basis': 'DOE Normal',
                'confirmed_cycle_definition': 'Normal with heated dry',
                'dedicated_no_other_loads': true,
                'created_at': DateTime.now().toUtc().toIso8601String(),
                'interpretation': cycleComparisonInterpretation,
              }),
              200,
            );
          }
          expect(
            request.url.path,
            '/v1/homes/$homeId/appliances/$applianceId/cycle-comparison',
          );
          expect(request.method, 'POST');
          submitted = jsonDecode(request.body) as Map<String, dynamic>;
          expect(submitted!['fact_id'], factId);
          expect(submitted!['attachment_id'], attachmentId);
          expect(submitted!['dedicated_no_other_loads'], isTrue);
          return http.Response(
            jsonEncode({
              'status': 'available',
              'start': submitted!['start'],
              'end': submitted!['end'],
              'fact_id': factId,
              'measured_kwh': 0.8,
              'lab_reference_kwh_per_cycle': 0.7,
              'difference_kwh': 0.1,
              'interpretation': cycleComparisonInterpretation,
            }),
            200,
          );
        }),
      );
      await tester.pumpWidget(
        MaterialApp(
          home: CloudCycleComparisonScreen(api: api, home: home),
        ),
      );
      await tester.pumpAndSettle();
      expect(find.byKey(const Key('cycleReferenceValue')), findsOneWidget);
      expect(submitted, isNull);
      await tester.ensureVisible(find.byKey(const Key('cycleBasisConfirmed')));
      await tester.tap(find.byKey(const Key('cycleBasisConfirmed')));
      await tester.pumpAndSettle();
      await tester.ensureVisible(find.byKey(const Key('cycleAttachment')));
      await tester.tap(find.byKey(const Key('cycleAttachment')));
      await tester.pumpAndSettle();
      await tester.tap(find.textContaining('Plug/outlet attachment').last);
      await tester.pumpAndSettle();
      await tester.ensureVisible(
        find.byKey(const Key('cycleDedicatedConfirmed')),
      );
      await tester.tap(find.byKey(const Key('cycleDedicatedConfirmed')));
      await tester.pumpAndSettle();
      await tester.ensureVisible(
        find.byKey(const Key('compareDishwasherCycle')),
      );
      await tester.tap(find.byKey(const Key('compareDishwasherCycle')));
      await tester.pumpAndSettle();
      expect(
        submitted,
        isNotNull,
        reason: 'compare action must submit after both confirmations',
      );
      expect(find.byKey(const Key('cycleComparisonError')), findsNothing);
      await tester.scrollUntilVisible(
        find.byKey(const Key('cycleMeasuredValue')),
        200,
        scrollable: find.byType(Scrollable).first,
      );
      expect(find.byKey(const Key('cycleMeasuredValue')), findsOneWidget);
      expect(find.textContaining('No Waste or savings amount'), findsOneWidget);
      await tester.scrollUntilVisible(
        find.byKey(const Key('saveCycleEvidence')),
        200,
        scrollable: find.byType(Scrollable).first,
      );
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('saveCycleEvidence')));
      await tester.pumpAndSettle();
      expect(saveAttempts, 1);
      await tester.scrollUntilVisible(
        find.byKey(const Key('saveCycleEvidence')),
        200,
        scrollable: find.byType(Scrollable).first,
      );
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('saveCycleEvidence')));
      await tester.pumpAndSettle();
      expect(saveAttempts, 2);
      expect(find.byKey(const Key('savedCycleEvidenceStatus')), findsOneWidget);
      expect(saveKey, matches(RegExp(r'^[0-9a-f-]{36}$')));
      await tester.ensureVisible(
        find.byKey(const Key('refreshSavedCycleEvidence')),
      );
      await tester.tap(find.byKey(const Key('refreshSavedCycleEvidence')));
      await tester.pumpAndSettle();
      expect(savedFetches, 1);
      expect(find.byKey(const Key('cycleMeasuredValue')), findsNothing);
      expect(find.textContaining('no longer available'), findsOneWidget);
      api.close();
    },
  );
}
