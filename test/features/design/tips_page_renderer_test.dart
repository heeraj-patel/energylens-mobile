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

CloudProgram program(String id, String title) => CloudProgram(
  id: id,
  title: title,
  administratorName: 'City utility',
  administratorKind: 'utility',
  benefitKind: 'rebate',
  benefitDisplay: 'Up to \$40',
  benefitTerms: const {},
  eligibilityTerms: const {},
  stackingTerms: const {},
  availabilityStatus: 'unknown',
  status: 'unknown',
  reasons: const ['reviewed'],
  sourceUrl: Uri.parse('https://utility.example/program/$id'),
  sourceSha256: 'a' * 64,
  reviewExpiresAt: DateTime.utc(2026, 12),
);

TipsDomainSnapshot snapshot(TipsPage page) => TipsDomainSnapshot(
  homeId: home,
  page: page,
  programs: CloudProgramPage(
    programs: [program('one', 'First offer'), program('two', 'Second offer')],
    asOf: DateTime.utc(2026, 10),
    locationRequired: false,
    coverage: null,
  ),
  recommendations: const [
    CloudRecommendation(
      ruleId: 'computer.sleep_settings',
      applianceId: appliance,
      state: 'candidate',
      title: 'First action',
      explanation: 'Find usage information.',
      nextQuestion: 'hours_per_week',
      evidenceCount: 0,
    ),
    CloudRecommendation(
      ruleId: 'refrigerator.maintenance',
      applianceId: appliance,
      state: 'active',
      title: 'Second action',
      explanation: 'Review the manual.',
      nextQuestion: null,
      evidenceCount: 2,
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
      tipCategory: CloudRecommendationTipCategory.upgrade,
    ),
  ],
  applianceNames: const {appliance: 'Saved appliance'},
  operatingEstimates: const [],
  usageFactsByAppliance: const {},
  factsIncomplete: false,
);

void main() {
  test(
    'source rows keep order and fields, and reject stale page scope',
    () async {
      final scripts = {
        'programs': const TipsPageRenderer().script(
          const DesignPageTicket(home, 'perks_tips', 3),
          snapshot(TipsPage.perksTips),
        ),
        'tips': const TipsPageRenderer().script(
          const DesignPageTicket(home, 'tips_efficiency', 3),
          snapshot(TipsPage.efficiency),
        ),
        'care': const TipsPageRenderer().script(
          const DesignPageTicket(home, 'tips_care_upgrades', 3),
          snapshot(TipsPage.careUpgrades),
        ),
      };
      final result = await Process.run('node', [
        '-e',
        r'''
const assert = require('node:assert/strict');
const vm = require('node:vm');
const scripts = JSON.parse(process.argv[1]);
class Element {
  constructor(tag) { this.tag = tag; this.children = []; this.attributes = {}; this.textContent = ''; }
  append(node) { this.children.push(node); }
  replaceChildren() { this.children = []; }
  setAttribute(key, value) { this.attributes[key] = value; }
}
function render(page, script, generation = 3) {
  const mount = new Element('mount');
  const document = {
    getElementById: id => id === ({perks_tips:'el-live-programs', tips_efficiency:'el-live-tips', tips_care_upgrades:'el-live-care'})[page] ? mount : null,
    createElement: tag => new Element(tag),
  };
  const context = {document, window: {__energyLensTextBindingContext: {homeId:'11111111-1111-4111-8111-111111111111', page, generation}}};
  return {accepted: vm.runInNewContext(script, context), mount};
}
const programs = render('perks_tips', scripts.programs);
assert.equal(programs.accepted, true);
const offers = programs.mount.children[1].children;
assert.deepEqual(offers.map(row => row.children[0].children[0].textContent), ['First offer', 'Second offer']);
assert.equal(offers[0].children[0].children[1].textContent, 'City utility');
assert.equal(offers[0].children[0].children[2].textContent, 'Up to $40');
assert.equal(offers[0].children[0].href, 'https://utility.example/program/one');
const tips = render('tips_efficiency', scripts.tips);
assert.deepEqual(tips.mount.children[1].children.map(row => row.children[0].children[0].textContent), ['First action', 'Second action', 'Third action']);
assert.equal(tips.mount.children[1].children[0].children[0].children[1].textContent, 'Saved appliance');
assert.equal(tips.mount.children[1].children[0].children[0].children[2].textContent, 'Find usage information.');
const care = render('tips_care_upgrades', scripts.care);
assert.deepEqual(care.mount.children[1].children.map(row => row.children[0].children[0].textContent), ['Second action', 'Third action']);
assert.equal(render('perks_tips', scripts.programs, 4).accepted, false);
assert.equal(render('tips_efficiency', scripts.programs).accepted, false);
''',
        jsonEncode(scripts),
      ]);
      expect(result.exitCode, 0, reason: '${result.stdout}\n${result.stderr}');
    },
  );
}
