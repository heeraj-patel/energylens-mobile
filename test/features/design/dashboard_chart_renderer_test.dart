import 'dart:convert';
import 'dart:io';

import 'package:energylens_mobile/features/design/dashboard_chart_projection.dart';
import 'package:energylens_mobile/features/design/dashboard_chart_renderer.dart';
import 'package:energylens_mobile/features/design/design_page_bridge.dart';
import 'package:flutter_test/flutter_test.dart';

const home = '11111111-1111-4111-8111-111111111111';

void main() {
  test('current ticket replaces bars and selects the matching period', () async {
    final gate = DesignPageRequestGate();
    final ticket = gate.select(home, 'dashboard');
    final chart = DashboardChartProjection(
      granularity: 'day',
      bars: [
        DashboardChartBar(
          label: 'Mon',
          usefulCents: BigInt.from(70),
          wasteCents: BigInt.from(20),
        ),
        DashboardChartBar(
          label: 'Tue',
          usefulCents: BigInt.from(50),
          wasteCents: BigInt.from(10),
        ),
      ],
      periodTotal: '\$1.50',
      usefulTotal: '\$1.20',
      wasteTotal: '\$0.30',
    );
    final script = DashboardChartRenderer(gate).script(ticket, chart)!;
    final sharedStyles = await File(
      'assets/design_pages/shared/mobile_refinements.css',
    ).readAsString();
    expect(sharedStyles, contains('.el-useful-graph'));
    expect(sharedStyles, contains('.el-waste-graph'));
    final file = await File(
      '${Directory.systemTemp.path}/energylens-dashboard-chart-${DateTime.now().microsecondsSinceEpoch}.json',
    ).writeAsString(jsonEncode({'script': script, 'homeId': home}));
    try {
      final result = await Process.run('node', [
        '-e',
        r'''
const assert = require('node:assert/strict');
const fs = require('node:fs');
const {script, homeId} = JSON.parse(fs.readFileSync(process.argv[1], 'utf8'));
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
globalThis.document = {
  querySelector(selector) { return selector.includes('dashboard-trends') ? svg : null; },
  querySelectorAll() { return buttons; },
  createElementNS(_, name) {
    return {localName: name, attrs: {}, children: [],
      setAttribute(key, value) { this.attrs[key] = value; },
      appendChild(child) { this.children.push(child); },
      remove() { svg.children.splice(svg.children.indexOf(this), 1); }};
  }
};
assert.equal(eval(script), true);
assert.equal(svg.children.length, 2);
assert.deepEqual(svg.children.map(group => group.children.at(-1).textContent), ['Mon', 'Tue']);
assert.equal(svg.children[0].children[0].attrs.class, 'el-useful-graph');
assert.equal(svg.children[0].children[1].attrs.class, 'el-waste-graph');
assert.equal(buttons[0].state['bg-white'], true);
assert.equal(buttons[1].state['bg-white'], false);
window.__energyLensDashboardRequestedPeriod = 'month';
assert.equal(eval(script), false);
assert.equal(svg.children.length, 2);
window.__energyLensDashboardRequestedPeriod = 'day';
window.__energyLensTextBindingContext.generation = 2;
assert.equal(eval(script), false);
''',
        file.path,
      ]);
      expect(result.exitCode, 0, reason: '${result.stdout}\n${result.stderr}');
    } finally {
      await file.delete();
    }
  });
}
