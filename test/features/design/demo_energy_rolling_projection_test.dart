import 'package:energylens_mobile/features/design/demo_energy_rolling_projection.dart';

import '../../support/demo_energy_tree_fixtures.dart';

import 'package:energylens_mobile/features/design/demo_energy_bindings.dart';
import 'package:energylens_mobile/features/design/demo_energy_tree.dart';
import 'package:flutter_test/flutter_test.dart';

const _home = '11111111-1111-4111-8111-111111111111';
const _otherHome = '22222222-2222-4222-8222-222222222222';

DemoMonthTree _october({int referenceDay = 7, String homeId = _home}) =>
    buildDemoMonthTree(
      homeId: homeId,
      year: 2026,
      month: 10,
      timezone: 'America/Chicago',
      referenceDay: referenceDay,
    );

void main() {
  test('total rounds once after summing sub-cent allocations', () {
    const cost = DemoCost.fromMicros(
      usefulMicros: 4000,
      wasteMicros: 4000,
      unclassifiedMicros: 0,
    );
    expect(cost.usefulCents, 0);
    expect(cost.wasteCents, 0);
    expect(cost.totalCents, 1);

    const other = DemoCost.fromMicros(
      usefulMicros: 6000,
      wasteMicros: 6000,
      unclassifiedMicros: 0,
    );
    expect(other.usefulCents + other.wasteCents, 2);
    expect(other.totalCents, 1);
    expect((cost + other).totalCents, 2);
  });

  test('last 7 local days use complete October leaves', () {
    final window = DemoRollingCostWindow.fromTrees(
      trees: [_october()],
      homeId: _home,
      referenceLocalDate: '2026-10-07',
      dayCount: 7,
    );
    expect(window.startLocalDate, '2026-10-01');
    expect(window.endExclusiveLocalDate, '2026-10-08');
    expect(window.timezone, 'America/Chicago');
    expect(window.source.usefulCents, 3096);
    expect(window.source.wasteCents, 646);
    expect(window.source.totalCents, 3742);
    expect(window.presentation.totalMicros, window.source.totalMicros);
    expect(window.hasUnknownSourceCost, isFalse);
  });

  test('approved Efficiency label and value use the complete last 30 days', () {
    final trees = [buildSeptember2026DemoTree(homeId: _home), _october()];
    final window = DemoRollingCostWindow.fromTrees(
      trees: trees,
      homeId: _home,
      referenceLocalDate: '2026-10-07',
      dayCount: 30,
    );
    final bindings = DemoEnergyBindings.forRollingEfficiency(
      trees: trees,
      homeId: _home,
      referenceLocalDate: '2026-10-07',
    );
    expect(bindings.bindings.map((row) => row.id), [
      'efficiency_text_008',
      'efficiency_text_009',
    ]);
    expect(bindings.bindings.map((row) => row.text), [
      'Last 30 days',
      '\$147.80',
    ]);
    expect(window.presentation.totalCents, 14780);
    expect(bindings.provenanceByBindingId['efficiency_text_009'], isNotNull);
    expect(
      () => DemoEnergyBindings.forRollingEfficiency(
        trees: [_october()],
        homeId: _home,
        referenceLocalDate: '2026-10-07',
      ),
      throwsFormatException,
    );
  });

  test(
    'last 30 local days join September and October without losing cents',
    () {
      final window = DemoRollingCostWindow.fromTrees(
        trees: [
          buildSeptember2026DemoTree(homeId: _home),
          _october(),
        ],
        homeId: _home,
        referenceLocalDate: '2026-10-07',
        dayCount: 30,
      );
      expect(window.startLocalDate, '2026-09-08');
      expect(window.endExclusiveLocalDate, '2026-10-08');
      expect(window.source.usefulCents, 12592);
      expect(window.source.wasteCents, 2188);
      expect(window.source.totalCents, 14780);
      expect(window.presentation.totalMicros, window.source.totalMicros);
    },
  );

  test(
    'rolling week crosses a month boundary and missing month is rejected',
    () {
      final october = _october(referenceDay: 3);
      expect(
        () => DemoRollingCostWindow.fromTrees(
          trees: [october],
          homeId: _home,
          referenceLocalDate: '2026-10-03',
          dayCount: 7,
        ),
        throwsFormatException,
      );
      final window = DemoRollingCostWindow.fromTrees(
        trees: [
          buildSeptember2026DemoTree(homeId: _home),
          october,
        ],
        homeId: _home,
        referenceLocalDate: '2026-10-03',
        dayCount: 7,
      );
      expect(window.startLocalDate, '2026-09-27');
      expect(window.endExclusiveLocalDate, '2026-10-04');
      expect(window.source.usefulCents, 3392);
      expect(window.source.wasteCents, 900);
    },
  );

  test('rejects one missing local day and accepts a 23-hour DST day', () {
    final complete = _october();
    final missingDay = DemoMonthTree(
      homeId: _home,
      referenceLocalDate: complete.referenceLocalDate,
      days: complete.days
          .where((day) => day.period.localDate != '2026-10-06')
          .toList(),
    );
    expect(
      () => DemoRollingCostWindow.fromTrees(
        trees: [missingDay],
        homeId: _home,
        referenceLocalDate: '2026-10-07',
        dayCount: 7,
      ),
      throwsFormatException,
    );

    final march = buildDemoMonthTree(
      homeId: _home,
      year: 2026,
      month: 3,
      timezone: 'America/Chicago',
      referenceDay: 8,
    );
    expect(march.day('2026-03-08').period.seconds, 23 * 3600);
    final window = DemoRollingCostWindow.fromTrees(
      trees: [march],
      homeId: _home,
      referenceLocalDate: '2026-03-08',
      dayCount: 7,
    );
    expect(window.startLocalDate, '2026-03-02');
    expect(window.endExclusiveLocalDate, '2026-03-09');
    expect(window.source.totalCents, 3742);
  });

  test('a 30-day window can span three calendar months after February', () {
    DemoMonthTree month(int number, int referenceDay) => buildDemoMonthTree(
      homeId: _home,
      year: 2026,
      month: number,
      timezone: 'America/Chicago',
      referenceDay: referenceDay,
    );
    final window = DemoRollingCostWindow.fromTrees(
      trees: [month(1, 31), month(2, 28), month(3, 1)],
      homeId: _home,
      referenceLocalDate: '2026-03-01',
      dayCount: 30,
    );
    expect(window.startLocalDate, '2026-01-31');
    expect(window.endExclusiveLocalDate, '2026-03-02');
    expect(window.dayCount, 30);
    expect(window.source.totalCents, greaterThan(0));
  });

  test('rejects mixed homes, timezones, duplicate months and future days', () {
    final september = buildSeptember2026DemoTree(homeId: _home);
    final october = _october();
    for (final trees in <List<DemoMonthTree>>[
      [september, _october(homeId: _otherHome)],
      [
        buildDemoMonthTree(
          homeId: _home,
          year: 2026,
          month: 9,
          timezone: 'America/New_York',
          referenceDay: 30,
        ),
        october,
      ],
      [september, september, october],
      [
        buildDemoMonthTree(
          homeId: _home,
          year: 2026,
          month: 9,
          timezone: 'America/Chicago',
          referenceDay: 29,
        ),
        october,
      ],
    ]) {
      expect(
        () => DemoRollingCostWindow.fromTrees(
          trees: trees,
          homeId: _home,
          referenceLocalDate: '2026-10-07',
          dayCount: 30,
        ),
        throwsFormatException,
      );
    }
    expect(
      () => DemoRollingCostWindow.fromTrees(
        trees: [october],
        homeId: _home,
        referenceLocalDate: '2026-10-08',
        dayCount: 7,
      ),
      throwsFormatException,
    );
    expect(
      () => DemoRollingCostWindow.fromTrees(
        trees: [october],
        homeId: _home,
        referenceLocalDate: '2026-10-07',
        dayCount: 31,
      ),
      throwsArgumentError,
    );
  });

  test('keeps a sub-cent unknown amount in source and presentation', () {
    final original = _october();
    final day = original.day('2026-10-07');
    final first = day.devices.first;
    final replacement = DemoBranch(
      deviceId: first.deviceId,
      name: first.name,
      period: first.period,
      cost: DemoCost.fromMicros(
        usefulMicros: first.cost.usefulMicros,
        wasteMicros: first.cost.wasteMicros,
        unclassifiedMicros: 1,
      ),
      origin: first.origin,
      sourceId: first.sourceId,
    );
    final alteredDay = DemoDayTree(
      homeId: _home,
      period: day.period,
      devices: [replacement, ...day.devices.skip(1)],
      unattributed: day.unattributed,
    );
    final altered = DemoMonthTree(
      homeId: _home,
      referenceLocalDate: original.referenceLocalDate,
      days: [
        for (final row in original.days)
          if (row == day) alteredDay else row,
      ],
    );
    final window = DemoRollingCostWindow.fromTrees(
      trees: [altered],
      homeId: _home,
      referenceLocalDate: '2026-10-07',
      dayCount: 7,
    );
    expect(window.source.unclassifiedMicros, 1);
    expect(window.presentation.unclassifiedMicros, 1);
    expect(window.source.totalMicros, 37420001);
    expect(window.hasUnknownSourceCost, isTrue);
    expect(window.hasUnknownPresentationCost, isTrue);
  });
}
