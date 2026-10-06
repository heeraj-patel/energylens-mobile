/// Exact identity scope accepted by the reviewed usage facts endpoint.
class CloudUsageFactScope {
  const CloudUsageFactScope({
    required this.category,
    required this.manufacturer,
    required this.model,
    required this.fuel,
    required this.variant,
  });

  final String category;
  final String manufacturer;
  final String model;
  final String fuel;
  final String variant;

  Map<String, String> toQueryParameters() => {
    'category': category,
    'manufacturer': manufacturer,
    'model': model,
    'fuel': fuel,
    'variant': variant,
  };

  factory CloudUsageFactScope.fromJson(Map<String, dynamic> json) {
    final fields = [
      json['category'],
      json['manufacturer'],
      json['model'],
      json['fuel'],
      json['variant'],
    ];
    if (fields.any((field) => field is! String)) {
      throw const FormatException('Invalid reviewed usage fact scope');
    }
    return CloudUsageFactScope(
      category: fields[0] as String,
      manufacturer: fields[1] as String,
      model: fields[2] as String,
      fuel: fields[3] as String,
      variant: fields[4] as String,
    );
  }
}

class CloudUsageFactIncludedEnergy {
  const CloudUsageFactIncludedEnergy({
    required this.status,
    required this.components,
    this.evidenceText,
  });

  final String status;
  final List<String> components;
  final String? evidenceText;

  factory CloudUsageFactIncludedEnergy.fromJson(Map<String, dynamic> json) {
    final status = json['status'];
    final components = json['components'];
    final evidenceText = json['evidence_text'];
    if (status is! String ||
        components is! List ||
        components.any((component) => component is! String) ||
        (evidenceText != null && evidenceText is! String)) {
      throw const FormatException('Invalid reviewed usage included energy');
    }
    return CloudUsageFactIncludedEnergy(
      status: status,
      components: List<String>.unmodifiable(components.cast<String>()),
      evidenceText: evidenceText as String?,
    );
  }
}

class CloudReviewedUsageFact {
  const CloudReviewedUsageFact({
    required this.id,
    required this.measurementKind,
    required this.value,
    required this.unit,
    required this.testBasis,
    required this.includedEnergy,
    required this.sourceKind,
    required this.sourceUrl,
    required this.sourceSha256,
    required this.reviewSha256,
    required this.reviewedAt,
    required this.publicationSha256,
    this.cycleDefinition,
    this.operationMode,
    this.sourcePageIndex,
    this.datasetId,
    this.rowIdentifier,
    this.fieldName,
    this.metadataSha256,
  });

  final String id;
  final String measurementKind;
  final String value;
  final String unit;
  final String testBasis;
  final CloudUsageFactIncludedEnergy includedEnergy;
  final String sourceKind;
  final String sourceUrl;
  final String sourceSha256;
  final String reviewSha256;
  final String reviewedAt;
  final String publicationSha256;
  final String? cycleDefinition;
  final String? operationMode;
  final int? sourcePageIndex;
  final String? datasetId;
  final String? rowIdentifier;
  final String? fieldName;
  final String? metadataSha256;

  factory CloudReviewedUsageFact.fromJson(Map<String, dynamic> json) {
    String requiredString(String key) {
      final value = json[key];
      if (value is! String) {
        throw FormatException('Invalid reviewed usage fact $key');
      }
      return value;
    }

    String? optionalString(String key) {
      final value = json[key];
      if (value != null && value is! String) {
        throw FormatException('Invalid reviewed usage fact $key');
      }
      return value as String?;
    }

    final includedEnergy = json['included_energy'];
    final pageIndex = json['source_page_index'];
    if (includedEnergy is! Map<String, dynamic> ||
        (pageIndex != null && pageIndex is! int)) {
      throw const FormatException('Invalid reviewed usage fact');
    }
    return CloudReviewedUsageFact(
      id: requiredString('id'),
      measurementKind: requiredString('measurement_kind'),
      value: requiredString('value'),
      unit: requiredString('unit'),
      testBasis: requiredString('test_basis'),
      includedEnergy: CloudUsageFactIncludedEnergy.fromJson(includedEnergy),
      sourceKind: requiredString('source_kind'),
      sourceUrl: requiredString('source_url'),
      sourceSha256: requiredString('source_sha256'),
      reviewSha256: requiredString('review_sha256'),
      reviewedAt: requiredString('reviewed_at'),
      publicationSha256: requiredString('publication_sha256'),
      cycleDefinition: optionalString('cycle_definition'),
      operationMode: optionalString('operation_mode'),
      sourcePageIndex: pageIndex as int?,
      datasetId: optionalString('dataset_id'),
      rowIdentifier: optionalString('row_identifier'),
      fieldName: optionalString('field_name'),
      metadataSha256: optionalString('metadata_sha256'),
    );
  }
}

class CloudReviewedUsageFacts {
  const CloudReviewedUsageFacts({required this.scope, required this.facts});

  final CloudUsageFactScope scope;
  final List<CloudReviewedUsageFact> facts;

  factory CloudReviewedUsageFacts.fromJson(Map<String, dynamic> json) {
    final scopeJson = json['scope'];
    final rows = json['facts'];
    if (json['schema'] != 'energylens.reviewed-usage-facts' ||
        json['schema_version'] != 1 ||
        scopeJson is! Map<String, dynamic> ||
        rows is! List ||
        rows.any((row) => row is! Map<String, dynamic>)) {
      throw const FormatException('Invalid reviewed usage facts response');
    }
    final facts = rows
        .map(
          (row) => CloudReviewedUsageFact.fromJson(row as Map<String, dynamic>),
        )
        .toList();
    if (facts.length > 2 ||
        facts.map((fact) => fact.id).toSet().length != facts.length) {
      throw const FormatException('Invalid reviewed usage facts list');
    }
    return CloudReviewedUsageFacts(
      scope: CloudUsageFactScope.fromJson(scopeJson),
      facts: List.unmodifiable(facts),
    );
  }
}
