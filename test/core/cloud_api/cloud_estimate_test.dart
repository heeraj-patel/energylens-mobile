import 'package:energylens_mobile/core/cloud_api/cloud_estimate.dart';
import 'package:flutter_test/flutter_test.dart';

Map<String, dynamic> _json({bool unavailable = false}) => {
  'id': 'e1',
  'appliance_id': 'a1',
  'kind': unavailable ? 'unavailable' : 'estimated_operating_cost',
  'period': {'start': '2026-10-01', 'end': '2026-11-01', 'timezone': 'UTC'},
  'energy': unavailable
      ? null
      : {'value': '30', 'unit': 'kWh', 'fuel': 'electricity'},
  'cost': unavailable
      ? null
      : {'value': '5.1', 'currency': 'USD', 'rate_kind': 'regional_average'},
  'quality': {
    'identity': 'confirmed_exact',
    'consumption': 'resolved',
    'source': 'datawiz_resolution',
    'context': 'unknown',
    'rate': 'regional_average',
  },
  'waste': 'not_yet_assessed',
  'evidence_refs': [],
  'formula_version': 'v1',
  'as_of': '2026-10-19T00:00:00Z',
  if (unavailable) 'unavailable_reason': 'no_energy_data',
};

void main() {
  test('parses assessed waste and basis markers', () {
    final json = _json()
      ..['waste'] = 'assessed'
      ..['waste_energy'] = {
        'value': '0.06',
        'unit': 'kWh',
        'fuel': 'electricity',
      }
      ..['waste_cost'] = {
        'value': '0.01',
        'currency': 'USD',
        'rate_kind': 'regional_average',
      }
      ..['waste_basis'] = 'floor'
      ..['rate_basis'] = 'us_average';
    final e = CloudEstimate.fromJson(json);
    expect(e.waste, 'assessed');
    expect(e.wasteEnergy?.value, '0.06');
    expect(e.wasteCost, '0.01');
    expect(e.wasteBasis, 'floor');
    expect(e.rateBasis, 'us_average');
  });

  test('old shape without new fields still parses', () {
    final e = CloudEstimate.fromJson(_json());
    expect(e.waste, 'not_yet_assessed');
    expect(e.wasteEnergy, isNull);
    expect(e.wasteBasis, isNull);
    expect(e.rateBasis, isNull);
  });

  test('parses no_energy_data unavailable estimate', () {
    final e = CloudEstimate.fromJson(_json(unavailable: true));
    expect(e.unavailableReason, 'no_energy_data');
  });

  test('rejects unknown waste, waste_basis and rate_basis', () {
    expect(
      () => CloudEstimate.fromJson(_json()..['waste'] = 'maybe'),
      throwsFormatException,
    );
    expect(
      () => CloudEstimate.fromJson(_json()..['waste_basis'] = 'x'),
      throwsFormatException,
    );
    expect(
      () => CloudEstimate.fromJson(_json()..['rate_basis'] = 'x'),
      throwsFormatException,
    );
  });
}
