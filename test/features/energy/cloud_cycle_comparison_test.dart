import 'package:energylens_mobile/core/cloud_api/cloud_cycle_comparison.dart';
import 'package:energylens_mobile/core/cloud_api/cloud_home.dart';
import 'package:flutter_test/flutter_test.dart';

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
}
