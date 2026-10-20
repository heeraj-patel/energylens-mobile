import 'package:energylens_mobile/core/cloud_api/cloud_estimate.dart';
import 'package:flutter_test/flutter_test.dart';

Map<String, dynamic> _run(
  String id,
  String applianceId,
  String kind, {
  String asOf = '2026-10-01T12:00:00Z',
  String? reason,
}) {
  final result = <String, dynamic>{
    'id': id,
    'appliance_id': applianceId,
    'kind': kind,
    'period': {
      'start': '2026-10-01',
      'end': '2026-11-01',
      'timezone': 'America/Chicago',
    },
    'energy': kind == 'unavailable'
        ? null
        : {'value': '54.916667', 'unit': 'kWh', 'fuel': 'electricity'},
    'cost': kind == 'unavailable'
        ? null
        : {'value': '10.983333', 'currency': 'USD', 'rate_kind': 'user_tariff'},
    'quality': {
      'identity': 'confirmed_exact',
      'consumption': kind == 'unavailable'
          ? 'unavailable'
          : 'published_test_basis',
      'source': kind == 'unavailable' ? 'unavailable' : 'reviewed_exact',
      'context': 'unknown',
      'rate': kind == 'unavailable' ? 'unavailable' : 'user_tariff',
    },
    'waste': 'not_yet_assessed',
    'evidence_refs': kind == 'unavailable'
        ? <Object>[]
        : [
            {
              'id': '77777777-7777-4777-8777-777777777777',
              'kind': 'catalog_fact',
              'revision': 2,
            },
            {
              'id': '88888888-8888-4888-8888-888888888888',
              'kind': 'tariff',
              'revision': 3,
            },
          ],
    'formula_version': 'reviewed-energy/v1',
    'as_of': asOf,
  };
  if (reason != null) {
    result['unavailable_reason'] = reason;
  }
  return result;
}

void main() {
  test('priced estimate validates fuel and energy unit as a pair', () {
    const id = '22222222-2222-4222-8222-222222222222';
    Map<String, dynamic> withEnergy(String fuel, String unit) => _run(
      '44444444-4444-4444-8444-444444444444',
      id,
      'estimated_useful_cost',
    )..['energy'] = {'value': '7.750000', 'fuel': fuel, 'unit': unit};

    final gas = CloudEstimate.fromJson(withEnergy('natural_gas', 'therm'));
    expect(gas.energy?.fuel, 'natural_gas');
    expect(gas.energy?.unit, 'therm');
    for (final (fuel, unit) in [
      ('natural_gas', 'kWh'),
      ('electricity', 'therm'),
      ('propane', 'therm'),
    ]) {
      expect(
        () => CloudEstimate.fromJson(withEnergy(fuel, unit)),
        throwsFormatException,
      );
    }
  });
}
