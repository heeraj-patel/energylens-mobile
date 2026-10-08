import 'package:energylens_mobile/core/cloud_api/cloud_appliance.dart';
import 'package:energylens_mobile/core/cloud_api/cloud_appliance_list.dart';
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
  CloudKbWasteResult? kbWasteResult,
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
    kbWasteResult: kbWasteResult,
  ),
  activeAttachmentIds: const [],
  measuredBuckets: buckets,
);

DesignContextRead read({
  String home = homeA,
  DesignContextMode mode = DesignContextMode.household,
  List<DeviceInventoryItem>? items,
  bool Function()? isCurrent,
  bool hasMore = false,
}) => DesignContextRead(
  accountId: 'account',
  homeId: home,
  mode: mode,
  page: 'devices',
  value: DevicesDomainSnapshot(
    homeId: homeA,
    items: items ?? const [],
    hasMoreMeteredPages: hasMore,
    dataMode: mode == DesignContextMode.sample
        ? CloudApplianceDataMode.sample
        : CloudApplianceDataMode.household,
    fixtureRevision: mode == DesignContextMode.sample ? 'fixture_v1' : null,
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
      expect(projection.rows.first.demoWasteMicrosPerDay, isNull);
      expect(() => projection.rows.clear(), throwsUnsupportedError);
    },
  );

  test('final KB miss alone permits eligible illustrative daily rate', () {
    const finalMiss = CloudKbWasteResult(
      id: 'kb-final',
      status: 'waste_evidence_unavailable_after_kb',
    );
    final projection = prepareLiveDevicesProjection(
      read(
        items: [
          item('a', 'Television', category: 'tv', kbWasteResult: finalMiss),
          item('b', 'Lamp', category: 'light', kbWasteResult: finalMiss),
          item(
            'c',
            'Fridge',
            category: 'refrigerator',
            kbWasteResult: finalMiss,
          ),
          item('d', 'Unknown', category: 'other', kbWasteResult: finalMiss),
          item('e', 'Pending', category: 'tv'),
          item(
            'f',
            'Metered TV',
            category: 'tv',
            kbWasteResult: finalMiss,
            buckets: [bucket],
          ),
        ],
      ),
    );
    expect(projection.rows.map((row) => row.demoWasteMicrosPerDay), [
      80000,
      800,
      null,
      null,
      null,
      null,
    ]);
    final sample = prepareLiveDevicesProjection(
      read(
        mode: DesignContextMode.sample,
        items: [
          item('a', 'Television', category: 'tv', kbWasteResult: finalMiss),
        ],
      ),
    );
    expect(sample.rows.single.demoWasteMicrosPerDay, isNull);
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
