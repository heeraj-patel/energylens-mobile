import '../discovery/discovery_api.dart';

/// Converts the hub's non-metering result to the daily amount used by Power Now.
/// Metered amounts have a separate daily evidence path.
double? sourceDailyCostUsd(EnergyEstimate? estimate) {
  if (estimate == null || estimate.status == 'measured') {
    return null;
  }
  final amount = estimate.estimatedCostUsd;
  if (amount == null || !amount.isFinite || amount < 0) return null;
  final days = switch (estimate.period) {
    'day' => 1,
    'week' => 7,
    'month' || '' => 30,
    _ => 0,
  };
  return days == 0 ? null : amount / days;
}

/// Returns today's measured cost only when coverage and the latest Hub sample
/// meet the approved display thresholds.
double? freshMeteredTodayCostUsd(DeviceEnergy? reading, {DateTime? now}) {
  if (reading == null ||
      reading.period != 'today' ||
      reading.coverageFraction < 0.8 ||
      reading.latestWatts == null ||
      reading.latestSample == null) {
    return null;
  }
  final amount = reading.observedCostUsd;
  if (amount == null || !amount.isFinite || amount < 0) return null;
  final age = (now ?? DateTime.now().toUtc()).difference(
    reading.latestSample!.ts.toUtc(),
  );
  if (age.isNegative || age > const Duration(seconds: 150)) return null;
  return amount;
}
