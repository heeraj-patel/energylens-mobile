/// Typed models for owner-scoped household dashboard and trend snapshots.
/// Decimal energy and money values intentionally remain strings to avoid
/// losing precision through binary floating point.
class CloudEnergyMoney {
  const CloudEnergyMoney({required this.amount, required this.currency});
  final String amount;
  final String currency;

  factory CloudEnergyMoney.fromJson(Object? value) {
    final json = _object(value, 'money');
    _keys(json, const {'amount', 'currency'});
    final amount = _decimal(json['amount'], 'money amount');
    final currency = json['currency'];
    if (currency is! String || !RegExp(r'^[A-Z]{3}$').hasMatch(currency)) {
      throw const FormatException('Invalid money currency');
    }
    return CloudEnergyMoney(amount: amount, currency: currency);
  }
}

class CloudEnergyQuantity {
  const CloudEnergyQuantity({required this.value, required this.unit});
  final String value;
  final String unit;

  factory CloudEnergyQuantity.fromJson(Object? value) {
    final json = _object(value, 'quantity');
    _keys(json, const {'value', 'unit'});
    final amount = _decimal(json['value'], 'quantity value');
    if (json['unit'] != 'kWh') {
      throw const FormatException('Invalid energy quantity unit');
    }
    return CloudEnergyQuantity(value: amount, unit: 'kWh');
  }
}

class CloudEnergyAllocation {
  const CloudEnergyAllocation({
    required this.energy,
    required this.cost,
    required this.usefulEnergy,
    required this.usefulCost,
    required this.wasteEnergy,
    required this.wasteCost,
    required this.unclassifiedEnergy,
    required this.unclassifiedCost,
    required this.availability,
    required this.evidenceBasis,
  });

  final CloudEnergyQuantity? energy;
  final CloudEnergyMoney? cost;
  final CloudEnergyQuantity? usefulEnergy;
  final CloudEnergyMoney? usefulCost;
  final CloudEnergyQuantity? wasteEnergy;
  final CloudEnergyMoney? wasteCost;
  final CloudEnergyQuantity? unclassifiedEnergy;
  final CloudEnergyMoney? unclassifiedCost;
  final String availability;
  final String evidenceBasis;

  factory CloudEnergyAllocation.fromJson(Object? value) {
    final json = _object(value, 'allocation');
    _keys(json, const {
      'energy',
      'cost',
      'useful_energy',
      'useful_cost',
      'waste_energy',
      'waste_cost',
      'unclassified_energy',
      'unclassified_cost',
      'availability',
      'evidence_basis',
    });
    return CloudEnergyAllocation(
      energy: _nullable(json['energy'], CloudEnergyQuantity.fromJson),
      cost: _nullable(json['cost'], CloudEnergyMoney.fromJson),
      usefulEnergy: _nullable(
        json['useful_energy'],
        CloudEnergyQuantity.fromJson,
      ),
      usefulCost: _nullable(json['useful_cost'], CloudEnergyMoney.fromJson),
      wasteEnergy: _nullable(
        json['waste_energy'],
        CloudEnergyQuantity.fromJson,
      ),
      wasteCost: _nullable(json['waste_cost'], CloudEnergyMoney.fromJson),
      unclassifiedEnergy: _nullable(
        json['unclassified_energy'],
        CloudEnergyQuantity.fromJson,
      ),
      unclassifiedCost: _nullable(
        json['unclassified_cost'],
        CloudEnergyMoney.fromJson,
      ),
      availability: _enumValue(json['availability'], const {
        'available',
        'partial',
        'unavailable',
      }, 'allocation availability'),
      evidenceBasis: _enumValue(json['evidence_basis'], const {
        'measured',
        'estimated',
        'inferred',
        'user_supplied',
        'mixed',
        'synthetic',
        'unavailable',
      }, 'allocation evidence basis'),
    );
  }
}

class CloudEnergyPeriod {
  const CloudEnergyPeriod({required this.start, required this.endExclusive});
  final DateTime start;
  final DateTime endExclusive;

  factory CloudEnergyPeriod.fromJson(Object? value) {
    final json = _object(value, 'period');
    _keys(json, const {'start_local', 'end_exclusive_local'});
    final start = _dateTime(json['start_local'], 'period start');
    final end = _dateTime(json['end_exclusive_local'], 'period end');
    if (!start.isBefore(end)) {
      throw const FormatException('Invalid period range');
    }
    return CloudEnergyPeriod(start: start, endExclusive: end);
  }
}

class CloudHouseholdEnergyMetadata {
  const CloudHouseholdEnergyMetadata({
    required this.schemaRevision,
    required this.contentRevision,
    required this.homeId,
    required this.dataMode,
    required this.fixtureRevision,
    required this.snapshotId,
    required this.generatedAt,
    required this.asOf,
    required this.timezone,
    required this.period,
    required this.scope,
    required this.availability,
    required this.evidenceBasis,
  });

  final String schemaRevision;
  final String contentRevision;
  final String homeId;
  final String dataMode;
  final String? fixtureRevision;
  final String snapshotId;
  final DateTime generatedAt;
  final DateTime? asOf;
  final String timezone;
  final CloudEnergyPeriod period;
  final String scope;
  final String availability;
  final String evidenceBasis;

  factory CloudHouseholdEnergyMetadata.fromJson(
    Map<String, dynamic> json, {
    required String expectedHomeId,
  }) {
    if (json['schema_revision'] != 'household_energy_v1') {
      throw const FormatException('Unsupported household energy schema');
    }
    final homeId = _nonempty(json['home_id'], 'home ID');
    if (homeId.toLowerCase() != expectedHomeId.toLowerCase()) {
      throw const FormatException('Household energy home ID changed');
    }
    final dataMode = _enumValue(json['data_mode'], const {
      'household',
      'sample',
    }, 'data mode');
    final fixture = json['fixture_revision'];
    if (fixture != null && (fixture is! String || fixture.isEmpty)) {
      throw const FormatException('Invalid fixture revision');
    }
    if (dataMode == 'sample' && fixture == null) {
      throw const FormatException(
        'Sample response is missing fixture revision',
      );
    }
    final evidenceBasis = _enumValue(json['evidence_basis'], const {
      'measured',
      'estimated',
      'inferred',
      'user_supplied',
      'mixed',
      'synthetic',
      'unavailable',
    }, 'evidence basis');
    if (dataMode == 'sample' && evidenceBasis != 'synthetic') {
      throw const FormatException(
        'Sample response must use synthetic evidence',
      );
    }
    return CloudHouseholdEnergyMetadata(
      schemaRevision: 'household_energy_v1',
      contentRevision: _nonempty(json['content_revision'], 'content revision'),
      homeId: homeId,
      dataMode: dataMode,
      fixtureRevision: fixture as String?,
      snapshotId: _nonempty(json['snapshot_id'], 'snapshot ID'),
      generatedAt: _dateTime(json['generated_at'], 'generated time'),
      asOf: json['as_of'] == null
          ? null
          : _dateTime(json['as_of'], 'as-of time'),
      timezone: _nonempty(json['timezone'], 'timezone'),
      period: CloudEnergyPeriod.fromJson(json['period']),
      scope: _enumValue(json['scope'], const {
        'whole_home_including_unattributed_load',
        'attributed_devices',
      }, 'scope'),
      availability: _enumValue(json['availability'], const {
        'available',
        'partial',
        'unavailable',
      }, 'availability'),
      evidenceBasis: evidenceBasis,
    );
  }
}

class CloudHouseholdDashboard {
  const CloudHouseholdDashboard({
    required this.metadata,
    required this.totals,
    required this.trendPeriod,
    required this.topRecommendationId,
    required this.assistantIntentId,
  });

  final CloudHouseholdEnergyMetadata metadata;
  final CloudEnergyAllocation totals;
  final String trendPeriod;
  final String? topRecommendationId;
  final String? assistantIntentId;

  String get schemaRevision => metadata.schemaRevision;
  String get contentRevision => metadata.contentRevision;
  String get homeId => metadata.homeId;
  String get dataMode => metadata.dataMode;
  String? get fixtureRevision => metadata.fixtureRevision;
  String get snapshotId => metadata.snapshotId;
  DateTime get generatedAt => metadata.generatedAt;
  DateTime? get asOf => metadata.asOf;
  String get timezone => metadata.timezone;
  CloudEnergyPeriod get period => metadata.period;
  String get scope => metadata.scope;
  String get availability => metadata.availability;
  String get evidenceBasis => metadata.evidenceBasis;

  factory CloudHouseholdDashboard.fromJson(
    Map<String, dynamic> json, {
    required String expectedHomeId,
  }) {
    _keys(
      json,
      const {
        'schema_revision',
        'content_revision',
        'home_id',
        'data_mode',
        'fixture_revision',
        'snapshot_id',
        'generated_at',
        'as_of',
        'timezone',
        'period',
        'scope',
        'availability',
        'evidence_basis',
        'view',
        'totals',
        'trend_period',
        'top_recommendation_id',
        'assistant_intent_id',
      },
      optional: const {'fixture_revision'},
    );
    if (json['view'] != 'dashboard') {
      throw const FormatException('Invalid household dashboard view');
    }
    final top = json['top_recommendation_id'];
    final intent = json['assistant_intent_id'];
    if ((top != null && top is! String) ||
        (intent != null && intent is! String)) {
      throw const FormatException('Invalid dashboard reference');
    }
    return CloudHouseholdDashboard(
      metadata: CloudHouseholdEnergyMetadata.fromJson(
        json,
        expectedHomeId: expectedHomeId,
      ),
      totals: CloudEnergyAllocation.fromJson(json['totals']),
      trendPeriod: _enumValue(json['trend_period'], const {
        'day',
        'week',
        'month',
      }, 'trend period'),
      topRecommendationId: top as String?,
      assistantIntentId: intent as String?,
    );
  }
}

class CloudEnergyTrendBucket {
  const CloudEnergyTrendBucket({
    required this.period,
    required this.allocation,
    required this.coverageFraction,
  });
  final CloudEnergyPeriod period;
  final CloudEnergyAllocation allocation;
  final String? coverageFraction;

  factory CloudEnergyTrendBucket.fromJson(Object? value) {
    final json = _object(value, 'trend bucket');
    _keys(json, const {
      'start_local',
      'end_exclusive_local',
      'allocation',
      'coverage_fraction',
    });
    final fraction = json['coverage_fraction'];
    return CloudEnergyTrendBucket(
      period: CloudEnergyPeriod.fromJson({
        'start_local': json['start_local'],
        'end_exclusive_local': json['end_exclusive_local'],
      }),
      allocation: CloudEnergyAllocation.fromJson(json['allocation']),
      coverageFraction: fraction == null
          ? null
          : _decimal(fraction, 'coverage fraction'),
    );
  }
}

class CloudHouseholdEnergyTrends {
  const CloudHouseholdEnergyTrends({
    required this.metadata,
    required this.granularity,
    required this.totals,
    required this.buckets,
  });

  final CloudHouseholdEnergyMetadata metadata;
  final String granularity;
  final CloudEnergyAllocation totals;
  final List<CloudEnergyTrendBucket> buckets;

  String get schemaRevision => metadata.schemaRevision;
  String get contentRevision => metadata.contentRevision;
  String get homeId => metadata.homeId;
  String get dataMode => metadata.dataMode;
  String? get fixtureRevision => metadata.fixtureRevision;
  String get snapshotId => metadata.snapshotId;
  DateTime get generatedAt => metadata.generatedAt;
  DateTime? get asOf => metadata.asOf;
  String get timezone => metadata.timezone;
  CloudEnergyPeriod get period => metadata.period;
  String get scope => metadata.scope;
  String get availability => metadata.availability;
  String get evidenceBasis => metadata.evidenceBasis;

  factory CloudHouseholdEnergyTrends.fromJson(
    Map<String, dynamic> json, {
    required String expectedHomeId,
  }) {
    _keys(
      json,
      const {
        'schema_revision',
        'content_revision',
        'home_id',
        'data_mode',
        'fixture_revision',
        'snapshot_id',
        'generated_at',
        'as_of',
        'timezone',
        'period',
        'scope',
        'availability',
        'evidence_basis',
        'view',
        'granularity',
        'totals',
        'buckets',
      },
      optional: const {'fixture_revision'},
    );
    if (json['view'] != 'energy_trends' || json['buckets'] is! List) {
      throw const FormatException('Invalid household energy trends');
    }
    final rows = json['buckets'] as List;
    return CloudHouseholdEnergyTrends(
      metadata: CloudHouseholdEnergyMetadata.fromJson(
        json,
        expectedHomeId: expectedHomeId,
      ),
      granularity: _enumValue(json['granularity'], const {
        'hour',
        'day',
        'week',
        'month',
      }, 'granularity'),
      totals: CloudEnergyAllocation.fromJson(json['totals']),
      buckets: List.unmodifiable(rows.map(CloudEnergyTrendBucket.fromJson)),
    );
  }
}

Map<String, dynamic> _object(Object? value, String field) {
  if (value is Map<String, dynamic>) return value;
  throw FormatException('Invalid $field object');
}

void _keys(
  Map<String, dynamic> json,
  Set<String> allowed, {
  Set<String> optional = const {},
}) {
  if (json.keys.any((key) => !allowed.contains(key)) ||
      allowed.any((key) => !optional.contains(key) && !json.containsKey(key))) {
    throw const FormatException('Invalid household energy response fields');
  }
}

String _nonempty(Object? value, String field) {
  if (value is String && value.trim().isNotEmpty) return value;
  throw FormatException('Invalid $field');
}

String _decimal(Object? value, String field) {
  if (value is String &&
      RegExp(r'^(0|[1-9][0-9]*)(\.[0-9]+)?$').hasMatch(value)) {
    return value;
  }
  throw FormatException('Invalid $field');
}

DateTime _dateTime(Object? value, String field) {
  final parsed = value is String ? DateTime.tryParse(value) : null;
  if (parsed != null) return parsed;
  throw FormatException('Invalid $field');
}

String _enumValue(Object? value, Set<String> choices, String field) {
  if (value is String && choices.contains(value)) return value;
  throw FormatException('Invalid $field');
}

T? _nullable<T>(Object? value, T Function(Object?) parse) =>
    value == null ? null : parse(value);
