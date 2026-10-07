import '../../core/cloud_api/cloud_api_client.dart';
import '../../core/cloud_api/cloud_appliance.dart';
import '../../core/cloud_api/cloud_appliance_list.dart';
import '../../core/cloud_api/cloud_interventions.dart';
import '../../core/cloud_api/cloud_sensor.dart';
import '../discovery/discovery_api.dart';

/// Shared owner-scoped reads for the three device setup pages.
abstract interface class ManageDevicesDomainSource {
  Future<CloudApplianceList> applianceList(String homeId);
  Future<List<CloudAttachment>> attachments(String homeId);
  Future<List<CloudSensor>> sensors(String homeId);
}

class CloudManageDevicesDomainSource implements ManageDevicesDomainSource {
  const CloudManageDevicesDomainSource(this.api);
  final CloudApiClient api;

  @override
  Future<CloudApplianceList> applianceList(String homeId) =>
      api.applianceList(homeId);
  @override
  Future<List<CloudAttachment>> attachments(String homeId) =>
      api.attachments(homeId);
  @override
  Future<List<CloudSensor>> sensors(String homeId) => api.sensors(homeId);
}

class MonitoredDeviceRow {
  const MonitoredDeviceRow(this.appliance, this.sensorIds);
  final CloudAppliance appliance;
  final List<String> sensorIds;
}

/// A local scan result is a review hint only. Confidence is OCR/discovery
/// confidence, not proof of a reviewed catalog identity or saved inventory.
class DeviceScanReview {
  const DeviceScanReview(this.candidate);
  final IdentificationCandidate candidate;
  String get brandHint => candidate.manufacturer;
  String get modelHint => candidate.model;
  double get recognitionConfidence => candidate.confidence;
  bool get confirmedExact => false;
}

class ManageDevicesDomainSnapshot {
  const ManageDevicesDomainSnapshot({
    required this.homeId,
    required this.monitoredRows,
    required this.inventoryCount,
    required this.dataMode,
    required this.fixtureRevision,
    this.scanReview,
  });
  final String homeId;
  final List<MonitoredDeviceRow> monitoredRows;
  final int inventoryCount;
  final CloudApplianceDataMode dataMode;
  final String? fixtureRevision;
  bool get isSample => dataMode == CloudApplianceDataMode.sample;
  final DeviceScanReview? scanReview;

  int get monitoredCount => monitoredRows.length;
  int? get circuitCount => null;
  int? get circuitTotal => null;
  int? get candidateCount => null;

  /// Manual and photo onboarding reuse the same monitored equipment readback.
  List<MonitoredDeviceRow> get manualEntryMonitoredRows => monitoredRows;
  List<MonitoredDeviceRow> get photoScanMonitoredRows => monitoredRows;

  ManageDevicesDomainSnapshot withScanCandidate(
    IdentificationCandidate candidate,
  ) => ManageDevicesDomainSnapshot(
    homeId: homeId,
    monitoredRows: monitoredRows,
    inventoryCount: inventoryCount,
    dataMode: dataMode,
    fixtureRevision: fixtureRevision,
    scanReview: DeviceScanReview(candidate),
  );
}

class ManageDevicesDomainRepository {
  ManageDevicesDomainRepository(this.source, {DateTime Function()? now})
    : _now = now ?? DateTime.now;
  final ManageDevicesDomainSource source;
  final DateTime Function() _now;
  String? _homeId;
  int _generation = 0;

  void clear() {
    _homeId = null;
    _generation++;
  }

  Future<ManageDevicesDomainSnapshot?> fetch(String homeId) async {
    if (!_uuid.hasMatch(homeId)) throw ArgumentError.value(homeId, 'homeId');
    _homeId = homeId;
    final generation = ++_generation;
    bool stale() => generation != _generation || _homeId != homeId;
    try {
      final values = await Future.wait<Object>([
        source.applianceList(homeId),
        source.attachments(homeId),
        source.sensors(homeId),
      ]);
      if (stale()) return null;
      return _compose(
        homeId,
        values[0] as CloudApplianceList,
        values[1] as List<CloudAttachment>,
        values[2] as List<CloudSensor>,
        _now().toUtc(),
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

ManageDevicesDomainSnapshot _compose(
  String homeId,
  CloudApplianceList applianceList,
  List<CloudAttachment> attachments,
  List<CloudSensor> sensors,
  DateTime now,
) {
  final appliances = applianceList.appliances;
  if (applianceList.dataMode == CloudApplianceDataMode.sample
      ? applianceList.fixtureRevision == null ||
            !RegExp(r'^[A-Za-z0-9][A-Za-z0-9._-]{0,127}$')
                .hasMatch(applianceList.fixtureRevision!)
      : applianceList.fixtureRevision != null) {
    throw const FormatException('Invalid appliance provenance');
  }
  if (appliances.any((item) => item.homeId != homeId) ||
      attachments.any((item) => item.homeId != homeId) ||
      sensors.any((item) => item.homeId != homeId)) {
    throw const FormatException('Device setup reads belong to different homes');
  }
  void requireUnique(Iterable<String> ids) {
    final seen = <String>{};
    for (final id in ids) {
      if (!seen.add(id)) throw const FormatException('Duplicate device record');
    }
  }

  requireUnique(appliances.map((item) => item.id));
  requireUnique(attachments.map((item) => item.id));
  requireUnique(sensors.map((item) => item.id));
  final sensorsById = {for (final sensor in sensors) sensor.id: sensor};
  final sensorIdsByAppliance = <String, Set<String>>{};
  for (final attachment
      in applianceList.isSample ? <CloudAttachment>[] : attachments) {
    if (attachment.sensorId == null ||
        attachment.startedAt.isAfter(now) ||
        attachment.endedAt != null) {
      continue;
    }
    final sensor = sensorsById[attachment.sensorId];
    if (sensor == null ||
        !sensor.capabilities.any(
          (value) => value == 'power' || value == 'energy',
        )) {
      continue;
    }
    sensorIdsByAppliance
        .putIfAbsent(attachment.applianceId, () => <String>{})
        .add(sensor.id);
  }
  final rows = <MonitoredDeviceRow>[];
  for (final appliance in appliances) {
    final sensorIds = sensorIdsByAppliance[appliance.id];
    if (sensorIds == null || sensorIds.isEmpty) continue;
    rows.add(
      MonitoredDeviceRow(
        appliance,
        List.unmodifiable(sensorIds.toList()..sort()),
      ),
    );
  }
  rows.sort((a, b) => a.appliance.id.compareTo(b.appliance.id));
  return ManageDevicesDomainSnapshot(
    homeId: homeId,
    monitoredRows: List.unmodifiable(rows),
    inventoryCount: appliances.length,
    dataMode: applianceList.dataMode,
    fixtureRevision: applianceList.fixtureRevision,
  );
}
