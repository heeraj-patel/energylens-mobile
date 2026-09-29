// Local recompute used while a usage slider is dragged. Must match the hub's
// formula (hub-openapi.yaml getEnergyEstimates / plan §3.1).

import 'package:flutter_test/flutter_test.dart';
import 'package:energylens_mobile/core/api/energy_models.dart';
import 'package:energylens_mobile/features/energy_estimate/logic/energy_estimate_calculator.dart';

import '../energy_fixtures.dart';

DeviceEnergyEstimate _row({
  EnergyUsageKind kind = EnergyUsageKind.hoursPerWeek,
  EnergyPowerSource source = EnergyPowerSource.categoryTypical,
  bool standbyApplies = true,
  double? activeWatts = 100,
  double? standbyWatts = 2,
  double? kwhPerCycle,
  double? cycleHours,
}) => DeviceEnergyEstimate(
  deviceId: 'd',
  name: 'D',
  profileCategory: 'tv',
  powerSource: source,
  usageKind: kind,
  slider: const EnergySlider(min: 0, max: 168, step: 1, defaultValue: 35),
  usageValue: 35,
  usageValueIsDefault: true,
  standbyApplies: standbyApplies,
  activeWatts: activeWatts,
  standbyWatts: standbyWatts,
  kwhPerCycle: kwhPerCycle,
  cycleHours: cycleHours,
  kwh: EnergySplit.zero,
  costUsd: EnergySplit.zero,
);

void main() {
  group('weeklyKwhFor', () {
    test('hours_per_week: active h, standby for the rest of the week', () {
      final w = weeklyKwhFor(_row(), 35)!;
      expect(w.active, closeTo(100 * 35 / 1000, 1e-9));
      expect(w.standby, closeTo(2 * (168 - 35) / 1000, 1e-9));
    });

    test('standby is zero when the category says it does not apply', () {
      final w = weeklyKwhFor(_row(standbyApplies: false), 35)!;
      expect(w.standby, 0);
    });

    test('cycles_per_week uses kwh_per_cycle and subtracts cycle time', () {
      final w = weeklyKwhFor(
        _row(
          kind: EnergyUsageKind.cyclesPerWeek,
          kwhPerCycle: 1.2,
          cycleHours: 2,
          standbyWatts: 1,
        ),
        4,
      )!;
      expect(w.active, closeTo(4.8, 1e-9));
      expect(w.standby, closeTo(1 * (168 - 8) / 1000, 1e-9));
    });

    test('cycles fall back to active_watts × cycle_hours', () {
      final w = weeklyKwhFor(
        _row(
          kind: EnergyUsageKind.cyclesPerWeek,
          activeWatts: 500,
          cycleHours: 1.5,
          standbyWatts: 0,
        ),
        2,
      )!;
      expect(w.active, closeTo(500 * 1.5 / 1000 * 2, 1e-9));
    });

    test('cycle standby never goes negative', () {
      final w = weeklyKwhFor(
        _row(
          kind: EnergyUsageKind.cyclesPerWeek,
          kwhPerCycle: 1,
          cycleHours: 20,
        ),
        21,
      )!;
      expect(w.standby, 0);
    });

    test('measured, none and always_on rows have no slider estimate', () {
      expect(weeklyKwhFor(_row(source: EnergyPowerSource.measured), 1), isNull);
      expect(weeklyKwhFor(_row(source: EnergyPowerSource.none), 1), isNull);
      expect(weeklyKwhFor(_row(kind: EnergyUsageKind.alwaysOn), 1), isNull);
    });
  });

  test('recomputeRow scales to a month (×52/12) and prices at the rate', () {
    final r = recomputeRow(_row(), usageValue: 35, rate: 0.2, period: 'month');
    const weekly = 100 * 35 / 1000 + 2 * 133 / 1000;
    expect(r.kwh!.total, closeTo(weekly * 52 / 12, 1e-9));
    expect(r.costUsd!.total, closeTo(weekly * 52 / 12 * 0.2, 1e-9));
    expect(
      r.costUsd!.active! + r.costUsd!.standby!,
      closeTo(r.costUsd!.total, 1e-9),
    );
    expect(r.usageValue, 35);
    expect(r.usageValueIsDefault, isFalse);
  });

  test('applyUsageOverrides shifts the household total by the row delta', () {
    final e = sampleHousehold();
    final before = e.deviceById('tv-1')!;
    final after = applyUsageOverrides(e, <String, double>{'tv-1': 70});
    final row = after.deviceById('tv-1')!;
    expect(row.usageValue, 70);
    expect(row.costUsd!.total, greaterThan(before.costUsd!.total));
    expect(
      after.totalCostUsd.total - e.totalCostUsd.total,
      closeTo(row.costUsd!.total - before.costUsd!.total, 1e-9),
    );
    // Order is kept so rows don't jump under the finger.
    expect(
      after.devices.map((d) => d.deviceId),
      e.devices.map((d) => d.deviceId),
    );
  });

  test('preview clamps usage to the hub slider range', () {
    final fixture = estimatesOf(<DeviceEnergyEstimate>[
      hoursRow('limited-tv', 'Limited TV', value: 21, max: 42),
    ]);
    final aboveRange = applyUsageOverrides(
      fixture,
      <String, double>{'limited-tv': 99},
    );
    final row = aboveRange.deviceById('limited-tv')!;

    // The hub rejects saved usage outside the profile slider range. Keep the
    // local preview and its displayed value within that same contract.
    expect(row.usageValue, 42);
    final expected = recomputeRow(
      fixture.devices.single,
      usageValue: 42,
      rate: fixture.rate.rateUsdPerKwh,
      period: fixture.period,
    );
    expect(row.kwh!.total, closeTo(expected.kwh!.total, 1e-9));
    expect(aboveRange.totalCostUsd.total, closeTo(row.costUsd!.total, 1e-9));

    final belowRange = applyUsageOverrides(
      fixture,
      <String, double>{'limited-tv': -5},
    );
    expect(belowRange.devices.single.usageValue, 0);
  });

  test('cycle preview clamps usage and recomputes household totals', () {
    final row = DeviceEnergyEstimate(
      deviceId: 'limited-washer',
      name: 'Washer',
      profileCategory: 'washer',
      powerSource: EnergyPowerSource.categoryTypical,
      usageKind: EnergyUsageKind.cyclesPerWeek,
      slider: const EnergySlider(min: 1, max: 8, step: 1, defaultValue: 4),
      usageValue: 4,
      usageValueIsDefault: true,
      standbyApplies: true,
      activeWatts: 100,
      standbyWatts: 1,
      kwhPerCycle: 1.2,
      cycleHours: 2,
      kwh: const EnergySplit(active: 4.8, standby: 0.16, total: 4.96),
      costUsd: const EnergySplit(active: 0.96, standby: 0.032, total: 0.992),
    );
    final fixture = estimatesOf(<DeviceEnergyEstimate>[row]);
    final preview = applyUsageOverrides(
      fixture,
      <String, double>{'limited-washer': 20},
    );
    final updated = preview.devices.single;

    expect(updated.usageValue, 8);
    final weekly = weeklyKwhFor(row, 8)!;
    final expectedTotal = (weekly.active + weekly.standby) * 52 / 12;
    expect(updated.kwh!.total, closeTo(expectedTotal, 1e-9));
    expect(
      preview.totalKwh.total - fixture.totalKwh.total,
      closeTo(updated.kwh!.total - row.kwh!.total, 1e-9),
    );
    expect(
      preview.totalCostUsd.total - fixture.totalCostUsd.total,
      closeTo(updated.costUsd!.total - row.costUsd!.total, 1e-9),
    );
  });

  test('overrides for rows without a slider are ignored', () {
    final e = sampleHousehold();
    final after = applyUsageOverrides(e, <String, double>{'fridge-1': 99});
    expect(after.totalCostUsd.total, e.totalCostUsd.total);
  });
}
