// Shared `GET /energy/estimates` fixtures (shapes per
// kernel-common-contracts/api/hub-openapi.yaml `EnergyEstimates`), built from
// the contract formula so the numbers are internally consistent.

import 'package:energylens_mobile/core/api/energy_models.dart';
import 'package:energylens_mobile/features/energy_estimate/logic/energy_estimate_calculator.dart';

const double kFixtureRate = 0.16;

const EnergyRate kFixtureRateState = EnergyRate(
  rateUsdPerKwh: kFixtureRate,
  source: EnergyRateSource.state,
  sourceLabel: 'Texas average (EIA)',
);

/// A slider row whose kWh/cost come from the §3.1 formula at [value].
DeviceEnergyEstimate hoursRow(
  String id,
  String name, {
  String category = 'tv',
  double activeWatts = 100,
  double standbyWatts = 1,
  double value = 35,
  EnergyPowerSource source = EnergyPowerSource.categoryTypical,
  String? ratingSource,
  double max = 168,
}) {
  final base = DeviceEnergyEstimate(
    deviceId: id,
    name: name,
    category: category,
    profileCategory: category,
    powerSource: source,
    ratingSource: ratingSource,
    usageKind: EnergyUsageKind.hoursPerWeek,
    slider: EnergySlider(min: 0, max: max, step: 1, defaultValue: 35),
    usageValue: value,
    usageValueIsDefault: true,
    standbyApplies: true,
    activeWatts: activeWatts,
    standbyWatts: standbyWatts,
    kwh: EnergySplit.zero,
    costUsd: EnergySplit.zero,
  );
  return recomputeRow(
    base,
    usageValue: value,
    rate: kFixtureRate,
    period: 'month',
  ).copyWith(usageValueIsDefault: true);
}

DeviceEnergyEstimate alwaysOnRow(
  String id,
  String name, {
  String category = 'refrigerator',
  double watts = 40,
}) {
  final kwh = watts * 168 / 1000 * 52 / 12;
  return DeviceEnergyEstimate(
    deviceId: id,
    name: name,
    category: category,
    profileCategory: category,
    powerSource: EnergyPowerSource.categoryTypical,
    usageKind: EnergyUsageKind.alwaysOn,
    usageValueIsDefault: true,
    standbyApplies: false,
    activeWatts: watts,
    kwh: EnergySplit(active: kwh, standby: 0, total: kwh),
    costUsd: EnergySplit(
      active: kwh * kFixtureRate,
      standby: 0,
      total: kwh * kFixtureRate,
    ),
  );
}

const DeviceEnergyEstimate kNoDataRow = DeviceEnergyEstimate(
  deviceId: 'sensor-1',
  name: 'Door sensor',
  category: 'sensor',
  profileCategory: 'other',
  powerSource: EnergyPowerSource.none,
  usageKind: EnergyUsageKind.hoursPerWeek,
  usageValueIsDefault: true,
  standbyApplies: false,
);

/// Wraps [rows] (sorted by cost, no-data last) with consistent totals.
EnergyEstimates estimatesOf(
  List<DeviceEnergyEstimate> rows, {
  EnergyRate rate = kFixtureRateState,
}) {
  final sorted = List<DeviceEnergyEstimate>.of(rows)
    ..sort((a, b) {
      final ca = a.costUsd?.total ?? -1;
      final cb = b.costUsd?.total ?? -1;
      return cb.compareTo(ca);
    });
  double sum(double? Function(EnergySplit s) f, {required bool cost}) =>
      rows.fold(
        0,
        (acc, r) =>
            acc +
            ((cost ? r.costUsd : r.kwh) == null
                ? 0
                : (f((cost ? r.costUsd : r.kwh)!) ?? 0)),
      );
  return EnergyEstimates(
    period: 'month',
    generatedAt: DateTime.utc(2026, 9, 23, 12),
    profileTableVersion: '1.0.0',
    rate: rate,
    totalKwh: EnergySplit(
      active: sum((s) => s.active, cost: false),
      standby: sum((s) => s.standby, cost: false),
      total: sum((s) => s.total, cost: false),
    ),
    totalCostUsd: EnergySplit(
      active: sum((s) => s.active, cost: true),
      standby: sum((s) => s.standby, cost: true),
      total: sum((s) => s.total, cost: true),
    ),
    devices: sorted,
  );
}

/// A realistic household: 7 devices with data + one without.
EnergyEstimates sampleHousehold() => estimatesOf(<DeviceEnergyEstimate>[
  hoursRow('tv-1', 'Living room TV', activeWatts: 120, standbyWatts: 1.5),
  hoursRow('tv-2', 'Bedroom TV', activeWatts: 80, value: 14),
  alwaysOnRow('fridge-1', 'Kitchen fridge'),
  alwaysOnRow('router-1', 'Router', category: 'router', watts: 10),
  hoursRow(
    'roku-1',
    'Roku',
    category: 'media_player',
    activeWatts: 4,
    value: 20,
  ),
  hoursRow(
    'light-1',
    'Hue lights',
    category: 'light',
    activeWatts: 30,
    value: 21,
  ),
  hoursRow(
    'hvac-1',
    'Heat pump',
    category: 'hvac',
    activeWatts: 2500,
    value: 21,
  ),
  kNoDataRow,
]);
