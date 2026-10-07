import '../../core/cloud_api/cloud_tariff.dart';
import 'demo_energy_tree.dart';
import 'devices_domain_repository.dart';

/// Owner-reviewed identity binding between a real appliance and one mock leaf.
/// A name match is never enough to replace a mock device.
class VerifiedDemoApplianceMapping {
  const VerifiedDemoApplianceMapping({
    required this.homeId,
    required this.applianceId,
    required this.mockBranchId,
    required this.evidenceId,
  });

  final String homeId;
  final String applianceId;
  final String mockBranchId;
  final String evidenceId;
}

class VerifiedDemoDeviceDay {
  const VerifiedDemoDeviceDay({required this.reading, this.mapping});

  final RealDeviceDay reading;
  final VerifiedDemoApplianceMapping? mapping;

  DemoMonthTree mergeInto(DemoMonthTree tree) => tree.mergeMeasured(
    reading,
    verifiedMockBranchId: mapping?.mockBranchId,
    mappingEvidenceId: mapping?.evidenceId,
  );
}

/// Converts a complete, owned, local-day meter bucket to a priced tree leaf.
/// The snapshot must be the authenticated household view and fully paged.
/// Each candidate needs exactly one matching bucket and one effective flat
/// electricity tariff for the whole day. A verified identity binding replaces
/// a mock leaf; otherwise the owned appliance joins as a distinct real leaf.
class DemoEnergyTreeLiveAdapter {
  const DemoEnergyTreeLiveAdapter();

  List<VerifiedDemoDeviceDay> readingsForDay({
    required DevicesDomainSnapshot snapshot,
    required DemoDayPeriod period,
    required List<CloudTariff> electricityTariffs,
    required List<VerifiedDemoApplianceMapping> mappings,
  }) {
    if (snapshot.isSample ||
        snapshot.hasMoreMeteredPages ||
        snapshot.isCurrent?.call() == false ||
        !_uuid.hasMatch(snapshot.homeId) ||
        period.seconds <= 0 ||
        !period.startUtc.isUtc ||
        !period.endUtc.isUtc) {
      return const [];
    }

    final rate = _applicableRate(snapshot.homeId, period, electricityTariffs);
    if (rate == null) return const [];

    final result = <VerifiedDemoDeviceDay>[];
    for (final item in snapshot.items) {
      final appliance = item.appliance;
      if (appliance.homeId.toLowerCase() != snapshot.homeId.toLowerCase() ||
          !_uuid.hasMatch(appliance.id) ||
          appliance.archivedAt != null ||
          appliance.fuel != 'electricity') {
        continue;
      }
      final matchingMappings = mappings
          .where(
            (m) =>
                m.homeId.toLowerCase() == snapshot.homeId.toLowerCase() &&
                m.applianceId.toLowerCase() == appliance.id.toLowerCase() &&
                m.mockBranchId.startsWith('demo-device-') &&
                m.evidenceId.trim().isNotEmpty,
          )
          .toList();
      if (matchingMappings.length > 1 ||
          (matchingMappings.isNotEmpty &&
              mappings
                      .where(
                        (m) =>
                            m.homeId.toLowerCase() ==
                                snapshot.homeId.toLowerCase() &&
                            m.mockBranchId ==
                                matchingMappings.single.mockBranchId,
                      )
                      .length !=
                  1)) {
        continue;
      }

      final buckets = item.measuredBuckets
          .where(
            (b) =>
                b.bucketStart.isAtSameMomentAs(period.startUtc) &&
                b.ownershipCoversBucket &&
                item.activeAttachmentIds.contains(b.attachmentId) &&
                b.coveredSeconds == period.seconds &&
                b.energyWh.isFinite &&
                b.energyWh > 0 &&
                b.energyWh == b.energyWh.roundToDouble(),
          )
          .toList();
      if (buckets.length != 1) continue;
      final bucket = buckets.single;
      result.add(
        VerifiedDemoDeviceDay(
          mapping: matchingMappings.isEmpty ? null : matchingMappings.single,
          reading: RealDeviceDay(
            homeId: snapshot.homeId,
            deviceId: appliance.id,
            period: period,
            coveredSeconds: period.seconds,
            usefulWh: 0,
            wasteWh: 0,
            unclassifiedWh: bucket.energyWh.round(),
            tariffRateUnitsPerKwh: rate.units,
            tariffId: rate.id,
            meterEvidenceId:
                '${bucket.attachmentId}:${bucket.bucketStart.toIso8601String()}:${bucket.computedAt.toIso8601String()}',
          ),
        ),
      );
    }
    return List.unmodifiable(result);
  }
}

({String id, int units})? _applicableRate(
  String homeId,
  DemoDayPeriod period,
  List<CloudTariff> tariffs,
) {
  final applicable = tariffs.where((t) {
    if (t.homeId.toLowerCase() != homeId.toLowerCase() ||
        t.id == null ||
        t.id!.isEmpty ||
        t.fuel != 'electricity' ||
        t.rateUnit != 'kWh' ||
        t.currency != 'USD' ||
        t.effectiveFrom.toUtc().isAfter(period.startUtc) ||
        (t.effectiveTo != null &&
            t.effectiveTo!.toUtc().isBefore(period.endUtc))) {
      return false;
    }
    return true;
  }).toList();
  if (applicable.length != 1) return null;
  final tariff = applicable.single;
  final match = RegExp(r'^(0|[1-9][0-9]{0,9})(?:\.([0-9]{1,8}))?$')
      .firstMatch(tariff.rate);
  if (match == null) return null;
  final fractional = (match.group(2) ?? '').padRight(8, '0');
  final units =
      int.parse(match.group(1)!) * 100000000 +
      int.parse(fractional.isEmpty ? '0' : fractional);
  if (units <= 0) return null;
  return (id: tariff.id!, units: units);
}

final _uuid = RegExp(
  r'^[0-9a-fA-F]{8}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{12}$',
);
