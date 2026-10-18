import 'package:flutter_test/flutter_test.dart';
import 'package:energylens_mobile/core/cloud_api/cloud_appliance.dart';

void main() {
  test('legacy KB waste metadata cannot affect appliance identity', () {
    final value = CloudAppliance.fromJson({
      'id': 'a',
      'home_id': 'h',
      'name': 'Dryer',
      'category': 'dryer',
      'identity': {
        'brand': '',
        'full_model': '',
        'fuel': 'electricity',
        'match_quality': 'unresolved',
      },
      'kb_waste_result': {
        'id': 'stale-scan',
        'status': 'waste_evidence_unavailable_after_kb',
      },
    });
    expect(value.brand, isEmpty);
    expect(value.fullModel, isEmpty);
    expect(value.category, 'dryer');
  });
}
