class CloudEnergyValues {
  const CloudEnergyValues({
    this.annualKwh,
    this.kwhPerDay,
    this.activeWatts,
    this.standbyWatts,
    this.kwhPerCycle,
    this.wasteKwhPerDay,
  });

  final double? annualKwh;
  final double? kwhPerDay;
  final double? activeWatts;
  final double? standbyWatts;
  final double? kwhPerCycle;
  final double? wasteKwhPerDay;

  factory CloudEnergyValues.fromJson(Map<String, dynamic> json) {
    double? number(String key) => (json[key] as num?)?.toDouble();
    return CloudEnergyValues(
      annualKwh: number('annual_kwh'),
      kwhPerDay: number('kwh_per_day'),
      activeWatts: number('active_watts'),
      standbyWatts: number('standby_watts'),
      kwhPerCycle: number('kwh_per_cycle'),
      wasteKwhPerDay: number('waste_kwh_per_day'),
    );
  }
}

class CloudEnergyResolution {
  const CloudEnergyResolution({
    required this.status,
    required this.deviceKind,
    required this.categoryKey,
    this.values,
  });

  final String status;
  final String deviceKind;
  final String categoryKey;
  final CloudEnergyValues? values;

  factory CloudEnergyResolution.fromJson(Map<String, dynamic> json) {
    final category = json['category'];
    final values = json['values'];
    if (json['status'] is! String ||
        json['device_kind'] is! String ||
        category is! Map<String, dynamic> ||
        category['key'] is! String ||
        (values != null && values is! Map<String, dynamic>)) {
      throw const FormatException('Invalid energy resolution');
    }
    return CloudEnergyResolution(
      status: json['status'] as String,
      deviceKind: json['device_kind'] as String,
      categoryKey: category['key'] as String,
      values: values == null ? null : CloudEnergyValues.fromJson(values),
    );
  }
}
