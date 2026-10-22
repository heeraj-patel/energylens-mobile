import 'dart:convert';
import 'dart:io';

import 'package:energylens_mobile/features/design/dashboard_chart_projection.dart';
import 'package:energylens_mobile/features/design/dashboard_chart_renderer.dart';
import 'package:energylens_mobile/features/design/design_page_bridge.dart';
import 'package:flutter_test/flutter_test.dart';

const home = '11111111-1111-4111-8111-111111111111';

DashboardChartBar bar(
  BigInt useful,
  BigInt waste, {
  String label = 'Mon',
  String periodLabel = 'Sep 30, 2026',
}) => DashboardChartBar(
  label: label,
  periodLabel: periodLabel,
  usefulCents: useful,
  wasteCents: waste,
);

void main() {
  test('scale uses useful plus waste and four nice integer-cent intervals', () {
    final zero = DashboardChartScale([bar(BigInt.zero, BigInt.zero)]);
    expect(zero.upperCents, BigInt.from(100));
    expect(zero.ticks, [0, 25, 50, 75, 100].map(BigInt.from));
    final one = DashboardChartScale([bar(BigInt.one, BigInt.zero)]);
    expect(one.upperCents, BigInt.from(4));
    expect(one.ratio(BigInt.one), .25);
    final normal = DashboardChartScale([bar(BigInt.from(70), BigInt.from(20))]);
    expect(normal.upperCents, BigInt.from(200));
    expect(normal.ratio(BigInt.from(90)), .45);
    expect(
      DashboardChartScale([
        bar(BigInt.from(1000), BigInt.zero),
        bar(BigInt.zero, BigInt.from(1000)),
      ]).upperCents,
      BigInt.from(2000),
    );
    final huge = BigInt.parse('100000000000000000000000000001');
    final large = DashboardChartScale([bar(huge, BigInt.one)]);
    expect(large.upperCents >= huge + BigInt.one, isTrue);
    expect(large.ratio(huge + BigInt.one), lessThanOrEqualTo(1));
  });

  test('period redraw, interaction and stale checks run in a DOM harness', () async {
    final gate = DesignPageRequestGate();
    final ticket = gate.select(home, 'dashboard');
    DashboardChartProjection chart(
      String period,
      List<DashboardChartBar> bars,
    ) => DashboardChartProjection(
      granularity: period,
      bars: bars,
      periodTotal: '\$1.00',
      usefulTotal: '\$0.70',
      wasteTotal: '\$0.20',
    );
    final renderer = DashboardChartRenderer(gate);
    final scripts = [
      renderer.script(
        ticket,
        chart('day', [
          bar(BigInt.from(70), BigInt.from(20)),
          bar(
            BigInt.from(30),
            BigInt.from(10),
            label: 'Thu',
            periodLabel: 'Oct 1, 2026',
          ),
        ]),
      )!,
      renderer.script(
        ticket,
        chart('week', [bar(BigInt.zero, BigInt.zero, label: 'Sep 28')]),
      )!,
      renderer.script(
        ticket,
        chart('month', [bar(BigInt.one, BigInt.zero, label: 'Sep')]),
      )!,
    ];
    final css = await File('assets/design_pages/shared/mobile_refinements.css')
        .readAsString();
    expect(
      css,
      contains('svg[data-el-chart="dashboard-trends"] .el-chart-hit'),
    );
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
class Node {
  constructor(name) { this.localName = name; this.attrs = {}; this.children = [];
    this.listeners = {}; this.textContent = ''; }
  setAttribute(key, value) { this.attrs[key] = String(value); }
  appendChild(child) { this.children.push(child); return child; }
  replaceChildren(...children) { this.children = children; }
  addEventListener(type, listener) { (this.listeners[type] ||= new Set()).add(listener); }
  removeEventListener(type, listener) { this.listeners[type]?.delete(listener); }
  fire(type, event = {}) { for (const listener of this.listeners[type] || [])
    listener({target: this, stopPropagation() {}, preventDefault() {},
      key: event.key, relatedTarget: event.relatedTarget}); }
  contains(node) { return node === this || this.children.some(child => child.contains(node)); }
}
const svg = new Node('svg');
svg.appendChild(new Node('line'));
const summaries = Object.fromEntries(['026', '027'].map(s => ['dashboard_text_' + s, new Node('span')]));
const buttons = ['004', '005', '006'].map(s => ({dataset: {elAction: 'dashboard_action_' + s},
  state: {}, classList: {toggle(name, value) { buttons.find(x => x.dataset.elAction.endsWith(s)).state[name] = value; }}}));
const document = new Node('document');
document.querySelector = selector => selector.includes('dashboard-trends') ? svg :
  summaries[selector.match(/dashboard_text_\d+/)?.[0]] || null;
document.querySelectorAll = () => buttons;
document.createElementNS = (_, name) => new Node(name);
globalThis.document = document;
globalThis.window = {__energyLensTextBindingContext: {homeId, page: 'dashboard', generation: 1}};
function descendants(node, name) { return node.children.flatMap(child =>
  [...(child.localName === name ? [child] : []), ...descendants(child, name)]); }
window.__energyLensDashboardRequestedPeriod = 'day';
assert.equal(eval(scripts[0]), true);
assert.equal(svg.children.length, 1);
assert.equal(svg.attrs.viewBox, '0 0 320 200');
assert.equal(descendants(svg, 'line').length, 5);
assert.ok(Math.abs(Number(descendants(svg, 'rect').filter(x => x.attrs.class === 'el-useful-graph')[0].attrs.height) - 39.2) < .00001);
const [group, secondGroup] = descendants(svg, 'g').filter(x => x.attrs.role === 'button');
const tooltip = descendants(svg, 'g').find(x => x.attrs.class === 'el-chart-tooltip');
assert.equal(group.attrs['aria-label'], 'Sep 30, 2026. Useful + Waste: $0.90');
assert.equal(tooltip.attrs.visibility, 'hidden');
group.fire('pointerenter');
assert.equal(tooltip.attrs.visibility, 'visible');
assert.equal(descendants(tooltip, 'text')[1].textContent, 'Useful + Waste: $0.90');
group.fire('click');
assert.equal(group.attrs['aria-pressed'], 'true');
secondGroup.fire('pointerenter');
assert.equal(descendants(tooltip, 'text')[0].textContent, 'Oct 1, 2026');
assert.equal(descendants(tooltip, 'text')[1].textContent, 'Useful + Waste: $0.40');
secondGroup.fire('focus');
assert.equal(descendants(tooltip, 'text')[1].textContent, 'Useful + Waste: $0.40');
svg.fire('pointerleave');
assert.equal(tooltip.attrs.visibility, 'visible');
assert.equal(descendants(tooltip, 'text')[1].textContent, 'Useful + Waste: $0.90');
secondGroup.fire('click');
assert.equal(secondGroup.attrs['aria-pressed'], 'true');
assert.equal(descendants(tooltip, 'text')[1].textContent, 'Useful + Waste: $0.40');
secondGroup.fire('click');
assert.equal(tooltip.attrs.visibility, 'hidden');
group.fire('keydown', {key: 'Escape'});
assert.equal(tooltip.attrs.visibility, 'hidden');
group.fire('keydown', {key: 'Enter'});
assert.equal(tooltip.attrs.visibility, 'visible');
document.fire('click');
assert.equal(tooltip.attrs.visibility, 'hidden');
window.__energyLensDashboardRequestedPeriod = 'week';
assert.equal(eval(scripts[0]), false);
assert.equal(eval(scripts[1]), true);
assert.equal(document.listeners.click.size, 1);
assert.equal(svg.listeners.pointerleave.size, 1);
assert.equal(summaries.dashboard_text_026.textContent, '$0.70 Useful');
assert.equal(buttons[1].state['bg-white'], true);
const zero = descendants(svg, 'g').find(x => x.attrs.role === 'button');
assert.equal(descendants(zero, 'rect').filter(x => x.attrs.class === 'el-chart-hit').length, 1);
zero.fire('focus');
assert.equal(descendants(svg, 'g').find(x => x.attrs.class === 'el-chart-tooltip').attrs.visibility, 'visible');
window.__energyLensDashboardRequestedPeriod = 'month';
assert.equal(eval(scripts[2]), true);
assert.equal(document.listeners.click.size, 1);
assert.equal(svg.listeners.pointerleave.size, 1);
assert.equal(buttons[2].state['bg-white'], true);
const currentSummary = summaries.dashboard_text_026.textContent;
window.__energyLensTextBindingContext.homeId = 'other';
assert.equal(eval(scripts[0]), false);
assert.equal(summaries.dashboard_text_026.textContent, currentSummary);
''',
        file.path,
      ]);
      expect(result.exitCode, 0, reason: '${result.stdout}\n${result.stderr}');
    } finally {
      await file.delete();
    }
  });
}
