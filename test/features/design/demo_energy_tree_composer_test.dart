import 'package:energylens_mobile/core/cloud_api/cloud_appliance.dart';
import 'package:energylens_mobile/core/cloud_api/cloud_appliance_list.dart';
import 'package:energylens_mobile/core/cloud_api/cloud_tariff.dart';
import 'package:energylens_mobile/features/design/demo_energy_tree.dart';
import 'package:energylens_mobile/features/design/demo_energy_tree_composer.dart';
import 'package:energylens_mobile/features/design/demo_energy_tree_live_adapter.dart';
import 'package:energylens_mobile/features/design/devices_domain_repository.dart';
import 'package:flutter_test/flutter_test.dart';

const home = '11111111-1111-4111-8111-111111111111';
const otherHome = '22222222-2222-4222-8222-222222222222';
const mappedId = 'aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa';
const distinctId = 'cccccccc-cccc-4ccc-8ccc-cccccccccccc';
const mappedAttachment = 'bbbbbbbb-bbbb-4bbb-8bbb-bbbbbbbbbbbb';
const distinctAttachment = 'dddddddd-dddd-4ddd-8ddd-dddddddddddd';
final reference = DateTime.utc(2026, 10, 7, 12);

final tariff = CloudTariff(
  id: 'tariff-1',
  homeId: home,
  fuel: 'electricity',
  rateUnit: 'kWh',
  currency: 'USD',
  rate: '0.20',
  sourceAsOf: DateTime.utc(2026, 10, 1),
  effectiveFrom: DateTime.utc(2026, 10, 1),
);

DeviceInventoryItem item(
  String id,
  String attachmentId,
  DemoDayPeriod period, {
  double energyWh = 5000,
  double? coveredSeconds,
}) => DeviceInventoryItem(
  appliance: CloudAppliance(
    id: id,
    homeId: home,
    name: id,
    category: 'computer',
    room: null,
    brand: 'Example',
    fullModel: 'Example',
    fuel: 'electricity',
    matchQuality: 'confirmed_exact',
  ),
  activeAttachmentIds: [attachmentId],
  measuredBuckets: [
    DeviceMeasuredBucket(
      bucketStart: period.startUtc,
      computedAt: period.endUtc,
      energyWh: energyWh,
      coveredSeconds: coveredSeconds ?? period.seconds.toDouble(),
      attachmentId: attachmentId,
      ownershipCoversBucket: true,
    ),
  ],
);

DevicesDomainSnapshot snapshot(
  List<DeviceInventoryItem> items, {
  String homeId = home,
  bool hasMore = false,
}) => DevicesDomainSnapshot(
  homeId: homeId,
  items: items,
  hasMoreMeteredPages: hasMore,
  dataMode: CloudApplianceDataMode.household,
  fixtureRevision: null,
  isCurrent: () => true,
);

DemoMonthTree compose({
  DevicesDomainSnapshot? devices,
  List<VerifiedDemoApplianceMapping> mappings = const [],
}) => const DemoEnergyTreeComposer().compose(
  homeId: home,
  timezone: 'America/Chicago',
  referenceUtc: reference,
  snapshot: devices,
  electricityTariffs: [tariff],
  mappings: mappings,
);

void main() {
  final mock = compose();
  final today = mock.day('2026-10-07').period;
  final prior = mock.day('2026-10-06').period;

  test(
    'mixes mapped and distinct real days into derived day and month totals',
    () {
      final result = compose(
        devices: snapshot([
          item(mappedId, mappedAttachment, today),
          item(distinctId, distinctAttachment, prior, energyWh: 2000),
        ]),
        mappings: const [
          VerifiedDemoApplianceMapping(
            homeId: home,
            applianceId: mappedId,
            mockBranchId: 'demo-device-01',
            evidenceId: 'verified-owner-binding',
          ),
        ],
      );
      final mapped = result.day('2026-10-07').devices.first;
      expect(mapped.deviceId, mappedId);
      expect(mapped.origin, DemoValueOrigin.measured);
      expect(mapped.cost.unclassifiedCents, 100);
      expect(mapped.mappedMockBranchId, 'demo-device-01');
      expect(mapped.mappingEvidenceId, 'verified-owner-binding');
      expect(mapped.tariffId, 'tariff-1');
      expect(mapped.sourceId, isNotEmpty);
      final distinctDay = result.day('2026-10-06');
      expect(distinctDay.devices, hasLength(19));
      expect(distinctDay.devices.last.deviceId, distinctId);
      expect(distinctDay.devices.last.cost.unclassifiedCents, 40);
      expect(distinctDay.devices.last.mappedMockBranchId, isNull);
      expect(result.day('2026-10-07').homeCost.totalCents, 981);
      expect(
        distinctDay.homeCost.totalCents,
        mock.day('2026-10-06').homeCost.totalCents + 40,
      );
      expect(result.homeCost.totalCents, mock.homeCost.totalCents - 3 + 40);
      expect(
        result.days
            .map((day) => day.homeCost.totalCents)
            .reduce((a, b) => a + b),
        result.homeCost.totalCents,
      );
    },
  );

  test('rejects a snapshot from another home', () {
    expect(
      () => compose(devices: snapshot(const [], homeId: otherHome)),
      throwsFormatException,
    );
  });

  test('incomplete live evidence retains the mock leaf and totals', () {
    final result = compose(
      devices: snapshot([
        item(mappedId, mappedAttachment, today, coveredSeconds: 3600),
      ]),
      mappings: const [
        VerifiedDemoApplianceMapping(
          homeId: home,
          applianceId: mappedId,
          mockBranchId: 'demo-device-01',
          evidenceId: 'verified-owner-binding',
        ),
      ],
    );
    expect(result.day('2026-10-07').devices.first.origin, DemoValueOrigin.mock);
    expect(result.homeCost.totalCents, mock.homeCost.totalCents);
    expect(
      compose(
        devices: snapshot([
          item(mappedId, mappedAttachment, today),
        ], hasMore: true),
      ).homeCost.totalCents,
      mock.homeCost.totalCents,
    );
  });

  test('duplicate appliance evidence cannot be counted twice', () {
    final duplicate = item(mappedId, mappedAttachment, today);
    final result = compose(devices: snapshot([duplicate, duplicate]));
    expect(result.homeCost.totalCents, mock.homeCost.totalCents);
    expect(result.day('2026-10-07').devices, hasLength(18));
  });
}
