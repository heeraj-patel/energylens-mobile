/// A nonvisual production-POC fallback. The leaf rows are the source of
/// truth: every device-list and home amount is calculated from them.
/// These values are illustrative and are never evidence of measured usage.
enum DemoValueOrigin { mock, measured }

/// Verified evidence that a device was off or idle for a measured interval.
/// Callers must not infer a full-day duration from missing data.
enum WasteDurationIntervalKind { verifiedOff, verifiedIdle }

class WasteDurationEvidence {
  WasteDurationEvidence({
    required this.seconds,
    required this.evidenceId,
    required this.intervalKind,
  }) {
    if (seconds <= 0 || evidenceId.trim().isEmpty) {
      throw const FormatException('Invalid verified waste duration evidence');
    }
  }

  final int seconds;
  final String evidenceId;
  final WasteDurationIntervalKind intervalKind;
}

class DemoCost {
  const DemoCost({
    required int usefulCents,
    required int wasteCents,
    required int unclassifiedCents,
  }) : _usefulMicros = usefulCents * 10000,
       _wasteMicros = wasteCents * 10000,
       _unclassifiedMicros = unclassifiedCents * 10000,
       assert(usefulCents >= 0),
       assert(wasteCents >= 0),
       assert(unclassifiedCents >= 0);

  const DemoCost.fromMicros({
    required int usefulMicros,
    required int wasteMicros,
    required int unclassifiedMicros,
  }) : _usefulMicros = usefulMicros,
       _wasteMicros = wasteMicros,
       _unclassifiedMicros = unclassifiedMicros,
       assert(usefulMicros >= 0),
       assert(wasteMicros >= 0),
       assert(unclassifiedMicros >= 0);

  static const zero = DemoCost(
    usefulCents: 0,
    wasteCents: 0,
    unclassifiedCents: 0,
  );

  final int _usefulMicros;
  final int _wasteMicros;
  final int _unclassifiedMicros;
  int get usefulMicros => _usefulMicros;
  int get wasteMicros => _wasteMicros;
  int get unclassifiedMicros => _unclassifiedMicros;
  int get totalMicros => _usefulMicros + _wasteMicros + _unclassifiedMicros;
  static int _roundedCents(int micros) => (micros + 5000) ~/ 10000;
  int get usefulCents => _roundedCents(_usefulMicros);
  int get wasteCents => _roundedCents(_wasteMicros);
  int get unclassifiedCents => _roundedCents(_unclassifiedMicros);
  int get totalCents => _roundedCents(totalMicros);

  DemoCost operator +(DemoCost other) => DemoCost.fromMicros(
    usefulMicros: usefulMicros + other.usefulMicros,
    wasteMicros: wasteMicros + other.wasteMicros,
    unclassifiedMicros: unclassifiedMicros + other.unclassifiedMicros,
  );
}

class DemoDayPeriod {
  const DemoDayPeriod({
    required this.localDate,
    required this.timezone,
    required this.startUtc,
    required this.endUtc,
  });

  final String localDate;
  final String timezone;
  final DateTime startUtc;
  final DateTime endUtc;

  bool sameAs(DemoDayPeriod other) =>
      localDate == other.localDate &&
      timezone == other.timezone &&
      startUtc.isAtSameMomentAs(other.startUtc) &&
      endUtc.isAtSameMomentAs(other.endUtc);

  int get seconds => endUtc.difference(startUtc).inSeconds;
}

class DemoBranch {
  const DemoBranch({
    required this.deviceId,
    required this.period,
    required this.cost,
    required this.origin,
    required this.sourceId,
    this.name,
    this.energyWh,
    this.tariffId,
    this.classificationEvidenceId,
    this.mappedMockBranchId,
    this.mappingEvidenceId,
    this.wasteProvenance,
    this.wasteDurationEvidenceId,
    this.illustrativePresentationCost,
  });

  final String deviceId;
  final String? name;
  final DemoDayPeriod period;
  final DemoCost cost;
  final DemoValueOrigin origin;
  final String sourceId;
  final int? energyWh;
  final String? tariffId;
  final String? classificationEvidenceId;
  final String? mappedMockBranchId;
  final String? mappingEvidenceId;
  final String? wasteProvenance;
  final String? wasteDurationEvidenceId;

  /// A display-only split of an otherwise unclassified measured total.
  /// [cost] remains the source allocation and must be used for evidence.
  final DemoCost? illustrativePresentationCost;

  DemoCost get presentationCost => illustrativePresentationCost ?? cost;
}

class DemoDayTree {
  DemoDayTree({
    required this.homeId,
    required this.period,
    required List<DemoBranch> devices,
    required this.unattributed,
  }) : devices = List.unmodifiable(devices) {
    if (!_uuid.hasMatch(homeId) ||
        unattributed.deviceId != unattributedId ||
        !unattributed.period.sameAs(period) ||
        devices.any((row) => !row.period.sameAs(period)) ||
        devices.map((row) => row.deviceId).toSet().length != devices.length ||
        devices.any((row) => row.deviceId == unattributedId)) {
      throw const FormatException('Inconsistent demo day tree');
    }
  }

  static const unattributedId = 'demo-unattributed';
  final String homeId;
  final DemoDayPeriod period;
  final List<DemoBranch> devices;
  final DemoBranch unattributed;

  DemoCost get devicesCost =>
      devices.fold(DemoCost.zero, (sum, row) => sum + row.cost);
  DemoCost get homeCost => devicesCost + unattributed.cost;

  /// A verified identity mapping replaces its mock leaf. An unmapped real
  /// device becomes a distinct leaf and increases the derived home total.
  DemoDayTree mergeMeasured(
    RealDeviceDay reading, {
    String? verifiedMockBranchId,
    String? mappingEvidenceId,
  }) {
    if (reading.homeId.toLowerCase() != homeId.toLowerCase() ||
        !reading.period.sameAs(period)) {
      throw const FormatException(
        'Measured home or day does not match demo day',
      );
    }
    if (devices.any((row) => row.deviceId == reading.deviceId)) {
      throw const FormatException('Measured device is already in demo tree');
    }
    final rows = devices.toList();
    if (verifiedMockBranchId != null) {
      if (mappingEvidenceId == null || mappingEvidenceId.isEmpty) {
        throw const FormatException('Missing verified device mapping');
      }
      final index = rows.indexWhere(
        (row) =>
            row.deviceId == verifiedMockBranchId &&
            row.origin == DemoValueOrigin.mock,
      );
      if (index < 0) {
        throw const FormatException('Verified mock branch is unavailable');
      }
      final mockCost = rows[index].cost;
      final measured = reading.toBranch(
        name: rows[index].name,
        mappedMockBranchId: verifiedMockBranchId,
        mappingEvidenceId: mappingEvidenceId,
      );
      rows[index] = DemoBranch(
        deviceId: measured.deviceId,
        name: measured.name,
        period: measured.period,
        cost: measured.cost,
        origin: measured.origin,
        sourceId: measured.sourceId,
        energyWh: measured.energyWh,
        tariffId: measured.tariffId,
        classificationEvidenceId: measured.classificationEvidenceId,
        mappedMockBranchId: measured.mappedMockBranchId,
        mappingEvidenceId: measured.mappingEvidenceId,
        illustrativePresentationCost: _mockProportionForUnclassified(
          measured.cost,
          mockCost,
        ),
      );
      return DemoDayTree(
        homeId: homeId,
        period: period,
        devices: rows,
        unattributed: unattributed,
      );
    }
    if (mappingEvidenceId != null) {
      throw const FormatException('Mapping evidence has no target branch');
    }
    rows.add(reading.toBranch());
    return DemoDayTree(
      homeId: homeId,
      period: period,
      devices: rows,
      unattributed: unattributed,
    );
  }
}

DemoCost? _mockProportionForUnclassified(DemoCost measured, DemoCost mock) {
  if (measured.unclassifiedMicros == 0 ||
      measured.usefulMicros != 0 ||
      measured.wasteMicros != 0 ||
      mock.unclassifiedMicros != 0 ||
      mock.usefulMicros + mock.wasteMicros == 0) {
    return null;
  }
  final useful =
      (measured.totalMicros * mock.usefulMicros +
          (mock.usefulMicros + mock.wasteMicros) ~/ 2) ~/
      (mock.usefulMicros + mock.wasteMicros);
  return DemoCost.fromMicros(
    usefulMicros: useful,
    wasteMicros: measured.totalMicros - useful,
    unclassifiedMicros: 0,
  );
}

/// A real replacement must have one complete local-day interval, an explicit
/// electricity tariff and an explicit classification allocation. If a source
/// cannot classify energy, it supplies all Wh as unclassified.
class RealDeviceDay {
  RealDeviceDay({
    required this.homeId,
    required this.deviceId,
    required this.period,
    required this.coveredSeconds,
    required this.usefulWh,
    required this.wasteWh,
    required this.unclassifiedWh,
    required this.tariffRateUnitsPerKwh,
    required this.tariffId,
    required this.meterEvidenceId,
    this.classificationEvidenceId,
  }) {
    if (!_uuid.hasMatch(homeId) ||
        !_uuid.hasMatch(deviceId) ||
        meterEvidenceId.isEmpty ||
        tariffId.isEmpty ||
        tariffRateUnitsPerKwh <= 0 ||
        usefulWh < 0 ||
        wasteWh < 0 ||
        unclassifiedWh < 0 ||
        usefulWh + wasteWh + unclassifiedWh <= 0 ||
        coveredSeconds != period.seconds ||
        period.seconds <= 0 ||
        ((usefulWh > 0 || wasteWh > 0) &&
            (classificationEvidenceId == null ||
                classificationEvidenceId!.isEmpty))) {
      throw const FormatException('Incomplete measured device day');
    }
  }

  final String homeId;
  final String deviceId;
  final DemoDayPeriod period;
  final int coveredSeconds;
  final int usefulWh;
  final int wasteWh;
  final int unclassifiedWh;

  /// USD per kWh scaled by 10^8, matching the CloudTariff decimal precision.
  final int tariffRateUnitsPerKwh;
  final String tariffId;
  final String meterEvidenceId;
  final String? classificationEvidenceId;

  int get energyWh => usefulWh + wasteWh + unclassifiedWh;

  /// Wh × (10^-8 USD/kWh) converted to cents, rounded once per category.
  static int _cents(int wh, int rateUnits) =>
      (wh * rateUnits + 500000000) ~/ 1000000000;

  DemoBranch toBranch({
    String? name,
    String? mappedMockBranchId,
    String? mappingEvidenceId,
  }) => DemoBranch(
    deviceId: deviceId,
    name: name,
    period: period,
    cost: DemoCost(
      usefulCents: _cents(usefulWh, tariffRateUnitsPerKwh),
      wasteCents: _cents(wasteWh, tariffRateUnitsPerKwh),
      unclassifiedCents: _cents(unclassifiedWh, tariffRateUnitsPerKwh),
    ),
    origin: DemoValueOrigin.measured,
    sourceId: meterEvidenceId,
    energyWh: energyWh,
    tariffId: tariffId,
    classificationEvidenceId: classificationEvidenceId,
    mappedMockBranchId: mappedMockBranchId,
    mappingEvidenceId: mappingEvidenceId,
  );
}

final _uuid = RegExp(
  r'^[0-9a-fA-F]{8}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{12}$',
);

class DemoMonthTree {
  DemoMonthTree({
    required this.homeId,
    required this.referenceLocalDate,
    required List<DemoDayTree> days,
  }) : days = List.unmodifiable(days) {
    if (!_uuid.hasMatch(homeId) ||
        days.isEmpty ||
        !days.any((day) => day.period.localDate == referenceLocalDate) ||
        days.any((day) => day.homeId.toLowerCase() != homeId.toLowerCase()) ||
        days.map((day) => day.period.localDate).toSet().length != days.length ||
        days.any((day) => day.period.timezone != days.first.period.timezone)) {
      throw const FormatException('Inconsistent demo month tree');
    }
  }

  final String homeId;
  final String referenceLocalDate;
  final List<DemoDayTree> days;
  DemoCost get homeCost =>
      days.fold(DemoCost.zero, (sum, day) => sum + day.homeCost);

  DemoDayTree day(String localDate) =>
      days.singleWhere((value) => value.period.localDate == localDate);

  DemoMonthTree mergeMeasured(
    RealDeviceDay reading, {
    String? verifiedMockBranchId,
    String? mappingEvidenceId,
  }) {
    if (reading.homeId.toLowerCase() != homeId.toLowerCase() ||
        !days.any((day) => day.period.sameAs(reading.period))) {
      throw const FormatException('Measured home or day is outside demo month');
    }
    return DemoMonthTree(
      homeId: homeId,
      referenceLocalDate: referenceLocalDate,
      days: days
          .map(
            (day) => day.period.sameAs(reading.period)
                ? day.mergeMeasured(
                    reading,
                    verifiedMockBranchId: verifiedMockBranchId,
                    mappingEvidenceId: mappingEvidenceId,
                  )
                : day,
          )
          .toList(),
    );
  }
}
