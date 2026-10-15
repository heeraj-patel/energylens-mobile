import 'dart:convert';

import 'dashboard_chart_projection.dart';
import 'design_page_bridge.dart';

/// Updates the selected-period summary, chart geometry, and period controls
/// under the current Dashboard ticket. The payload contains formatted values,
/// never API tokens.
class DashboardChartRenderer {
  const DashboardChartRenderer(this.gate);
  final DesignPageRequestGate gate;

  String? script(DesignPageTicket ticket, DashboardChartProjection chart) {
    if (!gate.acceptsTicket(ticket) || ticket.page != 'dashboard') return null;
    final largest = chart.bars.fold<BigInt>(
      BigInt.one,
      (maximum, bar) => bar.totalCents > maximum ? bar.totalCents : maximum,
    );
    int height(BigInt value) => value == BigInt.zero
        ? 0
        : ((value * BigInt.from(76) + largest ~/ BigInt.two) ~/ largest)
              .toInt()
              .clamp(1, 76);
    final payload = base64Encode(
      utf8.encode(
        jsonEncode({
          'context': {
            'homeId': ticket.homeId,
            'page': ticket.page,
            'generation': ticket.generation,
          },
          'granularity': chart.granularity,
          'usefulTotal': chart.usefulTotal,
          'wasteTotal': chart.wasteTotal,
          'bars': [
            for (final bar in chart.bars)
              {
                'label': bar.label,
                'useful': height(bar.usefulCents),
                'waste': height(bar.wasteCents),
              },
          ],
        }),
      ),
    );
    return '''
(() => {
  const payload = JSON.parse(new TextDecoder().decode(Uint8Array.from(atob('$payload'), c => c.charCodeAt(0))));
  const current = window.__energyLensTextBindingContext;
  const expected = payload.context;
  if (!current || current.homeId !== expected.homeId || current.page !== expected.page || current.generation !== expected.generation) return false;
  if (window.__energyLensDashboardRequestedPeriod && window.__energyLensDashboardRequestedPeriod !== payload.granularity) return false;
  const svg = document.querySelector('svg[data-el-chart="dashboard-trends"]');
  if (!svg || !Array.isArray(payload.bars) || payload.bars.length < 1 || payload.bars.length > 5) return false;
  const summary = [
    ['dashboard_text_026', payload.usefulTotal + ' Useful'],
    ['dashboard_text_027', payload.wasteTotal + ' Waste']
  ].map(([id, value]) => [document.querySelector('[data-el-bind="' + id + '"]'), value]);
  if (summary.some(([node]) => !node)) return false;
  for (const [node, value] of summary) node.textContent = value;
  const ns = 'http://www.w3.org/2000/svg';
  const element = (name, attrs, value) => {
    const node = document.createElementNS(ns, name);
    for (const [key, text] of Object.entries(attrs)) node.setAttribute(key, String(text));
    if (value !== undefined) node.textContent = value;
    return node;
  };
  const groups = [];
  const count = payload.bars.length;
  payload.bars.forEach((bar, index) => {
    const center = count === 1 ? 160 : 24 + index * 272 / (count - 1);
    const group = element('g', {});
    const base = 110;
    if (bar.useful > 0) group.appendChild(element('rect', {
      x: center - 12, y: base - bar.useful, width: 24, height: bar.useful,
      rx: 3, class: 'el-useful-graph'
    }));
    if (bar.waste > 0) group.appendChild(element('rect', {
      x: center - 12, y: base - bar.useful - bar.waste,
      width: 24, height: bar.waste, rx: 3, class: 'el-waste-graph'
    }));
    group.appendChild(element('text', {
      x: center, y: 126, 'text-anchor': 'middle',
      'font-family': 'Rubik, sans-serif', 'font-size': 10, fill: '#6f787e'
    }, bar.label));
    groups.push(group);
  });
  for (const child of Array.from(svg.children)) {
    if (child.localName === 'g') child.remove();
  }
  groups.forEach(group => svg.appendChild(group));
  const selected = {
    day: 'dashboard_action_004',
    week: 'dashboard_action_005',
    month: 'dashboard_action_006'
  }[payload.granularity];
  for (const button of document.querySelectorAll('button[data-el-action^="dashboard_action_00"]')) {
    if (!['dashboard_action_004', 'dashboard_action_005', 'dashboard_action_006'].includes(button.dataset.elAction)) continue;
    const active = button.dataset.elAction === selected;
    button.classList.toggle('bg-white', active);
    button.classList.toggle('shadow-sm', active);
    button.classList.toggle('text-slate-900', active);
    button.classList.toggle('font-bold', active);
    button.classList.toggle('text-slate-500', !active);
    button.classList.toggle('font-medium', !active);
  }
  return true;
})()
''';
  }
}
