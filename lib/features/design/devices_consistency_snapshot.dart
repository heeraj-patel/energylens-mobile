import 'devices_domain_repository.dart';
import 'devices_runtime_evidence_adapter.dart';

/// Two independent observations accepted under one verified native context.
/// Neither source has a shared server revision, so this is not an atomic
/// household measurement or a basis for a derived total.
class DevicesConsistencySnapshot {
  const DevicesConsistencySnapshot(
    this._inventory,
    this._runtimeEvidence, {
    required this.isCurrent,
  });

  final DevicesDomainSnapshot _inventory;
  final DevicesRuntimeEvidenceSnapshot _runtimeEvidence;
  final bool Function() isCurrent;

  DevicesDomainSnapshot get inventory {
    requireCurrent();
    return _inventory;
  }

  DevicesRuntimeEvidenceSnapshot get runtimeEvidence {
    requireCurrent();
    return _runtimeEvidence;
  }

  /// Call before using either snapshot after an asynchronous boundary.
  void requireCurrent() {
    if (!isCurrent()) throw StateError('Devices consistency read is stale');
  }

  double? get householdEnergyWh => null;
  double? get householdCost => null;
  double? get householdWasteWh => null;
  String? get liveState => null;
}
