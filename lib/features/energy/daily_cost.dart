import '../discovery/discovery_api.dart';

/// Converts a sourced estimate to the daily amount used by Power Now.
/// Metered amounts have a separate daily evidence path.
double? sourceDailyCostUsd(EnergyEstimate? estimate) {
  if (estimate == null ||
      estimate.status == 'measured' ||
      estimate.evidence == null) {
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
