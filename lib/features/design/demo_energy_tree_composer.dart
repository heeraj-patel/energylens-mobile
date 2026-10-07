import 'package:timezone/data/latest.dart' as tz_data;
import 'package:timezone/timezone.dart' as tz;

import '../../core/cloud_api/cloud_tariff.dart';
import 'demo_energy_tree.dart';
import 'demo_energy_tree_live_adapter.dart';
import 'devices_domain_repository.dart';

/// Composes one home-local calendar month from demo leaves and complete,
/// priced device days. The returned tree retains origin and evidence on every
/// leaf, and its device and home totals are derived from those leaves.
class DemoEnergyTreeComposer {
  const DemoEnergyTreeComposer({
    this.liveAdapter = const DemoEnergyTreeLiveAdapter(),
  });

  final DemoEnergyTreeLiveAdapter liveAdapter;

  DemoMonthTree compose({
    required String homeId,
    required String timezone,
    required DateTime referenceUtc,
    DevicesDomainSnapshot? snapshot,
    List<CloudTariff> electricityTariffs = const [],
    List<VerifiedDemoApplianceMapping> mappings = const [],
  }) {
    if (!referenceUtc.isUtc) {
      throw ArgumentError.value(referenceUtc, 'referenceUtc', 'Expected UTC');
    }
    tz_data.initializeTimeZones();
    late final tz.Location location;
    try {
      location = tz.getLocation(timezone);
    } catch (_) {
      throw const FormatException('Unknown demo timezone');
    }
    final local = tz.TZDateTime.from(referenceUtc, location);
    var tree = buildDemoMonthTree(
      homeId: homeId,
      year: local.year,
      month: local.month,
      timezone: timezone,
      referenceDay: local.day,
    );
    if (snapshot != null &&
        snapshot.homeId.toLowerCase() != homeId.toLowerCase()) {
      throw const FormatException('Devices snapshot belongs to another home');
    }
    if (snapshot == null ||
        snapshot.isSample ||
        snapshot.hasMoreMeteredPages ||
        snapshot.isCurrent?.call() == false) {
      return tree;
    }

    for (final day in tree.days) {
      final candidates = liveAdapter.readingsForDay(
        snapshot: snapshot,
        period: day.period,
        electricityTariffs: electricityTariffs,
        mappings: mappings,
      );
      // A duplicated appliance or mock target has ambiguous identity. Keep
      // the affected mock leaves, even if one candidate could merge first.
      final deviceCounts = <String, int>{};
      final targetCounts = <String, int>{};
      for (final candidate in candidates) {
        final deviceId = candidate.reading.deviceId.toLowerCase();
        deviceCounts.update(deviceId, (count) => count + 1, ifAbsent: () => 1);
        final target = candidate.mapping?.mockBranchId;
        if (target != null) {
          targetCounts.update(target, (count) => count + 1, ifAbsent: () => 1);
        }
      }
      for (final candidate in candidates) {
        if (deviceCounts[candidate.reading.deviceId.toLowerCase()] != 1 ||
            (candidate.mapping != null &&
                targetCounts[candidate.mapping!.mockBranchId] != 1)) {
          continue;
        }
        try {
          tree = candidate.mergeInto(tree);
        } on FormatException {
          // A malformed mapping or conflicting branch is not live evidence.
        }
      }
    }
    // A sign-out or home switch can invalidate the snapshot during traversal.
    // Discard every live merge rather than return a mixed stale view.
    if (snapshot.isCurrent?.call() == false) {
      return buildDemoMonthTree(
        homeId: homeId,
        year: local.year,
        month: local.month,
        timezone: timezone,
        referenceDay: local.day,
      );
    }
    return tree;
  }
}
