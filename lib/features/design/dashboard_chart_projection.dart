import 'package:timezone/data/latest.dart' as tz_data;
import 'package:timezone/timezone.dart' as tz;

import '../../core/cloud_api/cloud_household_energy.dart';
import 'dashboard_domain_repository.dart';

/// An evidenced useful/waste cost chart for the last five occurrences
/// returned by the API's home-local day, week, or month view. A missing split
/// remains unavailable; a measured total is never divided by a mock ratio.
class DashboardChartProjection {
  const DashboardChartProjection({
    required this.granularity,
    required this.bars,
    required this.periodTotal,
    required this.usefulTotal,
    required this.wasteTotal,
  });

  final String granularity;
  final List<DashboardChartBar> bars;
  final String periodTotal;
  final String usefulTotal;
  final String wasteTotal;

  static DashboardChartProjection? fromSnapshot(
    DashboardDomainSnapshot snapshot,
    String granularity,
  ) {
    if (!const {'day', 'week', 'month'}.contains(granularity) ||
        !snapshot.matchesHomeAndSnapshot(snapshot.homeId)) {
      return null;
    }
    final trends = snapshot.periodTrends[granularity];
    if (trends == null ||
        trends.granularity != granularity ||
        trends.homeId.toLowerCase() != snapshot.homeId.toLowerCase() ||
        trends.dataMode != snapshot.dataMode ||
        trends.fixtureRevision != snapshot.dashboard.fixtureRevision ||
        trends.timezone != snapshot.dashboard.timezone ||
        trends.scope != snapshot.dashboard.scope ||
        trends.availability == 'unavailable' ||
        trends.totals.availability == 'unavailable') {
      return null;
    }
    bool supportedBasis(String basis) =>
        const {'synthetic', 'measured', 'estimated', 'mixed'}.contains(basis);
    if (!supportedBasis(trends.evidenceBasis) ||
        !supportedBasis(trends.totals.evidenceBasis)) {
      return null;
    }
    final total = _usdCents(trends.totals.cost);
    final useful = _usdCents(trends.totals.usefulCost);
    final waste = _usdCents(trends.totals.wasteCost);
    if (total == null ||
        useful == null ||
        waste == null ||
        useful + waste > total) {
      return null;
    }
    final location = _location(trends.timezone);
    if (location == null) return null;
    final observed = <DashboardChartBar>[];
    DateTime? previousEnd;
    for (final bucket in trends.buckets) {
      if (bucket.period.start.isBefore(trends.period.start) ||
          bucket.period.endExclusive.isAfter(trends.period.endExclusive) ||
          (previousEnd != null &&
              !bucket.period.start.isAtSameMomentAs(previousEnd))) {
        return null;
      }
      previousEnd = bucket.period.endExclusive;
      final syntheticBucket = bucket.allocation.evidenceBasis == 'synthetic';
      if (bucket.period.start.isAfter(trends.generatedAt) ||
          (!syntheticBucket &&
              !bucket.period.start.isBefore(trends.generatedAt))) {
        continue;
      }
      if (bucket.allocation.availability == 'unavailable' ||
          !supportedBasis(bucket.allocation.evidenceBasis)) {
        return null;
      }
      final bucketUseful = _usdCents(bucket.allocation.usefulCost);
      final bucketWaste = _usdCents(bucket.allocation.wasteCost);
      final bucketTotal = _usdCents(bucket.allocation.cost);
      if (bucketUseful == null ||
          bucketWaste == null ||
          bucketTotal == null ||
          bucketUseful + bucketWaste > bucketTotal) {
        return null;
      }
      observed.add(
        DashboardChartBar(
          label: _label(bucket.period.start, location, granularity),
          usefulCents: bucketUseful,
          wasteCents: bucketWaste,
        ),
      );
    }
    if (observed.isEmpty) return null;
    return DashboardChartProjection(
      granularity: granularity,
      bars: List.unmodifiable(
        observed.length <= 5 ? observed : observed.sublist(observed.length - 5),
      ),
      periodTotal: _money(total),
      usefulTotal: _money(useful),
      wasteTotal: _money(waste),
    );
  }
}

class DashboardChartBar {
  const DashboardChartBar({
    required this.label,
    required this.usefulCents,
    required this.wasteCents,
  });
  final String label;
  final BigInt usefulCents;
  final BigInt wasteCents;
  BigInt get totalCents => usefulCents + wasteCents;
}

tz.Location? _location(String timezone) {
  tz_data.initializeTimeZones();
  try {
    return tz.getLocation(timezone);
  } catch (_) {
    return null;
  }
}

const _weekdays = ['Mon', 'Tue', 'Wed', 'Thu', 'Fri', 'Sat', 'Sun'];
const _months = [
  'Jan',
  'Feb',
  'Mar',
  'Apr',
  'May',
  'Jun',
  'Jul',
  'Aug',
  'Sep',
  'Oct',
  'Nov',
  'Dec',
];

String _label(DateTime start, tz.Location location, String granularity) {
  final local = tz.TZDateTime.from(start, location);
  return switch (granularity) {
    'day' => _weekdays[local.weekday - 1],
    'week' => '${_months[local.month - 1]} ${local.day}',
    _ => _months[local.month - 1],
  };
}

BigInt? _usdCents(CloudEnergyMoney? money) {
  if (money == null ||
      money.currency != 'USD' ||
      !RegExp(r'^(0|[1-9][0-9]*)(\.[0-9]+)?$').hasMatch(money.amount)) {
    return null;
  }
  final parts = money.amount.split('.');
  final fraction = parts.length == 1 ? '' : parts[1];
  var cents =
      BigInt.parse(parts[0]) * BigInt.from(100) +
      BigInt.parse(fraction.padRight(2, '0').substring(0, 2));
  if (fraction.length > 2 && fraction.codeUnitAt(2) >= 53) {
    cents += BigInt.one;
  }
  return cents;
}

String _money(BigInt cents) =>
    '\$${cents ~/ BigInt.from(100)}.${(cents % BigInt.from(100)).toString().padLeft(2, '0')}';

/// Customer display formatting only; Cloud decimal precision is retained in
/// the typed source allocation and all internal reconciliation.
String? formatDashboardUsd(CloudEnergyMoney? value) {
  final cents = _usdCents(value);
  return cents == null ? null : _money(cents);
}
