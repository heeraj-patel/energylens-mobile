class CloudTariff {
  const CloudTariff({
    this.id,
    this.fuel,
    this.rateUnit,
    this.currency,
    required this.homeId,
    required this.rate,
    required this.sourceAsOf,
    required this.effectiveFrom,
    this.effectiveTo,
  });

  /// These fields are retained from a validated server response. Callers that
  /// need priced evidence must require them; older display-only fixtures may
  /// omit them.
  final String? id;
  final String? fuel;
  final String? rateUnit;
  final String? currency;
  final String homeId;
  final String rate;
  final DateTime sourceAsOf;
  final DateTime effectiveFrom;
  final DateTime? effectiveTo;

  factory CloudTariff.fromJson(
    Map<String, dynamic> json,
    String homeId, {
    String fuel = 'electricity',
  }) {
    final rateUnit = fuel == 'natural_gas' ? 'therm' : 'kWh';
    final sourceAsOf = DateTime.tryParse(
      json['source_as_of'] is String ? json['source_as_of'] as String : '',
    );
    final effectiveFrom = DateTime.tryParse(
      json['effective_from'] is String ? json['effective_from'] as String : '',
    );
    final effectiveTo = json['effective_to'] == null
        ? null
        : DateTime.tryParse(
            json['effective_to'] is String
                ? json['effective_to'] as String
                : '',
          );
    if (json['id'] is! String ||
        json['home_id'] != homeId ||
        json['revision'] is! int ||
        (json['revision'] as int) < 1 ||
        json['fuel'] != fuel ||
        json['rate_unit'] != rateUnit ||
        json['currency'] != 'USD' ||
        json['rate'] is! String ||
        !RegExp(r'^(0|[1-9][0-9]{0,9})(\.[0-9]{1,8})?$')
            .hasMatch(json['rate'] as String) ||
        !const {
          'user_tariff',
          'official_tariff',
          'regional_average',
        }.contains(json['rate_kind']) ||
        json['source_ref'] is! String ||
        (json['source_ref'] as String).isEmpty ||
        json['is_fallback'] is! bool ||
        sourceAsOf == null ||
        effectiveFrom == null ||
        (json['effective_to'] != null && effectiveTo == null) ||
        (effectiveTo != null && !effectiveFrom.isBefore(effectiveTo))) {
      throw const FormatException('Invalid cloud tariff');
    }
    return CloudTariff(
      id: json['id'] as String,
      fuel: fuel,
      rateUnit: rateUnit,
      currency: 'USD',
      homeId: homeId,
      rate: json['rate'] as String,
      sourceAsOf: sourceAsOf,
      effectiveFrom: effectiveFrom,
      effectiveTo: effectiveTo,
    );
  }
}
