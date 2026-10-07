import 'package:flutter_test/flutter_test.dart';
import 'package:energylens_mobile/core/cloud_api/cloud_appliance.dart';

void main() {
  final appliance = <String, dynamic>{
    'id': 'a',
    'home_id': 'h',
    'name': 'Dryer',
    'category': 'dryer',
    'identity': <String, dynamic>{
      'brand': 'Acme',
      'full_model': 'A1',
      'fuel': 'electricity',
      'match_quality': 'confirmed_exact',
    },
  };

  test('old appliance response has no KB waste result', () {
    expect(CloudAppliance.fromJson(appliance).kbWasteResult, isNull);
  });

  test('explicit completed waste result is parsed', () {
    final value = CloudAppliance.fromJson({
      ...appliance,
      'kb_waste_result': {
        'id': 'scan-id',
        'status': 'waste_evidence_unavailable_after_kb',
      },
    });
    expect(value.kbWasteResult?.id, 'scan-id');
  });

  test('other KB statuses cannot appear as completed waste result', () {
    for (final status in [
      'pending',
      'failed',
      'review_pending',
      'no_evidence',
    ]) {
      expect(
        () => CloudAppliance.fromJson({
          ...appliance,
          'kb_waste_result': {'id': 'scan-id', 'status': status},
        }),
        throwsFormatException,
      );
    }
  });
}
