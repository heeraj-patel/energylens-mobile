import 'dart:async';

import 'package:energylens_mobile/core/cloud_api/cloud_appliance_list.dart';
import 'package:energylens_mobile/features/design/design_context_coordinator.dart';
import 'package:energylens_mobile/features/design/devices_domain_repository.dart';
import 'package:energylens_mobile/features/design/efficiency_domain_repository.dart';
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
  Completer<TipsDomainSnapshot?>? pendingTips;
  DevicesDomainSnapshot? deviceResult;

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
}) => VerifiedDesignContext(accountId: accountId, homeId: homeId, mode: mode);

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
    expect(adapters.efficiencyCalls, [(homeA, EfficiencyPage.away)]);
    expect(await coordinator.read('settings_manual_device_entry'), isNull);
    expect(await coordinator.read('settings_photo_scan_onboarding'), isNull);
    expect(() => coordinator.read('tips_knowledge'), throwsArgumentError);
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
}
