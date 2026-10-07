import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:energylens_mobile/features/design/design_context_coordinator.dart';
import 'package:energylens_mobile/features/design/identification_candidates_domain_adapter.dart';
import 'package:energylens_mobile/features/design/manage_devices_domain_repository.dart';
import 'package:energylens_mobile/features/design/dashboard_domain_repository.dart';
import 'package:energylens_mobile/features/design/devices_domain_repository.dart';
import 'package:energylens_mobile/features/design/efficiency_domain_repository.dart';
import 'package:energylens_mobile/features/design/efficiency_away_domain_adapter.dart';
import 'package:energylens_mobile/features/design/efficiency_habits_domain_adapter.dart';
import 'package:energylens_mobile/features/design/efficiency_peak_rates_adapter.dart';
import 'package:energylens_mobile/features/design/knowledge_domain_repository.dart';
import 'package:energylens_mobile/features/design/settings_domain_repository.dart';
import 'package:energylens_mobile/features/design/tips_domain_repository.dart';
import 'package:energylens_mobile/features/discovery/discovery_api.dart';

const _account = 'aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa';
const _homeOne = '11111111-1111-4111-8111-111111111111';
const _homeTwo = '22222222-2222-4222-8222-222222222222';

VerifiedDesignContext _context(
  String home, [
  DesignContextMode mode = DesignContextMode.household,
]) => VerifiedDesignContext(accountId: _account, homeId: home, mode: mode);

class _Source implements IdentificationCandidatesSource {
  final requests = <({String kind, String? ocr, String? upc})>[];
  Future<List<IdentificationCandidate>> Function()? response;

  @override
  Future<List<IdentificationCandidate>> lookup({
    required String targetKind,
    String? ocrText,
    String? upc,
  }) {
    requests.add((kind: targetKind, ocr: ocrText, upc: upc));
    return response?.call() ??
        Future.value(const [
          IdentificationCandidate(
            manufacturer: 'Acme',
            model: 'A-100',
            confidence: 0.62,
            source: 'ocr_candidate',
            matchedKinds: ['ocr'],
          ),
        ]);
  }
}

void main() {
  test(
    'rejects lookup until the native coordinator binds a verified home',
    () async {
      final source = _Source();
      final coordinator = DesignContextCoordinator(
        _NoopAdapters(),
        identificationCandidates: IdentificationCandidatesDomainAdapter(source),
      );

      await expectLater(
        coordinator.lookupIdentificationCandidates(targetKind: 'refrigerator'),
        throwsStateError,
      );
      expect(source.requests, isEmpty);
    },
  );

  test('home switch and sign-out suppress late candidate responses', () async {
    final source = _Source();
    final delayed = Completer<List<IdentificationCandidate>>();
    source.response = () => delayed.future;
    final coordinator = DesignContextCoordinator(
      _NoopAdapters(),
      identificationCandidates: IdentificationCandidatesDomainAdapter(source),
    );
    coordinator.useVerifiedContext(_context(_homeOne));
    final firstLookup = coordinator.lookupIdentificationCandidates(
      targetKind: 'refrigerator',
      ocrText: 'Acme A100',
    );
    coordinator.useVerifiedContext(_context(_homeTwo));
    delayed.complete(const []);
    expect(await firstLookup, isNull);

    final lateError = Completer<List<IdentificationCandidate>>();
    source.response = () => lateError.future;
    final secondLookup = coordinator.lookupIdentificationCandidates(
      targetKind: 'refrigerator',
    );
    coordinator.signOut();
    lateError.completeError(StateError('late discovery failure'));
    expect(await secondLookup, isNull);
    expect(source.requests, hasLength(2));
    await expectLater(
      coordinator.lookupIdentificationCandidates(targetKind: 'refrigerator'),
      throwsStateError,
    );
  });

  test('returns ambiguous matches as unconfirmed review hints', () async {
    final source = _Source();
    final coordinator = DesignContextCoordinator(
      _NoopAdapters(),
      identificationCandidates: IdentificationCandidatesDomainAdapter(source),
    )..useVerifiedContext(_context(_homeOne));

    final result = await coordinator.lookupIdentificationCandidates(
      targetKind: 'refrigerator',
      ocrText: 'Acme A100',
    );
    final candidate = result!.candidates.single;
    expect(result.homeId, _homeOne);
    expect(candidate.modelHint, 'A-100');
    expect(candidate.confirmedExact, isFalse);
  });

  test('sample mode cannot request discovery lookup', () async {
    final source = _Source();
    final coordinator = DesignContextCoordinator(
      _NoopAdapters(),
      identificationCandidates: IdentificationCandidatesDomainAdapter(source),
    )..useVerifiedContext(_context(_homeOne, DesignContextMode.sample));

    await expectLater(
      coordinator.lookupIdentificationCandidates(targetKind: 'refrigerator'),
      throwsStateError,
    );
    expect(source.requests, isEmpty);
  });

  test(
    'account and mode changes invalidate pending candidate lookups',
    () async {
      final source = _Source();
      final delayed = Completer<List<IdentificationCandidate>>();
      source.response = () => delayed.future;
      final coordinator = DesignContextCoordinator(
        _NoopAdapters(),
        identificationCandidates: IdentificationCandidatesDomainAdapter(source),
      )..useVerifiedContext(_context(_homeOne));

      final pending = coordinator.lookupIdentificationCandidates(
        targetKind: 'refrigerator',
      );
      coordinator.useVerifiedContext(
        VerifiedDesignContext(
          accountId: 'bbbbbbbb-bbbb-4bbb-8bbb-bbbbbbbbbbbb',
          homeId: _homeOne,
          mode: DesignContextMode.household,
        ),
      );
      delayed.complete(const []);
      expect(await pending, isNull);

      final modeDelayed = Completer<List<IdentificationCandidate>>();
      source.response = () => modeDelayed.future;
      final modePending = coordinator.lookupIdentificationCandidates(
        targetKind: 'refrigerator',
      );
      coordinator.useVerifiedContext(
        VerifiedDesignContext(
          accountId: 'bbbbbbbb-bbbb-4bbb-8bbb-bbbbbbbbbbbb',
          homeId: _homeOne,
          mode: DesignContextMode.sample,
        ),
      );
      modeDelayed.complete(const []);
      expect(await modePending, isNull);
    },
  );
}

class _NoopAdapters implements DesignContextAdapters {
  @override
  void clear() {}
  @override
  Future<DashboardDomainSnapshot?> dashboard(String homeId) async => null;
  @override
  Future<DevicesDomainSnapshot?> devices(String homeId) async => null;
  @override
  Future<EfficiencyDomainSnapshot?> efficiency(
    String homeId,
    EfficiencyPage page,
  ) async => null;
  @override
  Future<EfficiencyAwayDomainSnapshot?> efficiencyAway(String homeId) async =>
      null;
  @override
  Future<EfficiencyHabitsSnapshot?> efficiencyHabits(String homeId) async =>
      null;
  @override
  Future<EfficiencyPeakRatesSnapshot?> efficiencyPeakRates(
    String homeId,
  ) async => null;
  @override
  Future<TipsDomainSnapshot?> tips(String homeId, TipsPage page) async => null;
  @override
  Future<SettingsDomainSnapshot?> settings(String homeId) async => null;
  @override
  Future<ManageDevicesDomainSnapshot?> manageDevices(String homeId) async =>
      null;
  @override
  Future<KnowledgeAnswerResult?> knowledge(
    String homeId,
    String questionId, {
    String? applianceId,
  }) async => null;
}
