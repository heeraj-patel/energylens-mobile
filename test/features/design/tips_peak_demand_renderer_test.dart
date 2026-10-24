import 'dart:convert';
import 'dart:io';

import 'package:energylens_mobile/core/cloud_api/cloud_recommendations.dart';
import 'package:energylens_mobile/features/design/design_page_bridge.dart';
import 'package:energylens_mobile/features/design/tips_domain_repository.dart';
import 'package:energylens_mobile/features/design/tips_page_renderer.dart';
import 'package:flutter_test/flutter_test.dart';

const home = '11111111-1111-4111-8111-111111111111';
const appliance = '22222222-2222-4222-8222-222222222222';

CloudResearchTip tip(String text, [String url = 'https://www.pge.com/tips']) =>
    CloudResearchTip(sourceText: text, sourceUrl: Uri.parse(url));

CloudRecommendation deviceTip(
  String? peak, {
  String rule = 'air_conditioner.pre_cool',
}) => CloudRecommendation(
  ruleId: rule,
  applianceId: appliance,
  state: 'active',
  title: 'Pre-cool the home',
  explanation: 'Review the guidance.',
  nextQuestion: null,
  evidenceCount: 1,
  scenarioRefs: const [],
  researchTip: tip('Pre-cool before the peak.', 'https://www.sce.com/x'),
  peakDemandContext: peak,
);

TipsDomainSnapshot snapshot(
  TipsPage page, {
  CloudWeather? weather,
  CloudPeakDemand? peakDemand,
  List<CloudRecommendation> recommendations = const [],
}) => TipsDomainSnapshot(
  homeId: home,
  page: page,
  programs: null,
  recommendations: recommendations,
  applianceNames: const {appliance: 'Air conditioner'},
  operatingEstimates: const [],
  weather: weather,
  peakDemand: peakDemand,
);

const _runner = r'''
const vm = require('node:vm');
const scripts = JSON.parse(require('node:fs').readFileSync(process.argv[2], 'utf8'));
class Element {
  constructor(tag) { this.tag = tag; this.children = []; this.attributes = {}; this.textContent = ''; this.className = ''; this.style = {}; }
  append(...nodes) { for (const node of nodes) this.children.push(node); }
  replaceChildren() { this.children = []; }
  setAttribute(key, value) { this.attributes[key] = value; }
  dispatchEvent() {}
  after() {}
  remove() {}
}
const flat = (node, out = []) => {
  out.push({tag: node.tag, attrs: Object.keys(node.attributes), text: node.textContent, href: node.href || null});
  node.children.forEach(child => flat(child, out));
  return out;
};
const result = {};
for (const [name, entry] of Object.entries(scripts)) {
  const mount = new Element('mount');
  const document = {
    getElementById: id => id === 'el-live-tips' ? mount : null,
    createElement: tag => new Element(tag),
    querySelectorAll: () => [],
  };
  const context = {document, Event: class { constructor(type) { this.type = type; } }, Date: {now: () => 0},
    setTimeout: () => 0,
    window: {__energyLensTextBindingContext: {homeId: '11111111-1111-4111-8111-111111111111', page: 'tips_efficiency', generation: 3}}};
  const accepted = vm.runInNewContext(entry, context);
  result[name] = {accepted, nodes: flat(mount)};
}
process.stdout.write(JSON.stringify(result));
''';

Future<Map<String, List<Map<String, dynamic>>>> render(
  Map<String, TipsDomainSnapshot> cases,
) async {
  final dir = Directory.systemTemp.createTempSync('tips_peak');
  addTearDown(() => dir.deleteSync(recursive: true));
  final scripts = {
    for (final entry in cases.entries)
      entry.key: const TipsPageRenderer().script(
        const DesignPageTicket(home, 'tips_efficiency', 3),
        entry.value,
      ),
  };
  final scriptsFile = File('${dir.path}/scripts.json')
    ..writeAsStringSync(jsonEncode(scripts));
  final runnerFile = File('${dir.path}/run.js')..writeAsStringSync(_runner);
  final run = await Process.run('node', [runnerFile.path, scriptsFile.path]);
  expect(run.exitCode, 0, reason: '${run.stdout}\n${run.stderr}');
  final decoded = jsonDecode(run.stdout as String) as Map<String, dynamic>;
  return {
    for (final entry in decoded.entries)
      entry.key: [
        for (final node
            in (entry.value as Map<String, dynamic>)['nodes'] as List)
          node as Map<String, dynamic>,
      ],
  };
}

List<String> texts(List<Map<String, dynamic>> nodes) => [
  for (final node in nodes) node['text'] as String,
];

bool hasAttr(List<Map<String, dynamic>> nodes, String attr) =>
    nodes.any((node) => (node['attrs'] as List).contains(attr));

CloudPeakDemand peak([List<CloudResearchTip>? tips]) => CloudPeakDemand(
  windowLocal: '13:00-19:00',
  sourceUrl: Uri.parse('https://austinenergy.com/ps'),
  homeTips:
      tips ??
      [
        tip('Use fans.', 'https://austinenergy.com/ps'),
        tip('Delay the dryer.', 'https://austinenergy.com/ps'),
      ],
);

void main() {
  test('card and tips render without a metadata chip', () async {
    final out = await render({
      'on': snapshot(
        TipsPage.efficiency,
        peakDemand: peak(),
        recommendations: [deviceTip('peak_demand_day')],
      ),
      'off': snapshot(TipsPage.efficiency, recommendations: [deviceTip(null)]),
    });
    final on = texts(out['on']!);
    expect(on, contains('Peak demand days'));
    expect(
      on,
      contains(
        'Austin Energy tells selected customers about Peak Energy Demand Days '
        'by email, text or call. EnergyLens cannot see which days they are.',
      ),
    );
    expect(
      on,
      contains(
        'On those days, Austin Energy asks customers to save energy from 1 to 7 pm.',
      ),
    );
    expect(on, contains('"Use fans."'));
    expect(on, contains('"Delay the dryer."'));
    expect(on.where((t) => t == '(austinenergy.com) '), hasLength(2));
    expect(on, isNot(contains('Peak demand day')));
    expect(hasAttr(out['on']!, 'data-el-peak-demand-trigger'), isFalse);
    expect(on.where((t) => t == 'Source'), hasLength(3));
    expect(on.indexOf('Peak demand days') < on.indexOf('Your devices'), isTrue);
    expect(on.any((t) => t.contains(r'$')), isFalse);

    final off = out['off']!;
    expect(texts(off), isNot(contains('Peak demand days')));
    expect(texts(off), isNot(contains('Peak demand day')));
    expect(hasAttr(off, 'data-el-peak-demand-card'), isFalse);
    expect(hasAttr(off, 'data-el-peak-demand-trigger'), isFalse);
    expect(texts(off), contains('Pre-cool the home'));
  });

  test('card follows the weather card and works without device tips', () async {
    final out = await render({
      'both': snapshot(
        TipsPage.efficiency,
        peakDemand: peak(),
        weather: CloudWeather(
          available: true,
          reason: null,
          provider: 'nws',
          attribution: null,
          alerts: const [],
          runs: const [],
          homeTips: [
            CloudWeatherHomeTip(tip: tip('Close blinds.'), trigger: 'hot_run'),
          ],
        ),
      ),
    });
    final t = texts(out['both']!);
    expect(t.indexOf('Your home') < t.indexOf('Peak demand days'), isTrue);
  });

  test('peak demand card is not sent to the other Tips pages', () {
    final script = const TipsPageRenderer().script(
      const DesignPageTicket(home, 'perks_tips', 3),
      snapshot(TipsPage.perksTips, peakDemand: peak()),
    );
    expect(script, contains('"peakDemand":null'));
  });
}
