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
  applianceNames: const {appliance: 'Saved appliance'},
  operatingEstimates: const [],
  usageFactsByAppliance: const {},
  factsIncomplete: false,
);

CloudRecommendation reviewedRecommendation(
  String amount, {
  String state = 'active',
  String ruleId = 'refrigerator.maintenance',
  String savingsBasis = 'reviewed_action_scenario',
  Uri? sourceUrl,
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
        ),
        'care': const TipsPageRenderer().script(
          const DesignPageTicket(home, 'tips_care_upgrades', 3),
          snapshot(TipsPage.careUpgrades, recommendations),
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
      final result = await Process.run('node', [
        '-e',
        r'''
const assert = require('node:assert/strict');
const vm = require('node:vm');
const scripts = JSON.parse(process.argv[1]);
class Element {
  constructor(tag) { this.tag = tag; this.children = []; this.attributes = {}; this.events = []; this.textContent = ''; this.className = ''; this.style = {}; }
  append(node) { node.parent = this; this.children.push(node); }
  replaceChildren() { this.children = []; }
  setAttribute(key, value) { this.attributes[key] = value; }
  dispatchEvent(event) { this.events.push(event.type); }
  remove() { if (this.parent) this.parent.children = this.parent.children.filter(child => child !== this); this.parent = null; }
  get isConnected() { return !!this.parent; }
}
function render(page, script, generation = 3, startMs = Date.UTC(2026, 9, 13, 11, 59, 59)) {
  const mount = new Element('mount');
  const packaged = new Element('packaged-example');
  const timers = [];
  let nowMs = startMs;
  const document = {
    getElementById: id => id === ({perks_tips:'el-live-programs', tips_efficiency:'el-live-tips', tips_care_upgrades:'el-live-care'})[page] ? mount : null,
    createElement: tag => new Element(tag),
  };
  const context = {document, Event: class { constructor(type) { this.type = type; } }, Date: {now: () => nowMs},
    setTimeout: (fn, delay) => timers.push({fn, at: nowMs + delay}),
    window: {__energyLensTextBindingContext: {homeId:'11111111-1111-4111-8111-111111111111', page, generation}}};
  const accepted = vm.runInNewContext(script, context);
  return {accepted, mount, packaged, advanceTo: target => {
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
const tips = render('tips_efficiency', scripts.tips);
assert.deepEqual(tips.mount.children[1].children.map(row => row.children[0].children[0].textContent || row.children[0].children[0].children[0].textContent), ['First action', 'Supported action', 'Supported action']);
assert.equal(tips.mount.children[1].children[0].children[0].children[1].textContent, 'Saved appliance');
assert.equal(tips.mount.children[1].children[0].children[0].children[2].textContent, 'Find usage information.');
const efficiencyCards = tips.mount.children[1].children;
assert.equal(efficiencyCards.length, 3);
assert.ok(efficiencyCards.every(card => Object.hasOwn(card.attributes, 'data-el-tip-item')));
assert.deepEqual(tips.mount.events, ['energylens:tips-changed']);
assert.equal(efficiencyCards[1].children[0].tag, 'div');
assert.equal(efficiencyCards[1].children[0].children[0].children[0].href, 'https://manufacturer.example/eco-guide');
assert.equal(efficiencyCards[1].children[0].children[0].children[0].textContent, 'Supported action');
assert.equal(efficiencyCards[0].children[0].children[0].children.length, 0);
assert.equal(efficiencyCards[0].children[0].children.some(child => child.textContent.startsWith('Save ~')), false);
assert.equal(efficiencyCards[1].children[0].children[3].textContent, 'Save ~$0.42/mo');
assert.match(efficiencyCards[1].children[0].children[3].className, /bg-secondary-container/);
assert.equal(efficiencyCards[2].children[0].children.some(child => child.textContent.startsWith('Save ~')), false);
const care = render('tips_care_upgrades', scripts.care);
assert.deepEqual(care.mount.children[1].children.map(row => row.children[0].children[0].textContent || row.children[0].children[0].children[0].textContent), ['Supported action', 'Supported action']);
assert.equal(care.mount.children[1].children[0].children[0].children[3].textContent, 'Save ~$0.42/mo');
assert.equal(care.mount.children[1].children.length, 2);
assert.ok(care.mount.children[1].children.every(card => Object.hasOwn(card.attributes, 'data-el-tip-item')));
assert.deepEqual(care.mount.events, ['energylens:tips-changed']);
assert.equal(render('perks_tips', scripts.programs, 4).accepted, false);
assert.equal(render('tips_efficiency', scripts.programs).accepted, false);
''',
        jsonEncode(scripts),
      ]);
      expect(result.exitCode, 0, reason: '${result.stdout}\n${result.stderr}');
    },
  );
}
