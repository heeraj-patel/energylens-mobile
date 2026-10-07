import '../../core/cloud_api/cloud_api_client.dart';
import '../../core/cloud_api/cloud_appliance_list.dart';
import '../../core/cloud_api/cloud_interventions.dart';
import '../../core/cloud_api/cloud_kasa_runtime.dart';
import '../../core/cloud_api/cloud_sensor.dart';

/// Authenticated reads needed to associate Kasa runtime with local inventory.
abstract interface class DevicesRuntimeEvidenceSource {
  Future<CloudApplianceList> applianceList(String homeId);
  Future<List<CloudAttachment>> attachments(String homeId);
  Future<List<CloudSensor>> sensors(String homeId);
  Future<CloudKasaRuntimePage> kasaRuntimeHistory(
    String homeId, {
    String? cursor,
  });
}

class CloudDevicesRuntimeEvidenceSource
    implements DevicesRuntimeEvidenceSource {
  const CloudDevicesRuntimeEvidenceSource(this.api);
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
  Future<CloudKasaRuntimePage> kasaRuntimeHistory(
    String homeId, {
    String? cursor,
  }) => api.kasaRuntimeHistory(homeId, cursor: cursor);
}

/// One protocol reported window. Today, past7 and past30 overlap and must be
/// displayed as independent observations, never added together.
class DeviceRuntimeEvidence {
  const DeviceRuntimeEvidence({
    required this.applianceId,
    required this.attachmentId,
    required this.sensorId,
    required this.snapshotId,
    required this.windowLabel,
    required this.nativeMinutes,
    required this.observedAt,
    required this.method,
    required this.transport,
    required this.deviceClockValid,
    required this.quality,
  });

  final String applianceId;
  final String attachmentId;
  final String sensorId;
  final String snapshotId;
  final String windowLabel;
  final int nativeMinutes;
  final DateTime observedAt;
  final String method;
  final String transport;
  final bool deviceClockValid;
  final String quality;
}

class DevicesRuntimeEvidenceSnapshot {
  const DevicesRuntimeEvidenceSnapshot({
    required this.homeId,
    required this.evidence,
    required this.isSample,
    required this.isCurrent,
  });

  final String homeId;
  final List<DeviceRuntimeEvidence> evidence;
  final bool isSample;
  final bool Function() isCurrent;

  /// This adapter carries runtime only; runtime is not a live relay state,
  /// energy, cost, or waste measurement.
  double? get energyWh => null;
  double? get cost => null;
  double? get wasteEnergyWh => null;
  String? get liveState => null;
}

class DevicesRuntimeEvidenceAdapter {
  DevicesRuntimeEvidenceAdapter(this.source);

  static const maxPages = 5;
  static const maxRows = 250;
  static const maxInventory = 100;
  final DevicesRuntimeEvidenceSource source;
  String? _homeId;
  int _generation = 0;

  void invalidate() {
    _homeId = null;
    _generation++;
  }

  Future<DevicesRuntimeEvidenceSnapshot?> fetch(String homeId) async {
    if (!_uuid.hasMatch(homeId)) throw ArgumentError.value(homeId, 'homeId');
    _homeId = homeId;
    final generation = ++_generation;
    bool stale() => generation != _generation || _homeId != homeId;
    final reads = await Future.wait<Object>([
      source.applianceList(homeId),
      source.attachments(homeId),
      source.sensors(homeId),
    ]);
    if (stale()) return null;
    final inventory = reads[0] as CloudApplianceList;
    final attachments = reads[1] as List<CloudAttachment>;
    final sensors = reads[2] as List<CloudSensor>;
    _validateInventory(homeId, inventory, attachments, sensors);

    // Sample inventory provenance must not be combined with household runtime.
    if (inventory.isSample) {
      return DevicesRuntimeEvidenceSnapshot(
        homeId: homeId,
        evidence: const [],
        isSample: true,
        isCurrent: () => !stale(),
      );
    }

    final pages = await _readPages(homeId, stale);
    if (pages == null || stale()) return null;
    final appliances = {for (final a in inventory.appliances) a.id: a};
    final sensorsById = {for (final s in sensors) s.id: s};
    final activeBySensor = <String, List<CloudAttachment>>{};
    for (final attachment in attachments.where((a) => a.endedAt == null)) {
      final sensorId = attachment.sensorId;
      if (sensorId == null) continue;
      activeBySensor.putIfAbsent(sensorId, () => []).add(attachment);
    }

    final result = <DeviceRuntimeEvidence>[];
    for (final row in pages) {
      final sensor = sensorsById[row.sensorId];
      if (sensor == null) continue;
      final matches = activeBySensor[row.sensorId] ?? const [];
      // Runtime cannot be assigned when a sensor has multiple active owners.
      if (matches.length > 1) {
        throw const FormatException('Ambiguous active runtime attachment');
      }
      if (matches.isEmpty) continue;
      final attachment = matches.single;
      if (!appliances.containsKey(attachment.applianceId) ||
          attachment.homeId != homeId ||
          attachment.sensorId != sensor.id ||
          sensor.homeId != homeId) {
        throw const FormatException('Runtime evidence identity mismatch');
      }
      result.add(
        DeviceRuntimeEvidence(
          applianceId: attachment.applianceId,
          attachmentId: attachment.id,
          sensorId: sensor.id,
          snapshotId: row.snapshotId,
          windowLabel: row.windowLabel,
          nativeMinutes: row.nativeMinutes,
          observedAt: row.observedAt,
          method: row.method,
          transport: row.transport,
          deviceClockValid: row.deviceClockValid,
          quality: row.quality,
        ),
      );
    }
    result.sort((a, b) {
      final byObserved = b.observedAt.compareTo(a.observedAt);
      if (byObserved != 0) return byObserved;
      final byWindow = a.windowLabel.compareTo(b.windowLabel);
      return byWindow != 0 ? byWindow : a.snapshotId.compareTo(b.snapshotId);
    });
    return DevicesRuntimeEvidenceSnapshot(
      homeId: homeId,
      evidence: List.unmodifiable(result),
      isSample: false,
      isCurrent: () => !stale(),
    );
  }

  Future<List<CloudKasaRuntimeSnapshot>?> _readPages(
    String homeId,
    bool Function() stale,
  ) async {
    final rows = <CloudKasaRuntimeSnapshot>[];
    final snapshotIds = <String>{};
    final cursors = <String>{};
    String? cursor;
    DateTime? expectedFrom;
    DateTime? expectedTo;
    for (var pageNumber = 0; pageNumber < maxPages; pageNumber++) {
      if (stale()) return null;
      final page = await source.kasaRuntimeHistory(homeId, cursor: cursor);
      if (stale()) return null;
      if (page.snapshots.length > 50 ||
          (expectedFrom != null &&
              (page.from != expectedFrom || page.to != expectedTo))) {
        throw const FormatException('Runtime page changed or exceeds bound');
      }
      expectedFrom ??= page.from;
      expectedTo ??= page.to;
      for (final row in page.snapshots) {
        if (row.homeId != homeId || !snapshotIds.add(row.snapshotId)) {
          throw const FormatException(
            'Duplicate or cross-home runtime evidence',
          );
        }
        if (rows.length == maxRows) {
          return List.unmodifiable(rows);
        }
        rows.add(row);
      }
      final next = page.nextCursor;
      if (next == null) return List.unmodifiable(rows);
      if (next.isEmpty || !cursors.add(next)) {
        throw const FormatException('Runtime cursor loop');
      }
      if (pageNumber == maxPages - 1 || rows.length == maxRows) {
        return List.unmodifiable(rows);
      }
      cursor = next;
    }
    return List.unmodifiable(rows);
  }

  void _validateInventory(
    String homeId,
    CloudApplianceList inventory,
    List<CloudAttachment> attachments,
    List<CloudSensor> sensors,
  ) {
    if (inventory.appliances.length > maxInventory ||
        inventory.appliances.any((a) => a.homeId != homeId) ||
        attachments.any((a) => a.homeId != homeId) ||
        sensors.any((s) => s.homeId != homeId)) {
      throw const FormatException('Runtime inventory crosses home or bound');
    }
    final appliances = <String>{};
    final attachmentIds = <String>{};
    final sensorIds = <String>{};
    if (inventory.appliances.any((a) => !appliances.add(a.id)) ||
        attachments.any((a) => !attachmentIds.add(a.id)) ||
        sensors.any((s) => !sensorIds.add(s.id))) {
      throw const FormatException('Duplicate runtime inventory identity');
    }
    if (inventory.isSample && inventory.fixtureRevision == null) {
      throw const FormatException('Sample inventory lacks provenance');
    }
    if (!inventory.isSample && inventory.fixtureRevision != null) {
      throw const FormatException('Household inventory has sample provenance');
    }
  }
}

final _uuid = RegExp(
  r'^[0-9a-fA-F]{8}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{12}$',
);
