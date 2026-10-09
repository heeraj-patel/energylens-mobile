import 'dart:async';

import 'package:energylens_mobile/core/cloud_api/cloud_appliance_list.dart';
import 'package:energylens_mobile/features/design/design_context_coordinator.dart';
import 'package:energylens_mobile/features/design/devices_domain_repository.dart';
import 'package:energylens_mobile/features/design/devices_runtime_evidence_adapter.dart';
import 'package:energylens_mobile/features/design/efficiency_domain_repository.dart';
import 'package:energylens_mobile/features/design/efficiency_away_domain_adapter.dart';
import 'package:energylens_mobile/features/design/efficiency_habits_domain_adapter.dart';
import 'package:energylens_mobile/features/design/efficiency_peak_rates_adapter.dart';
import 'package:energylens_mobile/features/design/knowledge_domain_repository.dart';
import 'package:energylens_mobile/features/design/manage_devices_domain_repository.dart';
import 'package:energylens_mobile/features/design/tips_domain_repository.dart';
import 'package:flutter_test/flutter_test.dart';

const homeA = '11111111-1111-1111-1111-111111111111';
const homeB = '22222222-2222-2222-2222-222222222222';

class FakeAdapters implements DesignContextAdapters {
  int clears = 0;
  final tipCalls = <(String, TipsPage)>[];
  final efficiencyCalls = <(String, EfficiencyPage)>[];
  final typedEfficiencyCalls = <(String, String)>[];
  Completer<TipsDomainSnapshot?>? pendingTips;
  Completer<EfficiencyAwayDomainSnapshot?>? pendingAway;
  DevicesDomainSnapshot? deviceResult;
  DevicesRuntimeEvidenceSnapshot? runtimeResult;
  Completer<DevicesRuntimeEvidenceSnapshot?>? pendingRuntime;
  int runtimeCalls = 0;

  @override
  void clear() => clears++;
  @override
  Future<TipsDomainSnapshot?> tips(String homeId, TipsPage page) {
    tipCalls.add((homeId, page));
    return pendingTips?.future ?? Future.value(_tips(homeId, page));
  }

  @override
  Future<DevicesDomainSnapshot?> devices(String homeId) async => deviceResult;
  @override
  Future<DevicesRuntimeEvidenceSnapshot?> devicesRuntimeEvidence(
    String homeId,
  ) {
    runtimeCalls++;
    return pendingRuntime?.future ?? Future.value(runtimeResult);
  }

  @override
  Future<ManageDevicesDomainSnapshot?> manageDevices(String homeId) async =>
      null;
  @override
  Future<EfficiencyDomainSnapshot?> efficiency(
    String homeId,
    EfficiencyPage page,
  ) async {
    efficiencyCalls.add((homeId, page));
    return null;
  }

  @override
  Future<EfficiencyAwayDomainSnapshot?> efficiencyAway(String homeId) {
    typedEfficiencyCalls.add((homeId, 'away'));
    return pendingAway?.future ?? Future.value(null);
  }

  @override
  Future<EfficiencyHabitsSnapshot?> efficiencyHabits(String homeId) async {
    typedEfficiencyCalls.add((homeId, 'habits'));
    return null;
  }

  @override
  Future<EfficiencyPeakRatesSnapshot?> efficiencyPeakRates(
    String homeId,
  ) async {
    typedEfficiencyCalls.add((homeId, 'peak'));
    return null;
  }

  @override
  Future<KnowledgeAnswerResult?> knowledge(
    String homeId,
    String questionId, {
    String? applianceId,
  }) async => KnowledgeAnswerUnavailable(questionId);
  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

TipsDomainSnapshot _tips(String homeId, TipsPage page) => TipsDomainSnapshot(
  homeId: homeId,
  page: page,
  programs: null,
  recommendations: const [],
  operatingEstimates: const [],
  usageFactsByAppliance: const {},
  factsIncomplete: false,
);

VerifiedDesignContext _context(
  String homeId, {
  String accountId = 'account-a',
  DesignContextMode mode = DesignContextMode.household,
  DesignDataPolicy dataPolicy = DesignDataPolicy.modeOnly,
}) => VerifiedDesignContext(
  accountId: accountId,
  homeId: homeId,
  mode: mode,
  dataPolicy: dataPolicy,
);

void main() {
  test('routes supported pages and rejects unbound pages', () async {
    final adapters = FakeAdapters();
    final coordinator = DesignContextCoordinator(adapters);
    coordinator.useVerifiedContext(_context(homeA));
    final result = await coordinator.read('tips_care_upgrades');
    expect(result?.page, 'tips_care_upgrades');
    expect(result?.homeId, homeA);
    expect(adapters.tipCalls, [(homeA, TipsPage.careUpgrades)]);
    await coordinator.read('efficiency_away');
    await coordinator.read('efficiency_habits');
    await coordinator.read('efficiency_peak_rates');
    expect(adapters.typedEfficiencyCalls, [
      (homeA, 'away'),
      (homeA, 'habits'),
      (homeA, 'peak'),
    ]);
    expect(await coordinator.read('settings_manual_device_entry'), isNull);
    expect(await coordinator.read('settings_photo_scan_onboarding'), isNull);
    expect(() => coordinator.read('tips_knowledge'), throwsArgumentError);
  });

  test('typed Efficiency reads discard stale home responses', () async {
    final adapters = FakeAdapters();
    final coordinator = DesignContextCoordinator(adapters);
    coordinator.useVerifiedContext(_context(homeA));
    final pending = Completer<EfficiencyAwayDomainSnapshot?>();
    adapters.pendingAway = pending;
    final old = coordinator.read('efficiency_away');
    coordinator.useVerifiedContext(_context(homeB));
    pending.complete(null);
    expect(await old, isNull);
    expect(adapters.typedEfficiencyCalls, [(homeA, 'away')]);
  });

  test('peak tariff reads are unavailable in sample context', () async {
    final adapters = FakeAdapters();
    final coordinator = DesignContextCoordinator(adapters);
    coordinator.useVerifiedContext(
      _context(homeA, mode: DesignContextMode.sample),
    );
    expect(
      () => coordinator.read('efficiency_peak_rates'),
      throwsArgumentError,
    );
    expect(adapters.typedEfficiencyCalls, isEmpty);
  });

  test(
    'home switch and sign-out invalidate pending results and errors',
    () async {
      final adapters = FakeAdapters();
      final coordinator = DesignContextCoordinator(adapters);
      coordinator.useVerifiedContext(_context(homeA));
      final first = Completer<TipsDomainSnapshot?>();
      adapters.pendingTips = first;
      final old = coordinator.read('perks_tips');
      coordinator.useVerifiedContext(_context(homeB));
      first.complete(_tips(homeA, TipsPage.perksTips));
      expect(await old, isNull);

      final second = Completer<TipsDomainSnapshot?>();
      adapters.pendingTips = second;
      final lateError = coordinator.read('perks_tips');
      coordinator.signOut();
      second.completeError(StateError('old session'));
      expect(await lateError, isNull);
      expect(adapters.clears, 3);
      expect(() => coordinator.read('perks_tips'), throwsStateError);
    },
  );

  test(
    'account and mode transitions invalidate even with the same home',
    () async {
      final adapters = FakeAdapters();
      final coordinator = DesignContextCoordinator(adapters);
      coordinator.useVerifiedContext(_context(homeA));
      final pending = Completer<TipsDomainSnapshot?>();
      adapters.pendingTips = pending;
      final old = coordinator.read('perks_tips');
      coordinator.useVerifiedContext(_context(homeA, accountId: 'account-b'));
      pending.complete(_tips(homeA, TipsPage.perksTips));
      expect(await old, isNull);
      coordinator.useVerifiedContext(
        _context(homeA, accountId: 'account-b', mode: DesignContextMode.sample),
      );
      expect(() => coordinator.read('perks_tips'), throwsArgumentError);
      expect(
        () => coordinator.answerKnowledge('home_energy'),
        throwsStateError,
      );
      expect(adapters.clears, 3);
    },
  );

  test('sign-out and another account cannot reuse a prior home read', () async {
    final adapters = FakeAdapters();
    final coordinator = DesignContextCoordinator(adapters);
    coordinator.useVerifiedContext(_context(homeA));
    final pending = Completer<TipsDomainSnapshot?>();
    adapters.pendingTips = pending;
    final oldRead = coordinator.read('perks_tips');

    coordinator.signOut();
    coordinator.useVerifiedContext(_context(homeA, accountId: 'account-b'));
    pending.complete(_tips(homeA, TipsPage.perksTips));
    expect(await oldRead, isNull);

    adapters.pendingTips = null;
    final newRead = await coordinator.read('perks_tips');
    expect(newRead?.accountId, 'account-b');
    expect(newRead?.homeId, homeA);
    expect(adapters.clears, 3);
  });

  test(
    'rejects sample inventory in household context and permits matching sample',
    () async {
      final adapters = FakeAdapters();
      final coordinator = DesignContextCoordinator(adapters);
      adapters.deviceResult = const DevicesDomainSnapshot(
        homeId: homeA,
        items: [],
        hasMoreMeteredPages: false,
        dataMode: CloudApplianceDataMode.sample,
        fixtureRevision: 'fixture',
      );
      coordinator.useVerifiedContext(_context(homeA));
      await expectLater(coordinator.read('devices'), throwsFormatException);
      coordinator.useVerifiedContext(
        _context(homeA, mode: DesignContextMode.sample),
      );
      expect(
        (await coordinator.read('devices'))?.mode,
        DesignContextMode.sample,
      );
    },
  );

  test('verified home accepts only its authorized demo response', () async {
    final adapters = FakeAdapters();
    final coordinator = DesignContextCoordinator(adapters);
    adapters.deviceResult = const DevicesDomainSnapshot(
      homeId: homeA,
      items: [],
      hasMoreMeteredPages: false,
      dataMode: CloudApplianceDataMode.sample,
      fixtureRevision: 'fixture',
    );
    coordinator.useVerifiedContext(
      _context(homeA, dataPolicy: DesignDataPolicy.sameHomeDemoFallback),
    );
    final accepted = await coordinator.read('devices');
    expect(accepted?.homeId, homeA);
    expect(accepted?.mode, DesignContextMode.sample);
    expect(coordinator.context?.mode, DesignContextMode.household);

    adapters.deviceResult = const DevicesDomainSnapshot(
      homeId: homeB,
      items: [],
      hasMoreMeteredPages: false,
      dataMode: CloudApplianceDataMode.sample,
      fixtureRevision: 'fixture',
    );
    await expectLater(coordinator.read('devices'), throwsFormatException);

    coordinator.signOut();
    expect(coordinator.context, isNull);
    await expectLater(coordinator.read('devices'), throwsStateError);
  });

  test('runtime evidence is a separate authenticated household read', () async {
    final adapters = FakeAdapters()
      ..runtimeResult = DevicesRuntimeEvidenceSnapshot(
        homeId: homeA,
        evidence: const [],
        isSample: false,
        isCurrent: () => true,
      );
    final coordinator = DesignContextCoordinator(adapters);
    coordinator.useVerifiedContext(_context(homeA));
    final result = await coordinator.readDevicesRuntimeEvidence();
    expect(result?.page, 'devices_runtime_evidence');
    expect(result?.value, isA<DevicesRuntimeEvidenceSnapshot>());
    expect(adapters.runtimeCalls, 1);
    expect(adapters.deviceResult, isNull);
    final snapshot = result!.value as DevicesRuntimeEvidenceSnapshot;
    expect(snapshot.energyWh, isNull);
    expect(snapshot.cost, isNull);
    expect(snapshot.wasteEnergyWh, isNull);
    expect(snapshot.liveState, isNull);
  });

  test('runtime evidence rejects missing and sample contexts', () async {
    final adapters = FakeAdapters();
    final coordinator = DesignContextCoordinator(adapters);
    expect(() => coordinator.readDevicesRuntimeEvidence(), throwsStateError);
    coordinator.useVerifiedContext(
      _context(homeA, mode: DesignContextMode.sample),
    );
    expect(() => coordinator.readDevicesRuntimeEvidence(), throwsStateError);
    expect(adapters.runtimeCalls, 0);
  });

  test(
    'runtime evidence discards stale results and errors after context changes',
    () async {
      final adapters = FakeAdapters();
      final coordinator = DesignContextCoordinator(adapters);
      coordinator.useVerifiedContext(_context(homeA));
      final resultPending = Completer<DevicesRuntimeEvidenceSnapshot?>();
      adapters.pendingRuntime = resultPending;
      final oldResult = coordinator.readDevicesRuntimeEvidence();
      coordinator.useVerifiedContext(_context(homeB));
      resultPending.complete(
        DevicesRuntimeEvidenceSnapshot(
          homeId: homeA,
          evidence: const [],
          isSample: false,
          isCurrent: () => false,
        ),
      );
      expect(await oldResult, isNull);

      final errorPending = Completer<DevicesRuntimeEvidenceSnapshot?>();
      adapters.pendingRuntime = errorPending;
      final oldError = coordinator.readDevicesRuntimeEvidence();
      coordinator.signOut();
      errorPending.completeError(StateError('stale auth'));
      expect(await oldError, isNull);
    },
  );

  test('runtime evidence is invalidated by account and mode changes', () async {
    final adapters = FakeAdapters();
    final coordinator = DesignContextCoordinator(adapters);
    coordinator.useVerifiedContext(_context(homeA));
    final accountPending = Completer<DevicesRuntimeEvidenceSnapshot?>();
    adapters.pendingRuntime = accountPending;
    final oldAccount = coordinator.readDevicesRuntimeEvidence();
    coordinator.useVerifiedContext(_context(homeA, accountId: 'account-b'));
    accountPending.complete(
      DevicesRuntimeEvidenceSnapshot(
        homeId: homeA,
        evidence: const [],
        isSample: false,
        isCurrent: () => false,
      ),
    );
    expect(await oldAccount, isNull);

    final modePending = Completer<DevicesRuntimeEvidenceSnapshot?>();
    adapters.pendingRuntime = modePending;
    final oldMode = coordinator.readDevicesRuntimeEvidence();
    coordinator.useVerifiedContext(
      _context(homeA, accountId: 'account-b', mode: DesignContextMode.sample),
    );
    modePending.completeError(StateError('old household result'));
    expect(await oldMode, isNull);
  });

  test('runtime evidence rejects sample provenance and wrong home', () async {
    final adapters = FakeAdapters();
    final coordinator = DesignContextCoordinator(adapters);
    coordinator.useVerifiedContext(_context(homeA));
    adapters.runtimeResult = DevicesRuntimeEvidenceSnapshot(
      homeId: homeA,
      evidence: const [],
      isSample: true,
      isCurrent: () => true,
    );
    await expectLater(
      coordinator.readDevicesRuntimeEvidence(),
      throwsFormatException,
    );
    adapters.runtimeResult = DevicesRuntimeEvidenceSnapshot(
      homeId: homeB,
      evidence: const [],
      isSample: false,
      isCurrent: () => true,
    );
    await expectLater(
      coordinator.readDevicesRuntimeEvidence(),
      throwsFormatException,
    );
  });
}
