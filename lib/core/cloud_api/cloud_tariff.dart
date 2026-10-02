class CloudTariff {
  const CloudTariff({
    required this.homeId,
    required this.rate,
    required this.sourceAsOf,
    required this.effectiveFrom,
  });

  final String homeId;
  final String rate;
  final DateTime sourceAsOf;
  final DateTime effectiveFrom;

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
        effectiveFrom == null) {
      throw const FormatException('Invalid cloud tariff');
    }
    return CloudTariff(
      homeId: homeId,
      rate: json['rate'] as String,
      sourceAsOf: sourceAsOf,
      effectiveFrom: effectiveFrom,
    );
  }
}
