class CloudAppliance {
  const CloudAppliance({
    required this.id,
    required this.homeId,
    required this.name,
    required this.category,
    required this.room,
    required this.brand,
    required this.fullModel,
    required this.fuel,
    this.variant,
    this.region,
    this.catalogProductId,
    required this.matchQuality,
    this.fccId,
    this.icId,
    this.serialNumber,
    this.upc,
    this.version,
    this.createdAt,
    this.updatedAt,
    this.archivedAt,
    this.demoDeviceId,
    this.nearbyOrigin,
  });

  final String id;
  final String homeId;
  final String name;
  final String category;
  final String? room;
  final String brand;
  final String fullModel;
  final String fuel;
  final String? variant;
  final String? region;
  final String? catalogProductId;
  final String matchQuality;
  final String? fccId;
  final String? icId;
  final String? serialNumber;
  final String? upc;
  final int? version;
  final DateTime? createdAt;
  final DateTime? updatedAt;
  final DateTime? archivedAt;

  /// Present only for a database-backed synthetic inventory row.
  final String? demoDeviceId;
  final CloudNearbyOrigin? nearbyOrigin;

  factory CloudAppliance.fromJson(Map<String, dynamic> json) {
    final identity = json['identity'];
    if (json['id'] is! String ||
        json['home_id'] is! String ||
        json['name'] is! String ||
        json['category'] is! String ||
        identity is! Map<String, dynamic> ||
        identity['brand'] is! String ||
        identity['full_model'] is! String ||
        identity['fuel'] is! String ||
        identity['match_quality'] is! String ||
        (json['demo_device_id'] != null &&
            (json['demo_device_id'] is! String ||
                !RegExp(r'^demo-device-(0[1-9]|1[0-8])$')
                    .hasMatch(json['demo_device_id'] as String)))) {
      throw const FormatException('Invalid cloud appliance');
    }
    return CloudAppliance(
      id: json['id'] as String,
      homeId: json['home_id'] as String,
      name: json['name'] as String,
      category: json['category'] as String,
      room: json['room'] as String?,
      brand: identity['brand'] as String,
      fullModel: identity['full_model'] as String,
      fuel: identity['fuel'] as String,
      variant: identity['variant'] as String?,
      region: identity['region'] as String?,
      catalogProductId: identity['catalog_product_id'] as String?,
      matchQuality: identity['match_quality'] as String,
      fccId: identity['fcc_id'] as String?,
      icId: identity['ic_id'] as String?,
      serialNumber: identity['serial_number'] as String?,
      upc: identity['upc'] as String?,
      version: json['version'] as int?,
      createdAt: _optionalInstant(json['created_at']),
      updatedAt: _optionalInstant(json['updated_at']),
      archivedAt: _optionalInstant(json['archived_at']),
      demoDeviceId: json['demo_device_id'] as String?,
      nearbyOrigin: json['nearby_origin'] == null
          ? null
          : CloudNearbyOrigin.fromJson(
              json['nearby_origin'] as Map<String, dynamic>,
            ),
    );
  }

  static DateTime? _optionalInstant(Object? value) =>
      value == null ? null : DateTime.parse(value as String);
}

class CloudNearbyOrigin {
  const CloudNearbyOrigin({
    required this.hubId,
    required this.ownershipEpoch,
    required this.protocolDeviceId,
  });

  factory CloudNearbyOrigin.fromJson(Map<String, dynamic> json) =>
      CloudNearbyOrigin(
        hubId: json['hub_id'] as String,
        ownershipEpoch: json['ownership_epoch'] as int,
        protocolDeviceId: json['protocol_device_id'] as String,
      );

  final String hubId;
  final int ownershipEpoch;
  final String protocolDeviceId;

  Map<String, dynamic> toJson() => {
    'hub_id': hubId,
    'ownership_epoch': ownershipEpoch,
    'protocol_device_id': protocolDeviceId,
  };

  bool matches(CloudNearbyOrigin? other) =>
      other != null &&
      hubId == other.hubId &&
      ownershipEpoch == other.ownershipEpoch &&
      protocolDeviceId == other.protocolDeviceId;
}

class CloudApplianceCreate {
  const CloudApplianceCreate({
    required this.name,
    required this.category,
    required this.room,
    required this.brand,
    required this.fullModel,
    required this.fuel,
    this.variant,
    this.region,
    this.catalogProductId,
    this.fccId,
    this.icId,
    this.serialNumber,
    this.upc,
    this.bulbLabel,
    this.matchQuality = 'confirmed_exact',
    this.nearbyOrigin,
  });
  final String name;
  final String category;
  final String? room;
  final String brand;
  final String fullModel;
  final String fuel;
  final String? variant;
  final String? region;
  final String? catalogProductId;
  final String? fccId;
  final String? icId;
  final String? serialNumber;
  final String? upc;
  final BulbLabel? bulbLabel;
  final String matchQuality;
  final CloudNearbyOrigin? nearbyOrigin;

  Map<String, dynamic> toJson() => {
    'name': name,
    if (nearbyOrigin != null) 'nearby_origin': nearbyOrigin!.toJson(),
    'category': category,
    if (room != null && room!.isNotEmpty) 'room': room,
    'identity': {
      'brand': brand,
      'full_model': fullModel,
      'fuel': fuel,
      if (variant != null) 'variant': variant,
      if (region != null) 'region': region,
      'match_quality': matchQuality,
      if (catalogProductId != null) 'catalog_product_id': catalogProductId,
      if (fccId != null) 'fcc_id': fccId,
      if (icId != null) 'ic_id': icId,
      if (serialNumber != null) 'serial_number': serialNumber,
      if (upc != null) 'upc': upc,
      if (bulbLabel != null) 'bulb_label': bulbLabel!.toJson(),
    },
  };
}

class CloudAppliancePatch {
  const CloudAppliancePatch({
    this.name,
    this.category,
    this.room,
    this.clearRoom = false,
    this.identity,
  });
  final String? name;
  final String? category;
  final String? room;
  final bool clearRoom;
  final CloudApplianceIdentityPatch? identity;

  Map<String, dynamic> toJson() {
    final result = <String, dynamic>{};
    if (name != null) result['name'] = name;
    if (category != null) result['category'] = category;
    if (room != null && clearRoom) {
      throw ArgumentError('room and clearRoom cannot both be set');
    }
    if (room != null) result['room'] = room;
    if (clearRoom) result['room'] = null;
    if (identity != null) result['identity'] = identity!.toJson();
    if (result.isEmpty) {
      throw ArgumentError('Appliance update must not be empty');
    }
    return result;
  }
}

class CloudApplianceIdentityPatch {
  const CloudApplianceIdentityPatch({
    required this.brand,
    required this.fullModel,
    required this.fuel,
    required this.matchQuality,
    this.variant,
    this.region,
    this.catalogProductId,
    this.fccId,
    this.icId,
    this.serialNumber,
    this.upc,
    this.bulbLabel,
  });
  final String brand;
  final String fullModel;
  final String fuel;
  final String matchQuality;
  final String? variant;
  final String? region;
  final String? catalogProductId;
  final String? fccId;
  final String? icId;
  final String? serialNumber;
  final String? upc;
  final BulbLabel? bulbLabel;
  Map<String, dynamic> toJson() => {
    'brand': brand,
    'full_model': fullModel,
    'fuel': fuel,
    'match_quality': matchQuality,
    if (variant != null) 'variant': variant,
    if (region != null) 'region': region,
    if (catalogProductId != null) 'catalog_product_id': catalogProductId,
    if (fccId != null) 'fcc_id': fccId,
    if (icId != null) 'ic_id': icId,
    if (serialNumber != null) 'serial_number': serialNumber,
    if (upc != null) 'upc': upc,
    if (bulbLabel != null) 'bulb_label': bulbLabel!.toJson(),
  };
}

class BulbLabel {
  const BulbLabel({
    required this.loadKind,
    this.bulbCount,
    this.combinedInputWatts,
  });

  final String loadKind;
  final int? bulbCount;
  final double? combinedInputWatts;

  Map<String, dynamic> toJson() => {
    'load_kind': loadKind,
    if (loadKind == 'replaceable_bulb') ...{
      if (bulbCount != null) 'bulb_count': bulbCount,
      if (combinedInputWatts != null)
        'combined_input_watts': combinedInputWatts,
    },
  };
}
