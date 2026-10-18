import '../design/design_context_coordinator.dart';
import '../design/identification_candidates_domain_adapter.dart';
import '../design/manage_devices_domain_repository.dart';
import 'onboarding_persistence_repository.dart';

/// Values a person has supplied or reviewed while resolving a scan candidate.
/// Candidate text may fill brand, model, and category hints, but never fuel or
/// the appliance name.
class CandidateOnboardingReview {
  const CandidateOnboardingReview({
    this.name,
    this.category,
    this.brand,
    this.fullModel,
    this.fuel,
    this.room,
    this.fccId,
    this.icId,
    this.serialNumber,
    this.upc,
  });

  final String? name;
  final String? category;
  final String? brand;
  final String? fullModel;
  final String? fuel;
  final String? room;
  final String? fccId;
  final String? icId;
  final String? serialNumber;
  final String? upc;
}

enum CandidateOnboardingReviewState {
  ready,
  ambiguous,
  missingFields,
  staleContext,
  awaitingConfirmation,
}

class CandidateOnboardingReviewResult {
  const CandidateOnboardingReviewResult({
    required this.state,
    this.draft,
    this.choices = const [],
    this.missingFields = const [],
  });

  final CandidateOnboardingReviewState state;
  final OnboardingDraft? draft;
  final List<DeviceScanReview> choices;
  final List<String> missingFields;
}

/// Converts scan hints into an unresolved draft after an explicit human review.
/// This adapter has no persistence dependency and cannot create or save a row.
class CandidateOnboardingReviewAdapter {
  const CandidateOnboardingReviewAdapter(this.candidateSnapshots);

  final IdentificationCandidatesDomainAdapter candidateSnapshots;

  CandidateOnboardingReviewResult review({
    required IdentificationCandidatesSnapshot snapshot,
    required VerifiedDesignContext? activeContext,
    required CandidateOnboardingReview values,
    int? selectedCandidateIndex,
    required bool confirmed,
  }) {
    if (activeContext == null ||
        activeContext.mode != DesignContextMode.household ||
        snapshot.homeId != activeContext.homeId ||
        snapshot.accountId != activeContext.accountId ||
        !candidateSnapshots.isCurrent(snapshot)) {
      return const CandidateOnboardingReviewResult(
        state: CandidateOnboardingReviewState.staleContext,
      );
    }

    final candidates = snapshot.candidates;
    if (candidates.isEmpty) {
      return const CandidateOnboardingReviewResult(
        state: CandidateOnboardingReviewState.missingFields,
        missingFields: ['category'],
      );
    }
    if (selectedCandidateIndex == null && candidates.length > 1) {
      return CandidateOnboardingReviewResult(
        state: CandidateOnboardingReviewState.ambiguous,
        choices: List.unmodifiable(candidates),
      );
    }
    final index = selectedCandidateIndex ?? 0;
    if (index < 0 || index >= candidates.length) {
      return CandidateOnboardingReviewResult(
        state: CandidateOnboardingReviewState.ambiguous,
        choices: List.unmodifiable(candidates),
      );
    }

    final candidate = candidates[index];
    final name = _value(values.name);
    final category =
        _value(values.category) ?? _value(candidate.candidate.category);
    final brand = _value(values.brand) ?? _value(candidate.brandHint);
    final model = _value(values.fullModel) ?? _value(candidate.modelHint);
    final fuel = _value(values.fuel);
    final missing = <String>[
      if (name == null) 'name',
      if (category == null) 'category',
      if (fuel == null) 'fuel',
    ];
    if (missing.isNotEmpty) {
      return CandidateOnboardingReviewResult(
        state: CandidateOnboardingReviewState.missingFields,
        missingFields: List.unmodifiable(missing),
      );
    }
    if (!confirmed) {
      return const CandidateOnboardingReviewResult(
        state: CandidateOnboardingReviewState.awaitingConfirmation,
      );
    }

    final draft = OnboardingDraft(
      name: name!,
      category: category!,
      brand: brand ?? '',
      fullModel: model ?? '',
      fuel: fuel!,
      room: _value(values.room),
      fccId: _value(values.fccId),
      icId: _value(values.icId),
      serialNumber: _value(values.serialNumber),
      upc: _value(values.upc),
    );
    // Validation also rejects values that are present but unusable.
    draft.validated();
    return CandidateOnboardingReviewResult(
      state: CandidateOnboardingReviewState.ready,
      draft: draft,
    );
  }

  String? _value(String? value) {
    final trimmed = value?.trim();
    return trimmed == null || trimmed.isEmpty ? null : trimmed;
  }
}
