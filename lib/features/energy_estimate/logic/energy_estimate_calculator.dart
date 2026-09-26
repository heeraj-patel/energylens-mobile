/// Local recompute of one device's energy estimate while its usage slider is
/// being dragged (energy estimator plan §3.1).
///
/// The estimate math lives on the hub (`GET /energy/estimates`, one source of
/// truth for the app, the House Health Report and automations). The app only
/// recomputes locally between a drag and the hub's next answer, using the
/// inputs the hub returned for that row (`active_watts`, `standby_watts`,
/// `kwh_per_cycle`, `cycle_hours`, `standby_applies`) and the response's
/// effective rate. The formula below must stay identical to the one in
/// `hub-openapi.yaml`'s `getEnergyEstimates` description.
library;

import 'package:energylens_mobile/core/api/energy_models.dart';

/// Hours in a week.
const double kHoursPerWeek = 168;

/// Weeks → the response period: `month` = weekly × 52 / 12, `week` = 1.
double periodFactor(String period) => period == 'week' ? 1 : 52 / 12;

/// Weekly active/standby kWh for [row] at [usageValue] (hours/week or
/// cycles/week), or null when the row has no slider-driven estimate
/// (`measured`, `none`, `always_on`, or missing inputs).
({double active, double standby})? weeklyKwhFor(
  DeviceEnergyEstimate row,
  double usageValue,
) {
  if (row.powerSource == EnergyPowerSource.measured ||
      row.powerSource == EnergyPowerSource.none) {
    return null;
  }
  final standbyWatts = row.standbyApplies ? (row.standbyWatts ?? 0) : 0.0;
  switch (row.usageKind) {
    case EnergyUsageKind.hoursPerWeek:
      final activeWatts = row.activeWatts;
      if (activeWatts == null) return null;
      final h = usageValue.clamp(0, kHoursPerWeek).toDouble();
      return (
        active: activeWatts * h / 1000,
        standby: standbyWatts * (kHoursPerWeek - h) / 1000,
      );
    case EnergyUsageKind.cyclesPerWeek:
      final cycleHours = row.cycleHours ?? 0;
      final kwhPerCycle =
          row.kwhPerCycle ??
          (row.activeWatts == null
              ? null
              : row.activeWatts! * cycleHours / 1000);
      if (kwhPerCycle == null) return null;
      final c = usageValue < 0 ? 0.0 : usageValue;
      final idleHours = kHoursPerWeek - c * cycleHours;
      return (
        active: kwhPerCycle * c,
        standby: standbyWatts * (idleHours < 0 ? 0 : idleHours) / 1000,
      );
    case EnergyUsageKind.alwaysOn:
      return null;
  }
}

/// [row] with its usage set to [usageValue] and its period kWh / cost
/// recomputed at [rate]. Returns [row] unchanged when it has no slider-driven
/// estimate.
DeviceEnergyEstimate recomputeRow(
  DeviceEnergyEstimate row, {
  required double usageValue,
  required double rate,
  required String period,
}) {
  final weekly = weeklyKwhFor(row, usageValue);
  if (weekly == null) return row;
  final f = periodFactor(period);
  final active = weekly.active * f;
  final standby = weekly.standby * f;
  return row.copyWith(
    usageValue: usageValue,
    usageValueIsDefault: false,
    kwh: EnergySplit(active: active, standby: standby, total: active + standby),
    costUsd: EnergySplit(
      active: active * rate,
      standby: standby * rate,
      total: (active + standby) * rate,
    ),
  );
}

/// [estimates] with every device in [overrides] (device id → usage value)
/// recomputed and the household totals adjusted by each row's difference.
/// Row order is kept as the hub sent it, so rows don't jump while dragging.
EnergyEstimates applyUsageOverrides(
  EnergyEstimates estimates,
  Map<String, double> overrides,
) {
  if (overrides.isEmpty) return estimates;
  var kwh = estimates.totalKwh;
  var cost = estimates.totalCostUsd;
  final rows = <DeviceEnergyEstimate>[];
  for (final row in estimates.devices) {
    final value = overrides[row.deviceId];
    if (value == null || row.slider == null) {
      rows.add(row);
      continue;
    }
    final next = recomputeRow(
      row,
      usageValue: value,
      rate: estimates.rate.rateUsdPerKwh,
      period: estimates.period,
    );
    kwh = _shift(kwh, row.kwh, next.kwh);
    cost = _shift(cost, row.costUsd, next.costUsd);
    rows.add(next);
  }
  return estimates.copyWith(totalKwh: kwh, totalCostUsd: cost, devices: rows);
}

EnergySplit _shift(EnergySplit total, EnergySplit? before, EnergySplit? after) {
  double? add(double? t, double? b, double? a) =>
      t == null ? null : t - (b ?? 0) + (a ?? 0);
  return EnergySplit(
    active: add(total.active, before?.active, after?.active),
    standby: add(total.standby, before?.standby, after?.standby),
    total: total.total - (before?.total ?? 0) + (after?.total ?? 0),
  );
}
