import '../design/design_context_coordinator.dart';
import '../design/identification_candidates_domain_adapter.dart';
import '../../core/cloud_auth/cloud_auxiliary_domain_lifecycle.dart';
import '../../core/cloud_api/cloud_appliance.dart';
import 'candidate_onboarding_review_adapter.dart';
import 'onboarding_draft_store.dart';

/// Stages only a ready, explicitly confirmed unresolved review for its verified
/// account and home. Staging is local; it never creates an appliance.
class CandidateOnboardingDraftBridge {
  const CandidateOnboardingDraftBridge({
    required this.candidates,
    required this.lifecycle,
  });

  final IdentificationCandidatesDomainAdapter candidates;
  final CloudAuxiliaryDomainLifecycle lifecycle;

  Future<PendingOnboardingDraft> stage({
    required IdentificationCandidatesSnapshot snapshot,
    required VerifiedDesignContext? activeContext,
    required CandidateOnboardingReviewResult review,
  }) async {
    final draft = review.draft;
    if (review.state != CandidateOnboardingReviewState.ready ||
        draft == null ||
        draft.validated().matchQuality != 'unresolved' ||
        activeContext == null ||
        activeContext.mode != DesignContextMode.household ||
        snapshot.accountId != activeContext.accountId ||
        snapshot.homeId != activeContext.homeId ||
        !lifecycle.isVerifiedScope(
          activeContext.accountId,
          activeContext.homeId,
        ) ||
        !candidates.isCurrent(snapshot)) {
      throw StateError('Candidate review is no longer stageable');
    }
    if (!candidates.isCurrent(snapshot)) {
      throw StateError('Candidate review became stale before staging');
    }
    return lifecycle.stageOnboardingDraft(
      activeContext.accountId,
      activeContext.homeId,
      draft,
    );
  }

  Future<PendingOnboardingDraft?> restore(
    VerifiedDesignContext? activeContext,
  ) async {
    if (activeContext == null ||
        activeContext.mode != DesignContextMode.household) {
      await lifecycle.clear();
      return null;
    }
    if (!lifecycle.isVerifiedScope(
      activeContext.accountId,
      activeContext.homeId,
    )) {
      return null;
    }
    return lifecycle.restoreOnboardingDraft(
      activeContext.accountId,
      activeContext.homeId,
    );
  }

  /// Explicitly commits a staged review through appliance mutation/readback.
  Future<CloudAppliance?> commit({
    required VerifiedDesignContext? activeContext,
    required PendingOnboardingDraft pending,
    required bool explicitlyApproved,
  }) {
    if (activeContext == null ||
        activeContext.mode != DesignContextMode.household ||
        !lifecycle.isVerifiedScope(
          activeContext.accountId,
          activeContext.homeId,
        )) {
      throw StateError('No verified account and home for candidate commit');
    }
    return lifecycle.commitOnboardingDraft(
      activeContext.accountId,
      activeContext.homeId,
      pending,
      explicitlyApproved: explicitlyApproved,
    );
  }

  Future<void> clear() => lifecycle.clear();
}
