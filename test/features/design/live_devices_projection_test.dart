import 'package:energylens_mobile/core/cloud_api/cloud_appliance.dart';
import 'package:energylens_mobile/core/cloud_api/cloud_appliance_list.dart';
import 'package:energylens_mobile/core/cloud_api/cloud_device_states.dart';
import 'package:energylens_mobile/core/cloud_api/cloud_household_energy.dart';
import 'package:energylens_mobile/features/design/design_context_coordinator.dart';
import 'package:energylens_mobile/features/design/devices_domain_repository.dart';
import 'package:energylens_mobile/features/design/live_devices_projection.dart';
import 'package:flutter_test/flutter_test.dart';

const homeA = '11111111-1111-4111-8111-111111111111';
const homeB = '22222222-2222-4222-8222-222222222222';

DeviceInventoryItem item(
  String id,
  String name, {
  String home = homeA,
  List<DeviceMeasuredBucket> buckets = const [],
  String category = 'other',
  String? demoDeviceId,
  bool hasEnergyMonitoring = false,
}) => DeviceInventoryItem(
  appliance: CloudAppliance(
    id: id,
    homeId: home,
    name: name,
    category: category,
    room: null,
    brand: 'Brand',
    fullModel: 'Model',
    fuel: 'electric',
    matchQuality: 'confirmed_exact',
    demoDeviceId: demoDeviceId,
  ),
  activeAttachmentIds: const [],
  measuredBuckets: buckets,
  hasEnergyMonitoring: hasEnergyMonitoring,
);

DesignContextRead read({
  String home = homeA,
  DesignContextMode mode = DesignContextMode.household,
  List<DeviceInventoryItem>? items,
  bool Function()? isCurrent,
  bool hasMore = false,
  CloudHouseholdEnergyTrends? costs,
  CloudApplianceDataMode? dataMode,
  CloudDeviceStates? states,
  DateTime? statesRequestStartedAt,
}) => DesignContextRead(
  accountId: 'account',
  homeId: home,
  mode: mode,
  page: 'devices',
  value: DevicesDomainSnapshot(
    homeId: homeA,
    items: items ?? const [],
    hasMoreMeteredPages: hasMore,
    dataMode:
        dataMode ??
        (mode == DesignContextMode.sample
            ? CloudApplianceDataMode.sample
            : CloudApplianceDataMode.household),
    fixtureRevision:
        mode == DesignContextMode.sample ||
            dataMode == CloudApplianceDataMode.mixed
        ? 'fixture_v1'
        : null,
    sampleDayCosts: costs,
    deviceStates: states,
    deviceStatesRequestStartedAt: statesRequestStartedAt,
    isCurrent: isCurrent ?? () => true,
  ),
);

void main() {
  final day = DateTime.utc(2026, 10, 6);
  final bucket = DeviceMeasuredBucket(
    bucketStart: day,
    computedAt: day.add(const Duration(hours: 4)),
    energyWh: 1250,
    coveredSeconds: 3600,
    attachmentId: 'attachment',
  );

  test(
    'monitor attachment, rather than telemetry or history, selects status',
    () {
      final now = DateTime.now().toUtc();
      CloudDeviceStates states(List<CloudDeviceState> entries) =>
          CloudDeviceStates(homeId: homeA, asOf: now, states: entries);
      CloudDeviceState live(String id, String state, Duration age) =>
          CloudDeviceState(
            applianceId: id,
            state: state,
            observedAt: now.subtract(age),
            watts: state == 'active' ? 20 : 0,
          );
      final projected = prepareLiveDevicesProjection(
        read(
          items: [
            item('a', 'Former meter', buckets: [bucket]),
            item('b', 'Meter active', hasEnergyMonitoring: true),
            item('c', 'Meter idle', hasEnergyMonitoring: true),
            item('d', 'Meter stale', hasEnergyMonitoring: true),
            item('e', 'Meter missing', hasEnergyMonitoring: true),
            item('f', 'Meter offline', hasEnergyMonitoring: true),
            item('g', 'Unmonitored with raw active state'),
          ],
          states: states([
            live('b', 'active', const Duration(minutes: 1)),
            live('c', 'idle', const Duration(minutes: 1)),
            live('d', 'active', const Duration(minutes: 16)),
            const CloudDeviceState(applianceId: 'f', state: 'offline'),
            live('g', 'active', const Duration(minutes: 1)),
          ]),
          statesRequestStartedAt: now,
        ),
      );
      expect(projected.rows.map((row) => row.state), [
        'standalone',
        'active',
        'idle',
        'offline',
        'offline',
        'offline',
        'standalone',
      ]);
      expect(projected.rows.first.measuredBucket?.energyWh, 1250);
      expect(projected.rows.first.stateExpiresAt, isNull);
      expect(projected.rows.last.stateExpiresAt, isNull);
      expect(projected.rows[1].stateExpiresAt, isNotNull);
      expect(projected.rows[2].stateExpiresAt, isNotNull);
      expect(
        prepareLiveDevicesProjection(
          read(
            items: [
              item('b', 'Meter missing state read', hasEnergyMonitoring: true),
            ],
          ),
        ).rows.single.state,
        'offline',
      );
    },
  );

  test('real card values use only supported appliance split for today', () {
    const applianceA = 'aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa';
    const applianceB = 'bbbbbbbb-bbbb-4bbb-8bbb-bbbbbbbbbbbb';
    const applianceC = 'cccccccc-cccc-4ccc-8ccc-cccccccccccc';
    Map<String, Object?> money(String value) => {
      'amount': value,
      'currency': 'USD',
    };
    Map<String, Object?> allocation({
      String? cost,
      String? useful,
      String? waste,
    }) => {
      'energy': null,
      'cost': cost == null ? null : money(cost),
      'useful_energy': null,
      'useful_cost': useful == null ? null : money(useful),
      'waste_energy': null,
      'waste_cost': waste == null ? null : money(waste),
      'unclassified_energy': null,
      'unclassified_cost': null,
      'availability': 'partial',
      'evidence_basis': 'mixed',
    };
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
      'totals': allocation(),
      'buckets': [
        {
          'start_local': '2026-10-06T00:00:00-05:00',
          'end_exclusive_local': '2026-10-07T00:00:00-05:00',
          'allocation': allocation(),
          'coverage_fraction': null,
          'device_allocations': [
            {
              'appliance_id': applianceA,
              'allocation': allocation(
                cost: '1.239000',
                useful: '0.985000',
                waste: '0.254000',
              ),
            },
            {
              'appliance_id': applianceB,
              'allocation': allocation(
                cost: '0.500000',
                useful: '0.500000',
                waste: '0.000000',
              ),
            },
            {
              'appliance_id': applianceC,
              'allocation': allocation(
                cost: '1.000000',
                useful: '0.800000',
                waste: '0.800000',
              ),
            },
          ],
        },
      ],
    }, expectedHomeId: homeA);
    final projection = prepareLiveDevicesProjection(
      read(
        items: [
          item(applianceA, 'A'),
          item(applianceB, 'B', category: 'lighting'),
          item(applianceC, 'C'),
        ],
        costs: costs,
      ),
    );
    expect(projection.rows[0].usefulCost, '\$0.99');
    expect(projection.rows[0].wasteCost, '\$0.25');
    expect(projection.rows[1].usefulCost, '\$0.50');
    expect(projection.rows[1].wasteCost, '\$0.00');
    expect(projection.rows[2].usefulCost, isNull);
    expect(projection.rows[2].wasteCost, isNull);
  });

  test('estimated non-metered cost shows while measured stays unchanged', () {
    const measured = 'aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa';
    const estimated = 'bbbbbbbb-bbbb-4bbb-8bbb-bbbbbbbbbbbb';
    const zero = 'cccccccc-cccc-4ccc-8ccc-cccccccccccc';
    const standby = 'dddddddd-dddd-4ddd-8ddd-dddddddddddd';
    Map<String, Object?> money(String value) => {
      'amount': value,
      'currency': 'USD',
    };
    Map<String, Object?> allocation(
      String basis, {
      String? cost,
      String? useful,
      String? waste,
    }) => {
      'energy': null,
      'cost': cost == null ? null : money(cost),
      'useful_energy': null,
      'useful_cost': useful == null ? null : money(useful),
      'waste_energy': null,
      'waste_cost': waste == null ? null : money(waste),
      'unclassified_energy': null,
      'unclassified_cost': null,
      'availability': 'partial',
      'evidence_basis': basis,
    };
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
      'totals': allocation('mixed'),
      'buckets': [
        {
          'start_local': '2026-10-06T00:00:00-05:00',
          'end_exclusive_local': '2026-10-07T00:00:00-05:00',
          'allocation': allocation('mixed'),
          'coverage_fraction': null,
          'device_allocations': [
            {
              'appliance_id': measured,
              'allocation': allocation(
                'measured',
                cost: '1.239000',
                useful: '0.985000',
                waste: '0.254000',
              ),
            },
            {
              'appliance_id': estimated,
              'allocation': allocation(
                'estimated',
                cost: '0.420000',
                useful: '0.420000',
                waste: '0.000000',
              ),
            },
            {
              'appliance_id': standby,
              'allocation': allocation(
                'estimated',
                cost: '0.300000',
                useful: '0.180000',
                waste: '0.120000',
              ),
            },
            {
              'appliance_id': zero,
              'allocation': allocation('mixed', cost: '0.000000'),
            },
          ],
        },
      ],
    }, expectedHomeId: homeA);
    final projection = prepareLiveDevicesProjection(
      read(
        items: [
          item(measured, 'KS8'),
          item(estimated, 'Dyson'),
          item(zero, 'Fan'),
          item(standby, 'Purifier'),
        ],
        costs: costs,
      ),
    );
    expect(projection.rows[2].usageCost, '\$0.00');
    final renamed = prepareLiveDevicesProjection(
      read(
        items: [item(measured, 'Dyson fan plug'), item(estimated, 'Dyson')],
        costs: costs,
      ),
    );
    expect(renamed.rows[0].name, 'Dyson fan plug');
    expect(renamed.rows[0].usefulCost, '\$0.99');
    expect(renamed.rows[0].usageCost, '\$1.24');
    expect(projection.rows[0].usefulCost, '\$0.99');
    expect(projection.rows[0].wasteCost, '\$0.25');
    expect(projection.rows[1].usageCost, '\$0.42');
    expect(projection.rows[1].usefulCost, '\$0.42');
    expect(projection.rows[1].wasteCost, '\$0.00');
    expect(projection.rows[3].usageCost, '\$0.30');
    expect(projection.rows[3].usefulCost, '\$0.18');
    expect(projection.rows[3].wasteCost, '\$0.12');
  });

  test('mixed live projection leaves seeded demo cards to their bindings', () {
    final projection = prepareLiveDevicesProjection(
      read(
        dataMode: CloudApplianceDataMode.mixed,
        items: [
          item('a', 'Demo TV', demoDeviceId: 'demo-device-01'),
          item('b', 'Real TV', category: 'tv'),
        ],
      ),
    );
    expect(projection.rows.map((row) => row.name), ['Real TV']);
  });

  test(
    'projects stable identity and one observed bucket without inference',
    () {
      final older = DeviceMeasuredBucket(
        bucketStart: day.subtract(const Duration(days: 1)),
        computedAt: day,
        energyWh: 900,
        coveredSeconds: 1800,
        attachmentId: 'attachment',
      );
      final projection = prepareLiveDevicesProjection(
        read(
          items: [
            item('b', 'Washer'),
            item('a', 'Refrigerator', buckets: [older, bucket]),
          ],
          hasMore: true,
        ),
      );
      expect(projection.homeId, homeA);
      expect(projection.mode, DesignContextMode.household);
      expect(projection.fixtureRevision, isNull);
      expect(projection.hasMoreMeteredPages, isTrue);
      expect(projection.rows.map((row) => row.applianceId), ['a', 'b']);
      expect(projection.rows.map((row) => row.name), [
        'Refrigerator',
        'Washer',
      ]);
      expect(projection.rows.first.measuredBucket!.energyWh, 1250);
      expect(projection.rows.first.measuredBucket!.bucketStart, day);
      expect(projection.rows.first.measuredBucket!.coveredSeconds, 3600);
      expect(projection.rows.last.measuredBucket, isNull);
      expect(projection.rows.first.manufacturer, 'Brand');
      expect(projection.rows.first.model, 'Model');
      expect(() => projection.rows.clear(), throwsUnsupportedError);
    },
  );

  test('final KB miss does not allocate app-side waste', () {
    final projection = prepareLiveDevicesProjection(
      read(
        items: [
          item('a', 'Television', category: 'tv'),
          item('b', 'Lamp', category: 'light'),
          item('c', 'Fridge', category: 'refrigerator'),
          item('d', 'Unknown', category: 'other'),
          item('e', 'Pending', category: 'tv'),
          item('f', 'Metered TV', category: 'tv', buckets: [bucket]),
        ],
      ),
    );
    expect(projection.rows.every((row) => row.wasteCost == null), isTrue);
    final sample = prepareLiveDevicesProjection(
      read(
        mode: DesignContextMode.sample,
        items: [item('a', 'Television', category: 'tv')],
      ),
    );
    expect(sample.rows.single.wasteCost, isNull);
  });

  test('sample provenance has inventory but no household measurement', () {
    final projection = prepareLiveDevicesProjection(
      read(mode: DesignContextMode.sample, items: [item('a', 'Sample fridge')]),
    );
    expect(projection.mode, DesignContextMode.sample);
    expect(projection.fixtureRevision, 'fixture_v1');
    expect(projection.rows.single.measuredBucket, isNull);
    expect(
      () => prepareLiveDevicesProjection(
        read(
          mode: DesignContextMode.sample,
          items: [
            item('a', 'Sample fridge', buckets: [bucket]),
          ],
        ),
      ),
      throwsFormatException,
    );
  });

  test('rejects stale and cross-home reads, including row ownership', () {
    expect(
      () => prepareLiveDevicesProjection(read(home: homeB)),
      throwsFormatException,
    );
    expect(
      () => prepareLiveDevicesProjection(
        read(items: [item('a', 'Other', home: homeB)]),
      ),
      throwsFormatException,
    );
    expect(
      () => prepareLiveDevicesProjection(read(isCurrent: () => false)),
      throwsFormatException,
    );
    var calls = 0;
    expect(
      () => prepareLiveDevicesProjection(read(isCurrent: () => ++calls == 1)),
      throwsFormatException,
    );
  });

  test('rejects duplicate identities, invalid bucket, and oversized rows', () {
    expect(
      () => prepareLiveDevicesProjection(
        read(items: [item('a', 'One'), item('a', 'Two')]),
      ),
      throwsFormatException,
    );
    expect(
      () => prepareLiveDevicesProjection(
        read(
          items: [
            item(
              'a',
              'One',
              buckets: [
                DeviceMeasuredBucket(
                  bucketStart: day,
                  computedAt: day,
                  energyWh: double.nan,
                  coveredSeconds: 3600,
                  attachmentId: 'attachment',
                ),
              ],
            ),
          ],
        ),
      ),
      throwsFormatException,
    );
    expect(
      () => prepareLiveDevicesProjection(
        read(
          items: List.generate(
            DevicesDomainSnapshot.maxLocalInventory + 1,
            (index) => item('id_$index', 'Device $index'),
          ),
        ),
      ),
      throwsFormatException,
    );
  });
}
