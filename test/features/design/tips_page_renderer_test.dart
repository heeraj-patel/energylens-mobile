import 'dart:convert';
import 'dart:io';

import 'package:energylens_mobile/core/cloud_api/cloud_programs.dart';
import 'package:energylens_mobile/core/cloud_api/cloud_recommendations.dart';
import 'package:energylens_mobile/features/design/design_page_bridge.dart';
import 'package:energylens_mobile/features/design/tips_domain_repository.dart';
import 'package:energylens_mobile/features/design/tips_page_renderer.dart';
import 'package:flutter_test/flutter_test.dart';

const home = '11111111-1111-4111-8111-111111111111';
const appliance = '22222222-2222-4222-8222-222222222222';
const applianceB = '44444444-4444-4444-8444-444444444444';
const applianceC = '55555555-5555-4555-8555-555555555555';
const applianceD = '66666666-6666-4666-8666-666666666666';

CloudRecommendation candidate(String next, String applianceId) =>
    CloudRecommendation(
      ruleId: 'general.gather_information',
      applianceId: applianceId,
      state: 'candidate',
      title: 'Gather details',
      explanation: 'Generic explanation.',
      nextQuestion: next,
      evidenceCount: 0,
      scenarioRefs: const [],
    );

CloudProgram program(
  String id,
  String title, {
  DateTime? expiresAt,
  DateTime? availabilityExpiresAt,
  String availability = 'unknown',
  List<String> reasons = const ['reviewed'],
}) => CloudProgram(
  id: id,
  title: title,
  administratorName: 'City utility',
  administratorKind: 'utility',
  benefitKind: 'rebate',
  benefitDisplay: 'Up to \$40',
  benefitTerms: const {},
  eligibilityTerms: const {},
  stackingTerms: const {},
  availabilityStatus: availability,
  status: 'unknown',
  reasons: reasons,
  sourceUrl: Uri.parse('https://utility.example/program/$id'),
  sourceSha256: 'a' * 64,
  reviewExpiresAt: expiresAt ?? DateTime.utc(2026, 12),
  availabilityExpiresAt: availabilityExpiresAt,
);

TipsDomainSnapshot snapshot(
  TipsPage page, [
  List<CloudRecommendation>? recommendations,
  List<CloudProgram>? programs,
  Map<String, String> names = const {appliance: 'Saved appliance'},
]) => TipsDomainSnapshot(
  homeId: home,
  page: page,
  programs: CloudProgramPage(
    programs:
        programs ??
        [program('one', 'First offer'), program('two', 'Second offer')],
    asOf: DateTime.utc(2026, 10),
    locationRequired: false,
    coverage: null,
  ),
  recommendations:
      recommendations ??
      const [
        CloudRecommendation(
          ruleId: 'computer.sleep_settings',
          applianceId: appliance,
          state: 'candidate',
          title: 'First action',
          explanation: 'Find usage information.',
          nextQuestion: 'hours_per_week',
          evidenceCount: 0,
          scenarioRefs: [],
        ),
        CloudRecommendation(
          ruleId: 'refrigerator.maintenance',
          applianceId: appliance,
          state: 'active',
          title: 'Second action',
          explanation: 'Review the manual.',
          nextQuestion: null,
          evidenceCount: 2,
          scenarioRefs: [],
          tipCategory: CloudRecommendationTipCategory.care,
        ),
        CloudRecommendation(
          ruleId: 'lighting.equivalent_bulb',
          applianceId: appliance,
          state: 'active',
          title: 'Third action',
          explanation: 'Review supported bulbs.',
          nextQuestion: null,
          evidenceCount: 2,
          scenarioRefs: [],
          tipCategory: CloudRecommendationTipCategory.upgrade,
        ),
      ],
  applianceNames: names,
  operatingEstimates: const [],
);

CloudRecommendation reviewedRecommendation(
  String amount, {
  String state = 'active',
  String ruleId = 'refrigerator.maintenance',
  String savingsBasis = 'reviewed_action_scenario',
  Uri? sourceUrl,
  CloudResearchTip? researchTip,
  CloudRecommendationTipCategory tipCategory =
      CloudRecommendationTipCategory.care,
}) => CloudRecommendation(
  ruleId: ruleId,
  applianceId: appliance,
  state: state,
  title: 'Supported action',
  explanation: 'Review the manual.',
  nextQuestion: null,
  evidenceCount: 3,
  scenarioRefs: const [
    {
      'id': '33333333-3333-4333-8333-333333333333',
      'kind': 'reviewed_action_scenario',
      'revision': 1,
    },
  ],
  savingsAmount: amount,
  savingsPeriod: 'year',
  savingsCurrency: 'USD',
  savingsBasis: savingsBasis,
  sourceUrl: sourceUrl,
  researchTip: researchTip,
  tipCategory: tipCategory,
);

void main() {
  test('monthly savings chip uses supported annual USD scenarios only', () {
    expect(
      TipsPageRenderer.savingsChipLabel(reviewedRecommendation('5.04')),
      'Save ~\$0.42/mo',
    );
    expect(
      TipsPageRenderer.savingsChipLabel(reviewedRecommendation('120')),
      'Save ~\$10/mo',
    );
    expect(
      TipsPageRenderer.savingsChipLabel(
        reviewedRecommendation('120', state: 'accepted'),
      ),
      'Save ~\$10/mo',
    );
    expect(
      TipsPageRenderer.savingsChipLabel(reviewedRecommendation('0.01')),
      isNull,
    );
    for (final state in ['completed', 'snoozed', 'dismissed', 'superseded']) {
      expect(
        TipsPageRenderer.savingsChipLabel(
          reviewedRecommendation('120', state: state),
        ),
        isNull,
        reason: '$state actions keep the card but omit the savings chip',
      );
    }
    expect(
      TipsPageRenderer.savingsChipLabel(
        reviewedRecommendation('120', savingsBasis: 'annual_energy'),
      ),
      isNull,
    );
  });

  test(
    'source rows keep order and fields, and reject stale page scope',
    () async {
      final recommendations = [
        snapshot(TipsPage.efficiency).recommendations[0],
        reviewedRecommendation(
          '5.04',
          sourceUrl: Uri.parse('https://manufacturer.example/eco-guide'),
        ),
        reviewedRecommendation(
          '0.01',
          ruleId: 'lighting.equivalent_bulb',
          tipCategory: CloudRecommendationTipCategory.upgrade,
        ),
      ];
      final scripts = {
        'programs': const TipsPageRenderer().script(
          const DesignPageTicket(home, 'perks_tips', 3),
          snapshot(TipsPage.perksTips),
          now: DateTime.utc(2026, 10),
        ),
        'tips': const TipsPageRenderer().script(
          const DesignPageTicket(home, 'tips_efficiency', 3),
          snapshot(TipsPage.efficiency, recommendations),
          applianceFuels: const {appliance: 'natural_gas'},
        ),
        'fuel': const TipsPageRenderer().script(
          const DesignPageTicket(home, 'tips_efficiency', 3),
          snapshot(
            TipsPage.efficiency,
            [
              candidate('confirm_model', appliance),
              candidate('add_gas_rate', applianceB),
              candidate('add_gas_rate', applianceC),
              candidate('hours_per_week', applianceD),
              reviewedRecommendation('120'),
            ],
            null,
            const {
              appliance: 'Saved appliance',
              applianceB: 'Range',
              applianceC: 'Heater',
              applianceD: 'Fan',
            },
          ),
          applianceFuels: const {
            appliance: 'electricity',
            applianceB: 'natural_gas',
            applianceC: 'propane',
          },
        ),
        'empty': const TipsPageRenderer().script(
          const DesignPageTicket(home, 'tips_care_upgrades', 3),
          snapshot(TipsPage.careUpgrades, const []),
        ),
        'care': const TipsPageRenderer().script(
          const DesignPageTicket(home, 'tips_care_upgrades', 3),
          snapshot(TipsPage.careUpgrades, recommendations),
        ),
        'research': const TipsPageRenderer().script(
          const DesignPageTicket(home, 'tips_care_upgrades', 3),
          snapshot(TipsPage.careUpgrades, [
            reviewedRecommendation(
              '5.04',
              researchTip: CloudResearchTip(
                sourceText: 'Clean the coils twice a year.',
                sourceUrl: Uri.parse('https://energy.example/fridge'),
              ),
            ),
            reviewedRecommendation('5.04', ruleId: 'lighting.equivalent_bulb'),
          ]),
        ),
        'researchOtherPage': const TipsPageRenderer().script(
          const DesignPageTicket(home, 'tips_efficiency', 3),
          snapshot(TipsPage.efficiency, [
            reviewedRecommendation(
              '5.04',
              researchTip: CloudResearchTip(
                sourceText: 'Clean the coils twice a year.',
                sourceUrl: Uri.parse('https://energy.example/fridge'),
              ),
            ),
          ]),
        ),
        'boundary': const TipsPageRenderer().script(
          const DesignPageTicket(home, 'perks_tips', 3),
          snapshot(TipsPage.perksTips, null, [
            program(
              'expired',
              'Expired promotion',
              expiresAt: DateTime.utc(2026, 10, 13, 12),
            ),
            program(
              'current',
              'Current promotion',
              expiresAt: DateTime.utc(2027),
            ),
            program(
              'availability-ended',
              'Ended promotion',
              expiresAt: DateTime.utc(2027),
              availabilityExpiresAt: DateTime.utc(2026, 10, 13, 12),
            ),
            program(
              'closed',
              'Closed promotion',
              availability: 'closed',
              expiresAt: DateTime.utc(2027),
            ),
          ]),
          now: DateTime.utc(2026, 10, 13, 12),
        ),
        'after': const TipsPageRenderer().script(
          const DesignPageTicket(home, 'perks_tips', 3),
          snapshot(TipsPage.perksTips, null, [
            program(
              'expired',
              'Expired promotion',
              expiresAt: DateTime.utc(2026, 10, 13, 12),
            ),
            program(
              'current',
              'Current promotion',
              expiresAt: DateTime.utc(2027),
            ),
          ]),
          now: DateTime.utc(2026, 10, 13, 12, 0, 1),
        ),
        'mounted': const TipsPageRenderer().script(
          const DesignPageTicket(home, 'perks_tips', 3),
          snapshot(TipsPage.perksTips, null, [
            program(
              'ending',
              'Ending promotion',
              expiresAt: DateTime.utc(2026, 10, 13, 12),
            ),
            program(
              'current',
              'Current promotion',
              expiresAt: DateTime.utc(2027),
            ),
          ]),
          now: DateTime.utc(2026, 10, 13, 11, 59, 59),
        ),
      };
      final dir = Directory.systemTemp.createTempSync('tips_renderer');
      addTearDown(() => dir.deleteSync(recursive: true));
      final scriptsFile = File('${dir.path}/scripts.json')
        ..writeAsStringSync(jsonEncode(scripts));
      final runner = File('${dir.path}/run.js')
        ..writeAsStringSync(r'''
const assert = require('node:assert/strict');
const vm = require('node:vm');
const scripts = JSON.parse(require('node:fs').readFileSync(process.argv[2], 'utf8'));
class Element {
  constructor(tag) { this.tag = tag; this.children = []; this.attributes = {}; this.events = []; this.textContent = ''; this.className = ''; this.style = {}; }
  append(...nodes) { for (const node of nodes) { node.parent = this; this.children.push(node); } }
  replaceChildren() { this.children = []; }
  setAttribute(key, value) { this.attributes[key] = value; }
  dispatchEvent(event) { this.events.push(event.type); }
  after(node) { node.parent = null; node.sibling = true; this.siblings.push(node); }
  remove() { if (this.parent) this.parent.children = this.parent.children.filter(child => child !== this); this.parent = null; if (this.sibling) this.siblings.splice(this.siblings.indexOf(this), 1); }
  get isConnected() { return !!this.parent; }
}
function render(page, script, generation = 3, startMs = Date.UTC(2026, 9, 13, 11, 59, 59)) {
  const mount = new Element('mount');
  mount.siblings = Element.prototype.siblings = [];
  const packaged = new Element('packaged-example');
  const timers = [];
  let nowMs = startMs;
  const document = {
    getElementById: id => id === ({perks_tips:'el-live-programs', tips_efficiency:'el-live-tips', tips_care_upgrades:'el-live-care'})[page] ? mount : null,
    createElement: tag => new Element(tag),
    querySelectorAll: () => mount.siblings.filter(node => Object.hasOwn(node.attributes, 'data-el-live-examples')),
  };
  const context = {document, Event: class { constructor(type) { this.type = type; } }, Date: {now: () => nowMs},
    setTimeout: (fn, delay) => timers.push({fn, at: nowMs + delay}),
    window: {__energyLensTextBindingContext: {homeId:'11111111-1111-4111-8111-111111111111', page, generation}}};
  const accepted = vm.runInNewContext(script, context);
  return {accepted, mount, packaged, siblings: mount.siblings, advanceTo: target => {
    nowMs = target;
    for (const timer of timers.splice(0).filter(item => item.at <= target)) timer.fn();
  }};
}
const programs = render('perks_tips', scripts.programs);
assert.equal(programs.accepted, true);
const offers = programs.mount.children[1].children;
assert.deepEqual(offers.map(row => row.children[0].children[0].textContent), ['First offer', 'Second offer']);
assert.equal(offers[0].children[0].children[1].textContent, 'City utility');
assert.equal(offers[0].children[0].children[2].textContent, 'Up to $40');
assert.equal(offers[0].children[0].href, 'https://utility.example/program/one');
const mounted = render('perks_tips', scripts.mounted);
assert.deepEqual(mounted.mount.children[1].children.map(row => row.children[0].children[0].textContent), ['Ending promotion', 'Current promotion']);
mounted.advanceTo(Date.UTC(2026, 9, 13, 12));
assert.deepEqual(mounted.mount.children[1].children.map(row => row.children[0].children[0].textContent), ['Current promotion']);
for (const key of ['boundary', 'after']) {
  const rendered = render('perks_tips', scripts[key]);
  assert.equal(rendered.accepted, true);
  assert.deepEqual(rendered.mount.children[1].children.map(row => row.children[0].children[0].textContent), ['Current promotion']);
  assert.equal(rendered.packaged.tag, 'packaged-example');
}
const text = node => node.textContent || node.children[0].textContent;
const tips = render('tips_efficiency', scripts.tips);
assert.equal(tips.mount.children[0].textContent, 'Your devices');
assert.deepEqual(tips.siblings.map(node => node.textContent), ['Examples']);
const groups = tips.mount.children.slice(1);
assert.equal(groups.length, 1);
assert.ok(Object.hasOwn(groups[0].attributes, 'data-el-tip-group'));
const header = groups[0].children[0];
assert.equal(header.children[0].children[1].textContent, 'Saved appliance');
assert.equal(header.children[1].textContent, 'Save ~$0.42/mo');
const efficiencyCards = groups[0].children[1].children;
assert.deepEqual(efficiencyCards.map(card => text(card.children[0].children[0])), ['First action', 'Supported action', 'Supported action']);
assert.ok(efficiencyCards.every(card => Object.hasOwn(card.attributes, 'data-el-tip-item')));
assert.equal(efficiencyCards[0].children[0].children[1].textContent, 'Find usage information.');
assert.deepEqual(tips.mount.events, ['energylens:tips-changed']);
assert.equal(efficiencyCards[1].children[0].children[0].children[0].href, 'https://manufacturer.example/eco-guide');
assert.equal(efficiencyCards[0].children[0].children.some(child => child.textContent.startsWith('Save ~')), false);
assert.equal(efficiencyCards[1].children[0].children[2].textContent, 'Save ~$0.42/mo');
assert.match(efficiencyCards[1].children[0].children[2].className, /bg-secondary-container/);
assert.equal(efficiencyCards[2].children[0].children.some(child => child.textContent.startsWith('Save ~')), false);
tips.mount.replaceChildren();
const rerender = render('tips_efficiency', scripts.tips);
assert.equal(rerender.siblings.length, 1);
const fuel = render('tips_efficiency', scripts.fuel);
const fuelGroups = fuel.mount.children.slice(1);
assert.deepEqual(fuelGroups.map(group => group.children[0].children[0].children[1].textContent), ['Saved appliance', 'Range', 'Heater', 'Fan']);
assert.deepEqual(fuelGroups.map(group => group.children[0].children[1] && group.children[0].children[1].textContent), ['Save ~$10/mo', 'Gas', 'Propane', undefined]);
const detail = group => group.children[1].children[0].children[0].children[1].textContent;
assert.equal(detail(fuelGroups[0]), 'Add the model number to get advice for this Saved appliance.');
assert.equal(detail(fuelGroups[1]), 'Add your gas rate in Settings to see costs.');
assert.equal(detail(fuelGroups[3]), 'Generic explanation.');
const electric = render('tips_efficiency', scripts.fuel.replace('"Save ~$10/mo"', 'null'));
assert.equal(electric.mount.children[1].children[0].children[1].textContent, 'Electric');
const care = render('tips_care_upgrades', scripts.care);
const careGroup = care.mount.children[1];
assert.equal(care.mount.children[0].textContent, 'Your devices');
assert.deepEqual(careGroup.children[1].children.map(card => text(card.children[0].children[0])), ['Supported action', 'Supported action']);
assert.equal(careGroup.children[1].children[0].children[0].children[2].textContent, 'Save ~$0.42/mo');
assert.ok(careGroup.children[1].children.every(card => Object.hasOwn(card.attributes, 'data-el-tip-item')));
assert.deepEqual(care.mount.events, ['energylens:tips-changed']);
const research = render('tips_care_upgrades', scripts.research);
const researchCards = research.mount.children[1].children[1].children;
const researchLine = researchCards[0].children[0].children.find(child => Object.hasOwn(child.attributes, 'data-el-research-source'));
assert.equal(researchLine.textContent, '"Clean the coils twice a year." (energy.example) ');
assert.equal(researchLine.children[0].textContent, 'Source');
assert.equal(researchLine.children[0].href, 'https://energy.example/fridge');
assert.equal(researchCards[1].children[0].children.some(child => Object.hasOwn(child.attributes, 'data-el-research-source')), false);
const researchElsewhere = render('tips_efficiency', scripts.researchOtherPage);
const hasResearch = node => Object.hasOwn(node.attributes, 'data-el-research-source') || node.children.some(hasResearch);
assert.equal(researchElsewhere.mount.children.some(hasResearch), false);
const empty = render('tips_care_upgrades', scripts.empty);
assert.equal(empty.mount.children.length, 0);
assert.equal(empty.siblings.length, 0);
assert.deepEqual(empty.mount.events, ['energylens:tips-changed']);
assert.equal(render('perks_tips', scripts.programs, 4).accepted, false);
assert.equal(render('tips_efficiency', scripts.programs).accepted, false);
''');
      final result = await Process.run('node', [runner.path, scriptsFile.path]);
      expect(result.exitCode, 0, reason: '${result.stdout}\n${result.stderr}');
    },
  );

  test('packaged Tips pages mount live groups before the demo groups', () {
    for (final entry in {
      'tips_care_upgrades': 'el-live-care',
      'tips_efficiency': 'el-live-tips',
    }.entries) {
      final html = File('assets/design_pages/${entry.key}/app.html')
          .readAsStringSync();
      final mount = html.indexOf('id="${entry.value}"');
      final firstDemo = html.indexOf('<div data-el-tip-group');
      expect(mount, greaterThan(0), reason: entry.key);
      expect(mount, lessThan(firstDemo), reason: entry.key);
      expect('id="${entry.value}"'.allMatches(html), hasLength(1));
    }
  });

  group('Datawiz program offers', () {
    List<dynamic> payloadPrograms(CloudProgramPage page, DateTime now) {
      final script = const TipsPageRenderer().script(
        const DesignPageTicket(home, 'perks_tips', 3),
        TipsDomainSnapshot(
          homeId: home,
          page: TipsPage.perksTips,
          programs: page,
          recommendations: const [],
          applianceNames: const {},
          operatingEstimates: const [],
        ),
        now: now,
      );
      final line = script
          .split('\n')
          .firstWhere((l) => l.startsWith('  const payload = '));
      final json = line.substring('  const payload = '.length, line.length - 1);
      return (jsonDecode(json) as Map)['programs'] as List;
    }

    CloudProgramOffer offer(String id, String name, String url) =>
        CloudProgramOffer(
          id: 'research:program:$id',
          title: name,
          administratorName: 'Austin Energy',
          sourceUrl: Uri.parse(url),
          expiresAt: null,
        );

    CloudProgramPage page(List<CloudProgramOffer> offers) => CloudProgramPage(
      programs: [program('one', 'First offer')],
      offers: offers,
      asOf: DateTime.utc(2026, 10),
      locationRequired: false,
      coverage: null,
    );

    test('offers become cards with empty benefit after reviewed programs', () {
      final rows = payloadPrograms(
        page([
          offer(
            'saver',
            'Power Saver',
            'https://austinenergy.com/energy-efficiency/rebates-incentives/residential/ps-volunteer',
          ),
          offer(
            'pp',
            'Power Partner Thermostat',
            'https://austinenergy.com/PowerPartner',
          ),
        ]),
        DateTime.utc(2026, 10),
      );
      expect(rows.map((r) => r['title']), [
        'First offer',
        'Power Saver',
        'Power Partner Thermostat',
      ]);
      expect(rows[0]['benefit'], 'Up to \$40');
      expect(rows[1]['benefit'], '');
      expect(rows[1]['administrator'], 'Austin Energy');
      expect(rows[2]['url'], 'https://austinenergy.com/PowerPartner');
      expect(
        rows[2]['expiresAt'],
        greaterThan(DateTime.utc(2100).millisecondsSinceEpoch),
      );
    });

    test('a fact with its own past expiry is omitted', () {
      final expired = CloudProgramOffer(
        id: 'research:x',
        title: 'Old',
        administratorName: 'Austin Energy',
        sourceUrl: Uri.parse('https://austinenergy.com/old'),
        expiresAt: DateTime.utc(2026, 9),
      );
      expect(
        payloadPrograms(page([expired]), DateTime.utc(2026, 10)),
        hasLength(1),
      );
    });

    test('no offers leaves the payload unchanged', () {
      expect(
        payloadPrograms(page(const []), DateTime.utc(2026, 10)),
        hasLength(1),
      );
    });
  });
}
