import 'dart:convert';

import '../../core/cloud_api/cloud_household_energy.dart';
import 'dashboard_chart_projection.dart';
import 'design_page_bridge.dart';

/// Owner-approved copy E-G1-1..9 for measured Efficiency summaries.
const efficiencyCopyNightMeasured =
    'Overnight standby cost you {amount} so far this month.';
const efficiencyCopyAwayMeasured =
    'While you were away, devices on standby used {amount}.';
const efficiencyCopyPeakTou =
    'Running {devices} during peak hours cost {amount} more than off-peak.';
const efficiencyCopyHabits =
    '{device} used more per cycle than a typical model, about {amount} this month.';
const efficiencyCopyAwayNotConfigured =
    "Set your usual away hours to see what runs while you're out.";
const efficiencyCopyPeakFlatTariff =
    'Your rate is the same all day. Add time-of-use rates if your plan has them.';
const efficiencyCopyHabitsInsufficient =
    "Answer a few usage questions and we'll compare your cycles.";
const efficiencyCopyUnmetered =
    'Connect a smart plug to see when {device} uses energy.';
const efficiencyCopyGas =
    "Gas use isn't tracked by time of day, so night and peak don't apply.";

const efficiencyCopyPanels = ['night', 'away', 'peak', 'habits'];

/// Copy lines per panel ('night', 'away', 'peak', 'habits') for a measured
/// summary, or null for synthetic summaries. [names] maps lower-case
/// appliance ids to display names; a device without a name adds no line.
Map<String, List<String>>? efficiencyMeasuredCopy(
  CloudEfficiencyTrailing30Days summary,
  Map<String, String> names,
) {
  final bases = summary.bases;
  if (summary.evidenceBasis != 'measured' || bases == null) return null;
  String? nameOf(CloudEfficiencyDevice d) => names[d.applianceId.toLowerCase()];
  String fill(String t, Map<String, String> v) =>
      v.entries.fold(t, (s, e) => s.replaceAll('{${e.key}}', e.value));
  String joined(List<String> items) => items.length < 2
      ? items.join()
      : '${items.sublist(0, items.length - 1).join(', ')} and ${items.last}';

  List<String> panel({
    required CloudEnergyMoney? amount,
    required String basis,
    required String Function(CloudEfficiencyDevice) deviceBasis,
    required List<String> Function(String? formatted) measured,
    String? nullCopy,
    required String nullBasis,
  }) {
    final lines = <String>[];
    final formatted = formatDashboardUsd(amount);
    if (formatted != null) {
      lines.addAll(measured(formatted));
    } else if (basis == nullBasis && nullCopy != null) {
      lines.add(nullCopy);
    } else if (basis == 'fuel_not_applicable') {
      lines.add(efficiencyCopyGas);
    }
    final unmetered = <String>{};
    var gas = basis == 'fuel_not_applicable' && formatted == null;
    for (final d in summary.devices) {
      final b = deviceBasis(d);
      if (b == 'unmetered') {
        final name = nameOf(d);
        if (name != null && unmetered.add(name)) {
          lines.add(fill(efficiencyCopyUnmetered, {'device': name}));
        }
      } else if (b == 'fuel_not_applicable' && !gas) {
        gas = true;
        lines.add(efficiencyCopyGas);
      }
    }
    return lines;
  }

  String? amountOrNull(CloudEnergyMoney? m) => formatDashboardUsd(m);

  return {
    'night': panel(
      amount: summary.nightTotalOpportunity,
      basis: bases.night,
      nullBasis: 'none',
      deviceBasis: (d) => d.nightBasis,
      measured: (a) => [
        fill(efficiencyCopyNightMeasured, {'amount': a!}),
      ],
    ),
    'away': panel(
      amount: summary.awayTotalOpportunity ?? summary.awayOpportunity,
      basis: bases.away,
      nullBasis: 'not_configured',
      nullCopy: efficiencyCopyAwayNotConfigured,
      deviceBasis: (d) => d.awayBasis,
      measured: (a) => [
        fill(efficiencyCopyAwayMeasured, {'amount': a!}),
      ],
    ),
    'peak': panel(
      amount: summary.peakRatesOpportunity,
      basis: bases.peakRates,
      nullBasis: 'flat_tariff',
      nullCopy: efficiencyCopyPeakFlatTariff,
      deviceBasis: (d) => d.peakBasis,
      measured: (a) {
        final devices = [
          for (final d in summary.devices)
            if (d.peak != null && nameOf(d) != null) nameOf(d)!,
        ];
        if (devices.isEmpty) return const [];
        return [
          fill(efficiencyCopyPeakTou, {
            'devices': joined(devices),
            'amount': a!,
          }),
        ];
      },
    ),
    'habits': panel(
      amount: summary.habitsOpportunity,
      basis: bases.habits,
      nullBasis: 'insufficient_data',
      nullCopy: efficiencyCopyHabitsInsufficient,
      deviceBasis: (d) => d.habitsBasis,
      measured: (_) => [
        for (final d in summary.devices)
          if (amountOrNull(d.habits) != null && nameOf(d) != null)
            fill(efficiencyCopyHabits, {
              'device': nameOf(d)!,
              'amount': amountOrNull(d.habits)!,
            }),
      ],
    ),
  };
}

/// Fills the empty copy slots of the packaged panels and hides the Leak
/// Breakdown values whose amount is null. Packaged demo cards stay visible.
String buildEfficiencyMeasuredCopyScript(
  DesignPageTicket ticket,
  CloudEfficiencyTrailing30Days summary,
  Map<String, List<String>> copy,
) {
  final prefix = ticket.page == 'efficiency' ? 'efficiency' : ticket.page;
  final payload = jsonEncode({
    'homeId': ticket.homeId,
    'page': ticket.page,
    'generation': ticket.generation,
    'copy': copy,
    'hide': [
      if (summary.nightTotalOpportunity == null) '${prefix}_text_015',
      if (summary.awayTotalOpportunity == null) '${prefix}_text_017',
      if (summary.peakRatesOpportunity == null) '${prefix}_text_019',
      if (summary.habitsOpportunity == null) '${prefix}_text_021',
    ],
  });
  return '''
(() => {
  const payload = $payload;
  const context = window.__energyLensTextBindingContext;
  if (!context || context.homeId !== payload.homeId ||
      context.page !== payload.page || context.generation !== payload.generation) return false;
  for (const id of payload.hide) {
    const el = document.querySelector('[data-el-bind="' + id + '"]');
    if (el) el.style.display = 'none';
  }
  for (const key of Object.keys(payload.copy)) {
    const slot = document.querySelector('[data-el-eff-copy="' + key + '"]');
    if (!slot) continue;
    slot.replaceChildren(...payload.copy[key].map((line) => {
      const p = document.createElement('p');
      p.className = 'font-body-md text-[12px] leading-relaxed text-on-surface-variant';
      p.textContent = line;
      return p;
    }));
  }
  return true;
})()
''';
}
