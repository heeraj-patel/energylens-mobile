import 'dart:convert';

import 'package:timezone/data/latest.dart' as tz_data;
import 'package:timezone/timezone.dart' as tz;

import '../../core/cloud_api/cloud_household_energy.dart';
import 'dashboard_chart_projection.dart';
import 'design_page_bridge.dart';
import 'efficiency_domain_repository.dart';

/// Binds the existing top value slots from the selected home's exact
/// home-local trailing 30-day trends response. The packaged labels stay intact.
List<DesignTextBinding>? prepareEfficiencyTrailing30DaysBindings(
  EfficiencyDomainSnapshot snapshot,
) {
  final trailing30Days = snapshot.trailing30Days;
  final dashboard = snapshot.energy.dashboard;
  if (trailing30Days == null ||
      !snapshot.energy.matchesHomeAndSnapshot(snapshot.homeId) ||
      trailing30Days.homeId.toLowerCase() != snapshot.homeId.toLowerCase() ||
      trailing30Days.dataMode != snapshot.energy.dataMode ||
      trailing30Days.fixtureRevision != dashboard.fixtureRevision ||
      trailing30Days.timezone != dashboard.timezone ||
      trailing30Days.scope != dashboard.scope ||
      trailing30Days.granularity != 'day' ||
      trailing30Days.schemaRevision != dashboard.schemaRevision ||
      trailing30Days.availability == 'unavailable' ||
      trailing30Days.totals.availability == 'unavailable' ||
      trailing30Days.evidenceBasis == 'unavailable' ||
      trailing30Days.totals.evidenceBasis == 'unavailable' ||
      trailing30Days.generatedAt.difference(dashboard.generatedAt).abs() >
          const Duration(minutes: 5)) {
    return null;
  }

  tz_data.initializeTimeZones();
  late final tz.Location location;
  try {
    location = tz.getLocation(trailing30Days.timezone);
  } catch (_) {
    return null;
  }
  final current = tz.TZDateTime.from(trailing30Days.generatedAt, location);
  final periodStart = tz.TZDateTime(
    location,
    current.year,
    current.month,
    current.day - 29,
  );
  final tomorrow = tz.TZDateTime(
    location,
    current.year,
    current.month,
    current.day + 1,
  );
  if (!trailing30Days.period.start.isAtSameMomentAs(periodStart) ||
      !trailing30Days.period.endExclusive.isAtSameMomentAs(tomorrow)) {
    return null;
  }

  final summary = trailing30Days.efficiencyTrailing30Days;
  if (summary == null) return null;
  final total = summary.periodCost;
  final trendCost = trailing30Days.totals.cost;
  if (trendCost == null ||
      !total.hasSameValue(trendCost) ||
      total.currency != 'USD') {
    return null;
  }
  final formatted = formatDashboardUsd(total);
  if (formatted == null) return null;
  final measured = summary.evidenceBasis == 'measured';
  if (trailing30Days.dataMode == 'household' && !measured) return null;
  final opportunity = formatDashboardUsd(summary.identifiedOpportunity);
  final optimalBase = formatDashboardUsd(summary.optimalBase);
  final night = formatDashboardUsd(summary.nightTotalOpportunity);
  final away = formatDashboardUsd(summary.awayTotalOpportunity);
  final peak = formatDashboardUsd(summary.peakRatesOpportunity);
  final habits = formatDashboardUsd(summary.habitsOpportunity);
  if (opportunity == null ||
      optimalBase == null ||
      (!measured &&
          (night == null || away == null || peak == null || habits == null))) {
    return null;
  }
  return [
    DesignTextBinding('efficiency_text_006', opportunity),
    DesignTextBinding('efficiency_text_009', formatted),
    DesignTextBinding('efficiency_text_011', optimalBase),
    if (night != null) DesignTextBinding('efficiency_text_015', night),
    if (away != null) DesignTextBinding('efficiency_text_017', away),
    if (peak != null) DesignTextBinding('efficiency_text_019', peak),
    if (habits != null) DesignTextBinding('efficiency_text_021', habits),
  ];
}

/// Applies backend-calculated chart widths and matching tooltip amounts.
/// The four existing chart labels and DOM locations remain unchanged.
String buildEfficiencyTrailing30DaysChartScript(
  DesignPageTicket ticket,
  CloudEfficiencyTrailing30Days summary,
) {
  final payload = jsonEncode({
    'homeId': ticket.homeId,
    'page': ticket.page,
    'generation': ticket.generation,
    'widths': [
      summary.chartSegmentWidthPercent.night,
      summary.chartSegmentWidthPercent.away,
      summary.chartSegmentWidthPercent.peakRates,
      summary.chartSegmentWidthPercent.habits,
    ],
    'amounts': [
      formatDashboardUsd(summary.nightTotalOpportunity),
      formatDashboardUsd(summary.awayTotalOpportunity),
      formatDashboardUsd(summary.peakRatesOpportunity),
      formatDashboardUsd(summary.habitsOpportunity),
    ],
  });
  return '''
(() => {
  const payload = $payload;
  const context = window.__energyLensTextBindingContext;
  if (!context || context.homeId !== payload.homeId ||
      context.page !== payload.page || context.generation !== payload.generation) return false;
  const bar = document.getElementById('efficiency-details')?.querySelector('div.w-full.h-3');
  if (!bar || bar.children.length !== 4) return false;
  const labels = ['Night', 'Away', 'Peak', 'Habits'];
  for (let i = 0; i < 4; i++) {
    bar.children[i].style.width = payload.widths[i] + '%';
    bar.children[i].title = payload.amounts[i] == null ? '' : labels[i] + ': ' + payload.amounts[i];
  }
  return true;
})()
''';
}
