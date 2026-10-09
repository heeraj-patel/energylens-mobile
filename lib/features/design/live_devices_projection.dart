import '../../core/cloud_api/cloud_appliance_list.dart';
import '../../core/cloud_api/cloud_household_energy.dart';

import 'package:timezone/data/latest.dart' as tz_data;
import 'package:timezone/timezone.dart' as tz;

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
    this.wasteCost,
  });

  final String applianceId;
  final String name;
  final String manufacturer;
  final String model;
  final LiveDeviceMeasuredBucket? measuredBucket;

  /// Display-only rate, available only after a typed final KB waste miss.
  final int? demoWasteMicrosPerDay;
  final String? wasteCost;
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
      (value.dataMode != CloudApplianceDataMode.household
          ? value.fixtureRevision == null || value.fixtureRevision!.isEmpty
          : value.fixtureRevision != null) ||
      current == null ||
      !current() ||
      value.items.length > DevicesDomainSnapshot.maxLocalInventory) {
    throw const FormatException('Devices projection context changed');
  }

  final ids = <String>{};
  final rows = <LiveDeviceRow>[];
  final dailyCosts = _realDailyCosts(value);
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
    if (appliance.demoDeviceId != null) continue;
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
    final dailyCost = dailyCosts[appliance.id];
    int? illustrativeWaste;
    if (read.mode == DesignContextMode.household &&
        appliance.demoDeviceId == null &&
        appliance.kbWasteResult?.status ==
            'waste_evidence_unavailable_after_kb') {
      illustrativeWaste = switch (dummyWasteDrawForProfile(
        appliance.category,
      )) {
        DummyWasteDraw.low => dummyIdleHoursPerLocalDay * 100,
        DummyWasteDraw.high => dummyIdleHoursPerLocalDay * 10000,
        null => null,
      };
      final measuredTotal = dailyCost?.totalMicros;
      if (illustrativeWaste != null &&
          measuredTotal != null &&
          measuredTotal < BigInt.from(illustrativeWaste)) {
        illustrativeWaste = measuredTotal.toInt();
      }
    }
    rows.add(
      LiveDeviceRow(
        applianceId: appliance.id,
        name: appliance.name,
        manufacturer: appliance.brand,
        model: appliance.fullModel,
        measuredBucket: bucket,
        wasteCost: dailyCost?.wasteCost,
        demoWasteMicrosPerDay: illustrativeWaste,
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

class _DailyRealCost {
  const _DailyRealCost(this.wasteCost, this.totalMicros);
  final String? wasteCost;
  final BigInt totalMicros;
}

Map<String, _DailyRealCost> _realDailyCosts(DevicesDomainSnapshot snapshot) {
  tz_data.initializeTimeZones();
  final costs = snapshot.sampleDayCosts;
  if (costs == null ||
      costs.homeId.toLowerCase() != snapshot.homeId.toLowerCase() ||
      costs.dataMode != snapshot.dataMode.name ||
      costs.fixtureRevision != snapshot.fixtureRevision ||
      costs.granularity != 'day') {
    return const {};
  }
  tz.Location location;
  try {
    location = tz.getLocation(costs.timezone);
  } catch (_) {
    return const {};
  }
  final now = tz.TZDateTime.from(costs.generatedAt, location);
  final buckets = costs.buckets.where((bucket) {
    final start = tz.TZDateTime.from(bucket.period.start, location);
    return start.year == now.year &&
        start.month == now.month &&
        start.day == now.day;
  }).toList();
  if (buckets.length != 1) return const {};
  final rows = <String, _DailyRealCost>{};
  for (final row in buckets.single.deviceAllocations) {
    final id = row.applianceId;
    if (id == null || row.deviceId != null || rows.containsKey(id)) continue;
    final allocation = row.allocation;
    final total = _usdMicros(allocation.cost);
    final useful = _usdMicros(allocation.usefulCost);
    final waste = _usdMicros(allocation.wasteCost);
    if (total == null ||
        !const {'measured', 'mixed'}.contains(allocation.evidenceBasis) ||
        (useful != null && useful > total) ||
        (waste != null && waste > total) ||
        (useful != null && waste != null && useful + waste > total)) {
      continue;
    }
    rows[id] = _DailyRealCost(_costText(waste), total);
  }
  return rows;
}

BigInt? _usdMicros(CloudEnergyMoney? value) {
  if (value == null ||
      value.currency != 'USD' ||
      !RegExp(r'^(0|[1-9][0-9]*)(\.[0-9]{1,6})?$').hasMatch(value.amount)) {
    return null;
  }
  final parts = value.amount.split('.');
  return BigInt.parse(parts[0]) * BigInt.from(1000000) +
      BigInt.parse((parts.length == 1 ? '' : parts[1]).padRight(6, '0'));
}

String? _costText(BigInt? micros) {
  if (micros == null) return null;
  final cents = (micros + BigInt.from(5000)) ~/ BigInt.from(10000);
  return '\$${cents ~/ BigInt.from(100)}.${(cents % BigInt.from(100)).toString().padLeft(2, '0')}';
}
