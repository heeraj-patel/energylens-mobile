class CloudKasaRuntimeSnapshot {
  const CloudKasaRuntimeSnapshot({
    required this.snapshotId,
    required this.homeId,
    required this.sensorId,
    required this.windowLabel,
    required this.nativeMinutes,
    required this.observedAt,
    required this.method,
    required this.transport,
    required this.deviceClockValid,
    required this.quality,
  });

  final String snapshotId;
  final String homeId;
  final String sensorId;
  final String windowLabel;
  final int nativeMinutes;
  final DateTime observedAt;
  final String method;
  final String transport;
  final bool deviceClockValid;
  final String quality;

  factory CloudKasaRuntimeSnapshot.fromJson(Map<String, dynamic> json) {
    final id = json['snapshot_id'];
    final home = json['home_id'];
    final sensor = json['sensor_id'];
    final label = json['window_label'];
    final minutes = json['native_minutes'];
    final observed = json['observed_at'] is String
        ? DateTime.tryParse(json['observed_at'] as String)
        : null;
    final method = json['method'];
    final transport = json['transport'];
    final clock = json['device_clock_valid'];
    final quality = json['quality'];
    if (id is! String ||
        id.isEmpty ||
        home is! String ||
        home.isEmpty ||
        sensor is! String ||
        sensor.isEmpty ||
        !const {'today', 'past7', 'past30'}.contains(label) ||
        json['scope'] != 'single_plug' ||
        json['native_unit'] != 'minutes' ||
        minutes is! int ||
        minutes < 0 ||
        minutes > 43200 ||
        json['duration_seconds'] != minutes * 60 ||
        observed == null ||
        !const {'get_device_usage', 'get_daystat'}.contains(method) ||
        !const {'kasa_http_klap', 'kasa_legacy_tcp'}.contains(transport) ||
        clock is! bool ||
        !const {
          'protocol_reported_clock_verified',
          'protocol_reported_clock_unverified',
        }.contains(quality) ||
        (!clock && quality != 'protocol_reported_clock_unverified')) {
      throw const FormatException('Invalid Kasa runtime snapshot');
    }
    return CloudKasaRuntimeSnapshot(
      snapshotId: id,
      homeId: home,
      sensorId: sensor,
      windowLabel: label as String,
      nativeMinutes: minutes,
      observedAt: observed,
      method: method as String,
      transport: transport as String,
      deviceClockValid: clock,
      quality: quality as String,
    );
  }
}

class CloudKasaRuntimePage {
  const CloudKasaRuntimePage({
    required this.snapshots,
    required this.from,
    required this.to,
    required this.nextCursor,
  });

  final List<CloudKasaRuntimeSnapshot> snapshots;
  final DateTime from;
  final DateTime to;
  final String? nextCursor;

  factory CloudKasaRuntimePage.fromJson(
    Map<String, dynamic> json, {
    required String homeId,
  }) {
    final rows = json['snapshots'];
    final from = json['from'] is String
        ? DateTime.tryParse(json['from'] as String)
        : null;
    final to = json['to'] is String
        ? DateTime.tryParse(json['to'] as String)
        : null;
    final next = json['next_cursor'];
    if (rows is! List ||
        rows.length > 50 ||
        from == null ||
        to == null ||
        !to.isAfter(from) ||
        to.difference(from) > const Duration(days: 31) ||
        (next != null &&
            (next is! String || next.isEmpty || next.length > 2048))) {
      throw const FormatException('Invalid Kasa runtime page');
    }
    final snapshots = rows.map((row) {
      if (row is! Map<String, dynamic>) {
        throw const FormatException('Invalid Kasa runtime row');
      }
      final value = CloudKasaRuntimeSnapshot.fromJson(row);
      if (value.homeId != homeId ||
          value.observedAt.isBefore(from) ||
          value.observedAt.isAfter(to)) {
        throw const FormatException(
          'Kasa runtime row outside selected home or period',
        );
      }
      return value;
    }).toList();
    return CloudKasaRuntimePage(
      snapshots: snapshots,
      from: from,
      to: to,
      nextCursor: next as String?,
    );
  }
}
