class CloudMeteredEvent {
  const CloudMeteredEvent({
    required this.kind,
    required this.sensorId,
    required this.start,
    required this.end,
    this.watts,
    this.energyWh,
    this.coveredSeconds,
    this.applianceId,
    this.attachmentId,
    this.gapReason,
    this.droppedCount,
  });

  final String kind;
  final String sensorId;
  final DateTime start;
  final DateTime? end;
  final double? watts;
  final double? energyWh;
  final int? coveredSeconds;
  final String? applianceId;
  final String? attachmentId;
  final String? gapReason;
  final int? droppedCount;

  factory CloudMeteredEvent.fromJson(Map<String, dynamic> json) {
    final kind = json['kind'];
    final sensorId = json['sensor_id'];
    if (sensorId is! String || sensorId.isEmpty) {
      throw const FormatException('Invalid metered sensor');
    }
    DateTime timestamp(String key) {
      final raw = json[key];
      final parsed = raw is String ? DateTime.tryParse(raw) : null;
      if (parsed == null) throw const FormatException('Invalid metered time');
      return parsed;
    }

    double nonnegativeNumber(String key) {
      final raw = json[key];
      if (raw is! num || !raw.isFinite || raw < 0) {
        throw const FormatException('Invalid metered value');
      }
      return raw.toDouble();
    }

    switch (kind) {
      case 'power_point':
        return CloudMeteredEvent(
          kind: kind,
          sensorId: sensorId,
          start: timestamp('timestamp'),
          end: null,
          watts: nonnegativeNumber('watts'),
        );
      case 'energy_interval':
        final start = timestamp('start');
        final end = timestamp('end');
        final covered = json['covered_seconds'];
        final appliance = json['appliance_id'];
        final attachment = json['attachment_id'];
        if (!end.isAfter(start) ||
            covered is! int ||
            covered < 1 ||
            appliance is! String ||
            appliance.isEmpty ||
            attachment is! String ||
            attachment.isEmpty ||
            json['fuel'] != 'electricity' ||
            json['quality'] != 'metered' ||
            json['source'] != 'verified_driver') {
          throw const FormatException('Invalid metered interval');
        }
        return CloudMeteredEvent(
          kind: kind,
          sensorId: sensorId,
          start: start,
          end: end,
          energyWh: nonnegativeNumber('energy_wh'),
          coveredSeconds: covered,
          applianceId: appliance,
          attachmentId: attachment,
        );
      case 'coverage_gap':
        final start = timestamp('first_timestamp');
        final end = timestamp('last_timestamp');
        final reason = json['reason'];
        final dropped = json['dropped_count'];
        if (end.isBefore(start) ||
            reason is! String ||
            dropped is! int ||
            dropped < 1) {
          throw const FormatException('Invalid metered gap');
        }
        return CloudMeteredEvent(
          kind: kind,
          sensorId: sensorId,
          start: start,
          end: end,
          gapReason: reason,
          droppedCount: dropped,
        );
      default:
        throw const FormatException('Unknown metered event kind');
    }
  }
}

class CloudMeteredHistoryPage {
  const CloudMeteredHistoryPage({
    required this.events,
    required this.asOf,
    required this.asOfCursor,
    required this.nextCursor,
  });

  final List<CloudMeteredEvent> events;
  final DateTime asOf;
  final int asOfCursor;
  final String? nextCursor;

  factory CloudMeteredHistoryPage.fromJson(Map<String, dynamic> json) {
    final rows = json['events'];
    final rawAsOf = json['as_of'];
    final asOf = rawAsOf is String ? DateTime.tryParse(rawAsOf) : null;
    final cursor = json['as_of_cursor'];
    final next = json['next_cursor'];
    if (rows is! List ||
        rows.length > 100 ||
        asOf == null ||
        cursor is! int ||
        cursor < 0 ||
        (next != null && (next is! String || next.isEmpty))) {
      throw const FormatException('Invalid metered history page');
    }
    return CloudMeteredHistoryPage(
      events: rows
          .map((row) => CloudMeteredEvent.fromJson(row as Map<String, dynamic>))
          .toList(),
      asOf: asOf,
      asOfCursor: cursor,
      nextCursor: next as String?,
    );
  }
}
