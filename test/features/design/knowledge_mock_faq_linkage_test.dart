import 'package:energylens_mobile/features/design/demo_energy_projection.dart';
import 'package:energylens_mobile/features/design/demo_energy_tree.dart';
import 'package:energylens_mobile/features/design/knowledge_domain_repository.dart';
import 'package:energylens_mobile/features/design/knowledge_mock_faq_linkage.dart';
import 'package:flutter_test/flutter_test.dart';

const homeId = '123e4567-e89b-12d3-a456-426614174000';
const otherHomeId = '123e4567-e89b-12d3-a456-426614174001';
const day = '2026-10-07';

void main() {
  late DemoEnergyProjection projection;
  late KnowledgeMockFaqLinkage linkage;
  setUp(() {
    final tree = buildDemoMonthTree(
      homeId: homeId,
      year: 2026,
      month: 10,
      timezone: 'America/Chicago',
      referenceDay: 7,
    );
    projection = DemoEnergyProjection.fromTree(
      tree: tree,
      homeId: homeId,
      referenceLocalDate: day,
    );
    linkage = KnowledgeMockFaqLinkage(projection);
  });

  KnowledgeMockFaqFact? lookup(
    KnowledgeMockFaqLinkage linkage,
    String questionId, {
    String selectedHomeId = homeId,
    String localDate = day,
    String? selectedDeviceId,
  }) => linkage.forQuestion(
    questionId: questionId,
    selectedHomeId: selectedHomeId,
    localDate: localDate,
    selectedDeviceId: selectedDeviceId,
  );

  test('links only actual mock home and device costs for one local day', () {
    final result = lookup(linkage, 'home_vs_devices') as KnowledgeMockHomeCosts;
    expect(result.origin, DemoValueOrigin.mock);
    expect(result.homeId, homeId);
    expect(result.period.localDate, day);
    expect(result.period.timezone, 'America/Chicago');
    expect(
      result.home.totalMicros,
      result.devices.totalMicros + result.unattributed.totalMicros,
    );
    expect(result.home.totalMicros, projection.homeDayCost.totalMicros);
    expect(result.unattributed.totalMicros, greaterThan(0));
    expect(
      lookup(linkage, 'useful_waste_meaning'),
      isA<KnowledgeMockHomeCosts>(),
    );
    expect(
      lookup(linkage, 'unknown_cost_meaning'),
      isA<KnowledgeMockHomeCosts>(),
    );
  });

  test(
    'links device names and a selected mock leaf without inventing values',
    () {
      final inventory =
          lookup(linkage, 'device_inventory') as KnowledgeMockDeviceList;
      expect(inventory.devices.length, projection.deviceDayLeaves.length);
      expect(inventory.devices.first.name, 'Study Desktop & Rig');
      expect(
        inventory.devices.every(
          (device) => device.origin == DemoValueOrigin.mock,
        ),
        isTrue,
      );
      expect(() => inventory.devices.clear(), throwsUnsupportedError);

      final first = projection.deviceDayLeaves.first;
      final cost = lookup(
        linkage,
        'device_cost',
        selectedDeviceId: first.deviceId,
      ) as KnowledgeMockDeviceCost;
      expect(cost.device.deviceId, first.deviceId);
      expect(cost.device.cost.totalMicros, first.cost.totalMicros);
      expect(cost.device.energyWh, isNull);
      expect(lookup(linkage, 'device_cost'), isNull);
      expect(
        lookup(linkage, 'device_cost', selectedDeviceId: 'missing'),
        isNull,
      );
    },
  );

  test(
    'home switch, local period mismatch, and wrong device scope return no fact',
    () {
      expect(
        lookup(linkage, 'home_vs_devices', selectedHomeId: otherHomeId),
        isNull,
      );
      expect(
        lookup(linkage, 'device_inventory', localDate: '2026-10-08'),
        isNull,
      );
      expect(
        lookup(
          linkage,
          'device_cost',
          selectedDeviceId: 'demo-device-01',
          selectedHomeId: otherHomeId,
        ),
        isNull,
      );
      expect(
        lookup(linkage, 'home_vs_devices', selectedDeviceId: 'demo-device-01'),
        isNull,
      );
      expect(
        lookup(linkage, 'device_inventory', selectedDeviceId: 'demo-device-01'),
        isNull,
      );
    },
  );

  test('unsupported claims cannot be made from mock costs', () {
    for (final id in [
      'home_top_use',
      'high_use',
      'reduce_waste',
      'week_change',
      'away_use',
      'idle_devices',
      'ac_afternoon',
      'standby_cost',
      'fridge_use',
      'laundry_now',
      'peak_hours',
      'shift_cycle',
    ]) {
      expect(lookup(linkage, id), isNull, reason: id);
    }
  });

  test('unknown measured values never acquire mock FAQ provenance', () {
    final reference = projection.referenceDay;
    final reading = RealDeviceDay(
      homeId: homeId,
      deviceId: '123e4567-e89b-12d3-a456-426614174002',
      period: reference.period,
      coveredSeconds: reference.period.seconds,
      usefulWh: 0,
      wasteWh: 0,
      unclassifiedWh: 1000,
      tariffRateUnitsPerKwh: 20000000,
      tariffId: 'tariff-1',
      meterEvidenceId: 'meter-1',
    );
    final mixed = projection.tree.mergeMeasured(reading);
    final mixedLinkage = KnowledgeMockFaqLinkage(
      DemoEnergyProjection.fromTree(
        tree: mixed,
        homeId: homeId,
        referenceLocalDate: day,
      ),
    );
    expect(lookup(mixedLinkage, 'home_vs_devices'), isNull);
    expect(lookup(mixedLinkage, 'unknown_cost_meaning'), isNull);
    expect(
      lookup(mixedLinkage, 'device_cost', selectedDeviceId: reading.deviceId),
      isNull,
    );
    final inventory =
        lookup(mixedLinkage, 'device_inventory') as KnowledgeMockDeviceList;
    expect(
      inventory.devices.any((device) => device.deviceId == reading.deviceId),
      isFalse,
    );
  });

  test('verified replacement removes only its mapped mock FAQ device', () {
    final original = projection.deviceDayLeaves.first;
    final reference = projection.referenceDay;
    final reading = RealDeviceDay(
      homeId: homeId,
      deviceId: '123e4567-e89b-12d3-a456-426614174002',
      period: reference.period,
      coveredSeconds: reference.period.seconds,
      usefulWh: 0,
      wasteWh: 0,
      unclassifiedWh: 1000,
      tariffRateUnitsPerKwh: 20000000,
      tariffId: 'tariff-1',
      meterEvidenceId: 'meter-1',
    );
    final mapped = projection.tree.mergeMeasured(
      reading,
      verifiedMockBranchId: original.deviceId,
      mappingEvidenceId: 'mapping-1',
    );
    final mappedLinkage = KnowledgeMockFaqLinkage(
      DemoEnergyProjection.fromTree(
        tree: mapped,
        homeId: homeId,
        referenceLocalDate: day,
      ),
    );

    expect(lookup(mappedLinkage, 'home_vs_devices'), isNull);
    expect(
      lookup(mappedLinkage, 'device_cost', selectedDeviceId: original.deviceId),
      isNull,
    );
    expect(
      lookup(mappedLinkage, 'device_cost', selectedDeviceId: reading.deviceId),
      isNull,
    );
    final inventory =
        lookup(mappedLinkage, 'device_inventory') as KnowledgeMockDeviceList;
    expect(inventory.devices, hasLength(projection.deviceDayLeaves.length - 1));
    expect(
      inventory.devices.any((device) => device.deviceId == original.deviceId),
      isFalse,
    );
    expect(
      inventory.devices.any((device) => device.deviceId == reading.deviceId),
      isFalse,
    );
  });

  test('nonvisual link does not publish draft or local-pilot answers', () {
    expect(lookup(linkage, 'device_inventory'), isA<KnowledgeMockDeviceList>());
    final catalog = KnowledgeDomainRepository.bundledCatalog;
    expect(catalog.find('device_inventory'), isNull);
    expect(catalog.find('standby_cost'), isNull);
    expect(catalog.find('standby_cost', localPilot: true), isNotNull);
  });
}
