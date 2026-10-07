import 'package:flutter_test/flutter_test.dart';
import 'package:energylens_mobile/features/design/design_context_coordinator.dart';
import 'package:energylens_mobile/features/design/identification_candidates_domain_adapter.dart';
import 'package:energylens_mobile/features/design/manage_devices_domain_repository.dart';
import 'package:energylens_mobile/features/discovery/discovery_api.dart';
import 'package:energylens_mobile/features/identify/candidate_onboarding_review_adapter.dart';

const home = '11111111-1111-4111-8111-111111111111';
const otherHome = '22222222-2222-4222-8222-222222222222';
final context = VerifiedDesignContext(
  accountId: 'owner',
  homeId: home,
  mode: DesignContextMode.household,
);
final otherAccountSameHome = VerifiedDesignContext(
  accountId: 'different-owner',
  homeId: home,
  mode: DesignContextMode.household,
);

DeviceScanReview candidate(String model, {String? category = 'refrigerator'}) =>
    DeviceScanReview(
      IdentificationCandidate(
        manufacturer: 'Acme',
        model: model,
        category: category,
        confidence: .99,
        source: 'ocr',
        matchedKinds: const ['refrigerator'],
      ),
    );

const completeValues = CandidateOnboardingReview(
  name: 'Kitchen refrigerator',
  fuel: 'electricity',
);

class _Source implements IdentificationCandidatesSource {
  List<IdentificationCandidate> result = [];

  @override
  Future<List<IdentificationCandidate>> lookup({
    required String targetKind,
    String? ocrText,
    String? upc,
  }) async => result;
}

class _Harness {
  final source = _Source();
  late final candidateAdapter = IdentificationCandidatesDomainAdapter(source);
  late final adapter = CandidateOnboardingReviewAdapter(candidateAdapter);

  Future<IdentificationCandidatesSnapshot> lookup(
    List<DeviceScanReview> results, {
    VerifiedDesignContext? verifiedContext,
  }) async {
    source.result = results.map((review) => review.candidate).toList();
    candidateAdapter.useVerifiedContext(verifiedContext ?? context);
    return (await candidateAdapter.lookup(targetKind: 'appliance'))!;
  }
}

void main() {
  test(
    'review creates a valid unresolved draft only after confirmation',
    () async {
      final harness = _Harness();
      final snapshot = await harness.lookup([candidate('RF-100')]);
      final result = harness.adapter.review(
        snapshot: snapshot,
        activeContext: context,
        values: completeValues,
        confirmed: true,
      );

      expect(result.state, CandidateOnboardingReviewState.ready);
      expect(result.draft!.fullModel, 'RF-100');
      expect(result.draft!.validated().matchQuality, 'unresolved');
      expect(result.draft!.validated().catalogProductId, isNull);
    },
  );

  test('ambiguous candidates remain available until one is selected', () async {
    final harness = _Harness();
    final snapshot = await harness.lookup([
      candidate('RF-100'),
      candidate('RF-200'),
    ]);
    final result = harness.adapter.review(
      snapshot: snapshot,
      activeContext: context,
      values: completeValues,
      confirmed: true,
    );
    expect(result.state, CandidateOnboardingReviewState.ambiguous);
    expect(result.choices.map((choice) => choice.modelHint), [
      'RF-100',
      'RF-200',
    ]);
    expect(result.draft, isNull);
  });

  test(
    'missing reviewer-supplied name and fuel blocks draft creation',
    () async {
      final harness = _Harness();
      final snapshot = await harness.lookup([candidate('RF-100')]);
      final result = harness.adapter.review(
        snapshot: snapshot,
        activeContext: context,
        values: const CandidateOnboardingReview(),
        confirmed: true,
      );
      expect(result.state, CandidateOnboardingReviewState.missingFields);
      expect(result.missingFields, containsAll(['name', 'fuel']));
      expect(result.draft, isNull);
    },
  );

  test('rejects stale and cross-home snapshots', () async {
    final harness = _Harness();
    final snapshot = await harness.lookup([candidate('RF-100')]);
    final crossHome = IdentificationCandidatesSnapshot(
      accountId: snapshot.accountId,
      homeId: otherHome,
      generation: snapshot.generation,
      candidates: snapshot.candidates,
    );
    final stale = harness.adapter.review(
      snapshot: crossHome,
      activeContext: context,
      values: completeValues,
      confirmed: true,
    );
    final missingContext = harness.adapter.review(
      snapshot: snapshot,
      activeContext: null,
      values: completeValues,
      confirmed: true,
    );
    expect(stale.state, CandidateOnboardingReviewState.staleContext);
    expect(missingContext.state, CandidateOnboardingReviewState.staleContext);
  });

  test(
    'same-home account switch invalidates earlier candidate snapshot',
    () async {
      final harness = _Harness();
      final snapshot = await harness.lookup([candidate('RF-100')]);
      harness.candidateAdapter.useVerifiedContext(otherAccountSameHome);

      final result = harness.adapter.review(
        snapshot: snapshot,
        activeContext: otherAccountSameHome,
        values: completeValues,
        confirmed: true,
      );
      expect(result.state, CandidateOnboardingReviewState.staleContext);
      expect(result.draft, isNull);
    },
  );

  test('a newer lookup invalidates the previously returned snapshot', () async {
    final harness = _Harness();
    final oldSnapshot = await harness.lookup([candidate('RF-100')]);
    await harness.lookup([candidate('RF-200')]);

    final result = harness.adapter.review(
      snapshot: oldSnapshot,
      activeContext: context,
      values: completeValues,
      confirmed: true,
    );
    expect(result.state, CandidateOnboardingReviewState.staleContext);
    expect(result.draft, isNull);
  });

  test('OCR confidence cannot replace explicit confirmation', () async {
    final harness = _Harness();
    final snapshot = await harness.lookup([candidate('RF-100')]);
    final result = harness.adapter.review(
      snapshot: snapshot,
      activeContext: context,
      values: completeValues,
      confirmed: false,
    );
    expect(result.state, CandidateOnboardingReviewState.awaitingConfirmation);
    expect(result.draft, isNull);
  });
}
