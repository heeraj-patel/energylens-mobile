import 'package:energylens_mobile/core/cloud_api/cloud_appliance.dart';
import 'package:energylens_mobile/core/cloud_api/cloud_appliance_list.dart';
import 'package:energylens_mobile/core/cloud_api/cloud_tariff.dart';
import 'package:energylens_mobile/features/design/demo_energy_tree.dart';
import 'package:energylens_mobile/features/design/demo_energy_tree_live_adapter.dart';
import 'package:energylens_mobile/features/design/devices_domain_repository.dart';
import 'package:flutter_test/flutter_test.dart';

const home = '11111111-1111-4111-8111-111111111111';
const otherHome = '22222222-2222-4222-8222-222222222222';
const applianceId = 'aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa';
const attachmentId = 'bbbbbbbb-bbbb-4bbb-8bbb-bbbbbbbbbbbb';

final period = buildSeptember2026DemoTree(homeId: home)
    .day('2026-09-30')
    .period;

DevicesDomainSnapshot snapshot({
  String homeId = home,
  double coveredSeconds = 86400,
  DateTime? bucketStart,
  bool ownershipCoversBucket = true,
  bool hasMore = false,
  bool sample = false,
}) => DevicesDomainSnapshot(
  homeId: homeId,
  hasMoreMeteredPages: hasMore,
  dataMode: sample
      ? CloudApplianceDataMode.sample
      : CloudApplianceDataMode.household,
  fixtureRevision: sample ? 'fixture-1' : null,
  isCurrent: () => true,
  items: [
    DeviceInventoryItem(
      appliance: const CloudAppliance(
        id: applianceId,
        homeId: home,
        name: 'Desktop',
        category: 'computer',
        room: null,
        brand: 'Example',
        fullModel: 'Desktop',
        fuel: 'electricity',
        matchQuality: 'confirmed_exact',
      ),
      activeAttachmentIds: const [attachmentId],
      measuredBuckets: [
        DeviceMeasuredBucket(
          bucketStart: bucketStart ?? period.startUtc,
          computedAt: DateTime.utc(2026, 10, 1, 6),
          energyWh: 5000,
          coveredSeconds: coveredSeconds,
          attachmentId: attachmentId,
          ownershipCoversBucket: ownershipCoversBucket,
        ),
      ],
    ),
  ],
);

CloudTariff tariff({
  String homeId = home,
  String rate = '0.12345678',
  DateTime? effectiveFrom,
  DateTime? effectiveTo,
}) => CloudTariff(
  id: 'tariff-revision-1',
  homeId: homeId,
  fuel: 'electricity',
  rateUnit: 'kWh',
  currency: 'USD',
  rate: rate,
  sourceAsOf: DateTime.utc(2026, 9, 1),
  effectiveFrom: effectiveFrom ?? DateTime.utc(2026, 9, 1),
  effectiveTo: effectiveTo,
);

const mapping = VerifiedDemoApplianceMapping(
  homeId: home,
  applianceId: applianceId,
  mockBranchId: 'demo-device-01',
  evidenceId: 'owner-verified-mapping-1',
);

List<VerifiedDemoDeviceDay> adapt({
  DevicesDomainSnapshot? devices,
  List<CloudTariff>? tariffs,
  List<VerifiedDemoApplianceMapping> mappings = const [mapping],
}) => const DemoEnergyTreeLiveAdapter().readingsForDay(
  snapshot: devices ?? snapshot(),
  period: period,
  electricityTariffs: tariffs ?? [tariff()],
  mappings: mappings,
);

void main() {
  test('complete mapped real day prices with fractional-cent rate', () {
    final result = adapt().single;
    expect(result.reading.energyWh, 5000);
    expect(result.reading.usefulWh, 0);
    expect(result.reading.wasteWh, 0);
    expect(result.reading.unclassifiedWh, 5000);
    expect(result.reading.tariffRateUnitsPerKwh, 12345678);
    final merged = result.mergeInto(buildSeptember2026DemoTree(homeId: home));
    final day = merged.day('2026-09-30');
    expect(day.devices.first.deviceId, applianceId);
    expect(day.devices.first.cost.unclassifiedCents, 62);
    expect(day.homeCost.totalCents, 943);
  });

  test('rejects partial or displaced day buckets and incomplete paging', () {
    expect(adapt(devices: snapshot(coveredSeconds: 3600)), isEmpty);
    expect(
      adapt(
        devices: snapshot(
          bucketStart: period.startUtc.add(const Duration(hours: 1)),
        ),
      ),
      isEmpty,
    );
    expect(adapt(devices: snapshot(ownershipCoversBucket: false)), isEmpty);
    expect(adapt(devices: snapshot(hasMore: true)), isEmpty);
    expect(adapt(devices: snapshot(sample: true)), isEmpty);
  });

  test(
    'unmapped saved device joins distinctly; ambiguous evidence is withheld',
    () {
      expect(adapt(devices: snapshot(homeId: otherHome)), isEmpty);
      final unmapped = adapt(mappings: const []).single;
      expect(unmapped.mapping, isNull);
      final mergedUnmapped = unmapped.mergeInto(
        buildSeptember2026DemoTree(homeId: home),
      );
      expect(mergedUnmapped.day('2026-09-30').devices, hasLength(19));
      expect(
        mergedUnmapped.day('2026-09-30').devices.last.deviceId,
        applianceId,
      );
      expect(() => unmapped.mergeInto(mergedUnmapped), throwsFormatException);
      expect(adapt(mappings: const [mapping, mapping]), isEmpty);
      expect(adapt(tariffs: [tariff(homeId: otherHome)]), isEmpty);
      expect(adapt(tariffs: [tariff(), tariff()]), isEmpty);
      expect(
        adapt(
          tariffs: [
            tariff(
              effectiveFrom: period.startUtc.add(const Duration(hours: 1)),
            ),
          ],
        ),
        isEmpty,
      );
      expect(
        adapt(
          tariffs: [
            tariff(
              effectiveTo: period.endUtc.subtract(const Duration(seconds: 1)),
            ),
          ],
        ),
        isEmpty,
      );
    },
  );
}
