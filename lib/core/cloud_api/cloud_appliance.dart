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
    this.version,
    this.createdAt,
    this.updatedAt,
    this.archivedAt,
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
  final int? version;
  final DateTime? createdAt;
  final DateTime? updatedAt;
  final DateTime? archivedAt;

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
        identity['match_quality'] is! String) {
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
      version: json['version'] as int?,
      createdAt: _optionalInstant(json['created_at']),
      updatedAt: _optionalInstant(json['updated_at']),
      archivedAt: _optionalInstant(json['archived_at']),
    );
  }

  static DateTime? _optionalInstant(Object? value) =>
      value == null ? null : DateTime.parse(value as String);
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
    this.matchQuality = 'confirmed_exact',
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
  final String matchQuality;

  Map<String, dynamic> toJson() => {
    'name': name,
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
  });
  final String brand;
  final String fullModel;
  final String fuel;
  final String matchQuality;
  final String? variant;
  final String? region;
  final String? catalogProductId;
  Map<String, dynamic> toJson() => {
    'brand': brand,
    'full_model': fullModel,
    'fuel': fuel,
    'match_quality': matchQuality,
    if (variant != null) 'variant': variant,
    if (region != null) 'region': region,
    if (catalogProductId != null) 'catalog_product_id': catalogProductId,
  };
}
