import '../discovery/discovery_api.dart';
import '../discovery/discovery_credentials.dart';
import 'design_context_coordinator.dart';
import 'manage_devices_domain_repository.dart';

/// Candidate results are bound to the verified household that requested them.
/// Identification confidence remains a review hint and never confirms a model.
class IdentificationCandidatesSnapshot {
  const IdentificationCandidatesSnapshot({
    required this.accountId,
    required this.homeId,
    required this.generation,
    required this.candidates,
  });

  final String accountId;
  final String homeId;

  /// Context/lookup generation at the time this result was produced.
  final int generation;
  final List<DeviceScanReview> candidates;
}

abstract interface class IdentificationCandidatesSource {
  Future<List<IdentificationCandidate>> lookup({
    required String targetKind,
    String? ocrText,
    String? upc,
  });
}

/// Uses the same local discovery service as appliance onboarding.
class DiscoveryIdentificationCandidatesSource
    implements IdentificationCandidatesSource {
  const DiscoveryIdentificationCandidatesSource({
    this.api = const DiscoveryApi(),
    this.credentials = const DiscoveryCredentials(),
  });

  final DiscoveryApi api;
  final DiscoveryCredentials credentials;

  @override
  Future<List<IdentificationCandidate>> lookup({
    required String targetKind,
    String? ocrText,
    String? upc,
  }) async {
    final (address, token) = await credentials.read();
    if (address == null || token == null || token.isEmpty) {
      throw StateError('Identification service is not configured');
    }
    return api.identifyCandidates(
      address,
      token,
      targetKind: targetKind,
      ocrText: ocrText,
      upc: upc,
    );
  }
}

/// Nonvisual lookup boundary for verified design context.
class IdentificationCandidatesDomainAdapter {
  IdentificationCandidatesDomainAdapter(this.source);

  final IdentificationCandidatesSource source;
  VerifiedDesignContext? _context;
  int _generation = 0;

  VerifiedDesignContext? get context => _context;

  void useVerifiedContext(VerifiedDesignContext context) {
    final previous = _context;
    if (previous?.accountId == context.accountId &&
        previous?.homeId == context.homeId &&
        previous?.mode == context.mode) {
      return;
    }
    _context = context;
    _generation++;
  }

  void clear() {
    _context = null;
    _generation++;
  }

  /// True only while this exact account, home, and lookup remain active.
  bool isCurrent(IdentificationCandidatesSnapshot snapshot) {
    final context = _context;
    return context != null &&
        context.mode == DesignContextMode.household &&
        context.accountId == snapshot.accountId &&
        context.homeId == snapshot.homeId &&
        snapshot.generation == _generation;
  }

  Future<IdentificationCandidatesSnapshot?> lookup({
    required String targetKind,
    String? ocrText,
    String? upc,
  }) async {
    final context = _context;
    if (context == null || context.mode != DesignContextMode.household) {
      throw StateError('No verified household for identification lookup');
    }
    if (targetKind.isEmpty) throw ArgumentError.value(targetKind, 'targetKind');
    // A later lookup invalidates previously returned review candidates.
    final generation = ++_generation;
    bool stale() =>
        generation != _generation ||
        _context?.accountId != context.accountId ||
        _context?.homeId != context.homeId ||
        _context?.mode != context.mode;

    try {
      final candidates = await source.lookup(
        targetKind: targetKind,
        ocrText: ocrText,
        upc: upc,
      );
      if (stale()) return null;
      return IdentificationCandidatesSnapshot(
        accountId: context.accountId,
        homeId: context.homeId,
        generation: generation,
        candidates: List.unmodifiable(candidates.map(DeviceScanReview.new)),
      );
    } catch (_) {
      if (stale()) return null;
      rethrow;
    }
  }
}
