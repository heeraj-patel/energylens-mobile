class CloudEstimatePeriod {
  const CloudEstimatePeriod({
    required this.start,
    required this.end,
    required this.timezone,
  });
  final String start;
  final String end;
  final String timezone;
}

class CloudEstimateQuantity {
  const CloudEstimateQuantity({
    required this.value,
    required this.unit,
    required this.fuel,
  });
  final String value;
  final String unit;
  final String fuel;
}

class CloudEstimateRef {
  const CloudEstimateRef({
    required this.kind,
    required this.id,
    required this.revision,
  });
  final String kind;
  final String id;
  final int revision;
}

class CloudEstimate {
  const CloudEstimate({
    required this.id,
    required this.applianceId,
    required this.kind,
    required this.period,
    required this.energy,
    required this.cost,
    required this.currency,
    required this.rateKind,
    required this.identityQuality,
    required this.consumptionQuality,
    required this.sourceQuality,
    required this.contextQuality,
    required this.rateQuality,
    required this.waste,
    required this.evidenceRefs,
    required this.formulaVersion,
    required this.asOf,
    required this.unavailableReason,
    this.wasteEnergy,
    this.wasteCost,
    this.wasteBasis,
    this.rateBasis,
  });
  final String id;
  final String applianceId;
  final String kind;
  final CloudEstimatePeriod period;
  final CloudEstimateQuantity? energy;
  final String? cost;
  final String? currency;
  final String? rateKind;
  final String identityQuality;
  final String consumptionQuality;
  final String sourceQuality;
  final String contextQuality;
  final String rateQuality;
  final String waste;
  final List<CloudEstimateRef> evidenceRefs;
  final String formulaVersion;
  final DateTime asOf;
  final String? unavailableReason;
  final CloudEstimateQuantity? wasteEnergy;
  final String? wasteCost;
  final String? wasteBasis;
  final String? rateBasis;

  factory CloudEstimate.fromJson(Map<String, dynamic> json) {
    final period = json['period'];
    final energy = json['energy'];
    final cost = json['cost'];
    final quality = json['quality'];
    final refs = json['evidence_refs'];
    final asOf = json['as_of'] is String
        ? DateTime.tryParse(json['as_of'] as String)
        : null;
    if (json['id'] is! String ||
        json['appliance_id'] is! String ||
        !const {
          'estimated_operating_cost',
          'estimated_useful_cost',
          'unavailable',
        }.contains(json['kind']) ||
        period is! Map<String, dynamic> ||
        period['start'] is! String ||
        period['end'] is! String ||
        period['timezone'] is! String ||
        quality is! Map<String, dynamic> ||
        quality['identity'] is! String ||
        quality['consumption'] is! String ||
        quality['source'] is! String ||
        quality['context'] is! String ||
        quality['rate'] is! String ||
        !const {'not_yet_assessed', 'assessed'}.contains(json['waste']) ||
        !_optionalEnum(json['waste_basis'], const {
          'standby',
          'floor',
          'demo',
        }) ||
        !_optionalEnum(json['rate_basis'], const {
          'home_tariff',
          'us_average',
        }) ||
        refs is! List ||
        json['formula_version'] is! String ||
        asOf == null) {
      throw const FormatException('Invalid cloud estimate');
    }
    if (energy != null &&
            (energy is! Map<String, dynamic> ||
                energy['value'] is! String ||
                energy['unit'] is! String ||
                energy['fuel'] is! String ||
                !((energy['fuel'] == 'electricity' &&
                        energy['unit'] == 'kWh') ||
                    (energy['fuel'] == 'natural_gas' &&
                        energy['unit'] == 'therm'))) ||
        cost != null &&
            (cost is! Map<String, dynamic> ||
                cost['value'] is! String ||
                cost['currency'] is! String ||
                cost['rate_kind'] is! String)) {
      throw const FormatException('Invalid cloud estimate amount');
    }
    final wasteEnergy = json['waste_energy'];
    final wasteCost = json['waste_cost'];
    if (wasteEnergy != null &&
            (wasteEnergy is! Map<String, dynamic> ||
                wasteEnergy['value'] is! String ||
                wasteEnergy['unit'] != 'kWh' ||
                wasteEnergy['fuel'] != 'electricity') ||
        wasteCost != null &&
            (wasteCost is! Map<String, dynamic> ||
                wasteCost['value'] is! String ||
                wasteCost['currency'] is! String ||
                wasteCost['rate_kind'] is! String)) {
      throw const FormatException('Invalid cloud estimate waste');
    }
    if (json['kind'] == 'unavailable' &&
        (json['unavailable_reason'] is! String ||
            cost != null ||
            energy != null)) {
      throw const FormatException('Invalid unavailable estimate');
    }
    if (json['kind'] != 'unavailable' &&
        (energy == null ||
            cost == null ||
            json['unavailable_reason'] != null)) {
      throw const FormatException('Invalid priced estimate');
    }
    return CloudEstimate(
      id: json['id'] as String,
      applianceId: json['appliance_id'] as String,
      kind: json['kind'] as String,
      period: CloudEstimatePeriod(
        start: period['start'] as String,
        end: period['end'] as String,
        timezone: period['timezone'] as String,
      ),
      energy: energy == null
          ? null
          : CloudEstimateQuantity(
              value: energy['value'] as String,
              unit: energy['unit'] as String,
              fuel: energy['fuel'] as String,
            ),
      cost: cost == null ? null : cost['value'] as String,
      currency: cost == null ? null : cost['currency'] as String,
      rateKind: cost == null ? null : cost['rate_kind'] as String,
      identityQuality: quality['identity'] as String,
      consumptionQuality: quality['consumption'] as String,
      sourceQuality: quality['source'] as String,
      contextQuality: quality['context'] as String,
      rateQuality: quality['rate'] as String,
      waste: json['waste'] as String,
      evidenceRefs: refs.map((ref) {
        if (ref is! Map<String, dynamic> ||
            ref['kind'] is! String ||
            ref['id'] is! String ||
            ref['revision'] is! int) {
          throw const FormatException('Invalid estimate evidence reference');
        }
        return CloudEstimateRef(
          kind: ref['kind'] as String,
          id: ref['id'] as String,
          revision: ref['revision'] as int,
        );
      }).toList(),
      formulaVersion: json['formula_version'] as String,
      asOf: asOf,
      unavailableReason: json['unavailable_reason'] as String?,
      wasteEnergy: wasteEnergy == null
          ? null
          : CloudEstimateQuantity(
              value: wasteEnergy['value'] as String,
              unit: 'kWh',
              fuel: 'electricity',
            ),
      wasteCost: wasteCost == null ? null : wasteCost['value'] as String,
      wasteBasis: json['waste_basis'] as String?,
      rateBasis: json['rate_basis'] as String?,
    );
  }
}

bool _optionalEnum(Object? value, Set<String> allowed) =>
    value == null || (value is String && allowed.contains(value));

class CloudEstimateBatch {
  const CloudEstimateBatch({required this.estimates, required this.asOf});
  final List<CloudEstimate> estimates;
  final DateTime asOf;
}
