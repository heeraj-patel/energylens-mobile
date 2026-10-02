class CloudCatalogFact {
  const CloudCatalogFact({
    required this.kind,
    required this.value,
    required this.unit,
    required this.sourceKind,
    required this.sourceUrl,
    required this.testBasis,
    required this.reviewedAt,
  });
  final String kind;
  final String value;
  final String unit;
  final String sourceKind;
  final String sourceUrl;
  final Map<String, dynamic> testBasis;
  final DateTime reviewedAt;

  factory CloudCatalogFact.fromJson(Map<String, dynamic> json) {
    final reviewed = json['reviewed_at'];
    final parsed = reviewed is String ? DateTime.tryParse(reviewed) : null;
    if (json['kind'] is! String ||
        json['value'] is! String ||
        json['unit'] is! String ||
        json['source_kind'] is! String ||
        json['source_url'] is! String ||
        json['test_basis'] is! Map<String, dynamic> ||
        parsed == null) {
      throw const FormatException('Invalid reviewed catalog fact');
    }
    return CloudCatalogFact(
      kind: json['kind'] as String,
      value: json['value'] as String,
      unit: json['unit'] as String,
      sourceKind: json['source_kind'] as String,
      sourceUrl: json['source_url'] as String,
      testBasis: json['test_basis'] as Map<String, dynamic>,
      reviewedAt: parsed,
    );
  }
}

class CloudCatalogProduct {
  const CloudCatalogProduct({
    required this.id,
    required this.category,
    required this.brand,
    required this.fullModel,
    required this.variant,
    required this.region,
    required this.fuel,
    required this.matchQuality,
    required this.facts,
    this.queryMatch,
    this.matchedModel,
    this.variantMatch,
  });
  final String id;
  final String category;
  final String brand;
  final String fullModel;
  final String? variant;
  final String? region;
  final String fuel;
  final String matchQuality;
  final List<CloudCatalogFact> facts;
  final String? queryMatch;
  final String? matchedModel;
  final String? variantMatch;
  bool get isConfirmedExact => matchQuality == 'confirmed_exact';
  bool get isDocumentedFamilyCandidate => queryMatch == 'documented_family';

  factory CloudCatalogProduct.fromJson(Map<String, dynamic> json) {
    final facts = json['facts'];
    if (json['id'] is! String ||
        json['category'] is! String ||
        json['brand'] is! String ||
        json['full_model'] is! String ||
        json['fuel'] is! String ||
        json['match_quality'] is! String ||
        facts is! List ||
        json['variant'] != null && json['variant'] is! String ||
        json['region'] != null && json['region'] is! String ||
        json['query_match'] != null && json['query_match'] is! String ||
        json['matched_model'] != null && json['matched_model'] is! String ||
        json['variant_match'] != null && json['variant_match'] is! String ||
        json['query_match'] == 'documented_family' &&
            (json['match_quality'] != 'documented_variant_family' ||
                json['matched_model'] is! String ||
                (json['matched_model'] as String).isEmpty ||
                !const [
                  'confirmed',
                  'unresolved',
                ].contains(json['variant_match']) ||
                facts.isNotEmpty)) {
      throw const FormatException('Invalid reviewed catalog product');
    }
    return CloudCatalogProduct(
      id: json['id'] as String,
      category: json['category'] as String,
      brand: json['brand'] as String,
      fullModel: json['full_model'] as String,
      variant: json['variant'] as String?,
      region: json['region'] as String?,
      fuel: json['fuel'] as String,
      matchQuality: json['match_quality'] as String,
      queryMatch: json['query_match'] as String?,
      matchedModel: json['matched_model'] as String?,
      variantMatch: json['variant_match'] as String?,
      facts: facts
          .map(
            (fact) => CloudCatalogFact.fromJson(fact as Map<String, dynamic>),
          )
          .toList(),
    );
  }
}
