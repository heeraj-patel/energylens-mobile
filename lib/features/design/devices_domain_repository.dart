import 'dart:convert';

import '../../core/cloud_api/cloud_api_client.dart';
import '../../core/cloud_api/cloud_appliance.dart';
import '../../core/cloud_api/cloud_appliance_list.dart';
import '../../core/cloud_api/cloud_interventions.dart';
import '../../core/cloud_api/cloud_metered_summary.dart';
import '../../core/cloud_api/cloud_sensor.dart';

/// Owner-scoped reads used by the Devices domain. These endpoints do not share
/// a snapshot token, so their results must not be added into a household total.
abstract interface class DevicesDomainSource {
  Future<CloudApplianceList> applianceList(String homeId);
  Future<List<CloudAttachment>> attachments(String homeId);
  Future<List<CloudSensor>> sensors(String homeId);
  Future<CloudMeteredSummaryPage> meteredSummaries(
    String homeId, {
    String? cursor,
  });
}

class CloudDevicesDomainSource implements DevicesDomainSource {
  const CloudDevicesDomainSource(this.api);
  final CloudApiClient api;

  @override
  Future<CloudApplianceList> applianceList(String homeId) =>
      api.applianceList(homeId);
  @override
  Future<List<CloudAttachment>> attachments(String homeId) =>
      api.attachments(homeId);
  @override
  Future<List<CloudSensor>> sensors(String homeId) => api.sensors(homeId);
  @override
  Future<CloudMeteredSummaryPage> meteredSummaries(
    String homeId, {
    String? cursor,
  }) => api.meteredSummaries(homeId, granularity: 'day', cursor: cursor);
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
    this.ownershipCoversBucket = false,
  });
  final DateTime bucketStart;
  final DateTime computedAt;
  final double energyWh;
  final double coveredSeconds;
  final String attachmentId;
  final bool ownershipCoversBucket;
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

  /// A single observed bucket, not a device or period total.
  double? get latestMeasuredBucketWh =>
      measuredBuckets.isEmpty ? null : measuredBuckets.first.energyWh;

  /// No tariff, waste policy or live state is established by these endpoints.
  double? get cost => null;
  double? get wasteEnergyWh => null;
  String? get liveState => null;
}

enum DeviceLocalSort { name, latestMeasuredBucketDesc }

class DeviceLocalPage {
  const DeviceLocalPage({
    required this.items,
    required this.matchingCount,
    required this.nextOffset,
    required this.isGlobalEnergyRanking,
  });
  final List<DeviceInventoryItem> items;
  final int matchingCount;
  final int? nextOffset;
  final bool isGlobalEnergyRanking;
}

class DevicesDomainSnapshot {
  const DevicesDomainSnapshot({
    required this.homeId,
    required this.items,
    required this.hasMoreMeteredPages,
    required this.dataMode,
    required this.fixtureRevision,
    this.sampleMeteredSummaries = const [],
    this.isCurrent,
  });

  /// The local inventory envelope. The unpaged appliance API currently has no
  /// continuation or revision token; reject larger results rather than imply
  /// that a globally complete view was obtained.
  static const maxLocalInventory = 100;
  final String homeId;
  final List<DeviceInventoryItem> items;
  final bool hasMoreMeteredPages;
  final CloudApplianceDataMode dataMode;
  final String? fixtureRevision;

  /// Fixture evidence only. These rows do not establish installed sensors,
  /// attachments, measured usage, or household totals.
  final List<CloudMeteredSummary> sampleMeteredSummaries;
  final bool Function()? isCurrent;
  bool get isSample => dataMode == CloudApplianceDataMode.sample;

  /// Pages are frozen within this one read. A later read, mutation, sign-out,
  /// or home switch invalidates the result. The measured sort is explicitly a
  /// local observed-bucket order, never a global energy ranking.
  DeviceLocalPage localPage({
    int offset = 0,
    int limit = 20,
    String? nameContains,
    DeviceLocalSort sort = DeviceLocalSort.name,
  }) {
    if (isCurrent != null && !isCurrent!()) {
      throw StateError('Devices snapshot is stale');
    }
    if (offset < 0 || limit < 1 || limit > maxLocalInventory) {
      throw RangeError('Invalid local page bounds');
    }
    final query = nameContains?.trim().toLowerCase();
    final matches = items
        .where(
          (item) =>
              query == null ||
              query.isEmpty ||
              item.appliance.name.toLowerCase().contains(query),
        )
        .toList();
    matches.sort((a, b) {
      if (sort == DeviceLocalSort.latestMeasuredBucketDesc) {
        final aEnergy = a.latestMeasuredBucketWh;
        final bEnergy = b.latestMeasuredBucketWh;
        if (aEnergy == null && bEnergy != null) return 1;
        if (aEnergy != null && bEnergy == null) return -1;
        if (aEnergy != null && bEnergy != null) {
          final byEnergy = bEnergy.compareTo(aEnergy);
          if (byEnergy != 0) return byEnergy;
        }
      } else {
        final byName = a.appliance.name.toLowerCase().compareTo(
          b.appliance.name.toLowerCase(),
        );
        if (byName != 0) return byName;
      }
      return a.appliance.id.compareTo(b.appliance.id);
    });
    final end = (offset + limit).clamp(0, matches.length);
    return DeviceLocalPage(
      items: List.unmodifiable(
        offset >= matches.length
            ? <DeviceInventoryItem>[]
            : matches.sublist(offset, end),
      ),
      matchingCount: matches.length,
      nextOffset: end < matches.length ? end : null,
      isGlobalEnergyRanking: false,
    );
  }

  /// List resources have no common snapshot token. Never present a derived
  /// total as an atomic household measurement.
  double? get householdEnergyWh => null;
  double? get householdCost => null;
  double? get householdWasteWh => null;
}

class DevicesDomainRepository {
  DevicesDomainRepository(this.source);
  static const maxConsistencyAttempts = 2;
  static const maxMeteredPages = 5;
  static const maxMeteredRows = 250;
  final DevicesDomainSource source;
  String? _homeId;
  int _generation = 0;

  void clear() {
    _homeId = null;
    _generation++;
  }

  /// Call after appliance, attachment, sensor, or metered-evidence mutation.
  void invalidate() => clear();

  /// Rechecks the three inventory routes after metered pagination. Matching
  /// reads reduce mixed evidence but cannot establish a shared server snapshot.
  Future<DevicesDomainSnapshot?> fetch(String homeId) async {
    if (!_uuid.hasMatch(homeId)) throw ArgumentError.value(homeId, 'homeId');
    _homeId = homeId;
    final generation = ++_generation;
    bool stale() => generation != _generation || _homeId != homeId;
    try {
      for (var attempt = 0; attempt < maxConsistencyAttempts; attempt++) {
        try {
          final before = await _readInventory(homeId);
          if (stale()) return null;
          final metered = await _readMetered(homeId, stale, before.inventory);
          if (stale() || metered == null) return null;
          final after = await _readInventory(homeId);
          if (stale()) return null;
          if (before.fingerprint != after.fingerprint) {
            if (attempt + 1 < maxConsistencyAttempts) continue;
            throw const FormatException(
              'Devices inventory changed during read',
            );
          }
          return _compose(
            homeId,
            before.inventory,
            before.attachments,
            before.sensors,
            metered,
            () => !stale(),
          );
        } on CloudApiException catch (error) {
          if (stale()) return null;
          if (attempt + 1 < maxConsistencyAttempts &&
              error.statusCode == 409 &&
              error.code == 'evidence_changed') {
            continue;
          }
          rethrow;
        } on _MeteredRevisionChanged {
          if (stale()) return null;
          if (attempt + 1 < maxConsistencyAttempts) continue;
          throw const FormatException(
            'Devices metered evidence changed during read',
          );
        }
      }
      throw StateError('Devices consistency attempts exhausted');
    } catch (_) {
      if (stale()) return null;
      rethrow;
    }
  }

  Future<_DeviceInventoryRead> _readInventory(String homeId) async {
    final results = await Future.wait<Object>([
      source.applianceList(homeId),
      source.attachments(homeId),
      source.sensors(homeId),
    ]);
    return _DeviceInventoryRead(
      results[0] as CloudApplianceList,
      results[1] as List<CloudAttachment>,
      results[2] as List<CloudSensor>,
    );
  }

  Future<CloudMeteredSummaryPage?> _readMetered(
    String homeId,
    bool Function() stale,
    CloudApplianceList inventory,
  ) async {
    final rows = <CloudMeteredSummary>[];
    final cursors = <String>{};
    final bucketIds = <(String, DateTime, String, String, int, String?)>{};
    String? cursor;
    String? evidenceRevision;
    var pages = 0;
    Future<CloudMeteredSummaryPage?> finish(String? nextCursor) async {
      if (evidenceRevision != null) {
        if (stale()) return null;
        final first = await source.meteredSummaries(homeId);
        if (stale()) return null;
        if (first.granularity != 'day' || first.summaries.length > 100) {
          throw const FormatException('Invalid Devices metered page');
        }
        if (first.dataMode != inventory.dataMode ||
            first.fixtureRevision != inventory.fixtureRevision) {
          throw const FormatException('Devices metered provenance changed');
        }
        if (first.evidenceRevision != evidenceRevision) {
          throw const _MeteredRevisionChanged();
        }
      }
      return CloudMeteredSummaryPage(
        granularity: 'day',
        summaries: rows,
        nextCursor: nextCursor,
        dataMode: inventory.dataMode,
        fixtureRevision: inventory.fixtureRevision,
        evidenceRevision: evidenceRevision,
      );
    }

    while (true) {
      if (stale()) return null;
      final page = await source.meteredSummaries(homeId, cursor: cursor);
      if (stale()) return null;
      if (page.granularity != 'day' || page.summaries.length > 100) {
        throw const FormatException('Invalid Devices metered page');
      }
      if (page.dataMode != inventory.dataMode ||
          page.fixtureRevision != inventory.fixtureRevision) {
        throw const FormatException('Devices metered provenance changed');
      }
      if (pages == 0) {
        evidenceRevision = page.evidenceRevision;
      } else if (page.evidenceRevision != evidenceRevision) {
        throw const _MeteredRevisionChanged();
      }
      pages++;
      for (final row in page.summaries) {
        final id = (
          row.kind,
          row.bucketStart,
          row.sensorId,
          row.hubId,
          row.ownershipEpoch,
          row.attachmentId,
        );
        if (!bucketIds.add(id)) {
          throw const FormatException('Duplicate Devices metered bucket');
        }
        if (rows.length == maxMeteredRows) {
          return finish(page.nextCursor ?? cursor ?? 'bounded');
        }
        rows.add(row);
      }
      final next = page.nextCursor;
      if (next == null) {
        return finish(null);
      }
      if (next.isEmpty || !cursors.add(next)) {
        throw const FormatException('Devices metered cursor loop');
      }
      if (pages == maxMeteredPages || rows.length == maxMeteredRows) {
        return finish(next);
      }
      cursor = next;
    }
  }
}

class _MeteredRevisionChanged implements Exception {
  const _MeteredRevisionChanged();
}

class _DeviceInventoryRead {
  _DeviceInventoryRead(this.inventory, this.attachments, this.sensors);

  final CloudApplianceList inventory;
  final List<CloudAttachment> attachments;
  final List<CloudSensor> sensors;

  String get fingerprint => jsonEncode({
    'mode': inventory.dataMode.name,
    'fixture_revision': inventory.fixtureRevision,
    'inventory_revision': inventory.inventoryRevision,
    'appliances':
        (inventory.appliances.toList()..sort((a, b) => a.id.compareTo(b.id)))
            .map(
              (a) => [
                a.id,
                a.homeId,
                a.name,
                a.category,
                a.room,
                a.brand,
                a.fullModel,
                a.fuel,
                a.variant,
                a.region,
                a.catalogProductId,
                a.matchQuality,
                a.version,
                a.createdAt?.toUtc().toIso8601String(),
                a.updatedAt?.toUtc().toIso8601String(),
                a.archivedAt?.toUtc().toIso8601String(),
              ],
            )
            .toList(),
    'attachments': (attachments.toList()..sort((a, b) => a.id.compareTo(b.id)))
        .map(
          (a) => [
            a.id,
            a.homeId,
            a.applianceId,
            a.startedAt.toUtc().toIso8601String(),
            a.endedAt?.toUtc().toIso8601String(),
            a.sensorId,
            a.identityRevision,
            a.version,
          ],
        )
        .toList(),
    'sensors': (sensors.toList()..sort((a, b) => a.id.compareTo(b.id)))
        .map(
          (s) => [
            s.id,
            s.homeId,
            s.kind,
            [...s.capabilities]..sort(),
            s.hubId,
            s.ownershipEpoch,
            s.localSensorId,
            s.version,
            s.parentSensorId,
          ],
        )
        .toList(),
  });
}

final _uuid = RegExp(
  r'^[0-9a-fA-F]{8}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{12}$',
);

DevicesDomainSnapshot _compose(
  String homeId,
  CloudApplianceList applianceList,
  List<CloudAttachment> attachments,
  List<CloudSensor> sensors,
  CloudMeteredSummaryPage page,
  bool Function() isCurrent,
) {
  final appliances = applianceList.appliances;
  if (appliances.length > DevicesDomainSnapshot.maxLocalInventory) {
    throw const FormatException('Devices inventory exceeds local envelope');
  }
  if (applianceList.dataMode == CloudApplianceDataMode.sample
      ? applianceList.fixtureRevision == null ||
            !RegExp(r'^[A-Za-z0-9][A-Za-z0-9._-]{0,127}$')
                .hasMatch(applianceList.fixtureRevision!)
      : applianceList.fixtureRevision != null) {
    throw const FormatException('Invalid appliance provenance');
  }
  if (page.granularity != 'day' ||
      page.dataMode != applianceList.dataMode ||
      page.fixtureRevision != applianceList.fixtureRevision ||
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
    final active = (applianceList.isSample ? <CloudAttachment>[] : attachments)
        .where(
          (a) =>
              a.applianceId == appliance.id &&
              a.endedAt == null &&
              a.sensorId != null &&
              bySensor.containsKey(a.sensorId),
        )
        .toList();
    final buckets = <DeviceMeasuredBucket>[];
    for (final summary
        in applianceList.isSample ? <CloudMeteredSummary>[] : page.summaries) {
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
          ownershipCoversBucket:
              !attachment.startedAt.isAfter(summary.bucketStart) &&
              (attachment.endedAt == null ||
                  !attachment.endedAt!.isBefore(
                    summary.bucketStart.add(
                      Duration(seconds: summary.coveredSeconds!.round()),
                    ),
                  )),
        ),
      );
    }
    buckets.sort((a, b) {
      final byStart = b.bucketStart.compareTo(a.bucketStart);
      if (byStart != 0) return byStart;
      final byCorrection = b.computedAt.compareTo(a.computedAt);
      if (byCorrection != 0) return byCorrection;
      return a.attachmentId.compareTo(b.attachmentId);
    });
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
    dataMode: applianceList.dataMode,
    fixtureRevision: applianceList.fixtureRevision,
    sampleMeteredSummaries: applianceList.isSample
        ? List.unmodifiable(page.summaries)
        : const [],
    isCurrent: isCurrent,
  );
}
