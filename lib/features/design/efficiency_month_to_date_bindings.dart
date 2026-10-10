import 'dart:convert';

import 'package:timezone/data/latest.dart' as tz_data;
import 'package:timezone/timezone.dart' as tz;

import '../../core/cloud_api/cloud_household_energy.dart';
import 'dashboard_chart_projection.dart';
import 'design_page_bridge.dart';
import 'efficiency_domain_repository.dart';

/// Binds the existing top value slots from the selected home's exact
/// home-local month-to-date trends response. The packaged labels stay intact.
List<DesignTextBinding>? prepareEfficiencyMonthToDateBindings(
  EfficiencyDomainSnapshot snapshot,
) {
  final monthToDate = snapshot.monthToDate;
  final dashboard = snapshot.energy.dashboard;
  if (monthToDate == null ||
      !snapshot.energy.matchesHomeAndSnapshot(snapshot.homeId) ||
      monthToDate.homeId.toLowerCase() != snapshot.homeId.toLowerCase() ||
      monthToDate.dataMode != snapshot.energy.dataMode ||
      monthToDate.fixtureRevision != dashboard.fixtureRevision ||
      monthToDate.timezone != dashboard.timezone ||
      monthToDate.scope != dashboard.scope ||
      monthToDate.granularity != 'day' ||
      monthToDate.schemaRevision != dashboard.schemaRevision ||
      monthToDate.availability == 'unavailable' ||
      monthToDate.totals.availability == 'unavailable' ||
      monthToDate.evidenceBasis == 'unavailable' ||
      monthToDate.totals.evidenceBasis == 'unavailable' ||
      monthToDate.generatedAt.difference(dashboard.generatedAt).abs() >
          const Duration(minutes: 5)) {
    return null;
  }

  tz_data.initializeTimeZones();
  late final tz.Location location;
  try {
    location = tz.getLocation(monthToDate.timezone);
  } catch (_) {
    return null;
  }
  final current = tz.TZDateTime.from(monthToDate.generatedAt, location);
  final monthStart = tz.TZDateTime(location, current.year, current.month);
  final tomorrow = tz.TZDateTime(
    location,
    current.year,
    current.month,
    current.day + 1,
  );
  if (!monthToDate.period.start.isAtSameMomentAs(monthStart) ||
      !monthToDate.period.endExclusive.isAtSameMomentAs(tomorrow)) {
    return null;
  }

  final summary = monthToDate.efficiencyMonthToDate;
  final total = summary?.monthToDateCost ?? monthToDate.totals.cost;
  if (total == null || total.currency != 'USD') {
    return null;
  }
  final formatted = formatDashboardUsd(total);
  if (formatted == null) return null;
  if (summary == null) {
    return [DesignTextBinding('efficiency_text_009', formatted)];
  }
  if (monthToDate.dataMode == 'household') return null;
  final opportunity = formatDashboardUsd(summary.identifiedOpportunity);
  final optimalBase = formatDashboardUsd(summary.optimalBase);
  final night = formatDashboardUsd(summary.nightTotalOpportunity);
  final away = formatDashboardUsd(summary.awayTotalOpportunity);
  final peak = formatDashboardUsd(summary.peakRatesOpportunity);
  final habits = formatDashboardUsd(summary.habitsOpportunity);
  if (opportunity == null ||
      optimalBase == null ||
      night == null ||
      away == null ||
      peak == null ||
      habits == null) {
    return null;
  }
  return [
    DesignTextBinding('efficiency_text_006', opportunity),
    DesignTextBinding('efficiency_text_009', formatted),
    DesignTextBinding('efficiency_text_011', optimalBase),
    DesignTextBinding('efficiency_text_015', night),
    DesignTextBinding('efficiency_text_017', away),
    DesignTextBinding('efficiency_text_019', peak),
    DesignTextBinding('efficiency_text_021', habits),
  ];
}

/// Applies backend-calculated chart widths and matching tooltip amounts.
/// The four existing chart labels and DOM locations remain unchanged.
String buildEfficiencyMonthToDateChartScript(
  DesignPageTicket ticket,
  CloudEfficiencyMonthToDate summary,
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
    bar.children[i].title = labels[i] + ': ' + payload.amounts[i];
  }
  return true;
})()
''';
}
