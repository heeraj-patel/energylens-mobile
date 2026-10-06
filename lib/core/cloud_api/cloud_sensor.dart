class CloudSensor {
  const CloudSensor({
    required this.id,
    required this.homeId,
    required this.kind,
    required this.capabilities,
    required this.hubId,
    required this.ownershipEpoch,
    required this.localSensorId,
    required this.version,
    this.parentSensorId,
  });
  final String id;
  final String homeId;
  final String kind;
  final List<String> capabilities;
  final String hubId;
  final int ownershipEpoch;
  final String localSensorId;
  final int version;
  final String? parentSensorId;

  factory CloudSensor.fromJson(Map<String, dynamic> json, String homeId) {
    final caps = json['capabilities'];
    if (json['id'] is! String ||
        json['home_id'] != homeId ||
        json['kind'] is! String ||
        caps is! List ||
        caps.any((value) => value is! String) ||
        json['hub_id'] is! String ||
        json['ownership_epoch'] is! int ||
        json['local_sensor_id'] is! String ||
        json['version'] is! int) {
      throw const FormatException('Invalid cloud sensor');
    }
    return CloudSensor(
      id: json['id'] as String,
      homeId: homeId,
      kind: json['kind'] as String,
      capabilities: List<String>.unmodifiable(caps.cast<String>()),
      hubId: json['hub_id'] as String,
      ownershipEpoch: json['ownership_epoch'] as int,
      localSensorId: json['local_sensor_id'] as String,
      version: json['version'] as int,
      parentSensorId: json['parent_sensor_id'] as String?,
    );
  }
}

class CloudSensorCreate {
  const CloudSensorCreate({
    required this.kind,
    required this.capabilities,
    required this.hubId,
    required this.ownershipEpoch,
    required this.localSensorId,
    this.parentSensorId,
  });
  final String kind;
  final List<String> capabilities;
  final String hubId;
  final int ownershipEpoch;
  final String localSensorId;
  final String? parentSensorId;
  Map<String, dynamic> toJson() => {
    'kind': kind,
    'capabilities': capabilities,
    'hub_id': hubId,
    'ownership_epoch': ownershipEpoch,
    'local_sensor_id': localSensorId,
    if (parentSensorId != null) 'parent_sensor_id': parentSensorId,
  };
}

class CloudAttachmentCreate {
  const CloudAttachmentCreate({
    required this.sensorId,
    required this.applianceId,
    required this.startedAt,
    required this.identityRevision,
  });
  final String sensorId;
  final String applianceId;
  final DateTime startedAt;
  final int identityRevision;
  Map<String, dynamic> toJson() {
    if (!startedAt.isUtc) throw ArgumentError('startedAt must be UTC');
    return {
      'sensor_id': sensorId,
      'appliance_id': applianceId,
      'started_at': startedAt.toIso8601String(),
      'identity_revision': identityRevision,
    };
  }
}

class CloudAttachmentClose {
  const CloudAttachmentClose(this.endedAt);
  final DateTime endedAt;
  Map<String, dynamic> toJson() {
    if (!endedAt.isUtc) throw ArgumentError('endedAt must be UTC');
    return {'ended_at': endedAt.toIso8601String()};
  }
}
