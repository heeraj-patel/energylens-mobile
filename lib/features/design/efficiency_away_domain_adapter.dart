import '../../core/cloud_api/cloud_estimate.dart';
import 'efficiency_domain_repository.dart';

/// Availability of an Away claim in the current backend contract.
///
/// Appliance operating estimates and household energy totals do not establish
/// occupancy, vacancy windows, or savings caused by being away.
enum AwayEvidenceAvailability { unknown, unsupported }

/// Nonvisual, evidence-backed view of the Away domain.
///
/// This adapter deliberately does not infer vacancy from low consumption or
/// turn operating estimates into avoided-cost claims.
class EfficiencyAwayDomainSnapshot {
  const EfficiencyAwayDomainSnapshot(this.efficiency);

  final EfficiencyDomainSnapshot efficiency;

  String get homeId => efficiency.homeId;
  String get householdSnapshotId => efficiency.energy.snapshotId;
  String get dataMode => efficiency.energy.dataMode;

  /// Existing estimates remain available with their source period and quality.
  /// They are not classified as Away events.
  List<CloudEstimate> get operatingEstimates => efficiency.operatingEstimates;

  /// No existing API supplies reviewed occupancy evidence.
  AwayEvidenceAvailability get occupancyAvailability =>
      AwayEvidenceAvailability.unknown;

  /// The current contract does not identify away-event windows.
  AwayEvidenceAvailability get awayEventAvailability =>
      AwayEvidenceAvailability.unsupported;

  /// No supported counterfactual connects these estimates to Away savings.
  AwayEvidenceAvailability get savingsAvailability =>
      AwayEvidenceAvailability.unsupported;

  /// No event is emitted unless a backend contract supplies the event and its
  /// occupancy/context evidence.
  List<Never> get awayEvents => const [];

  /// A missing Away savings value is unknown, never a computed zero.
  String? get savingsAmount => null;
}

/// Fetches Away evidence through the existing authenticated Efficiency
/// repository. It adds no route and owns response freshness across calls.
class EfficiencyAwayDomainAdapter {
  EfficiencyAwayDomainAdapter(this.repository);

  final EfficiencyDomainRepository repository;
  String? _homeId;
  int _generation = 0;

  void clear() {
    _homeId = null;
    _generation++;
  }

  Future<EfficiencyAwayDomainSnapshot?> fetch(String homeId) async {
    _homeId = homeId;
    final generation = ++_generation;
    bool stale() => generation != _generation || _homeId != homeId;

    final result = await repository.fetch(homeId, EfficiencyPage.away);
    if (stale() || result == null) return null;
    if (result.homeId.toLowerCase() != homeId.toLowerCase() ||
        result.page != EfficiencyPage.away) {
      throw const FormatException('Away evidence belongs to another request');
    }
    return EfficiencyAwayDomainSnapshot(result);
  }
}
