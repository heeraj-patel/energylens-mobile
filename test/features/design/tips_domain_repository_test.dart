import 'dart:async';

import 'package:energylens_mobile/core/cloud_api/cloud_appliance.dart';
import 'package:energylens_mobile/core/cloud_api/cloud_estimate.dart';
import 'package:energylens_mobile/core/cloud_api/cloud_programs.dart';
import 'package:energylens_mobile/core/cloud_api/cloud_recommendations.dart';
import 'package:energylens_mobile/features/design/tips_domain_repository.dart';
import 'package:flutter_test/flutter_test.dart';

const homeA = '11111111-1111-4111-8111-111111111111';
const homeB = '22222222-2222-4222-8222-222222222222';
const applianceId = '33333333-3333-4333-8333-333333333333';

CloudAppliance appliance(String home, {bool exact = true}) => CloudAppliance(
  id: applianceId,
  homeId: home,
  name: 'Appliance',
  category: 'refrigerator',
  room: null,
  brand: 'Brand',
  fullModel: 'Model',
  fuel: 'electricity',
  variant: exact ? 'standard' : null,
  matchQuality: exact ? 'confirmed_exact' : 'unverified',
);

CloudRecommendation recommendation({String id = applianceId}) =>
    CloudRecommendation(
      ruleId: 'refrigerator.maintenance',
      applianceId: id,
      state: 'active',
      title: 'Reviewed recommendation',
      explanation: 'Reviewed explanation',
      nextQuestion: null,
      evidenceCount: 2,
      scenarioRefs: [],
    );

CloudEstimate estimate({String id = applianceId}) => CloudEstimate(
  id: 'estimate',
  applianceId: id,
  kind: 'estimated_operating_cost',
  period: const CloudEstimatePeriod(
    start: '2026-10-01',
    end: '2026-11-01',
    timezone: 'UTC',
  ),
  energy: const CloudEstimateQuantity(
    value: '10.0',
    unit: 'kWh',
    fuel: 'electricity',
  ),
  cost: '2.00',
  currency: 'USD',
  rateKind: 'flat',
  identityQuality: 'confirmed',
  consumptionQuality: 'estimated',
  sourceQuality: 'reviewed',
  contextQuality: 'unknown',
  rateQuality: 'known',
  waste: 'not_yet_assessed',
  evidenceRefs: const [],
  formulaVersion: 'v1',
  asOf: DateTime.utc(2026, 10, 6),
  unavailableReason: null,
);

class FakeSource implements TipsDomainSource {
  FakeSource({this.inventory, this.programRead});

  final Future<List<CloudAppliance>> Function(String)? inventory;
  final Future<CloudProgramPage> Function(String)? programRead;
  List<CloudRecommendation> actions = [recommendation()];
  List<CloudEstimate> estimateRows = [estimate()];
  int programCalls = 0;
  int estimateCalls = 0;

  @override
  Future<List<CloudAppliance>> appliances(String homeId) =>
      inventory?.call(homeId) ?? Future.value([appliance(homeId)]);

  @override
  Future<CloudProgramPage> programs(String homeId) {
    programCalls++;
    return programRead?.call(homeId) ??
        Future.value(
          CloudProgramPage(
            programs: const [],
            asOf: DateTime.utc(2026, 10, 6),
            locationRequired: true,
            coverage: null,
          ),
        );
  }

  @override
  Future<CloudRecommendationBatch> recommendations(
    String homeId,
    Set<String> applianceIds,
  ) async => CloudRecommendationBatch(actions, DateTime.utc(2026, 10, 6));

  @override
  Future<CloudEstimateBatch> estimates(String homeId) async {
    estimateCalls++;
    return CloudEstimateBatch(
      estimates: estimateRows,
      asOf: DateTime.utc(2026, 10, 6),
    );
  }
}

void main() {
  test('perks retains program unknowns and does not infer claims', () async {
    final source = FakeSource();
    final result = await TipsDomainRepository(source)
        .fetch(homeA, TipsPage.perksTips);
    expect(result!.programs?.locationRequired, isTrue);
    expect(result.recommendations.single.ruleId, 'refrigerator.maintenance');
    expect(result.operatingEstimates, isEmpty);
    expect(result.promotion, isNull);
    expect(result.savingsAmount, isNull);
    expect(result.eligibility, isNull);
    expect(source.programCalls, 1);
    expect(source.estimateCalls, 0);
  });

  test('empty home inventory produces an empty Tips snapshot', () async {
    final source = FakeSource(inventory: (_) async => [])..actions = [];
    final result = await TipsDomainRepository(source)
        .fetch(homeA, TipsPage.perksTips);

    expect(result, isNotNull);
    expect(result!.applianceNames, isEmpty);
    expect(result.recommendations, isEmpty);
    expect(result.programs!.programs, isEmpty);
  });

  test('efficiency keeps operating cost separate from savings', () async {
    final source = FakeSource();
    source.actions = [
      recommendation(),
      const CloudRecommendation(
        ruleId: 'computer.sleep_settings',
        applianceId: applianceId,
        state: 'active',
        title: 'Reviewed efficiency action',
        explanation: 'Reviewed explanation',
        nextQuestion: null,
        evidenceCount: 2,
        scenarioRefs: [],
      ),
    ];
    final result = await TipsDomainRepository(source)
        .fetch(homeA, TipsPage.efficiency);
    expect(result!.operatingEstimates.single.cost, '2.00');
    expect(result.recommendations.map((action) => action.ruleId), [
      'refrigerator.maintenance',
      'computer.sleep_settings',
    ]);
    expect(result.savingsAmount, isNull);
    expect(result.programs, isNull);
    expect(source.programCalls, 0);
  });

  test('every Tips page retains all actions in source order', () async {
    final source = FakeSource()
      ..actions = [
        const CloudRecommendation(
          ruleId: 'general.gather_information',
          applianceId: applianceId,
          state: 'candidate',
          title: 'Identify the appliance',
          explanation: 'More information needed',
          nextQuestion: 'confirm_model',
          evidenceCount: 0,
          scenarioRefs: [],
        ),
        recommendation(),
        const CloudRecommendation(
          ruleId: 'computer.sleep_settings',
          applianceId: applianceId,
          state: 'active',
          title: 'Adjust sleep settings',
          explanation: 'Reviewed explanation',
          nextQuestion: null,
          evidenceCount: 2,
          scenarioRefs: [],
        ),
      ];
    final repository = TipsDomainRepository(source);
    for (final page in TipsPage.values) {
      final result = await repository.fetch(homeA, page);
      expect(result!.recommendations, orderedEquals(source.actions));
      expect(result.recommendations.map((action) => action.state), [
        'candidate',
        'active',
        'active',
      ]);
      expect(result.savingsAmount, isNull);
      expect(result.eligibility, isNull);
    }
  });

  test('perks retains every program status and availability', () async {
    final programs = [
      for (var index = 0; index < 3; index++)
        CloudProgram(
          id: '44444444-4444-4444-8444-${(index + 1).toString().padLeft(12, '0')}',
          title: 'Program $index',
          administratorName: 'Administrator $index',
          administratorKind: 'utility',
          benefitKind: 'rebate',
          benefitDisplay: 'Benefit $index',
          benefitTerms: const {},
          eligibilityTerms: const {},
          stackingTerms: const {},
          availabilityStatus: ['unknown', 'waitlist', 'suspended'][index],
          status: index.isEven ? 'unknown' : 'potentially_eligible',
          reasons: const ['provider_unknown'],
          sourceUrl: Uri.parse('https://utility.example/program/$index'),
          sourceSha256: 'a' * 64,
          reviewExpiresAt: DateTime.utc(2026, 11),
        ),
    ];
    final source = FakeSource(
      programRead: (_) async => CloudProgramPage(
        programs: programs,
        asOf: DateTime.utc(2026, 10, 6),
        locationRequired: false,
        coverage: null,
      ),
    );
    final result = await TipsDomainRepository(source)
        .fetch(homeA, TipsPage.perksTips);
    expect(result!.programs!.programs, orderedEquals(programs));
    expect(result.eligibility, isNull);
    expect(result.savingsAmount, isNull);
  });

  test('care page carries appliance fuel in the snapshot', () async {
    final source = FakeSource(
      inventory: (home) async => [
        appliance(home),
        CloudAppliance(
          id: 'AAAAAAAA-3333-4333-8333-333333333333',
          homeId: home,
          name: 'Dryer',
          category: 'dryer',
          room: null,
          brand: 'Brand',
          fullModel: 'Model',
          fuel: 'natural_gas',
          variant: null,
          matchQuality: 'unverified',
        ),
      ],
    );
    final result = await TipsDomainRepository(source)
        .fetch(homeA, TipsPage.careUpgrades);
    expect(result!.applianceFuels, {
      applianceId: 'electricity',
      'aaaaaaaa-3333-4333-8333-333333333333': 'natural_gas',
    });
    expect(result.savingsAmount, isNull);
  });

  test(
    'rejects foreign appliance, recommendation and estimate records',
    () async {
      final foreign = FakeSource(inventory: (_) async => [appliance(homeB)]);
      await expectLater(
        TipsDomainRepository(foreign).fetch(homeA, TipsPage.perksTips),
        throwsFormatException,
      );
      final badRecommendation = FakeSource()
        ..actions = [recommendation(id: homeB)];
      await expectLater(
        TipsDomainRepository(badRecommendation)
            .fetch(homeA, TipsPage.efficiency),
        throwsFormatException,
      );
      final badEstimate = FakeSource()..estimateRows = [estimate(id: homeB)];
      await expectLater(
        TipsDomainRepository(badEstimate).fetch(homeA, TipsPage.careUpgrades),
        throwsFormatException,
      );
    },
  );

  test('home switch and sign-out discard in-flight reads', () async {
    final pending = Completer<CloudProgramPage>();
    final source = FakeSource(
      programRead: (home) => home == homeA
          ? pending.future
          : Future.value(
              CloudProgramPage(
                programs: const [],
                asOf: DateTime.utc(2026, 10, 6),
                locationRequired: true,
                coverage: null,
              ),
            ),
    );
    final repository = TipsDomainRepository(source);
    final old = repository.fetch(homeA, TipsPage.perksTips);
    expect((await repository.fetch(homeB, TipsPage.perksTips))?.homeId, homeB);
    pending.complete(
      CloudProgramPage(
        programs: const [],
        asOf: DateTime.utc(2026, 10, 6),
        locationRequired: true,
        coverage: null,
      ),
    );
    expect(await old, isNull);

    final pendingPrograms = Completer<CloudProgramPage>();
    final signOut = TipsDomainRepository(
      FakeSource(programRead: (_) => pendingPrograms.future),
    );
    final read = signOut.fetch(homeA, TipsPage.perksTips);
    await Future<void>.delayed(Duration.zero);
    signOut.clear();
    pendingPrograms.complete(
      CloudProgramPage(
        programs: const [],
        asOf: DateTime.utc(2026, 10, 6),
        locationRequired: true,
        coverage: null,
      ),
    );
    expect(await read, isNull);
  });
}
