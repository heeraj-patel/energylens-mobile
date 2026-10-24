import 'dart:convert';

import 'dashboard_chart_projection.dart';
import 'design_page_bridge.dart';

/// The dollar axis and bar ratios are derived entirely with integer cents.
class DashboardChartScale {
  DashboardChartScale(Iterable<DashboardChartBar> bars)
    : intervalCents = _interval(bars),
      maximumCents = bars.fold<BigInt>(
        BigInt.zero,
        (value, bar) => bar.totalCents > value ? bar.totalCents : value,
      );

  final BigInt intervalCents;
  final BigInt maximumCents;
  BigInt get upperCents =>
      (maximumCents ~/ intervalCents + BigInt.one) * intervalCents;

  static BigInt _interval(Iterable<DashboardChartBar> bars) {
    final maximum = bars.fold<BigInt>(
      BigInt.zero,
      (value, bar) => bar.totalCents > value ? bar.totalCents : value,
    );
    if (maximum == BigInt.zero) return BigInt.from(100);
    final target = (maximum + BigInt.from(3)) ~/ BigInt.from(4);
    var power = BigInt.one;
    while (BigInt.from(10) * power < target) {
      power *= BigInt.from(10);
    }
    for (final multiple in [
      BigInt.one,
      BigInt.two,
      BigInt.from(5),
      BigInt.from(10),
    ]) {
      final interval = multiple * power;
      if (interval >= target) return interval;
    }
    throw StateError('No chart interval');
  }

  List<BigInt> get ticks => [
    for (var tick = BigInt.zero; tick <= upperCents; tick += intervalCents)
      tick,
  ];

  /// JS only receives a bounded ratio, never a monetary floating point value.
  double ratio(BigInt cents) =>
      ((cents * BigInt.from(1000000000)) ~/ upperCents).toInt() / 1000000000;
}

String _money(BigInt cents, {required bool showCents}) {
  final dollars = (cents ~/ BigInt.from(100)).toString();
  final grouped = dollars.replaceAllMapped(
    RegExp(r'\B(?=(\d{3})+(?!\d))'),
    (match) => ',',
  );
  if (!showCents) return '\$$grouped';
  return '\$$grouped.${(cents % BigInt.from(100)).toString().padLeft(2, '0')}';
}

/// Updates the selected-period summary, chart geometry, and period controls
/// under the current Dashboard ticket. The payload contains formatted values,
/// never API tokens.
class DashboardChartRenderer {
  const DashboardChartRenderer(this.gate);
  final DesignPageRequestGate gate;

  String? script(DesignPageTicket ticket, DashboardChartProjection chart) {
    if (!gate.acceptsTicket(ticket) ||
        ticket.page != 'dashboard' ||
        chart.bars.isEmpty ||
        chart.bars.length > 5 ||
        !const {'day', 'week', 'month'}.contains(chart.granularity) ||
        chart.bars.any(
          (bar) =>
              bar.usefulCents < BigInt.zero || bar.wasteCents < BigInt.zero,
        )) {
      return null;
    }
    final scale = DashboardChartScale(chart.bars);
    final showTickCents = scale.ticks.any(
      (tick) => tick % BigInt.from(100) != BigInt.zero,
    );
    final payload = base64Encode(
      utf8.encode(
        jsonEncode({
          'context': {
            'homeId': ticket.homeId,
            'page': ticket.page,
            'generation': ticket.generation,
          },
          'granularity': chart.granularity,
          'xTitle': const {
            'day': 'Day',
            'week': 'Week',
            'month': 'Month',
          }[chart.granularity],
          'usefulTotal': chart.usefulTotal,
          'wasteTotal': chart.wasteTotal,
          'ticks': [
            for (final tick in scale.ticks)
              _money(tick, showCents: showTickCents),
          ],
          'bars': [
            for (final bar in chart.bars)
              {
                'label': bar.label,
                'periodLabel': bar.periodLabel,
                'amount': _money(bar.totalCents, showCents: true),
                'usefulRatio': scale.ratio(bar.usefulCents),
                'totalRatio': scale.ratio(bar.totalCents),
              },
          ],
        }),
      ),
    );
    return '''
(() => {
  const payload = JSON.parse(new TextDecoder().decode(Uint8Array.from(atob('$payload'), c => c.charCodeAt(0))));
  const expected = payload.context;
  const isCurrent = () => {
    const current = window.__energyLensTextBindingContext;
    return current && current.homeId === expected.homeId && current.page === expected.page &&
      current.generation === expected.generation &&
      (!window.__energyLensDashboardRequestedPeriod ||
       window.__energyLensDashboardRequestedPeriod === payload.granularity) &&
      document.querySelector('svg[data-el-chart="dashboard-trends"]') === svg;
  };
  const svg = document.querySelector('svg[data-el-chart="dashboard-trends"]');
  if (!svg || !Array.isArray(payload.bars) || payload.bars.length < 1 || payload.bars.length > 5 ||
      !Array.isArray(payload.ticks) || payload.ticks.length < 2 || !isCurrent()) return false;
  const summary = [
    ['dashboard_text_026', payload.usefulTotal + ' Useful'],
    ['dashboard_text_027', payload.wasteTotal + ' Waste']
  ].map(([id, value]) => [document.querySelector('[data-el-bind="' + id + '"]'), value]);
  if (summary.some(([node]) => !node)) return false;
  const ns = 'http://www.w3.org/2000/svg';
  const element = (name, attrs, value) => {
    const node = document.createElementNS(ns, name);
    for (const [key, text] of Object.entries(attrs)) node.setAttribute(key, String(text));
    if (value !== undefined) node.textContent = value;
    return node;
  };
  const width = Math.max(320, 270 + Math.max(...payload.ticks.map(tick => tick.length)) * 6.8);
  const gutter = width - 262;
  const plotLeft = gutter + 8;
  const plotRight = width - 12;
  const plotTop = 30;
  const baseline = 142;
  const plotHeight = baseline - plotTop;
  const root = element('g', {class: 'el-dashboard-chart-content'});
  const yTitle = element('text', {x: 4, y: 14, class: 'el-chart-title'}, 'Cost (USD)');
  root.appendChild(yTitle);
  payload.ticks.forEach((tick, index) => {
    const y = baseline - index * plotHeight / (payload.ticks.length - 1);
    root.appendChild(element('line', {x1: plotLeft, x2: plotRight, y1: y, y2: y,
      class: index === 0 ? 'el-chart-baseline' : 'el-chart-grid'}));
    root.appendChild(element('text', {x: gutter, y: y + 4, 'text-anchor': 'end',
      class: 'el-chart-tick'}, tick));
  });
  const tooltip = element('g', {class: 'el-chart-tooltip', visibility: 'hidden',
    'pointer-events': 'none', 'aria-hidden': 'true'});
  const tipBack = element('rect', {x: 0, y: 0, width: 0, height: 42, rx: 6,
    class: 'el-chart-tooltip-back'});
  const tipPeriod = element('text', {x: 0, y: 0, class: 'el-chart-tooltip-period'});
  const tipAmount = element('text', {x: 0, y: 0, class: 'el-chart-tooltip-amount'});
  tooltip.appendChild(tipBack);
  tooltip.appendChild(tipPeriod);
  tooltip.appendChild(tipAmount);
  const count = payload.bars.length;
  const slot = (plotRight - plotLeft) / count;
  const hits = [];
  payload.bars.forEach((bar, index) => {
    const center = plotLeft + slot * (index + .5);
    const usefulY = baseline - Math.max(0, Math.min(1, bar.usefulRatio)) * plotHeight;
    const totalY = baseline - Math.max(0, Math.min(1, bar.totalRatio)) * plotHeight;
    const group = element('g', {class: 'el-chart-bar', tabindex: 0, role: 'button',
      'aria-label': bar.periodLabel + '. Useful + Waste: ' + bar.amount,
      'aria-pressed': 'false'});
    if (bar.usefulRatio > 0) group.appendChild(element('rect', {
      x: center - 12, y: usefulY, width: 24, height: baseline - usefulY,
      class: 'el-useful-graph'}));
    if (bar.totalRatio > bar.usefulRatio) group.appendChild(element('rect', {
      x: center - 12, y: totalY, width: 24, height: usefulY - totalY,
      class: 'el-waste-graph'}));
    group.appendChild(element('text', {x: center, y: 166, 'text-anchor': 'middle',
      class: 'el-chart-x-label'}, bar.label));
    group.appendChild(element('rect', {x: center - slot / 2, y: plotTop,
      width: slot, height: 140, class: 'el-chart-hit'}));
    root.appendChild(group);
    hits.push({group, center, top: totalY, bar});
  });
  root.appendChild(element('text', {x: (plotLeft + plotRight) / 2, y: 193,
    'text-anchor': 'middle', class: 'el-chart-title'}, payload.xTitle));
  root.appendChild(tooltip);
  let pinned = -1;
  let shown = -1;
  const hide = () => {
    tooltip.setAttribute('visibility', 'hidden');
    shown = -1;
    hits.forEach(({group}) => group.setAttribute('aria-pressed', 'false'));
  };
  const show = index => {
    if (!isCurrent()) return;
    const hit = hits[index];
    const first = hit.bar.periodLabel;
    const second = 'Useful + Waste: ' + hit.bar.amount;
    const tipWidth = Math.min(width - 8, Math.max(first.length, second.length) * 6.5 + 20);
    const x = Math.max(4, Math.min(width - tipWidth - 4, hit.center - tipWidth / 2));
    const y = hit.top >= 52 ? Math.max(2, hit.top - 49) : Math.min(149, hit.top + 7);
    tipBack.setAttribute('x', x);
    tipBack.setAttribute('y', y);
    tipBack.setAttribute('width', tipWidth);
    tipPeriod.setAttribute('x', x + 10);
    tipPeriod.setAttribute('y', y + 16);
    tipAmount.setAttribute('x', x + 10);
    tipAmount.setAttribute('y', y + 33);
    tipPeriod.textContent = first;
    tipAmount.textContent = second;
    tooltip.setAttribute('visibility', 'visible');
    shown = index;
    hits.forEach(({group}, i) => group.setAttribute('aria-pressed', String(i === pinned)));
  };
  hits.forEach(({group}, index) => {
    group.addEventListener('pointerenter', () => show(index));
    group.addEventListener('focus', () => show(index));
    const toggle = () => {
      if (!isCurrent()) return;
      pinned = pinned === index ? -1 : index;
      if (pinned < 0) hide(); else show(index);
    };
    group.addEventListener('click', event => {
      event.stopPropagation();
      toggle();
    });
    group.addEventListener('keydown', event => {
      if (event.key === 'Escape') { pinned = -1; hide(); event.preventDefault(); }
      if (event.key === 'Enter' || event.key === ' ') {
        event.preventDefault();
        toggle();
      }
    });
  });
  const onLeave = () => { if (pinned < 0) hide(); else show(pinned); };
  const onFocusOut = event => {
    if (!svg.contains(event.relatedTarget)) {
      if (pinned < 0) hide(); else show(pinned);
    }
  };
  // The navigation script stops bubble propagation on period buttons.
  const outside = event => {
    if (!isCurrent()) { svg.__energyLensChartCleanup?.(); return; }
    if (!svg.contains(event.target)) { pinned = -1; hide(); }
  };
  if (svg.__energyLensChartCleanup) svg.__energyLensChartCleanup();
  svg.addEventListener('pointerleave', onLeave);
  svg.addEventListener('focusout', onFocusOut);
  document.addEventListener('click', outside, true);
  svg.__energyLensChartCleanup = () => {
    document.removeEventListener('click', outside, true);
    svg.removeEventListener('pointerleave', onLeave);
    svg.removeEventListener('focusout', onFocusOut);
    hide();
  };
  svg.setAttribute('viewBox', '0 0 ' + width + ' 200');
  svg.setAttribute('role', 'group');
  svg.setAttribute('aria-label', 'Cost (USD)');
  svg.replaceChildren(root);
  for (const [node, value] of summary) node.textContent = value;
  const selected = {
    day: 'dashboard_action_004', week: 'dashboard_action_005',
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
