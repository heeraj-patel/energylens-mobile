import 'package:timezone/data/latest.dart' as tz_data;
import 'package:timezone/timezone.dart' as tz;

import '../../core/cloud_api/cloud_household_energy.dart';
import 'dashboard_demo_period_costs.dart';
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

  /// Cost-only illustration for local pilot and design tour. The same axis
  /// formatter is used for Cloud periods and the approved fixture.
  static DashboardChartProjection fromDemo(String granularity) {
    final location = _location('America/Chicago')!;
    final bars = [
      for (final bucket in DashboardDemoPeriodCosts.lastFive(granularity))
        DashboardChartBar(
          label: _label(
            tz.TZDateTime(
              location,
              bucket.startLocalDate.year,
              bucket.startLocalDate.month,
              bucket.startLocalDate.day,
            ),
            location,
            granularity,
          ),
          periodLabel: _periodLabel(
            tz.TZDateTime(
              location,
              bucket.startLocalDate.year,
              bucket.startLocalDate.month,
              bucket.startLocalDate.day,
            ),
            location,
            granularity,
          ),
          usefulCents: BigInt.from(bucket.usefulCents),
          wasteCents: BigInt.from(bucket.wasteCents),
        ),
    ];
    final useful = bars.fold<BigInt>(
      BigInt.zero,
      (sum, bar) => sum + bar.usefulCents,
    );
    final waste = bars.fold<BigInt>(
      BigInt.zero,
      (sum, bar) => sum + bar.wasteCents,
    );
    return DashboardChartProjection(
      granularity: granularity,
      bars: List.unmodifiable(bars),
      periodTotal: _money(useful + waste),
      usefulTotal: _money(useful),
      wasteTotal: _money(waste),
    );
  }

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
        (trends.dataMode != 'mixed' &&
            (trends.availability == 'unavailable' ||
                trends.totals.availability == 'unavailable'))) {
      return null;
    }
    bool supportedBasis(String basis) =>
        const {'synthetic', 'measured', 'estimated', 'mixed'}.contains(basis);
    if (trends.dataMode != 'mixed' &&
        (!supportedBasis(trends.evidenceBasis) ||
            !supportedBasis(trends.totals.evidenceBasis))) {
      return null;
    }
    final seededMode = trends.dataMode == 'mixed';
    final total = seededMode ? null : _usdCents(trends.totals.cost);
    final useful = seededMode ? null : _usdCents(trends.totals.usefulCost);
    final waste = seededMode ? null : _usdCents(trends.totals.wasteCost);
    if (!seededMode &&
        (total == null ||
            useful == null ||
            waste == null ||
            useful + waste > total)) {
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
      if (!seededMode &&
          (bucket.allocation.availability == 'unavailable' ||
              !supportedBasis(bucket.allocation.evidenceBasis))) {
        return null;
      }
      final seeded = seededMode ? _seededBucketCosts(bucket) : null;
      final bucketUseful = seededMode
          ? seeded?.$2
          : _usdCents(bucket.allocation.usefulCost);
      final bucketWaste = seededMode
          ? seeded?.$3
          : _usdCents(bucket.allocation.wasteCost);
      final bucketTotal = seededMode
          ? seeded?.$1
          : _usdCents(bucket.allocation.cost);
      if (bucketUseful == null ||
          bucketWaste == null ||
          bucketTotal == null ||
          bucketUseful + bucketWaste > bucketTotal) {
        return null;
      }
      observed.add(
        DashboardChartBar(
          label: _label(bucket.period.start, location, granularity),
          periodLabel: _periodLabel(bucket.period.start, location, granularity),
          usefulCents: bucketUseful,
          wasteCents: bucketWaste,
        ),
      );
    }
    if (observed.isEmpty) return null;
    final visible = observed.length <= 5
        ? observed
        : observed.sublist(observed.length - 5);
    final visibleUseful = seededMode
        ? visible.fold<BigInt>(BigInt.zero, (sum, bar) => sum + bar.usefulCents)
        : useful!;
    final visibleWaste = seededMode
        ? visible.fold<BigInt>(BigInt.zero, (sum, bar) => sum + bar.wasteCents)
        : waste!;
    final visibleTotal = seededMode
        ? visible.fold<BigInt>(BigInt.zero, (sum, bar) => sum + bar.totalCents)
        : total!;
    return DashboardChartProjection(
      granularity: granularity,
      bars: List.unmodifiable(visible),
      periodTotal: _money(visibleTotal),
      usefulTotal: _money(visibleUseful),
      wasteTotal: _money(visibleWaste),
    );
  }
}

(BigInt, BigInt, BigInt)? _seededBucketCosts(CloudEnergyTrendBucket bucket) {
  final rows = bucket.deviceAllocations
      // Mixed Cloud periods may also carry owned real-appliance rows. Those
      // have no verified identity binding to a demo leaf and their measured
      // unclassified cost cannot be placed in useful/waste bars.
      .where((row) => row.deviceId != null && row.applianceId == null)
      .toList();
  if (rows.length != 18) return null;
  final ids = <String>{};
  var total = BigInt.zero;
  var useful = BigInt.zero;
  var waste = BigInt.zero;
  for (final row in rows) {
    if (row.applianceId != null ||
        !ids.add(row.deviceId!) ||
        row.allocation.evidenceBasis != 'synthetic') {
      return null;
    }
    final rowTotal = _usdMicros(row.allocation.cost);
    final rowUseful = _usdMicros(row.allocation.usefulCost);
    final rowWaste = _usdMicros(row.allocation.wasteCost);
    if (rowTotal == null ||
        rowUseful == null ||
        rowWaste == null ||
        rowUseful + rowWaste > rowTotal) {
      return null;
    }
    total += rowTotal;
    useful += rowUseful;
    waste += rowWaste;
  }
  BigInt cents(BigInt micros) =>
      (micros + BigInt.from(5000)) ~/ BigInt.from(10000);
  return (cents(total), cents(useful), cents(waste));
}

BigInt? _usdMicros(CloudEnergyMoney? money) {
  if (money == null ||
      money.currency != 'USD' ||
      !RegExp(r'^(0|[1-9][0-9]*)(\.[0-9]{1,6})?$').hasMatch(money.amount)) {
    return null;
  }
  final parts = money.amount.split('.');
  return BigInt.parse(parts[0]) * BigInt.from(1000000) +
      BigInt.parse((parts.length == 1 ? '' : parts[1]).padRight(6, '0'));
}

class DashboardChartBar {
  const DashboardChartBar({
    required this.label,
    required this.periodLabel,
    required this.usefulCents,
    required this.wasteCents,
  });
  final String label;
  final String periodLabel;
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

String _periodLabel(DateTime start, tz.Location location, String granularity) {
  final local = tz.TZDateTime.from(start, location);
  final full = '${_months[local.month - 1]} ${local.day}, ${local.year}';
  return switch (granularity) {
    'day' => full,
    'week' => 'Week of $full',
    _ => '${_months[local.month - 1]} ${local.year}',
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
