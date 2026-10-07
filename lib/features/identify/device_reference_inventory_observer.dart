import '../design/devices_domain_repository.dart';
import 'cloud_device_reference_resolver.dart';

/// Runs native reviewed-catalog lookups after a verified household read.
/// A catalog miss may still be waiting for KB research, so this observer does
/// not attach a human-help report or classify any measured energy.
class DeviceReferenceInventoryObserver {
  DeviceReferenceInventoryObserver(this.resolver);

  final CloudDeviceReferenceResolver resolver;
  final Set<String> _seen = {};
  final Map<String, DeviceReferenceResolution> _results = {};
  int _generation = 0;

  DeviceReferenceResolution? resultFor(String applianceId) =>
      _results[applianceId];

  void clear() {
    _generation++;
    _seen.clear();
    _results.clear();
  }

  Future<void> observe(DevicesDomainSnapshot snapshot) async {
    if (snapshot.isSample || snapshot.isCurrent?.call() == false) return;
    final generation = _generation;
    bool current() =>
        generation == _generation && (snapshot.isCurrent?.call() ?? true);
    final pending = <Future<void>>[];
    for (final item in snapshot.items) {
      final appliance = item.appliance;
      final key = [
        snapshot.homeId,
        appliance.id,
        appliance.brand,
        appliance.fullModel,
        appliance.variant ?? '',
        appliance.region ?? '',
        appliance.category,
        appliance.fuel,
        appliance.matchQuality,
        appliance.catalogProductId ?? '',
      ].join('\u001f');
      if (!_seen.add(key)) continue;
      pending.add(() async {
        try {
          if (!current()) return;
          final result = await resolver.resolve(appliance, isCurrent: current);
          if (!current()) return;
          if (result.status == DeviceReferenceStatus.lookupFailed) {
            _seen.remove(key);
            return;
          }
          _results[appliance.id] = result;
        } catch (_) {
          if (current()) _seen.remove(key);
        }
      }());
    }
    await Future.wait(pending);
  }
}
