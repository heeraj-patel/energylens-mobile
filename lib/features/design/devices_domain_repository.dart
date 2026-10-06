import '../../core/cloud_api/cloud_api_client.dart';
import '../../core/cloud_api/cloud_appliance.dart';
import '../../core/cloud_api/cloud_interventions.dart';
import '../../core/cloud_api/cloud_metered_summary.dart';
import '../../core/cloud_api/cloud_sensor.dart';

/// Owner-scoped reads used by the Devices domain. These endpoints do not share
/// a snapshot token, so their results must not be added into a household total.
abstract interface class DevicesDomainSource {
  Future<List<CloudAppliance>> appliances(String homeId);
  Future<List<CloudAttachment>> attachments(String homeId);
  Future<List<CloudSensor>> sensors(String homeId);
  Future<CloudMeteredSummaryPage> meteredSummaries(String homeId);
}

class CloudDevicesDomainSource implements DevicesDomainSource {
  const CloudDevicesDomainSource(this.api);
  final CloudApiClient api;

  @override
  Future<List<CloudAppliance>> appliances(String homeId) =>
      api.appliances(homeId);
  @override
  Future<List<CloudAttachment>> attachments(String homeId) =>
      api.attachments(homeId);
  @override
  Future<List<CloudSensor>> sensors(String homeId) => api.sensors(homeId);
  @override
  Future<CloudMeteredSummaryPage> meteredSummaries(String homeId) =>
      api.meteredSummaries(homeId, granularity: 'day');
}

/// One measured bucket, with its own time and coverage. It is not a full-day
/// or current-use estimate and cannot be safely summed across these reads.
class DeviceMeasuredBucket {
  const DeviceMeasuredBucket({
    required this.bucketStart,
    required this.computedAt,
    required this.energyWh,
    required this.coveredSeconds,
    required this.attachmentId,
  });
  final DateTime bucketStart;
  final DateTime computedAt;
  final double energyWh;
  final double coveredSeconds;
  final String attachmentId;
}

class DeviceInventoryItem {
  const DeviceInventoryItem({
    required this.appliance,
    required this.activeAttachmentIds,
    required this.measuredBuckets,
  });
  final CloudAppliance appliance;
  final List<String> activeAttachmentIds;
  final List<DeviceMeasuredBucket> measuredBuckets;

  /// No tariff, waste policy or live state is established by these endpoints.
  double? get cost => null;
  double? get wasteEnergyWh => null;
  String? get liveState => null;
}

class DevicesDomainSnapshot {
  const DevicesDomainSnapshot({
    required this.homeId,
    required this.items,
    required this.hasMoreMeteredPages,
  });
  final String homeId;
  final List<DeviceInventoryItem> items;
  final bool hasMoreMeteredPages;

  /// List resources have no common snapshot token. Never present a derived
  /// total as an atomic household measurement.
  double? get householdEnergyWh => null;
  double? get householdCost => null;
  double? get householdWasteWh => null;
}

class DevicesDomainRepository {
  DevicesDomainRepository(this.source);
  final DevicesDomainSource source;
  String? _homeId;
  int _generation = 0;

  void clear() {
    _homeId = null;
    _generation++;
  }

  Future<DevicesDomainSnapshot?> fetch(String homeId) async {
    if (!_uuid.hasMatch(homeId)) throw ArgumentError.value(homeId, 'homeId');
    _homeId = homeId;
    final generation = ++_generation;
    bool stale() => generation != _generation || _homeId != homeId;
    try {
      final results = await Future.wait<Object>([
        source.appliances(homeId),
        source.attachments(homeId),
        source.sensors(homeId),
        source.meteredSummaries(homeId),
      ]);
      if (stale()) return null;
      return _compose(
        homeId,
        results[0] as List<CloudAppliance>,
        results[1] as List<CloudAttachment>,
        results[2] as List<CloudSensor>,
        results[3] as CloudMeteredSummaryPage,
      );
    } catch (_) {
      if (stale()) return null;
      rethrow;
    }
  }
}

final _uuid = RegExp(
  r'^[0-9a-fA-F]{8}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{12}$',
);

DevicesDomainSnapshot _compose(
  String homeId,
  List<CloudAppliance> appliances,
  List<CloudAttachment> attachments,
  List<CloudSensor> sensors,
  CloudMeteredSummaryPage page,
) {
  if (page.granularity != 'day' ||
      appliances.any((a) => a.homeId != homeId) ||
      attachments.any((a) => a.homeId != homeId) ||
      sensors.any((s) => s.homeId != homeId)) {
    throw const FormatException('Devices reads belong to different homes');
  }
  final byAppliance = <String, CloudAppliance>{};
  final bySensor = <String, CloudSensor>{};
  final byAttachment = <String, CloudAttachment>{};
  for (final appliance in appliances) {
    if (byAppliance.containsKey(appliance.id)) {
      throw const FormatException('Duplicate appliance');
    }
    byAppliance[appliance.id] = appliance;
  }
  for (final sensor in sensors) {
    if (bySensor.containsKey(sensor.id)) {
      throw const FormatException('Duplicate sensor');
    }
    bySensor[sensor.id] = sensor;
  }
  for (final attachment in attachments) {
    if (byAttachment.containsKey(attachment.id)) {
      throw const FormatException('Duplicate attachment');
    }
    byAttachment[attachment.id] = attachment;
  }

  final items = appliances.map((appliance) {
    final active = attachments
        .where(
          (a) =>
              a.applianceId == appliance.id &&
              a.endedAt == null &&
              a.sensorId != null &&
              bySensor.containsKey(a.sensorId),
        )
        .toList();
    final buckets = <DeviceMeasuredBucket>[];
    for (final summary in page.summaries) {
      if (summary.kind != 'energy' ||
          summary.status != 'complete' ||
          summary.allocationMethod != 'exact' ||
          summary.energyWh == null ||
          summary.coveredSeconds == null) {
        continue;
      }
      final attachment = byAttachment[summary.attachmentId];
      if (attachment == null ||
          attachment.applianceId != appliance.id ||
          attachment.sensorId != summary.sensorId ||
          !attachment.activeAt(summary.bucketStart)) {
        continue;
      }
      final sensor = bySensor[summary.sensorId];
      if (sensor == null ||
          sensor.hubId != summary.hubId ||
          sensor.ownershipEpoch != summary.ownershipEpoch) {
        continue;
      }
      buckets.add(
        DeviceMeasuredBucket(
          bucketStart: summary.bucketStart,
          computedAt: summary.computedAt,
          energyWh: summary.energyWh!,
          coveredSeconds: summary.coveredSeconds!,
          attachmentId: attachment.id,
        ),
      );
    }
    buckets.sort((a, b) => b.bucketStart.compareTo(a.bucketStart));
    return DeviceInventoryItem(
      appliance: appliance,
      activeAttachmentIds: List.unmodifiable(active.map((a) => a.id)),
      measuredBuckets: List.unmodifiable(buckets),
    );
  }).toList()..sort((a, b) => a.appliance.id.compareTo(b.appliance.id));

  return DevicesDomainSnapshot(
    homeId: homeId,
    items: List.unmodifiable(items),
    hasMoreMeteredPages: page.nextCursor != null,
  );
}
