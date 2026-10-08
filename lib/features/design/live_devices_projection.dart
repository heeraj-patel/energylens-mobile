import '../../core/cloud_api/cloud_appliance_list.dart';
import 'design_context_coordinator.dart';
import 'devices_domain_repository.dart';
import 'demo_energy_tree.dart';

/// Native-only projection. A bucket is an observation with partial coverage,
/// not a device total, current power, cost, or operating state.
class LiveDeviceMeasuredBucket {
  const LiveDeviceMeasuredBucket({
    required this.energyWh,
    required this.bucketStart,
    required this.computedAt,
    required this.coveredSeconds,
  });

  final double energyWh;
  final DateTime bucketStart;
  final DateTime computedAt;
  final double coveredSeconds;
}

class LiveDeviceRow {
  const LiveDeviceRow({
    required this.applianceId,
    required this.name,
    this.manufacturer = '',
    this.model = '',
    required this.measuredBucket,
    this.demoWasteMicrosPerDay,
  });

  final String applianceId;
  final String name;
  final String manufacturer;
  final String model;
  final LiveDeviceMeasuredBucket? measuredBucket;

  /// Display-only rate, available only after a typed final KB waste miss.
  final int? demoWasteMicrosPerDay;
}

class LiveDevicesProjection {
  const LiveDevicesProjection({
    required this.homeId,
    required this.mode,
    required this.fixtureRevision,
    required this.hasMoreMeteredPages,
    required this.rows,
  });

  final String homeId;
  final DesignContextMode mode;
  final String? fixtureRevision;
  final bool hasMoreMeteredPages;
  final List<LiveDeviceRow> rows;
}

/// The coordinator owns the read lifetime; the snapshot must remain current
/// during projection. No values are synthesized when metered evidence is absent.
LiveDevicesProjection prepareLiveDevicesProjection(DesignContextRead read) {
  final value = read.value;
  if (read.page != 'devices' || value is! DevicesDomainSnapshot) {
    throw ArgumentError.value(read.page, 'page', 'Unsupported device read');
  }
  final current = value.isCurrent;
  if (read.accountId.isEmpty ||
      read.homeId.isEmpty ||
      value.homeId.toLowerCase() != read.homeId.toLowerCase() ||
      value.isSample != (read.mode == DesignContextMode.sample) ||
      (value.isSample
          ? value.fixtureRevision == null || value.fixtureRevision!.isEmpty
          : value.fixtureRevision != null) ||
      current == null ||
      !current() ||
      value.items.length > DevicesDomainSnapshot.maxLocalInventory) {
    throw const FormatException('Devices projection context changed');
  }

  final ids = <String>{};
  final rows = <LiveDeviceRow>[];
  for (final item in value.items) {
    final appliance = item.appliance;
    if (appliance.homeId.toLowerCase() != read.homeId.toLowerCase() ||
        appliance.id.isEmpty ||
        !ids.add(appliance.id) ||
        appliance.name.trim().isEmpty ||
        appliance.archivedAt != null ||
        (value.dataMode == CloudApplianceDataMode.sample &&
            item.measuredBuckets.isNotEmpty)) {
      throw const FormatException('Invalid Devices projection row');
    }
    LiveDeviceMeasuredBucket? bucket;
    DeviceMeasuredBucket? latest;
    for (final observed in item.measuredBuckets) {
      if (!observed.energyWh.isFinite ||
          observed.energyWh < 0 ||
          !observed.coveredSeconds.isFinite ||
          observed.coveredSeconds <= 0 ||
          observed.coveredSeconds > 86400 ||
          !observed.bucketStart.isUtc ||
          !observed.computedAt.isUtc ||
          observed.computedAt.isBefore(observed.bucketStart)) {
        throw const FormatException('Invalid measured device bucket');
      }
      if (latest == null ||
          observed.bucketStart.isAfter(latest.bucketStart) ||
          (observed.bucketStart == latest.bucketStart &&
              observed.computedAt.isAfter(latest.computedAt))) {
        latest = observed;
      }
    }
    if (latest != null) {
      bucket = LiveDeviceMeasuredBucket(
        energyWh: latest.energyWh,
        bucketStart: latest.bucketStart,
        computedAt: latest.computedAt,
        coveredSeconds: latest.coveredSeconds,
      );
    }
    rows.add(
      LiveDeviceRow(
        applianceId: appliance.id,
        name: appliance.name,
        manufacturer: appliance.brand,
        model: appliance.fullModel,
        measuredBucket: bucket,
        demoWasteMicrosPerDay:
            bucket == null &&
                read.mode == DesignContextMode.household &&
                appliance.kbWasteResult?.status ==
                    'waste_evidence_unavailable_after_kb'
            ? switch (dummyWasteDrawForProfile(appliance.category)) {
                DummyWasteDraw.low => dummyIdleHoursPerLocalDay * 100,
                DummyWasteDraw.high => dummyIdleHoursPerLocalDay * 10000,
                null => null,
              }
            : null,
      ),
    );
  }
  if (!current()) {
    throw const FormatException('Devices projection became stale');
  }
  rows.sort((a, b) => a.applianceId.compareTo(b.applianceId));
  return LiveDevicesProjection(
    homeId: value.homeId,
    mode: read.mode,
    fixtureRevision: value.fixtureRevision,
    hasMoreMeteredPages: value.hasMoreMeteredPages,
    rows: List.unmodifiable(rows),
  );
}
