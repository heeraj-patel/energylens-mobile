/// Typed models for owner-scoped household dashboard and trend snapshots.
/// Decimal energy and money values intentionally remain strings to avoid
/// losing precision through binary floating point.
class CloudEnergyMoney {
  const CloudEnergyMoney({required this.amount, required this.currency});
  final String amount;
  final String currency;

  /// Compares validated decimal money without binary floating-point rounding.
  bool hasSameValue(CloudEnergyMoney other) {
    if (currency != other.currency) return false;
    final left = amount.split('.');
    final right = other.amount.split('.');
    String fraction(List<String> parts) =>
        (parts.length == 1 ? '' : parts[1]).replaceFirst(RegExp(r'0+$'), '');
    return left[0] == right[0] && fraction(left) == fraction(right);
  }

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

/// Natural gas quantity; therms only, kept apart from electric kWh.
class CloudFuelQuantity {
  const CloudFuelQuantity({required this.value, required this.unit});
  final String value;
  final String unit;

  factory CloudFuelQuantity.fromJson(Object? value) {
    final json = _object(value, 'fuel quantity');
    _keys(json, const {'value', 'unit'});
    final amount = _decimal(json['value'], 'fuel quantity value');
    if (json['unit'] != 'therm') {
      throw const FormatException('Invalid fuel quantity unit');
    }
    return CloudFuelQuantity(value: amount, unit: 'therm');
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
    this.wasteBasis,
    this.rateBasis,
    this.fuel,
    this.gasEnergy,
    this.gasEnergyKwhEq,
    this.totalEnergyKwhEq,
    this.gasCost,
    this.totalCost,
    this.standbyCost,
    this.gasRateBasis,
    this.gasBasis,
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

  /// Provenance markers for tracking only; never shown on screen.
  final String? wasteBasis;
  final String? rateBasis;

  /// Gas fields are absent or null on electric-only and older payloads.
  final String? fuel;
  final CloudFuelQuantity? gasEnergy;
  final CloudEnergyQuantity? gasEnergyKwhEq;
  final CloudEnergyQuantity? totalEnergyKwhEq;
  final CloudEnergyMoney? gasCost;
  final CloudEnergyMoney? totalCost;
  final CloudEnergyMoney? standbyCost;
  final String? gasRateBasis;
  final String? gasBasis;

  factory CloudEnergyAllocation.fromJson(Object? value) {
    final json = _object(value, 'allocation');
    _keys(
      json,
      const {
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
        'waste_basis',
        'rate_basis',
        'fuel',
        'gas_energy',
        'gas_energy_kwh_eq',
        'total_energy_kwh_eq',
        'gas_cost',
        'total_cost',
        'standby_cost',
        'gas_rate_basis',
        'gas_basis',
      },
      optional: const {
        'waste_basis',
        'rate_basis',
        'fuel',
        'gas_energy',
        'gas_energy_kwh_eq',
        'total_energy_kwh_eq',
        'gas_cost',
        'total_cost',
        'standby_cost',
        'gas_rate_basis',
        'gas_basis',
      },
    );
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
      wasteBasis: _nullable(
        json['waste_basis'],
        (v) => _enumValue(v, const {
          'standby',
          'floor',
          'demo',
          'rated_standby',
        }, 'waste basis'),
      ),
      rateBasis: _nullable(
        json['rate_basis'],
        (v) => _enumValue(v, const {'home_tariff', 'us_average'}, 'rate basis'),
      ),
      fuel: _nullable(
        json['fuel'],
        (v) => _enumValue(v, const {
          'electricity',
          'natural_gas',
          'propane',
        }, 'fuel'),
      ),
      gasEnergy: _nullable(json['gas_energy'], CloudFuelQuantity.fromJson),
      gasEnergyKwhEq: _nullable(
        json['gas_energy_kwh_eq'],
        CloudEnergyQuantity.fromJson,
      ),
      totalEnergyKwhEq: _nullable(
        json['total_energy_kwh_eq'],
        CloudEnergyQuantity.fromJson,
      ),
      gasCost: _nullable(json['gas_cost'], CloudEnergyMoney.fromJson),
      totalCost: _nullable(json['total_cost'], CloudEnergyMoney.fromJson),
      standbyCost: _nullable(json['standby_cost'], CloudEnergyMoney.fromJson),
      gasRateBasis: _nullable(
        json['gas_rate_basis'],
        (v) => _enumValue(v, const {
          'user_tariff',
          'state_average',
          'national_average',
          'static',
        }, 'gas rate basis'),
      ),
      gasBasis: _nullable(
        json['gas_basis'],
        (v) => _enumValue(v, const {
          'rated_fact',
          'derived_from_cef',
          'typical',
        }, 'gas basis'),
      ),
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
      'mixed',
    }, 'data mode');
    final fixture = json['fixture_revision'];
    if (fixture != null && (fixture is! String || fixture.isEmpty)) {
      throw const FormatException('Invalid fixture revision');
    }
    if (dataMode != 'household' && fixture == null) {
      throw const FormatException(
        'Seeded response is missing fixture revision',
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
    this.deviceAllocations = const [],
    this.unattributed,
  });

  final CloudHouseholdEnergyMetadata metadata;
  final CloudEnergyAllocation totals;
  final String trendPeriod;
  final String? topRecommendationId;
  final String? assistantIntentId;
  final List<CloudDeviceEnergyAllocation> deviceAllocations;
  final CloudEnergyAllocation? unattributed;

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
        'device_allocations',
        'unattributed',
      },
      optional: const {
        'fixture_revision',
        'device_allocations',
        'unattributed',
      },
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
      deviceAllocations: _deviceAllocations(json['device_allocations']),
      unattributed: _nullable(
        json['unattributed'],
        CloudEnergyAllocation.fromJson,
      ),
    );
  }
}

class CloudEnergyTrendBucket {
  const CloudEnergyTrendBucket({
    required this.period,
    required this.allocation,
    required this.coverageFraction,
    this.deviceAllocations = const [],
    this.unattributed,
  });
  final CloudEnergyPeriod period;
  final CloudEnergyAllocation allocation;
  final String? coverageFraction;
  final List<CloudDeviceEnergyAllocation> deviceAllocations;
  final CloudEnergyAllocation? unattributed;

  factory CloudEnergyTrendBucket.fromJson(Object? value) {
    final json = _object(value, 'trend bucket');
    _keys(
      json,
      const {
        'start_local',
        'end_exclusive_local',
        'allocation',
        'coverage_fraction',
        'device_allocations',
        'unattributed',
      },
      optional: const {'device_allocations', 'unattributed'},
    );
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
      deviceAllocations: _deviceAllocations(json['device_allocations']),
      unattributed: _nullable(
        json['unattributed'],
        CloudEnergyAllocation.fromJson,
      ),
    );
  }
}

class CloudDeviceEnergyAllocation {
  const CloudDeviceEnergyAllocation({
    this.applianceId,
    this.deviceId,
    this.name,
    required this.allocation,
  });

  final String? applianceId;
  final String? deviceId;
  final String? name;
  final CloudEnergyAllocation allocation;

  factory CloudDeviceEnergyAllocation.fromJson(Object? value) {
    final json = _object(value, 'device allocation');
    _keys(
      json,
      const {'appliance_id', 'device_id', 'name', 'allocation'},
      optional: const {'appliance_id', 'device_id', 'name'},
    );
    final applianceId = json['appliance_id'];
    final deviceId = json['device_id'];
    final name = json['name'];
    if ((applianceId == null) == (deviceId == null) ||
        (applianceId != null &&
            (applianceId is! String ||
                !RegExp(r'^[0-9a-fA-F]{8}(-[0-9a-fA-F]{4}){3}-[0-9a-fA-F]{12}$')
                    .hasMatch(applianceId))) ||
        (deviceId != null &&
            (deviceId is! String ||
                !RegExp(r'^demo-device-(0[1-9]|1[0-8])$')
                    .hasMatch(deviceId))) ||
        (name != null && (name is! String || name.trim().isEmpty)) ||
        (applianceId != null && name != null)) {
      throw const FormatException('Invalid device allocation ID');
    }
    return CloudDeviceEnergyAllocation(
      applianceId: applianceId as String?,
      deviceId: deviceId as String?,
      name: name as String?,
      allocation: CloudEnergyAllocation.fromJson(json['allocation']),
    );
  }
}

List<CloudDeviceEnergyAllocation> _deviceAllocations(Object? raw) {
  if (raw == null) return const [];
  if (raw is! List) {
    throw const FormatException('Invalid device allocations');
  }
  final rows = raw.map(CloudDeviceEnergyAllocation.fromJson).toList();
  if (rows
          .map((row) => (row.applianceId ?? row.deviceId!).toLowerCase())
          .toSet()
          .length !=
      rows.length) {
    throw const FormatException('Duplicate device allocation');
  }
  return List.unmodifiable(rows);
}

const _efficiencyBasisValues = {
  'measured',
  'estimated',
  'not_configured',
  'flat_tariff',
  'insufficient_data',
  'unmetered',
  'fuel_not_applicable',
};

String _efficiencyBasis(Object? value) =>
    _enumValue(value, _efficiencyBasisValues, 'efficiency basis');

/// Why each measured efficiency amount is set or null.
class CloudEfficiencyBases {
  const CloudEfficiencyBases({
    required this.night,
    required this.away,
    required this.peakRates,
    required this.habits,
    required this.waste,
  });

  final String night;
  final String away;
  final String peakRates;
  final String habits;
  final String waste;
}

class CloudEfficiencyNightWindow {
  const CloudEfficiencyNightWindow({
    required this.startLocal,
    required this.endLocal,
    required this.timezone,
  });

  final String startLocal;
  final String endLocal;
  final String timezone;

  factory CloudEfficiencyNightWindow.fromJson(Object? value) {
    final json = _object(value, 'efficiency night window');
    _keys(json, const {'start_local', 'end_local', 'timezone'});
    String time(String key) {
      final v = json[key];
      if (v is String &&
          RegExp(r'^([01][0-9]|2[0-3]):[0-5][0-9]$').hasMatch(v)) {
        return v;
      }
      throw const FormatException('Invalid Efficiency night window');
    }

    return CloudEfficiencyNightWindow(
      startLocal: time('start_local'),
      endLocal: time('end_local'),
      timezone: _nonempty(json['timezone'], 'night window timezone'),
    );
  }
}

class CloudEfficiencyDevice {
  const CloudEfficiencyDevice({
    required this.applianceId,
    required this.night,
    required this.away,
    required this.peak,
    required this.habits,
    required this.nightBasis,
    required this.awayBasis,
    required this.peakBasis,
    required this.habitsBasis,
  });

  final String applianceId;
  final CloudEnergyMoney? night;
  final CloudEnergyMoney? away;
  final CloudEnergyMoney? peak;
  final CloudEnergyMoney? habits;
  final String nightBasis;
  final String awayBasis;
  final String peakBasis;
  final String habitsBasis;

  factory CloudEfficiencyDevice.fromJson(Object? value) {
    final json = _object(value, 'efficiency device');
    _keys(json, const {
      'appliance_id',
      'night',
      'away',
      'peak',
      'habits',
      'basis',
    });
    final id = json['appliance_id'];
    if (id is! String || id.isEmpty) {
      throw const FormatException('Invalid Efficiency device');
    }
    final basis = _object(json['basis'], 'efficiency device basis');
    _keys(basis, const {'night', 'away', 'peak', 'habits'});
    return CloudEfficiencyDevice(
      applianceId: id,
      night: _nullable(json['night'], CloudEnergyMoney.fromJson),
      away: _nullable(json['away'], CloudEnergyMoney.fromJson),
      peak: _nullable(json['peak'], CloudEnergyMoney.fromJson),
      habits: _nullable(json['habits'], CloudEnergyMoney.fromJson),
      nightBasis: _efficiencyBasis(basis['night']),
      awayBasis: _efficiencyBasis(basis['away']),
      peakBasis: _efficiencyBasis(basis['peak']),
      habitsBasis: _efficiencyBasis(basis['habits']),
    );
  }
}

/// Parsed efficiency summary shared by the month-to-date and trailing-30-day
/// objects. Synthetic keeps every amount; measured amounts may be null.
class _EfficiencyParts {
  const _EfficiencyParts({
    required this.cost,
    required this.identified,
    required this.optimalBase,
    required this.waste,
    required this.away,
    required this.peak,
    required this.habits,
    required this.night,
    required this.awayTotal,
    required this.widths,
    required this.evidenceBasis,
    required this.bases,
    required this.nightWindow,
    required this.awaySource,
    required this.devices,
  });

  final CloudEnergyMoney cost;
  final CloudEnergyMoney identified;
  final CloudEnergyMoney optimalBase;
  final CloudEnergyMoney? waste;
  final CloudEnergyMoney? away;
  final CloudEnergyMoney? peak;
  final CloudEnergyMoney? habits;
  final CloudEnergyMoney? night;
  final CloudEnergyMoney? awayTotal;
  final CloudEfficiencyChartSegmentWidthPercent widths;
  final String evidenceBasis;
  final CloudEfficiencyBases? bases;
  final CloudEfficiencyNightWindow? nightWindow;
  final String? awaySource;
  final List<CloudEfficiencyDevice> devices;
}

const _efficiencyCommonKeys = {
  'identified_opportunity',
  'optimal_base',
  'waste_opportunity',
  'away_opportunity',
  'peak_rates_opportunity',
  'habits_opportunity',
  'night_total_opportunity',
  'away_total_opportunity',
  'chart_segment_width_percent',
  'waste_timing_basis',
  'evidence_basis',
};

const _efficiencyMeasuredKeys = {
  'night_basis',
  'away_basis',
  'peak_rates_basis',
  'habits_basis',
  'waste_basis',
  'night_window',
  'away_source',
  'devices',
};

_EfficiencyParts _parseEfficiency(Map<String, dynamic> json, String costKey) {
  final measured = json['evidence_basis'] == 'measured';
  _keys(
    json,
    {
      costKey,
      ..._efficiencyCommonKeys,
      if (measured) ..._efficiencyMeasuredKeys,
    },
    optional: const {'devices'},
  );
  if (json['evidence_basis'] != 'synthetic' && !measured) {
    throw const FormatException('Invalid Efficiency evidence basis');
  }
  if (json['waste_timing_basis'] !=
      (measured ? 'measured_local_time' : 'unknown_75_25_demo_fallback')) {
    throw const FormatException('Invalid Efficiency evidence basis');
  }
  CloudEnergyMoney money(String key) => CloudEnergyMoney.fromJson(json[key]);
  CloudEnergyMoney? amount(String key) =>
      measured ? _nullable(json[key], CloudEnergyMoney.fromJson) : money(key);
  final cost = money(costKey);
  final identified = money('identified_opportunity');
  final optimalBase = money('optimal_base');
  final waste = amount('waste_opportunity');
  final away = amount('away_opportunity');
  final peak = amount('peak_rates_opportunity');
  final habits = amount('habits_opportunity');
  final night = amount('night_total_opportunity');
  final awayTotal = amount('away_total_opportunity');
  final all = [
    cost,
    identified,
    optimalBase,
    waste,
    away,
    peak,
    habits,
    night,
    awayTotal,
  ];
  if (all.any((value) => value != null && value.currency != 'USD')) {
    throw const FormatException('Invalid Efficiency currency');
  }
  final widths = CloudEfficiencyChartSegmentWidthPercent.fromJson(
    json['chart_segment_width_percent'],
  );
  if (!measured) {
    return _EfficiencyParts(
      cost: cost,
      identified: identified,
      optimalBase: optimalBase,
      waste: waste,
      away: away,
      peak: peak,
      habits: habits,
      night: night,
      awayTotal: awayTotal,
      widths: widths,
      evidenceBasis: 'synthetic',
      bases: null,
      nightWindow: null,
      awaySource: null,
      devices: const [],
    );
  }
  final devices = json['devices'];
  if (devices != null && devices is! List) {
    throw const FormatException('Invalid Efficiency devices');
  }
  return _EfficiencyParts(
    cost: cost,
    identified: identified,
    optimalBase: optimalBase,
    waste: waste,
    away: away,
    peak: peak,
    habits: habits,
    night: night,
    awayTotal: awayTotal,
    widths: widths,
    evidenceBasis: 'measured',
    bases: CloudEfficiencyBases(
      night: _efficiencyBasis(json['night_basis']),
      away: _efficiencyBasis(json['away_basis']),
      peakRates: _efficiencyBasis(json['peak_rates_basis']),
      habits: _efficiencyBasis(json['habits_basis']),
      waste: _efficiencyBasis(json['waste_basis']),
    ),
    nightWindow: CloudEfficiencyNightWindow.fromJson(json['night_window']),
    awaySource: _enumValue(json['away_source'], const {
      'user_schedule',
      'baseline_inferred',
      'default_schedule',
      'none',
    }, 'away source'),
    devices: List.unmodifiable(
      ((devices as List?) ?? const []).map(CloudEfficiencyDevice.fromJson),
    ),
  );
}

/// Efficiency amounts calculated by Cloud, month to date. Mobile keeps them as
/// typed API values and performs no savings math. Measured amounts may be null.
class CloudEfficiencyMonthToDate {
  CloudEfficiencyMonthToDate._(_EfficiencyParts p)
    : monthToDateCost = p.cost,
      identifiedOpportunity = p.identified,
      optimalBase = p.optimalBase,
      wasteOpportunity = p.waste,
      awayOpportunity = p.away,
      peakRatesOpportunity = p.peak,
      habitsOpportunity = p.habits,
      nightTotalOpportunity = p.night,
      awayTotalOpportunity = p.awayTotal,
      chartSegmentWidthPercent = p.widths,
      evidenceBasis = p.evidenceBasis,
      bases = p.bases,
      nightWindow = p.nightWindow,
      awaySource = p.awaySource,
      devices = p.devices;

  final CloudEnergyMoney monthToDateCost;
  final CloudEnergyMoney identifiedOpportunity;
  final CloudEnergyMoney optimalBase;
  final CloudEnergyMoney? wasteOpportunity;
  final CloudEnergyMoney? awayOpportunity;
  final CloudEnergyMoney? peakRatesOpportunity;
  final CloudEnergyMoney? habitsOpportunity;
  final CloudEnergyMoney? nightTotalOpportunity;
  final CloudEnergyMoney? awayTotalOpportunity;
  final CloudEfficiencyChartSegmentWidthPercent chartSegmentWidthPercent;
  final String evidenceBasis;
  final CloudEfficiencyBases? bases;
  final CloudEfficiencyNightWindow? nightWindow;
  final String? awaySource;
  final List<CloudEfficiencyDevice> devices;

  factory CloudEfficiencyMonthToDate.fromJson(Object? value) =>
      CloudEfficiencyMonthToDate._(
        _parseEfficiency(
          _object(value, 'efficiency month-to-date'),
          'month_to_date_cost',
        ),
      );
}

/// Efficiency amounts calculated by Cloud for the trailing 30 days. Mobile
/// keeps them as typed API values and performs no savings math.
class CloudEfficiencyTrailing30Days {
  CloudEfficiencyTrailing30Days._(_EfficiencyParts p)
    : periodCost = p.cost,
      identifiedOpportunity = p.identified,
      optimalBase = p.optimalBase,
      wasteOpportunity = p.waste,
      awayOpportunity = p.away,
      peakRatesOpportunity = p.peak,
      habitsOpportunity = p.habits,
      nightTotalOpportunity = p.night,
      awayTotalOpportunity = p.awayTotal,
      chartSegmentWidthPercent = p.widths,
      evidenceBasis = p.evidenceBasis,
      bases = p.bases,
      nightWindow = p.nightWindow,
      awaySource = p.awaySource,
      devices = p.devices;

  final CloudEnergyMoney periodCost;
  final CloudEnergyMoney identifiedOpportunity;
  final CloudEnergyMoney optimalBase;
  final CloudEnergyMoney? wasteOpportunity;
  final CloudEnergyMoney? awayOpportunity;
  final CloudEnergyMoney? peakRatesOpportunity;
  final CloudEnergyMoney? habitsOpportunity;
  final CloudEnergyMoney? nightTotalOpportunity;
  final CloudEnergyMoney? awayTotalOpportunity;
  final CloudEfficiencyChartSegmentWidthPercent chartSegmentWidthPercent;
  final String evidenceBasis;
  final CloudEfficiencyBases? bases;
  final CloudEfficiencyNightWindow? nightWindow;
  final String? awaySource;
  final List<CloudEfficiencyDevice> devices;

  factory CloudEfficiencyTrailing30Days.fromJson(Object? value) =>
      CloudEfficiencyTrailing30Days._(
        _parseEfficiency(
          _object(value, 'efficiency trailing 30 days'),
          'period_cost',
        ),
      );
}

class CloudEfficiencyChartSegmentWidthPercent {
  const CloudEfficiencyChartSegmentWidthPercent({
    required this.night,
    required this.away,
    required this.peakRates,
    required this.habits,
  });

  final String night;
  final String away;
  final String peakRates;
  final String habits;

  factory CloudEfficiencyChartSegmentWidthPercent.fromJson(Object? value) {
    final json = _object(value, 'efficiency chart widths');
    _keys(json, const {'night', 'away', 'peak_rates', 'habits'});
    String percent(String key) {
      final value = json[key];
      if (value is String &&
          RegExp(r'^(?:[0-9]|[1-9][0-9])\.[0-9]{2}$|^100\.00$')
              .hasMatch(value)) {
        return value;
      }
      throw const FormatException('Invalid Efficiency chart width');
    }

    return CloudEfficiencyChartSegmentWidthPercent(
      night: percent('night'),
      away: percent('away'),
      peakRates: percent('peak_rates'),
      habits: percent('habits'),
    );
  }
}

class CloudHouseholdEnergyTrends {
  const CloudHouseholdEnergyTrends({
    required this.metadata,
    required this.granularity,
    required this.totals,
    required this.buckets,
    this.efficiencyMonthToDate,
    this.efficiencyTrailing30Days,
  });

  final CloudHouseholdEnergyMetadata metadata;
  final String granularity;
  final CloudEnergyAllocation totals;
  final List<CloudEnergyTrendBucket> buckets;
  final CloudEfficiencyMonthToDate? efficiencyMonthToDate;
  final CloudEfficiencyTrailing30Days? efficiencyTrailing30Days;

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
        'efficiency_month_to_date',
        'efficiency_trailing_30_days',
      },
      optional: const {
        'fixture_revision',
        'efficiency_month_to_date',
        'efficiency_trailing_30_days',
      },
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
      efficiencyMonthToDate: json['efficiency_month_to_date'] == null
          ? null
          : CloudEfficiencyMonthToDate.fromJson(
              json['efficiency_month_to_date'],
            ),
      efficiencyTrailing30Days: json['efficiency_trailing_30_days'] == null
          ? null
          : CloudEfficiencyTrailing30Days.fromJson(
              json['efficiency_trailing_30_days'],
            ),
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
