import 'package:energylens_mobile/core/cloud_api/cloud_appliance.dart';
import 'package:energylens_mobile/core/cloud_api/cloud_appliance_list.dart';
import 'package:energylens_mobile/core/cloud_api/cloud_household_energy.dart';
import 'package:energylens_mobile/features/design/design_context_coordinator.dart';
import 'package:energylens_mobile/features/design/devices_domain_repository.dart';
import 'package:energylens_mobile/features/design/live_devices_projection.dart';
import 'package:flutter_test/flutter_test.dart';

const homeA = '11111111-1111-4111-8111-111111111111';
const electric = 'aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa';
const dryer = 'bbbbbbbb-bbbb-4bbb-8bbb-bbbbbbbbbbbb';
const boiler = 'cccccccc-cccc-4ccc-8ccc-cccccccccccc';
const noRate = 'dddddddd-dddd-4ddd-8ddd-dddddddddddd';
const gasOnly = 'eeeeeeee-eeee-4eee-8eee-eeeeeeeeeeee';
const unknownGas = '11111111-2222-4222-8222-222222222222';
const meteredGas = '33333333-3333-4333-8333-333333333333';
const tagged = 'ffffffff-ffff-4fff-8fff-ffffffffffff';

DeviceInventoryItem _item(String id, String name) => DeviceInventoryItem(
  appliance: CloudAppliance(
    id: id,
    homeId: homeA,
    name: name,
    category: 'other',
    room: null,
    brand: 'Brand',
    fullModel: 'Model',
    fuel: 'electric',
    matchQuality: 'confirmed_exact',
  ),
  activeAttachmentIds: const [],
  measuredBuckets: const [],
);

Map<String, Object?> _money(String value) => {
  'amount': value,
  'currency': 'USD',
};

Map<String, Object?> _allocation(
  String basis, {
  String? cost,
  String? useful,
  String? waste,
  String? unclassified,
  String? fuel,
  String? gasCost,
  bool gasKnown = false,
  String? totalCost,
  String? wasteBasis,
}) => {
  'energy': null,
  'cost': cost == null ? null : _money(cost),
  'useful_energy': null,
  'useful_cost': useful == null ? null : _money(useful),
  'waste_energy': null,
  'waste_cost': waste == null ? null : _money(waste),
  'unclassified_energy': null,
  'unclassified_cost': unclassified == null ? null : _money(unclassified),
  'availability': 'partial',
  'evidence_basis': basis,
  'waste_basis': ?wasteBasis,
  'fuel': ?fuel,
  if (gasKnown) 'gas_energy': {'value': '1.0', 'unit': 'therm'},
  if (gasCost != null) 'gas_cost': _money(gasCost),
  if (totalCost != null) 'total_cost': _money(totalCost),
  if (wasteBasis == 'rated_standby' && waste != null)
    'standby_cost': _money(waste),
};

LiveDevicesProjection _project(Map<String, Map<String, Object?>> rows) {
  final costs = CloudHouseholdEnergyTrends.fromJson({
    'schema_revision': 'household_energy_v1',
    'content_revision': 'v1',
    'home_id': homeA,
    'data_mode': 'household',
    'snapshot_id': 'snapshot-1',
    'generated_at': '2026-10-06T18:00:00Z',
    'as_of': null,
    'timezone': 'America/Chicago',
    'period': {
      'start_local': '2026-10-05T00:00:00-05:00',
      'end_exclusive_local': '2026-10-12T00:00:00-05:00',
    },
    'scope': 'attributed_devices',
    'availability': 'partial',
    'evidence_basis': 'mixed',
    'view': 'energy_trends',
    'granularity': 'day',
    'totals': _allocation('mixed'),
    'buckets': [
      {
        'start_local': '2026-10-06T00:00:00-05:00',
        'end_exclusive_local': '2026-10-07T00:00:00-05:00',
        'allocation': _allocation('mixed'),
        'coverage_fraction': null,
        'device_allocations': [
          for (final e in rows.entries)
            {'appliance_id': e.key, 'allocation': e.value},
        ],
      },
    ],
  }, expectedHomeId: homeA);
  return prepareLiveDevicesProjection(
    DesignContextRead(
      accountId: 'account',
      homeId: homeA,
      mode: DesignContextMode.household,
      page: 'devices',
      value: DevicesDomainSnapshot(
        homeId: homeA,
        items: [for (final id in rows.keys) _item(id, 'Device $id')],
        hasMoreMeteredPages: false,
        dataMode: CloudApplianceDataMode.household,
        fixtureRevision: null,
        sampleDayCosts: costs,
        isCurrent: () => true,
      ),
    ),
  );
}

LiveDeviceRow _row(LiveDevicesProjection p, String id) =>
    p.rows.firstWhere((r) => r.applianceId == id);

void main() {
  final projection = _project({
    electric: _allocation(
      'measured',
      cost: '0.680000',
      useful: '0.330000',
      waste: '0.350000',
    ),
    tagged: _allocation(
      'measured',
      cost: '0.680000',
      useful: '0.330000',
      waste: '0.350000',
      fuel: 'electricity',
    ),
    dryer: _allocation(
      'estimated',
      cost: '0.100000',
      unclassified: '0.100000',
      fuel: 'natural_gas',
      gasCost: '0.500000',
      gasKnown: true,
      totalCost: '0.600000',
    ),
    boiler: _allocation(
      'estimated',
      cost: '0.200000',
      useful: '0.150000',
      waste: '0.050000',
      wasteBasis: 'rated_standby',
      fuel: 'natural_gas',
      gasCost: '0.400000',
      gasKnown: true,
      totalCost: '0.600000',
    ),
    noRate: _allocation(
      'estimated',
      cost: '0.100000',
      unclassified: '0.100000',
      fuel: 'natural_gas',
      gasKnown: true,
    ),
    gasOnly: _allocation(
      'estimated',
      fuel: 'natural_gas',
      gasCost: '0.500000',
      gasKnown: true,
    ),
    unknownGas: _allocation(
      'estimated',
      cost: '0.100000',
      unclassified: '0.100000',
      fuel: 'natural_gas',
      gasCost: '0.500000',
    ),
    meteredGas: _allocation(
      'measured',
      cost: '0.200000',
      useful: '0.150000',
      waste: '0.050000',
      wasteBasis: 'floor',
      fuel: 'natural_gas',
      gasCost: '0.400000',
      gasKnown: true,
    ),
  });

  test('electric device rows are unchanged, with or without fuel', () {
    for (final id in [electric, tagged]) {
      final row = _row(projection, id);
      expect(row.usefulCost, '\$0.33');
      expect(row.wasteCost, '\$0.35');
      expect(row.usageCost, '\$0.68');
    }
  });

  test('G-C1: gas row cost is total cost with no waste', () {
    final row = _row(projection, dryer);
    expect(row.usefulCost, '\$0.60');
    expect(row.usageCost, '\$0.60');
    expect(row.wasteCost, isNull);
  });

  test('G-C10: boiler keeps only its rated standby as Waste', () {
    final row = _row(projection, boiler);
    expect(row.usefulCost, '\$0.55');
    expect(row.wasteCost, '\$0.05');
    expect(row.usageCost, '\$0.60');
  });

  test('gas row without a gas rate shows electric cost only', () {
    final row = _row(projection, noRate);
    expect(row.usefulCost, '\$0.10');
    expect(row.usageCost, '\$0.10');
    expect(row.wasteCost, isNull);
  });

  test('gas row with unknown gas use shows no cost', () {
    final row = _row(projection, unknownGas);
    expect(row.usefulCost, isNull);
    expect(row.usageCost, isNull);
    expect(row.wasteCost, isNull);
  });

  test('metered gas row does not show measured waste', () {
    final row = _row(projection, meteredGas);
    expect(row.wasteCost, isNull);
    expect(row.usageCost, '\$0.60');
  });

  test('gas row with no electric cost shows the gas cost', () {
    final row = _row(projection, gasOnly);
    expect(row.usefulCost, '\$0.50');
    expect(row.usageCost, '\$0.50');
  });

  test('gas row with neither electric nor gas cost shows no values', () {
    final p = _project({dryer: _allocation('estimated', fuel: 'natural_gas')});
    final row = _row(p, dryer);
    expect(row.usefulCost, isNull);
    expect(row.usageCost, isNull);
  });
}
