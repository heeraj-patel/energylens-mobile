import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:energylens_mobile/core/cloud_api/cloud_appliance.dart';
import 'package:energylens_mobile/core/cloud_auth/cloud_auxiliary_domain_lifecycle.dart';
import 'package:energylens_mobile/features/design/design_context_coordinator.dart';
import 'package:energylens_mobile/features/design/identification_candidates_domain_adapter.dart';
import 'package:energylens_mobile/features/design/report_preview_domain_repository.dart';
import 'package:energylens_mobile/features/design/report_delivery_domain_adapter.dart';
import 'package:energylens_mobile/features/discovery/discovery_api.dart';
import 'package:energylens_mobile/features/identify/candidate_onboarding_draft_bridge.dart';
import 'package:energylens_mobile/features/identify/candidate_onboarding_review_adapter.dart';
import 'package:energylens_mobile/features/identify/onboarding_draft_store.dart';
import 'package:energylens_mobile/features/identify/onboarding_persistence_repository.dart';

const owner = 'aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa';
const otherOwner = 'bbbbbbbb-bbbb-4bbb-8bbb-bbbbbbbbbbbb';
const home = '11111111-1111-4111-8111-111111111111';
const otherHome = '22222222-2222-4222-8222-222222222222';
final context = VerifiedDesignContext(
  accountId: owner,
  homeId: home,
  mode: DesignContextMode.household,
);
final otherContext = VerifiedDesignContext(
  accountId: otherOwner,
  homeId: otherHome,
  mode: DesignContextMode.household,
);

class _Storage implements OnboardingDraftStorage {
  String? value;
  @override
  Future<String?> read() async => value;
  @override
  Future<void> write(String value) async => this.value = value;
  @override
  Future<void> clear() async => value = null;
}

class _Source implements OnboardingPersistenceSource {
  int posts = 0;
  int reads = 0;
  int inventories = 0;
  bool allowCreate = false;
  bool uncertainCreate = false;
  bool failDetailOnce = false;
  Completer<void>? createGate;
  Completer<void>? createEntered;
  final keys = <String>[];
  CloudApplianceCreate? input;
  CloudAppliance row(String homeId) => CloudAppliance(
    id: '33333333-3333-4333-8333-333333333333',
    homeId: homeId,
    name: input!.name,
    category: input!.category,
    room: input!.room,
    brand: input!.brand,
    fullModel: input!.fullModel,
    fuel: input!.fuel,
    matchQuality: input!.matchQuality,
  );
  @override
  Future<CloudAppliance> create(
    String homeId,
    CloudApplianceCreate value,
    String key,
  ) async {
    posts++;
    keys.add(key);
    if (!allowCreate) throw StateError('unexpected POST');
    input = value;
    createEntered?.complete();
    if (createGate case final gate?) await gate.future;
    if (uncertainCreate) {
      uncertainCreate = false;
      throw StateError('response lost');
    }
    return row(homeId);
  }

  @override
  Future<CloudAppliance> detail(String homeId, String applianceId) async {
    reads++;
    if (failDetailOnce) {
      failDetailOnce = false;
      throw StateError('readback unavailable');
    }
    return row(homeId);
  }

  @override
  Future<List<CloudAppliance>> inventory(String homeId) async {
    inventories++;
    return [row(homeId)];
  }

  @override
  Future<String> version(String homeId, String applianceId) =>
      throw UnimplementedError();
  @override
  Future<void> archive(
    String homeId,
    String applianceId,
    String etag,
    String key,
  ) => throw UnimplementedError();
}

class _Candidates implements IdentificationCandidatesSource {
  @override
  Future<List<IdentificationCandidate>> lookup({
    required String targetKind,
    String? ocrText,
    String? upc,
  }) async => [
    IdentificationCandidate(
      manufacturer: 'Acme',
      model: 'RF-100',
      category: 'refrigerator',
      confidence: .9,
      source: 'ocr',
      matchedKinds: const ['refrigerator'],
    ),
  ];
}

class _ReportSource implements ReportPreviewDomainSource {
  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _DeliverySource implements ReportDeliveryDomainSource {
  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

CloudAuxiliaryDomainLifecycle _lifecycle(_Storage storage, _Source source) =>
    CloudAuxiliaryDomainLifecycle(
      drafts: DurableOnboardingDrafts(
        storage,
        OnboardingPersistenceRepository(source),
      ),
      reports: ReportPreviewDomainRepository(_ReportSource()),
      deliveries: ReportDeliveryDomainAdapter(_DeliverySource()),
    );

void main() {
  test('unbound lifecycle cannot stage or restore a candidate draft', () async {
    final candidates = IdentificationCandidatesDomainAdapter(_Candidates())
      ..useVerifiedContext(context);
    final snapshot = (await candidates.lookup(targetKind: 'appliance'))!;
    final review = CandidateOnboardingReviewAdapter(candidates).review(
      snapshot: snapshot,
      activeContext: context,
      values: const CandidateOnboardingReview(
        name: 'Kitchen fridge',
        fuel: 'electricity',
      ),
      confirmed: true,
    );
    final bridge = CandidateOnboardingDraftBridge(
      candidates: candidates,
      lifecycle: _lifecycle(_Storage(), _Source()),
    );
    expect(await bridge.restore(context), isNull);
    await expectLater(
      () => bridge.stage(
        snapshot: snapshot,
        activeContext: context,
        review: review,
      ),
      throwsStateError,
    );
  });

  test(
    'stages confirmed unresolved review, restores it, and does not POST',
    () async {
      final candidateAdapter = IdentificationCandidatesDomainAdapter(
        _Candidates(),
      )..useVerifiedContext(context);
      final snapshot = (await candidateAdapter.lookup(
        targetKind: 'appliance',
      ))!;
      final result = CandidateOnboardingReviewAdapter(candidateAdapter).review(
        snapshot: snapshot,
        activeContext: context,
        values: const CandidateOnboardingReview(
          name: 'Kitchen fridge',
          fuel: 'electricity',
        ),
        confirmed: true,
      );
      final storage = _Storage();
      final source = _Source();
      final lifecycle = _lifecycle(storage, source);
      await lifecycle.selectVerifiedHome(owner, home);
      final bridge = CandidateOnboardingDraftBridge(
        candidates: candidateAdapter,
        lifecycle: lifecycle,
      );
      final pending = await bridge.stage(
        snapshot: snapshot,
        activeContext: context,
        review: result,
      );
      final retried = await bridge.stage(
        snapshot: snapshot,
        activeContext: context,
        review: result,
      );
      expect(retried.operationKey, pending.operationKey);
      final restartedLifecycle = _lifecycle(storage, source);
      await restartedLifecycle.selectVerifiedHome(owner, home);
      final restarted = CandidateOnboardingDraftBridge(
        candidates: candidateAdapter,
        lifecycle: restartedLifecycle,
      );
      expect(
        (await restarted.restore(context))!.operationKey,
        pending.operationKey,
      );
      final restored = (await restarted.restore(context))!;
      expect(restored.draft.name, pending.draft.name);
      expect(restored.draft.category, pending.draft.category);
      expect(restored.draft.brand, pending.draft.brand);
      expect(restored.draft.fullModel, pending.draft.fullModel);
      expect(restored.draft.fuel, pending.draft.fuel);
      expect(restored.draft.validated().matchQuality, 'unresolved');
      expect(restored.draft.validated().catalogProductId, isNull);
      expect(source.posts, 0);
    },
  );

  test('rejects stale, ambiguous, and cross-scope results; scope change clears slot', () async {
    final candidateAdapter = IdentificationCandidatesDomainAdapter(
      _Candidates(),
    )..useVerifiedContext(context);
    final snapshot = (await candidateAdapter.lookup(targetKind: 'appliance'))!;
    final adapter = CandidateOnboardingReviewAdapter(candidateAdapter);
    final ready = adapter.review(
      snapshot: snapshot,
      activeContext: context,
      values: const CandidateOnboardingReview(
        name: 'Kitchen fridge',
        fuel: 'electricity',
      ),
      confirmed: true,
    );
    final storage = _Storage();
    final source = _Source();
    final lifecycle = _lifecycle(storage, source);
    await lifecycle.selectVerifiedHome(owner, home);
    final bridge = CandidateOnboardingDraftBridge(
      candidates: candidateAdapter,
      lifecycle: lifecycle,
    );
    await bridge.stage(
      snapshot: snapshot,
      activeContext: context,
      review: ready,
    );
    await lifecycle.selectVerifiedHome(otherOwner, home);
    expect(await bridge.restore(context), isNull);
    expect(storage.value, isNull);
    await expectLater(
      () => bridge.stage(
        snapshot: snapshot,
        activeContext: context,
        review: ready,
      ),
      throwsStateError,
    );
    await lifecycle.selectVerifiedHome(owner, home);
    await bridge.stage(
      snapshot: snapshot,
      activeContext: context,
      review: ready,
    );
    expect(await bridge.restore(otherContext), isNull);
    expect(storage.value, isNotNull);
    await expectLater(
      () => bridge.stage(
        snapshot: snapshot,
        activeContext: otherContext,
        review: ready,
      ),
      throwsStateError,
    );
    candidateAdapter.clear();
    await expectLater(
      () => bridge.stage(
        snapshot: snapshot,
        activeContext: context,
        review: ready,
      ),
      throwsStateError,
    );
  });

  test('ambiguous selection cannot stage until review is resolved', () async {
    final source = _Candidates();
    final candidates = IdentificationCandidatesDomainAdapter(source)
      ..useVerifiedContext(context);
    final snapshot = (await candidates.lookup(targetKind: 'appliance'))!;
    final ambiguous = const CandidateOnboardingReviewResult(
      state: CandidateOnboardingReviewState.ambiguous,
    );
    final bridge = CandidateOnboardingDraftBridge(
      candidates: candidates,
      lifecycle: _lifecycle(_Storage(), _Source()),
    );
    expect(
      () => bridge.stage(
        snapshot: snapshot,
        activeContext: context,
        review: ambiguous,
      ),
      throwsStateError,
    );
  });

  test(
    'explicit commit retries stored key after uncertain POST and reads back',
    () async {
      final candidates = IdentificationCandidatesDomainAdapter(_Candidates())
        ..useVerifiedContext(context);
      final snapshot = (await candidates.lookup(targetKind: 'appliance'))!;
      final review = CandidateOnboardingReviewAdapter(candidates).review(
        snapshot: snapshot,
        activeContext: context,
        values: const CandidateOnboardingReview(
          name: 'Kitchen fridge',
          fuel: 'electricity',
        ),
        confirmed: true,
      );
      final storage = _Storage();
      final source = _Source()
        ..allowCreate = true
        ..uncertainCreate = true;
      final lifecycle = _lifecycle(storage, source);
      await lifecycle.selectVerifiedHome(owner, home);
      final bridge = CandidateOnboardingDraftBridge(
        candidates: candidates,
        lifecycle: lifecycle,
      );
      final pending = await bridge.stage(
        snapshot: snapshot,
        activeContext: context,
        review: review,
      );
      await expectLater(
        bridge.commit(
          activeContext: context,
          pending: pending,
          explicitlyApproved: false,
        ),
        throwsStateError,
      );
      expect(source.posts, 0);
      await expectLater(
        bridge.commit(
          activeContext: context,
          pending: pending,
          explicitlyApproved: true,
        ),
        throwsStateError,
      );
      expect(
        (await bridge.restore(context))!.operationKey,
        pending.operationKey,
      );

      final restartedLifecycle = _lifecycle(storage, source);
      await restartedLifecycle.selectVerifiedHome(owner, home);
      final restarted = CandidateOnboardingDraftBridge(
        candidates: candidates,
        lifecycle: restartedLifecycle,
      );
      final restored = (await restarted.restore(context))!;
      final saved = await restarted.commit(
        activeContext: context,
        pending: restored,
        explicitlyApproved: true,
      );
      expect(saved?.homeId, home);
      expect(saved?.matchQuality, 'unresolved');
      expect(source.keys, [pending.operationKey, pending.operationKey]);
      expect(source.reads, 1);
      expect(source.inventories, 1);
      expect(await restarted.restore(context), isNull);
    },
  );

  test('changed draft, forged key, and changed account never commit', () async {
    final candidates = IdentificationCandidatesDomainAdapter(_Candidates())
      ..useVerifiedContext(context);
    final snapshot = (await candidates.lookup(targetKind: 'appliance'))!;
    final review = CandidateOnboardingReviewAdapter(candidates).review(
      snapshot: snapshot,
      activeContext: context,
      values: const CandidateOnboardingReview(
        name: 'Kitchen fridge',
        fuel: 'electricity',
      ),
      confirmed: true,
    );
    final source = _Source()..allowCreate = true;
    final lifecycle = _lifecycle(_Storage(), source);
    await lifecycle.selectVerifiedHome(owner, home);
    final bridge = CandidateOnboardingDraftBridge(
      candidates: candidates,
      lifecycle: lifecycle,
    );
    final pending = await bridge.stage(
      snapshot: snapshot,
      activeContext: context,
      review: review,
    );
    for (final invalid in [
      PendingOnboardingDraft(
        pending.draft,
        '44444444-4444-4444-8444-444444444444',
      ),
      PendingOnboardingDraft(
        const OnboardingDraft(
          name: 'Different fridge',
          category: 'refrigerator',
          brand: 'Acme',
          fullModel: 'RF-100',
          fuel: 'electricity',
        ),
        pending.operationKey,
      ),
    ]) {
      await expectLater(
        bridge.commit(
          activeContext: context,
          pending: invalid,
          explicitlyApproved: true,
        ),
        throwsStateError,
      );
    }
    await lifecycle.selectVerifiedHome(otherOwner, otherHome);
    expect(
      () => bridge.commit(
        activeContext: context,
        pending: pending,
        explicitlyApproved: true,
      ),
      throwsStateError,
    );
    expect(source.posts, 0);
  });

  test(
    'failed readback retains exact draft and key for explicit retry',
    () async {
      final candidates = IdentificationCandidatesDomainAdapter(_Candidates())
        ..useVerifiedContext(context);
      final snapshot = (await candidates.lookup(targetKind: 'appliance'))!;
      final review = CandidateOnboardingReviewAdapter(candidates).review(
        snapshot: snapshot,
        activeContext: context,
        values: const CandidateOnboardingReview(
          name: 'Kitchen fridge',
          fuel: 'electricity',
        ),
        confirmed: true,
      );
      final source = _Source()
        ..allowCreate = true
        ..failDetailOnce = true;
      final lifecycle = _lifecycle(_Storage(), source);
      await lifecycle.selectVerifiedHome(owner, home);
      final bridge = CandidateOnboardingDraftBridge(
        candidates: candidates,
        lifecycle: lifecycle,
      );
      final pending = await bridge.stage(
        snapshot: snapshot,
        activeContext: context,
        review: review,
      );
      await expectLater(
        bridge.commit(
          activeContext: context,
          pending: pending,
          explicitlyApproved: true,
        ),
        throwsStateError,
      );
      final restored = (await bridge.restore(context))!;
      expect(restored.operationKey, pending.operationKey);
      expect(restored.draft.validated().matchQuality, 'unresolved');
      expect(source.posts, 1);
      expect(source.inventories, 0);
      expect(
        (await bridge.commit(
          activeContext: context,
          pending: restored,
          explicitlyApproved: true,
        ))?.homeId,
        home,
      );
      expect(source.posts, 1);
      expect(source.reads, 2);
      expect(source.inventories, 1);
      expect(await bridge.restore(context), isNull);
    },
  );

  test(
    'late create after verified scope change stops old-home readback',
    () async {
      final candidates = IdentificationCandidatesDomainAdapter(_Candidates())
        ..useVerifiedContext(context);
      final snapshot = (await candidates.lookup(targetKind: 'appliance'))!;
      final review = CandidateOnboardingReviewAdapter(candidates).review(
        snapshot: snapshot,
        activeContext: context,
        values: const CandidateOnboardingReview(
          name: 'Kitchen fridge',
          fuel: 'electricity',
        ),
        confirmed: true,
      );
      final storage = _Storage();
      final source = _Source()
        ..allowCreate = true
        ..createGate = Completer<void>()
        ..createEntered = Completer<void>();
      final lifecycle = _lifecycle(storage, source);
      await lifecycle.selectVerifiedHome(owner, home);
      final bridge = CandidateOnboardingDraftBridge(
        candidates: candidates,
        lifecycle: lifecycle,
      );
      final pending = await bridge.stage(
        snapshot: snapshot,
        activeContext: context,
        review: review,
      );
      final committing = bridge.commit(
        activeContext: context,
        pending: pending,
        explicitlyApproved: true,
      );
      await source.createEntered!.future;
      final switching = lifecycle.selectVerifiedHome(otherOwner, otherHome);
      source.createGate!.complete();
      expect(await committing, isNull);
      await switching;
      expect(source.posts, 1);
      expect(source.reads, 0);
      expect(source.inventories, 0);
      expect(await bridge.restore(context), isNull);
      expect(storage.value, isNull);
      expect(
        () => bridge.commit(
          activeContext: context,
          pending: pending,
          explicitlyApproved: true,
        ),
        throwsStateError,
      );
      expect(source.posts, 1);
    },
  );
}
