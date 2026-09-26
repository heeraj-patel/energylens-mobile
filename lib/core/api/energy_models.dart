/// DTOs for the hub's energy cost estimator (energy estimator plan §3.1-§3.6,
/// `kernel-common/docs/plans/2026-09-22-energy-cost-estimator-plan.md`).
///
/// Hand-written to match `kernel-common-contracts/api/hub-openapi.yaml`
/// (`EnergyEstimates`, `DeviceEnergyEstimate`, `EnergyRate`, `EnergySplit`,
/// `EnergySlider`, `DeviceUsageProfile`, `HouseholdEnergyRate`), the same way
/// `models.dart` mirrors the rest of the spec (`lib/core/api/generated/` is
/// still a placeholder re-export). Unknown enum strings parse to a tolerant
/// fallback instead of throwing, so a newer hub adding a value doesn't blank
/// the whole card.
library;

/// `EnergyUsageKind`: how a device's category is used.
enum EnergyUsageKind {
  hoursPerWeek('hours_per_week'),
  cyclesPerWeek('cycles_per_week'),
  alwaysOn('always_on');

  const EnergyUsageKind(this.wire);

  /// The contract's string value.
  final String wire;

  static EnergyUsageKind fromWire(String? value) => EnergyUsageKind.values
      .firstWhere((k) => k.wire == value, orElse: () => alwaysOn);
}

/// `EnergyPowerSource`: which power figures an estimate uses (plan §3.2).
enum EnergyPowerSource {
  measured('measured'),
  rated('rated'),
  derivedAnnual('derived_annual'),
  categoryTypical('category_typical'),
  none('none');

  const EnergyPowerSource(this.wire);

  final String wire;

  static EnergyPowerSource fromWire(String? value) => EnergyPowerSource.values
      .firstWhere((s) => s.wire == value, orElse: () => none);
}

/// `EnergyRateSource`: where the electricity rate comes from (plan §3.4).
enum EnergyRateSource {
  user('user'),
  utility('utility'),
  state('state'),
  national('national'),
  builtIn('built_in');

  const EnergyRateSource(this.wire);

  final String wire;

  static EnergyRateSource fromWire(String? value) => EnergyRateSource.values
      .firstWhere((s) => s.wire == value, orElse: () => builtIn);
}

double? _numOrNull(Object? v) => (v as num?)?.toDouble();

/// `EnergySlider`: range/default for a category, in the usage kind's unit.
class EnergySlider {
  const EnergySlider({
    required this.min,
    required this.max,
    required this.step,
    required this.defaultValue,
  });

  factory EnergySlider.fromJson(Map<String, dynamic> j) => EnergySlider(
    min: (j['min'] as num).toDouble(),
    max: (j['max'] as num).toDouble(),
    step: (j['step'] as num).toDouble(),
    defaultValue: (j['default'] as num).toDouble(),
  );

  final double min;
  final double max;
  final double step;
  final double defaultValue;

  Map<String, dynamic> toJson() => <String, dynamic>{
    'min': min,
    'max': max,
    'step': step,
    'default': defaultValue,
  };

  /// Number of discrete slider positions, for `Slider.divisions`. Null when
  /// the step doesn't divide the range into a sane count.
  int? get divisions {
    if (step <= 0 || max <= min) return null;
    final n = ((max - min) / step).round();
    return n > 0 && n <= 1000 ? n : null;
  }
}

/// `EnergyRate`: an electricity rate plus its provenance.
class EnergyRate {
  const EnergyRate({
    required this.rateUsdPerKwh,
    required this.source,
    required this.sourceLabel,
    this.asOf,
  });

  factory EnergyRate.fromJson(Map<String, dynamic> j) => EnergyRate(
    rateUsdPerKwh: (j['rate_usd_per_kwh'] as num).toDouble(),
    source: EnergyRateSource.fromWire(j['source'] as String?),
    sourceLabel: j['source_label'] as String? ?? '',
    asOf: j['as_of'] == null ? null : DateTime.tryParse(j['as_of'] as String),
  );

  final double rateUsdPerKwh;
  final EnergyRateSource source;

  /// Hub-supplied, human-readable provenance (e.g. "Texas average (EIA)").
  /// English-only, so the app localizes `user`/`built_in` itself and shows
  /// this label only for cloud-resolved sources.
  final String sourceLabel;

  /// Date of the underlying rate data (e.g. the EIA data month).
  final DateTime? asOf;

  Map<String, dynamic> toJson() => <String, dynamic>{
    'rate_usd_per_kwh': rateUsdPerKwh,
    'source': source.wire,
    'source_label': sourceLabel,
    'as_of': asOf == null
        ? null
        : '${asOf!.year.toString().padLeft(4, '0')}-'
              '${asOf!.month.toString().padLeft(2, '0')}-'
              '${asOf!.day.toString().padLeft(2, '0')}',
  };
}

/// `EnergySplit`: active / standby / total for one quantity. `active` and
/// `standby` are null for `measured` rows (no split).
class EnergySplit {
  const EnergySplit({required this.total, this.active, this.standby});

  factory EnergySplit.fromJson(Map<String, dynamic> j) => EnergySplit(
    active: _numOrNull(j['active']),
    standby: _numOrNull(j['standby']),
    total: (j['total'] as num).toDouble(),
  );

  static const EnergySplit zero = EnergySplit(total: 0, active: 0, standby: 0);

  final double? active;
  final double? standby;
  final double total;

  Map<String, dynamic> toJson() => <String, dynamic>{
    'active': active,
    'standby': standby,
    'total': total,
  };
}

/// `DeviceEnergyEstimate`: one device's row in `GET /energy/estimates`.
class DeviceEnergyEstimate {
  const DeviceEnergyEstimate({
    required this.deviceId,
    required this.name,
    required this.profileCategory,
    required this.powerSource,
    required this.usageKind,
    required this.usageValueIsDefault,
    required this.standbyApplies,
    this.category,
    this.ratingSource,
    this.slider,
    this.usageValue,
    this.activeWatts,
    this.standbyWatts,
    this.kwhPerCycle,
    this.cycleHours,
    this.kwh,
    this.costUsd,
  });

  factory DeviceEnergyEstimate.fromJson(Map<String, dynamic> j) =>
      DeviceEnergyEstimate(
        deviceId: j['device_id'] as String,
        name: j['name'] as String? ?? '',
        category: j['category'] as String?,
        profileCategory: j['profile_category'] as String? ?? 'other',
        powerSource: EnergyPowerSource.fromWire(j['power_source'] as String?),
        ratingSource: j['rating_source'] as String?,
        usageKind: EnergyUsageKind.fromWire(j['usage_kind'] as String?),
        slider: j['slider'] is Map<String, dynamic>
            ? EnergySlider.fromJson(j['slider'] as Map<String, dynamic>)
            : null,
        usageValue: _numOrNull(j['usage_value']),
        usageValueIsDefault: j['usage_value_is_default'] == true,
        standbyApplies: j['standby_applies'] == true,
        activeWatts: _numOrNull(j['active_watts']),
        standbyWatts: _numOrNull(j['standby_watts']),
        kwhPerCycle: _numOrNull(j['kwh_per_cycle']),
        cycleHours: _numOrNull(j['cycle_hours']),
        kwh: j['kwh'] is Map<String, dynamic>
            ? EnergySplit.fromJson(j['kwh'] as Map<String, dynamic>)
            : null,
        costUsd: j['cost_usd'] is Map<String, dynamic>
            ? EnergySplit.fromJson(j['cost_usd'] as Map<String, dynamic>)
            : null,
      );

  final String deviceId;
  final String name;

  /// The device's raw `devices.category`.
  final String? category;

  /// Resolved key in `energy/category_energy_profiles.json`.
  final String profileCategory;
  final EnergyPowerSource powerSource;

  /// `energy_star` / `manual_extracted` for `rated`/`derived_annual` rows.
  final String? ratingSource;
  final EnergyUsageKind usageKind;

  /// Null when there is no user control (always-on, measured, no data).
  final EnergySlider? slider;
  final double? usageValue;
  final bool usageValueIsDefault;
  final bool standbyApplies;
  final double? activeWatts;
  final double? standbyWatts;
  final double? kwhPerCycle;
  final double? cycleHours;

  /// Null when `power_source` is `none`.
  final EnergySplit? kwh;

  /// Null when `power_source` is `none`.
  final EnergySplit? costUsd;

  bool get hasData => powerSource != EnergyPowerSource.none && costUsd != null;

  DeviceEnergyEstimate copyWith({
    double? usageValue,
    bool? usageValueIsDefault,
    EnergySplit? kwh,
    EnergySplit? costUsd,
  }) => DeviceEnergyEstimate(
    deviceId: deviceId,
    name: name,
    category: category,
    profileCategory: profileCategory,
    powerSource: powerSource,
    ratingSource: ratingSource,
    usageKind: usageKind,
    slider: slider,
    usageValue: usageValue ?? this.usageValue,
    usageValueIsDefault: usageValueIsDefault ?? this.usageValueIsDefault,
    standbyApplies: standbyApplies,
    activeWatts: activeWatts,
    standbyWatts: standbyWatts,
    kwhPerCycle: kwhPerCycle,
    cycleHours: cycleHours,
    kwh: kwh ?? this.kwh,
    costUsd: costUsd ?? this.costUsd,
  );

  Map<String, dynamic> toJson() => <String, dynamic>{
    'device_id': deviceId,
    'name': name,
    'category': category,
    'profile_category': profileCategory,
    'power_source': powerSource.wire,
    'rating_source': ratingSource,
    'usage_kind': usageKind.wire,
    'slider': slider?.toJson(),
    'usage_value': usageValue,
    'usage_value_is_default': usageValueIsDefault,
    'standby_applies': standbyApplies,
    'active_watts': activeWatts,
    'standby_watts': standbyWatts,
    'kwh_per_cycle': kwhPerCycle,
    'cycle_hours': cycleHours,
    'kwh': kwh?.toJson(),
    'cost_usd': costUsd?.toJson(),
  };
}

/// `EnergyEstimates`: the `GET /energy/estimates` response.
class EnergyEstimates {
  const EnergyEstimates({
    required this.period,
    required this.generatedAt,
    required this.profileTableVersion,
    required this.rate,
    required this.totalKwh,
    required this.totalCostUsd,
    required this.devices,
  });

  factory EnergyEstimates.fromJson(Map<String, dynamic> j) {
    final total = j['total'] as Map<String, dynamic>;
    return EnergyEstimates(
      period: j['period'] as String? ?? 'month',
      generatedAt: DateTime.tryParse(j['generated_at'] as String? ?? ''),
      profileTableVersion: j['profile_table_version'] as String? ?? '',
      rate: EnergyRate.fromJson(j['rate'] as Map<String, dynamic>),
      totalKwh: EnergySplit.fromJson(total['kwh'] as Map<String, dynamic>),
      totalCostUsd: EnergySplit.fromJson(
        total['cost_usd'] as Map<String, dynamic>,
      ),
      devices: (j['devices'] as List<dynamic>? ?? const <dynamic>[])
          .map((e) => DeviceEnergyEstimate.fromJson(e as Map<String, dynamic>))
          .toList(growable: false),
    );
  }

  /// `week` or `month`.
  final String period;
  final DateTime? generatedAt;
  final String profileTableVersion;
  final EnergyRate rate;
  final EnergySplit totalKwh;
  final EnergySplit totalCostUsd;

  /// Sorted by `cost_usd.total` descending; rows without data last.
  final List<DeviceEnergyEstimate> devices;

  DeviceEnergyEstimate? deviceById(String deviceId) {
    for (final d in devices) {
      if (d.deviceId == deviceId) return d;
    }
    return null;
  }

  EnergyEstimates copyWith({
    EnergySplit? totalKwh,
    EnergySplit? totalCostUsd,
    List<DeviceEnergyEstimate>? devices,
  }) => EnergyEstimates(
    period: period,
    generatedAt: generatedAt,
    profileTableVersion: profileTableVersion,
    rate: rate,
    totalKwh: totalKwh ?? this.totalKwh,
    totalCostUsd: totalCostUsd ?? this.totalCostUsd,
    devices: devices ?? this.devices,
  );

  Map<String, dynamic> toJson() => <String, dynamic>{
    'period': period,
    'generated_at': generatedAt?.toUtc().toIso8601String(),
    'profile_table_version': profileTableVersion,
    'rate': rate.toJson(),
    'total': <String, dynamic>{
      'kwh': totalKwh.toJson(),
      'cost_usd': totalCostUsd.toJson(),
    },
    'devices': devices.map((d) => d.toJson()).toList(),
  };
}

/// `DeviceUsageProfile`: the stored slider value (`PUT
/// /devices/{id}/usage-profile` response).
class DeviceUsageProfile {
  const DeviceUsageProfile({
    required this.deviceId,
    required this.usageKind,
    required this.value,
    this.updatedAt,
    this.updatedBy,
  });

  factory DeviceUsageProfile.fromJson(Map<String, dynamic> j) =>
      DeviceUsageProfile(
        deviceId: j['device_id'] as String,
        usageKind: EnergyUsageKind.fromWire(j['usage_kind'] as String?),
        value: (j['value'] as num).toDouble(),
        updatedAt: j['updated_at'] as String?,
        updatedBy: j['updated_by'] as String?,
      );

  final String deviceId;
  final EnergyUsageKind usageKind;
  final double value;
  final String? updatedAt;
  final String? updatedBy;
}

/// `HouseholdEnergyRate`: `GET/PUT /household/energy-rate`.
class HouseholdEnergyRate {
  const HouseholdEnergyRate({
    required this.effective,
    this.userRateUsdPerKwh,
    this.cloud,
    this.cloudFetchedAt,
    this.postalCode,
    this.country,
  });

  factory HouseholdEnergyRate.fromJson(Map<String, dynamic> j) =>
      HouseholdEnergyRate(
        effective: EnergyRate.fromJson(j['effective'] as Map<String, dynamic>),
        userRateUsdPerKwh: _numOrNull(j['user_rate_usd_per_kwh']),
        cloud: j['cloud'] is Map<String, dynamic>
            ? EnergyRate.fromJson(j['cloud'] as Map<String, dynamic>)
            : null,
        cloudFetchedAt: j['cloud_fetched_at'] == null
            ? null
            : DateTime.tryParse(j['cloud_fetched_at'] as String),
        postalCode: j['postal_code'] as String?,
        country: j['country'] as String?,
      );

  final EnergyRate effective;
  final double? userRateUsdPerKwh;
  final EnergyRate? cloud;
  final DateTime? cloudFetchedAt;
  final String? postalCode;
  final String? country;
}
