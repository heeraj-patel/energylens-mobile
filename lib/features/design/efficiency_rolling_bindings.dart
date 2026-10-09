import 'package:timezone/data/latest.dart' as tz_data;
import 'package:timezone/timezone.dart' as tz;

import '../../core/cloud_api/cloud_household_energy.dart';
import 'dashboard_chart_projection.dart';
import 'design_page_bridge.dart';
import 'efficiency_domain_repository.dart';

/// Approved label and value for a complete synthetic trailing 30-day source.
/// Household reads remain unbound until the API supplies verified coverage for
/// every local day; partial live observations cannot become a 30-day spend.
List<DesignTextBinding>? prepareEfficiencyRollingBindings(
  EfficiencyDomainSnapshot snapshot,
) {
  final rolling = snapshot.rolling30Days;
  if (snapshot.page != EfficiencyPage.overview ||
      rolling == null ||
      !snapshot.energy.matchesHomeAndSnapshot(snapshot.homeId) ||
      rolling.homeId.toLowerCase() != snapshot.homeId.toLowerCase() ||
      rolling.dataMode != 'sample' ||
      rolling.fixtureRevision != snapshot.energy.dashboard.fixtureRevision ||
      rolling.timezone != snapshot.energy.dashboard.timezone ||
      rolling.scope != snapshot.energy.dashboard.scope ||
      rolling.granularity != 'day' ||
      rolling.evidenceBasis != 'synthetic' ||
      rolling.totals.evidenceBasis != 'synthetic' ||
      rolling.availability == 'unavailable' ||
      rolling.totals.availability == 'unavailable' ||
      rolling.generatedAt
              .difference(snapshot.energy.dashboard.generatedAt)
              .abs() >
          const Duration(minutes: 5) ||
      rolling.buckets.length != 30) {
    return null;
  }
  tz_data.initializeTimeZones();
  late final tz.Location location;
  try {
    location = tz.getLocation(rolling.timezone);
  } catch (_) {
    return null;
  }
  final today = tz.TZDateTime.from(rolling.generatedAt, location);
  final todayDate = DateTime.utc(today.year, today.month, today.day);
  final firstDate = todayDate.subtract(const Duration(days: 29));
  final expectedStart = tz.TZDateTime(
    location,
    firstDate.year,
    firstDate.month,
    firstDate.day,
  );
  final expectedEnd = tz.TZDateTime(
    location,
    today.year,
    today.month,
    today.day + 1,
  );
  if (!rolling.period.start.isAtSameMomentAs(expectedStart) ||
      !rolling.period.endExclusive.isAtSameMomentAs(expectedEnd)) {
    return null;
  }
  var sum = BigInt.zero;
  for (var i = 0; i < 30; i++) {
    final day = firstDate.add(Duration(days: i));
    final start = tz.TZDateTime(location, day.year, day.month, day.day);
    final end = tz.TZDateTime(location, day.year, day.month, day.day + 1);
    final bucket = rolling.buckets[i];
    final cost = _moneyUnits(bucket.allocation.cost);
    if (!bucket.period.start.isAtSameMomentAs(start) ||
        !bucket.period.endExclusive.isAtSameMomentAs(end) ||
        bucket.allocation.availability == 'unavailable' ||
        bucket.allocation.evidenceBasis != 'synthetic' ||
        cost == null) {
      return null;
    }
    sum += cost;
  }
  final total = _moneyUnits(rolling.totals.cost);
  if (total == null || total != sum) return null;
  final formatted = formatDashboardUsd(rolling.totals.cost);
  if (formatted == null) return null;
  return [
    const DesignTextBinding('efficiency_text_008', 'Last 30 days'),
    DesignTextBinding('efficiency_text_009', formatted),
  ];
}

BigInt? _moneyUnits(CloudEnergyMoney? value) {
  if (value == null ||
      value.currency != 'USD' ||
      !RegExp(r'^(0|[1-9][0-9]*)(\.[0-9]{1,8})?$').hasMatch(value.amount)) {
    return null;
  }
  final parts = value.amount.split('.');
  return BigInt.parse(parts[0]) * BigInt.from(100000000) +
      BigInt.parse((parts.length == 1 ? '' : parts[1]).padRight(8, '0'));
}
