class EnergyCategoryType {
  const EnergyCategoryType({required this.key, required this.label});
  final String key;
  final String label;

  factory EnergyCategoryType.fromJson(Map<String, dynamic> json) =>
      EnergyCategoryType(
        key: json['key'] as String,
        label: json['label'] as String,
      );
}

class EnergyCategoryGroup {
  const EnergyCategoryGroup({
    required this.key,
    required this.label,
    required this.types,
  });
  final String key;
  final String label;
  final List<EnergyCategoryType> types;

  factory EnergyCategoryGroup.fromJson(Map<String, dynamic> json) =>
      EnergyCategoryGroup(
        key: json['key'] as String,
        label: json['label'] as String,
        types: (json['types'] as List)
            .map(
              (item) =>
                  EnergyCategoryType.fromJson(item as Map<String, dynamic>),
            )
            .toList(growable: false),
      );
}

class EnergyCategories {
  const EnergyCategories({
    required this.version,
    required this.etag,
    required this.groups,
  });
  final int version;
  final String etag;
  final List<EnergyCategoryGroup> groups;

  factory EnergyCategories.fromJson(Map<String, dynamic> json, String etag) =>
      EnergyCategories(
        version: json['version'] as int,
        etag: etag,
        groups: (json['groups'] as List)
            .map(
              (item) =>
                  EnergyCategoryGroup.fromJson(item as Map<String, dynamic>),
            )
            .toList(growable: false),
      );
}
