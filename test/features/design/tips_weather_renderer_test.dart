import 'dart:convert';
import 'dart:io';

import 'package:energylens_mobile/core/cloud_api/cloud_faq.dart';
import 'package:energylens_mobile/core/cloud_api/cloud_recommendations.dart';
import 'package:energylens_mobile/features/design/design_page_bridge.dart';
import 'package:energylens_mobile/features/design/tips_domain_repository.dart';
import 'package:energylens_mobile/features/design/tips_page_renderer.dart';
import 'package:flutter_test/flutter_test.dart';

const home = '11111111-1111-4111-8111-111111111111';
const appliance = '22222222-2222-4222-8222-222222222222';

CloudResearchTip tip(String text, [String url = 'https://www.pge.com/tips']) =>
    CloudResearchTip(sourceText: text, sourceUrl: Uri.parse(url));

CloudWeatherAlert alert(String event, DateTime ends) => CloudWeatherAlert(
  event: event,
  headline: null,
  startsAt: ends.subtract(const Duration(hours: 6)),
  endsAt: ends,
  sourceUrl: Uri.parse('https://alerts.example/a'),
  evidence: const CloudFaqEvidence(
    '33333333-3333-4333-8333-333333333333',
    'weather_alert',
    1,
  ),
);

CloudWeather weather({
  bool available = true,
  String provider = 'nws',
  List<CloudWeatherAlert> alerts = const [],
  List<CloudWeatherHomeTip>? homeTips,
}) => CloudWeather(
  available: available,
  reason: available ? null : 'provider_unavailable',
  provider: provider,
  attribution: null,
  alerts: alerts,
  runs: const [CloudWeatherRun(kind: 'hot', days: 12, lastDay: '2026-10-22')],
  homeTips:
      homeTips ??
      [
        CloudWeatherHomeTip(
          tip: tip('Close blinds during the day.'),
          trigger: 'hot_run',
        ),
      ],
);

CloudRecommendation deviceTip(
  CloudWeatherContext? context, {
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
  weatherContext: context,
);

TipsDomainSnapshot snapshot(
  TipsPage page, {
  CloudWeather? weather,
  List<CloudRecommendation> recommendations = const [],
}) => TipsDomainSnapshot(
  homeId: home,
  page: page,
  programs: null,
  recommendations: recommendations,
  applianceNames: const {appliance: 'Air conditioner'},
  operatingEstimates: const [],
  weather: weather,
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
    getElementById: id => id === entry.mountId ? mount : null,
    createElement: tag => new Element(tag),
    querySelectorAll: () => [],
  };
  const context = {document, Event: class { constructor(type) { this.type = type; } }, Date: {now: () => 0},
    setTimeout: () => 0,
    window: {__energyLensTextBindingContext: {homeId: '11111111-1111-4111-8111-111111111111', page: entry.page, generation: 3}}};
  const accepted = vm.runInNewContext(entry.script, context);
  result[name] = {accepted, nodes: flat(mount)};
}
process.stdout.write(JSON.stringify(result));
''';

Future<Map<String, List<Map<String, dynamic>>>> render(
  Map<String, TipsDomainSnapshot> cases,
) async {
  final dir = Directory.systemTemp.createTempSync('tips_weather');
  addTearDown(() => dir.deleteSync(recursive: true));
  final scripts = {
    for (final entry in cases.entries)
      entry.key: {
        'page': switch (entry.value.page) {
          TipsPage.perksTips => 'perks_tips',
          TipsPage.efficiency => 'tips_efficiency',
          TipsPage.careUpgrades => 'tips_care_upgrades',
        },
        'mountId': switch (entry.value.page) {
          TipsPage.perksTips => 'el-live-programs',
          TipsPage.efficiency => 'el-live-tips',
          TipsPage.careUpgrades => 'el-live-care',
        },
        'script': const TipsPageRenderer().script(
          DesignPageTicket(home, switch (entry.value.page) {
            TipsPage.perksTips => 'perks_tips',
            TipsPage.efficiency => 'tips_efficiency',
            TipsPage.careUpgrades => 'tips_care_upgrades',
          }, 3),
          entry.value,
        ),
      },
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

void main() {
  const cost = CloudWeatherContext(
    trigger: 'hot_run',
    measuredUse: false,
    touSavingPerKwh: '0.083400',
    currency: 'USD',
    peakStartLocal: '16:00',
    peakEndLocal: '21:30',
  );

  test('chip labels cover each trigger and unknown triggers get none', () {
    String? chip(String trigger) => TipsPageRenderer.weatherChip(
      CloudWeatherContext(trigger: trigger, measuredUse: true),
    );
    expect(chip('heat_alert'), 'Heat alert');
    expect(chip('cold_alert'), 'Cold alert');
    expect(chip('hot_run'), 'Hot spell');
    expect(chip('cold_run'), 'Cold spell');
    expect(chip('other'), isNull);
    expect(TipsPageRenderer.weatherChip(null), isNull);
  });

  test('cost line formats the exact approved sentence', () {
    expect(
      TipsPageRenderer.weatherCostLine(cost),
      'On your plan, each kWh moved out of 4 PM-9:30 PM saves \$0.0834.',
    );
    expect(
      TipsPageRenderer.weatherCostLine(
        const CloudWeatherContext(
          trigger: 'hot_run',
          measuredUse: true,
          touSavingPerKwh: '0.1',
          currency: 'USD',
          peakStartLocal: '00:00',
          peakEndLocal: '12:00',
        ),
      ),
      'On your plan, each kWh moved out of 12 AM-12 PM saves \$0.10.',
    );
    expect(
      TipsPageRenderer.weatherCostLine(
        const CloudWeatherContext(trigger: 'hot_run', measuredUse: true),
      ),
      isNull,
    );
  });

  test('alert line capitalises only the first letter and ends locally', () {
    final ends = DateTime.utc(2026, 10, 24, 3, 5);
    final local = ends.toLocal();
    final hour = local.hour % 12 == 0 ? 12 : local.hour % 12;
    final expectedWhen =
        '${const ['Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun', 'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec'][local.month - 1]} '
        '${local.day}, $hour:${local.minute.toString().padLeft(2, '0')} '
        '${local.hour < 12 ? 'AM' : 'PM'}';
    expect(
      TipsPageRenderer.weatherAlertLine(alert('heat warning', ends)),
      'Heat warning until $expectedWhen',
    );
    expect(
      TipsPageRenderer.weatherAlertLine(alert('Extreme Heat Warning', ends)),
      'Extreme Heat Warning until $expectedWhen',
    );
  });

  test('home card, cost line, alerts and attribution render', () async {
    final ends = DateTime.utc(2026, 10, 24, 3);
    final out = await render({
      'us': snapshot(
        TipsPage.efficiency,
        weather: weather(alerts: [alert('Heat Advisory', ends)]),
        recommendations: [deviceTip(cost)],
      ),
      'ca': snapshot(
        TipsPage.efficiency,
        weather: weather(
          provider: 'eccc',
          alerts: [alert('heat warning', ends)],
        ),
      ),
      'caNoAlert': snapshot(
        TipsPage.efficiency,
        weather: weather(provider: 'eccc'),
      ),
      'alertOnly': snapshot(
        TipsPage.efficiency,
        weather: weather(
          alerts: [alert('Heat Advisory', ends)],
          homeTips: const [],
        ),
        recommendations: [deviceTip(null)],
      ),
      'unavailable': snapshot(
        TipsPage.efficiency,
        weather: weather(available: false),
        recommendations: [deviceTip(null)],
      ),
      'absent': snapshot(
        TipsPage.efficiency,
        recommendations: [deviceTip(null)],
      ),
    });

    final us = texts(out['us']!);
    expect(us, contains('Your home'));
    expect(us, contains('"Close blinds during the day."'));
    expect(us, contains('(www.pge.com) '));
    expect(us.any((t) => t.startsWith('Heat Advisory until ')), isTrue);
    expect(us, isNot(contains('Hot spell')));
    expect(hasAttr(out['us']!, 'data-el-weather-trigger'), isFalse);
    expect(
      us,
      contains(
        'On your plan, each kWh moved out of 4 PM-9:30 PM saves \$0.0834.',
      ),
    );
    expect(us, contains('"Pre-cool before the peak."'));
    expect(us, contains('(www.sce.com) '));
    expect(us.where((t) => t == 'Source'), hasLength(3));
    expect(us.any((t) => t.contains('days in a row')), isFalse);
    expect(us.any((t) => t.contains('No measured use')), isFalse);
    expect(
      us,
      isNot(contains('Data Source: Environment and Climate Change Canada')),
    );
    expect(us.indexOf('Your home') < us.indexOf('Air conditioner'), isTrue);

    final ca = texts(out['ca']!);
    expect(ca.any((t) => t.startsWith('Heat warning until ')), isTrue);
    expect(ca, contains('Data Source: Environment and Climate Change Canada'));
    expect(
      texts(out['caNoAlert']!),
      isNot(contains('Data Source: Environment and Climate Change Canada')),
    );

    for (final key in ['alertOnly', 'unavailable', 'absent']) {
      final nodes = out[key]!;
      expect(texts(nodes), isNot(contains('Your home')), reason: key);
      expect(hasAttr(nodes, 'data-el-weather-alert'), isFalse, reason: key);
      expect(hasAttr(nodes, 'data-el-weather-card'), isFalse, reason: key);
    }
    expect(texts(out['alertOnly']!), contains('Air conditioner'));
    expect(texts(out['absent']!), contains('Pre-cool the home'));
  });

  test('every trigger keeps device advice without a metadata chip', () async {
    final cases = {
      for (final trigger in ['heat_alert', 'cold_alert', 'hot_run', 'cold_run'])
        trigger: snapshot(
          TipsPage.efficiency,
          recommendations: [
            deviceTip(
              CloudWeatherContext(trigger: trigger, measuredUse: false),
            ),
          ],
        ),
    };
    final out = await render(cases);
    const labels = {
      'heat_alert': 'Heat alert',
      'cold_alert': 'Cold alert',
      'hot_run': 'Hot spell',
      'cold_run': 'Cold spell',
    };
    for (final entry in labels.entries) {
      final nodes = out[entry.key]!;
      expect(texts(nodes), isNot(contains(entry.value)), reason: entry.key);
      expect(texts(nodes), contains('Pre-cool the home'), reason: entry.key);
      expect(hasAttr(nodes, 'data-el-weather-trigger'), isFalse);
      expect(hasAttr(nodes, 'data-el-weather-cost'), isFalse);
      expect(texts(nodes).any((t) => t.contains('No measured use')), isFalse);
    }
  });

  test('weather card is not sent to the other Tips pages', () {
    final script = const TipsPageRenderer().script(
      const DesignPageTicket(home, 'perks_tips', 3),
      snapshot(TipsPage.perksTips, weather: weather()),
    );
    expect(script, contains('"weather":null'));
  });

  test('empty article feeds show the approved empty state', () async {
    final out = await render({
      'programs': snapshot(TipsPage.perksTips),
      'general': snapshot(TipsPage.efficiency),
      'care': snapshot(TipsPage.careUpgrades),
      'populated': snapshot(
        TipsPage.efficiency,
        recommendations: [deviceTip(null)],
      ),
    });

    for (final key in ['programs', 'general']) {
      expect(
        texts(out[key]!),
        contains(
          'No relevant information available to display. Check back later.',
        ),
        reason: key,
      );
      expect(hasAttr(out[key]!, 'data-el-empty-articles'), isTrue, reason: key);
    }
    expect(
      texts(out['care']!),
      isNot(
        contains(
          'No relevant information available to display. Check back later.',
        ),
      ),
    );
    expect(hasAttr(out['care']!, 'data-el-empty-articles'), isFalse);
    expect(
      texts(out['populated']!),
      isNot(
        contains(
          'No relevant information available to display. Check back later.',
        ),
      ),
    );
  });
}
