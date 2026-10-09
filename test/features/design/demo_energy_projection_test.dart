import 'package:energylens_mobile/features/design/demo_energy_projection.dart';

import '../../support/demo_energy_tree_fixtures.dart';

import 'package:energylens_mobile/features/design/demo_energy_tree.dart';
import 'package:flutter_test/flutter_test.dart';

const _homeId = '11111111-1111-4111-8111-111111111111';
const _mappedId = 'aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa';
const _distinctId = 'bbbbbbbb-bbbb-4bbb-8bbb-bbbbbbbbbbbb';

void main() {
  test('mock day parents equal device leaves plus unattributed load', () {
    final tree = buildDemoMonthTree(
      homeId: _homeId,
      year: 2026,
      month: 10,
      timezone: 'America/Chicago',
      referenceDay: 7,
    );
    final projection = DemoEnergyProjection.fromTree(
      tree: tree,
      homeId: _homeId,
      referenceLocalDate: '2026-10-07',
    );

    expect(projection.deviceDayLeaves, hasLength(18));
    expect(projection.devicesDayCost.usefulCents, 683);
    expect(projection.devicesDayCost.wasteCents, 196);
    expect(projection.unattributedDayCost.usefulCents, 13);
    expect(projection.unattributedDayCost.wasteCents, 92);
    expect(projection.homeDayCost.usefulCents, 696);
    expect(projection.homeDayCost.wasteCents, 288);
    expect(projection.monthToDateCost.totalCents, 3742);
    expect(projection.hasUnclassifiedMonthToDateCost, isFalse);
    expect(
      projection.deviceDayLeaves
          .fold(DemoCost.zero, (sum, leaf) => sum + leaf.cost)
          .totalMicros,
      projection.devicesDayCost.totalMicros,
    );
    expect(
      projection.devicesDayCost.totalMicros +
          projection.unattributedDayCost.totalMicros,
      projection.homeDayCost.totalMicros,
    );
    final mondayThroughReference = projection.costForLocalDateRange(
      startLocalDate: '2026-10-05',
      endExclusiveLocalDate: '2026-10-08',
    );
    expect(mondayThroughReference.source.usefulCents, 1496);
    expect(mondayThroughReference.source.wasteCents, 422);
    expect(mondayThroughReference.source.totalCents, 1918);
    expect(
      mondayThroughReference.presentation.totalMicros,
      mondayThroughReference.source.totalMicros,
    );
    final monthThroughReference = projection.costForLocalDateRange(
      startLocalDate: '2026-10-01',
      endExclusiveLocalDate: '2026-10-08',
    );
    expect(monthThroughReference.source.usefulCents, 3096);
    expect(monthThroughReference.source.wasteCents, 646);
    expect(monthThroughReference.source.totalCents, 3742);
    expect(
      () => projection.costForLocalDateRange(
        startLocalDate: '2026-10-05',
        endExclusiveLocalDate: '2026-10-09',
      ),
      throwsFormatException,
    );
    expect(
      () => projection.costForLocalDateRange(
        startLocalDate: '2026-09-30',
        endExclusiveLocalDate: '2026-10-08',
      ),
      throwsFormatException,
    );
  });

  test(
    'mapped and distinct real leaves reconcile without classifying unknown',
    () {
      final mock = buildSeptember2026DemoTree(homeId: _homeId);
      final period = mock.day('2026-09-30').period;
      final mapped = mock.mergeMeasured(
        RealDeviceDay(
          homeId: _homeId,
          deviceId: _mappedId,
          period: period,
          coveredSeconds: period.seconds,
          usefulWh: 1000,
          wasteWh: 500,
          unclassifiedWh: 0,
          tariffRateUnitsPerKwh: 20000000,
          tariffId: 'tariff-1',
          meterEvidenceId: 'meter-mapped',
          classificationEvidenceId: 'classified-mapped',
        ),
        verifiedMockBranchId: 'demo-device-01',
        mappingEvidenceId: 'reviewed-map',
      );
      final mixed = mapped.mergeMeasured(
        RealDeviceDay(
          homeId: _homeId,
          deviceId: _distinctId,
          period: period,
          coveredSeconds: period.seconds,
          usefulWh: 0,
          wasteWh: 0,
          unclassifiedWh: 2000,
          tariffRateUnitsPerKwh: 20000000,
          tariffId: 'tariff-1',
          meterEvidenceId: 'meter-distinct',
        ),
      );
      final projection = DemoEnergyProjection.fromTree(
        tree: mixed,
        homeId: _homeId,
        referenceLocalDate: '2026-09-30',
      );

      expect(projection.deviceDayLeaves, hasLength(19));
      expect(projection.deviceDayLeaves.first.deviceId, _mappedId);
      expect(projection.deviceDayLeaves.last.deviceId, _distinctId);
      expect(projection.devicesDayCost.usefulCents, 635);
      expect(projection.devicesDayCost.wasteCents, 171);
      expect(projection.devicesDayCost.unclassifiedCents, 40);
      expect(projection.homeDayCost.usefulCents, 648);
      expect(projection.homeDayCost.wasteCents, 263);
      expect(projection.homeDayCost.unclassifiedCents, 40);
      expect(projection.homeDayCost.totalCents, 951);
      expect(projection.monthToDateCost.totalCents, 14197);
      expect(projection.hasUnclassifiedMonthToDateCost, isTrue);
      final range = projection.costForLocalDateRange(
        startLocalDate: '2026-09-30',
        endExclusiveLocalDate: '2026-10-01',
      );
      expect(range.source.unclassifiedCents, 40);
      expect(range.presentation.unclassifiedCents, 40);
      expect(
        projection.devicesDayCost.totalMicros +
            projection.unattributedDayCost.totalMicros,
        projection.homeDayCost.totalMicros,
      );
    },
  );

  test('rejects incomplete months and another home', () {
    final tree = buildSeptember2026DemoTree(homeId: _homeId);
    expect(
      () => DemoEnergyProjection.fromTree(
        tree: tree,
        homeId: '22222222-2222-4222-8222-222222222222',
        referenceLocalDate: '2026-09-30',
      ),
      throwsFormatException,
    );
    final incomplete = DemoMonthTree(
      homeId: _homeId,
      referenceLocalDate: tree.referenceLocalDate,
      days: tree.days.take(28).toList()..add(tree.days.last),
    );
    expect(
      () => DemoEnergyProjection.fromTree(
        tree: incomplete,
        homeId: _homeId,
        referenceLocalDate: '2026-09-30',
      ),
      throwsFormatException,
    );
    final shiftedDays = tree.days.map((day) {
      final shifted = DemoDayPeriod(
        localDate: day.period.localDate,
        timezone: day.period.timezone,
        startUtc: day.period.startUtc.add(const Duration(hours: 1)),
        endUtc: day.period.endUtc.add(const Duration(hours: 1)),
      );
      return DemoDayTree(
        homeId: day.homeId,
        period: shifted,
        devices: [
          for (final leaf in day.devices)
            DemoBranch(
              deviceId: leaf.deviceId,
              name: leaf.name,
              period: shifted,
              cost: leaf.cost,
              origin: leaf.origin,
              sourceId: leaf.sourceId,
            ),
        ],
        unattributed: DemoBranch(
          deviceId: day.unattributed.deviceId,
          period: shifted,
          cost: day.unattributed.cost,
          origin: day.unattributed.origin,
          sourceId: day.unattributed.sourceId,
        ),
      );
    }).toList();
    final shifted = DemoMonthTree(
      homeId: _homeId,
      referenceLocalDate: tree.referenceLocalDate,
      days: shiftedDays,
    );
    expect(
      () => DemoEnergyProjection.fromTree(
        tree: shifted,
        homeId: _homeId,
        referenceLocalDate: tree.referenceLocalDate,
      ),
      throwsFormatException,
    );
  });

  test(
    'mapped unclassified measured cost uses mock proportions only for display',
    () {
      final mock = buildSeptember2026DemoTree(homeId: _homeId);
      final period = mock.day('2026-09-30').period;
      final original = mock.day('2026-09-30').devices.first;
      final mapped = mock.mergeMeasured(
        RealDeviceDay(
          homeId: _homeId,
          deviceId: _mappedId,
          period: period,
          coveredSeconds: period.seconds,
          usefulWh: 0,
          wasteWh: 0,
          unclassifiedWh: 2000,
          tariffRateUnitsPerKwh: 20000000,
          tariffId: 'tariff-1',
          meterEvidenceId: 'meter-mapped',
        ),
        verifiedMockBranchId: original.deviceId,
        mappingEvidenceId: 'reviewed-map',
      );
      final projection = DemoEnergyProjection.fromTree(
        tree: mapped,
        homeId: _homeId,
        referenceLocalDate: '2026-09-30',
      );
      final leaf = projection.deviceDayLeaves.first;
      final expectedUseful =
          (leaf.cost.totalMicros * original.cost.usefulMicros +
              (original.cost.usefulMicros + original.cost.wasteMicros) ~/ 2) ~/
          (original.cost.usefulMicros + original.cost.wasteMicros);

      expect(leaf.cost.unclassifiedCents, 40);
      expect(leaf.cost.usefulMicros, 0);
      expect(leaf.cost.wasteMicros, 0);
      expect(leaf.illustrativePresentationCost, isNotNull);
      expect(leaf.presentationCost.usefulMicros, expectedUseful);
      expect(
        leaf.presentationCost.wasteMicros,
        leaf.cost.totalMicros - expectedUseful,
      );
      expect(leaf.presentationCost.totalMicros, leaf.cost.totalMicros);
      expect(
        projection.homeDayCost.totalMicros,
        projection.presentedHomeDayCost.totalMicros,
      );
      expect(projection.presentedHomeDayCost.unclassifiedMicros, 0);
      expect(projection.hasUnknownPresentedDayCost, isFalse);

      final distinct = mapped.mergeMeasured(
        RealDeviceDay(
          homeId: _homeId,
          deviceId: _distinctId,
          period: period,
          coveredSeconds: period.seconds,
          usefulWh: 0,
          wasteWh: 0,
          unclassifiedWh: 1000,
          tariffRateUnitsPerKwh: 20000000,
          tariffId: 'tariff-1',
          meterEvidenceId: 'meter-distinct',
        ),
      );
      final mixed = DemoEnergyProjection.fromTree(
        tree: distinct,
        homeId: _homeId,
        referenceLocalDate: '2026-09-30',
      );
      expect(mixed.deviceDayLeaves.last.illustrativePresentationCost, isNull);
      expect(mixed.presentedHomeDayCost.unclassifiedCents, 20);
      expect(mixed.hasUnknownPresentedDayCost, isTrue);
      expect(
        mixed.homeDayCost.totalMicros,
        mixed.presentedHomeDayCost.totalMicros,
      );
    },
  );
}
