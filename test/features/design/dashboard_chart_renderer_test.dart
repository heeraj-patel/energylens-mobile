import 'dart:convert';
import 'dart:io';

import 'package:energylens_mobile/features/design/dashboard_chart_projection.dart';
import 'package:energylens_mobile/features/design/dashboard_chart_renderer.dart';
import 'package:energylens_mobile/features/design/design_page_bridge.dart';
import 'package:flutter_test/flutter_test.dart';

const home = '11111111-1111-4111-8111-111111111111';

void main() {
  test('period changes update totals, bars, and selected control together', () async {
    final gate = DesignPageRequestGate();
    final ticket = gate.select(home, 'dashboard');
    DashboardChartProjection chart(
      String period,
      String dayLabel,
      String total,
    ) => DashboardChartProjection(
      granularity: period,
      bars: [
        DashboardChartBar(
          label: dayLabel,
          usefulCents: BigInt.from(70),
          wasteCents: BigInt.from(20),
        ),
      ],
      periodTotal: total,
      usefulTotal:
          '\$${period == 'day'
              ? '1.20'
              : period == 'week'
              ? '8.20'
              : '32.20'}',
      wasteTotal:
          '\$${period == 'day'
              ? '0.30'
              : period == 'week'
              ? '1.80'
              : '4.80'}',
    );
    final renderer = DashboardChartRenderer(gate);
    final scripts = [
      for (final chart in [
        chart('day', 'Mon', '\$1.50'),
        chart('week', 'Week 1', '\$10.00'),
        chart('month', 'Jan', '\$37.00'),
        chart('day', 'Tue', '\$1.50'),
      ])
        renderer.script(ticket, chart)!,
    ];
    final sharedStyles = await File(
      'assets/design_pages/shared/mobile_refinements.css',
    ).readAsString();
    expect(sharedStyles, contains('.el-useful-graph'));
    expect(sharedStyles, contains('.el-waste-graph'));
    final file = await File(
      '${Directory.systemTemp.path}/energylens-dashboard-chart-${DateTime.now().microsecondsSinceEpoch}.json',
    ).writeAsString(jsonEncode({'scripts': scripts, 'homeId': home}));
    try {
      final result = await Process.run('node', [
        '-e',
        r'''
const assert = require('node:assert/strict');
const fs = require('node:fs');
const {scripts, homeId} = JSON.parse(fs.readFileSync(process.argv[1], 'utf8'));
globalThis.atob = input => Buffer.from(input, 'base64').toString('binary');
globalThis.window = {__energyLensTextBindingContext: {homeId, page: 'dashboard', generation: 1}};
const svg = {children: [], appendChild(node) { this.children.push(node); }};
const old = {localName: 'g', remove() { svg.children.splice(svg.children.indexOf(this), 1); }};
svg.children.push(old);
const buttons = ['004', '005', '006'].map(suffix => {
  const state = {};
  return {dataset: {elAction: 'dashboard_action_' + suffix}, state,
    classList: {toggle(name, enabled) { state[name] = enabled; }}};
});
const summaries = Object.fromEntries(['025', '026', '027'].map(suffix => [
  'dashboard_text_' + suffix, {textContent: ''}
]));
globalThis.document = {
  querySelector(selector) {
    if (selector.includes('dashboard-trends')) return svg;
    const match = selector.match(/dashboard_text_\d+/);
    return match ? summaries[match[0]] : null;
  },
  querySelectorAll() { return buttons; },
  createElementNS(_, name) {
    return {localName: name, attrs: {}, children: [],
      setAttribute(key, value) { this.attrs[key] = value; },
      appendChild(child) { this.children.push(child); },
      remove() { svg.children.splice(svg.children.indexOf(this), 1); }};
  }
};
for (const [index, period] of ['day', 'week', 'month', 'day'].entries()) {
  window.__energyLensDashboardRequestedPeriod = period;
  assert.equal(eval(scripts[index]), true);
  assert.equal(svg.children.length, 1);
  assert.equal(svg.children[0].children.at(-1).textContent, ['Mon', 'Week 1', 'Jan', 'Tue'][index]);
  assert.deepEqual(
    [summaries.dashboard_text_026.textContent, summaries.dashboard_text_027.textContent],
    [
      ['\$1.20 Useful', '\$0.30 Waste'],
      ['\$8.20 Useful', '\$1.80 Waste'],
      ['\$32.20 Useful', '\$4.80 Waste'],
      ['\$1.20 Useful', '\$0.30 Waste'],
    ][index],
  );
  assert.equal(buttons[['day', 'week', 'month'].indexOf(period)].state['bg-white'], true);
}
assert.equal(svg.children[0].children[0].attrs.class, 'el-useful-graph');
assert.equal(svg.children[0].children[1].attrs.class, 'el-waste-graph');
const currentSummary = ['026', '027'].map(suffix => summaries['dashboard_text_' + suffix].textContent);
window.__energyLensDashboardRequestedPeriod = 'month';
assert.equal(eval(scripts[0]), false);
assert.equal(svg.children[0].children.at(-1).textContent, 'Tue');
assert.deepEqual(['026', '027'].map(suffix => summaries['dashboard_text_' + suffix].textContent), currentSummary);
window.__energyLensDashboardRequestedPeriod = 'day';
window.__energyLensTextBindingContext.generation = 2;
assert.equal(eval(scripts[0]), false);
assert.deepEqual(['026', '027'].map(suffix => summaries['dashboard_text_' + suffix].textContent), currentSummary);
''',
        file.path,
      ]);
      expect(result.exitCode, 0, reason: '${result.stdout}\n${result.stderr}');
    } finally {
      await file.delete();
    }
  });
}
