import 'package:timezone/data/latest.dart' as tz_data;
import 'package:timezone/timezone.dart' as tz;

/// A nonvisual production-POC fallback. The leaf rows are the source of
/// truth: every device-list and home amount is calculated from them.
/// These values are illustrative and are never evidence of measured usage.
enum DemoValueOrigin { mock, measured }

enum KbWasteResult {
  wasteEvidenceUnavailableAfterKb,
  pending,
  reviewedEvidence,
}

enum DummyWasteDraw { low, high }

/// Provisional low-draw device and high-draw appliance groupings from the
/// versioned category profiles. Unlisted categories stay unresolved.
DummyWasteDraw? dummyWasteDrawForProfile(String profileCategory) {
  const low = {
    'media_player',
    'media_server',
    'speaker',
    'router',
    'access_point',
    'bridge',
    'camera',
    'smart_plug',
    'printer',
    'thermostat',
    'light',
    'fan',
    'vacuum',
    'garage_door',
  };
  const high = {
    'tv',
    'washer',
    'dryer',
    'dishwasher',
    'refrigerator',
    'freezer',
    'hvac',
    'water_heater',
    'dehumidifier',
    'microwave',
    'oven',
    'projector',
  };
  if (low.contains(profileCategory)) return DummyWasteDraw.low;
  if (high.contains(profileCategory)) return DummyWasteDraw.high;
  return null;
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
  int get totalCents => usefulCents + wasteCents + unclassifiedCents;

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
    this.kbWasteResultId,
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
  final String? kbWasteResultId;
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

  /// Applies an internal illustrative waste allocation only after a completed
  /// KB decision establishes that no waste-specific evidence is available.
  /// An existing priced real leaf keeps its measured total unchanged.
  DemoDayTree applyDummyWasteAfterKb({
    required String deviceId,
    required String profileCategory,
    required int wasteSeconds,
    required KbWasteResult kbResult,
    required String kbResultId,
  }) {
    if (kbResult != KbWasteResult.wasteEvidenceUnavailableAfterKb ||
        kbResultId.isEmpty ||
        !_uuid.hasMatch(deviceId) ||
        wasteSeconds < 0 ||
        wasteSeconds > period.seconds) {
      throw const FormatException('No final KB waste fallback decision');
    }
    final draw = dummyWasteDrawForProfile(profileCategory);
    if (draw == null) {
      throw const FormatException('No dummy waste draw class for profile');
    }
    // USD micros/hour: $0.0001 for low draw, $0.01 for high draw.
    // A day or month is summed in micros before any cent display rounding.
    final rateMicrosPerHour = draw == DummyWasteDraw.low ? 100 : 10000;
    final proposedMicros = (rateMicrosPerHour * wasteSeconds + 1800) ~/ 3600;
    final rows = devices.toList();
    final index = rows.indexWhere((row) => row.deviceId == deviceId);
    if (index >= 0) {
      final row = rows[index];
      if (row.origin != DemoValueOrigin.measured ||
          row.wasteProvenance != null ||
          row.cost.wasteMicros != 0) {
        throw const FormatException('Real waste allocation is unavailable');
      }
      final allocated = proposedMicros < row.cost.unclassifiedMicros
          ? proposedMicros
          : row.cost.unclassifiedMicros;
      rows[index] = DemoBranch(
        deviceId: row.deviceId,
        name: row.name,
        period: row.period,
        cost: DemoCost.fromMicros(
          usefulMicros: row.cost.usefulMicros,
          wasteMicros: allocated,
          unclassifiedMicros: row.cost.unclassifiedMicros - allocated,
        ),
        origin: row.origin,
        sourceId: row.sourceId,
        energyWh: row.energyWh,
        tariffId: row.tariffId,
        classificationEvidenceId: row.classificationEvidenceId,
        mappedMockBranchId: row.mappedMockBranchId,
        mappingEvidenceId: row.mappingEvidenceId,
        wasteProvenance: 'dummy_after_kb_miss',
        kbWasteResultId: kbResultId,
      );
    } else {
      rows.add(
        DemoBranch(
          deviceId: deviceId,
          period: period,
          cost: DemoCost.fromMicros(
            usefulMicros: 0,
            wasteMicros: proposedMicros,
            unclassifiedMicros: 0,
          ),
          origin: DemoValueOrigin.mock,
          sourceId: kbResultId,
          wasteProvenance: 'dummy_after_kb_miss',
          kbWasteResultId: kbResultId,
        ),
      );
    }
    return DemoDayTree(
      homeId: homeId,
      period: period,
      devices: rows,
      unattributed: unattributed,
    );
  }

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
      rows[index] = reading.toBranch(
        name: rows[index].name,
        mappedMockBranchId: verifiedMockBranchId,
        mappingEvidenceId: mappingEvidenceId,
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

  DemoMonthTree applyDummyWasteAfterKb({
    required String localDate,
    required String deviceId,
    required String profileCategory,
    required int wasteSeconds,
    required KbWasteResult kbResult,
    required String kbResultId,
  }) {
    if (!days.any((day) => day.period.localDate == localDate)) {
      throw const FormatException('Waste day is outside demo month');
    }
    return DemoMonthTree(
      homeId: homeId,
      referenceLocalDate: referenceLocalDate,
      days: days
          .map(
            (day) => day.period.localDate == localDate
                ? day.applyDummyWasteAfterKb(
                    deviceId: deviceId,
                    profileCategory: profileCategory,
                    wasteSeconds: wasteSeconds,
                    kbResult: kbResult,
                    kbResultId: kbResultId,
                  )
                : day,
          )
          .toList(),
    );
  }

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

const _fixtureId = 'mobile_demo_september_2026_v1';
final bool _timeZonesReady = _initializeTimeZones();

bool _initializeTimeZones() {
  tz_data.initializeTimeZones();
  return true;
}

/// September 2026 is a fixed illustrative reference period, not the current
/// calendar month. Names/amounts are internal data until UI copy is approved.
DemoMonthTree buildSeptember2026DemoTree({required String homeId}) =>
    buildDemoMonthTree(
      homeId: homeId,
      year: 2026,
      month: 9,
      timezone: 'America/Chicago',
      referenceDay: 30,
    );

/// Builds one complete home-local calendar month. The reference day uses the
/// ten existing design-card values; other days have a smaller daily pattern.
/// Month cost is always the sum of its actual calendar-day leaves.
DemoMonthTree buildDemoMonthTree({
  required String homeId,
  required int year,
  required int month,
  required String timezone,
  required int referenceDay,
}) {
  if (!_uuid.hasMatch(homeId)) {
    throw ArgumentError.value(
      homeId,
      'homeId',
      'Expected a verified home UUID',
    );
  }
  if (!_timeZonesReady ||
      year < 2000 ||
      year > 2100 ||
      month < 1 ||
      month > 12 ||
      referenceDay < 1 ||
      referenceDay > DateTime.utc(year, month + 1, 0).day) {
    throw const FormatException('Invalid demo calendar month');
  }
  late final tz.Location location;
  try {
    location = tz.getLocation(timezone);
  } catch (_) {
    throw const FormatException('Unknown demo timezone');
  }
  final dayCount = DateTime.utc(year, month + 1, 0).day;
  final adjustmentDay = referenceDay == 1 ? 2 : referenceDay - 1;
  final sourceId =
      year == 2026 &&
          month == 9 &&
          referenceDay == 30 &&
          timezone == 'America/Chicago'
      ? _fixtureId
      : 'mobile_demo_calendar_v1:$year-${month.toString().padLeft(2, '0')}';
  const names = <String?>[
    'Study Desktop & Rig',
    'Living Room 65" TV',
    'Phone & Tablet Chargers',
    'Kitchen Refrigerator',
    'Hallway Central AC',
    'Living Room Soundbar',
    'Home Office Monitors',
    'Mesh Wi-Fi Gateway & Router',
    'Subwoofer & Amp Rack',
    'Central Heat Pump',
    null,
    null,
    null,
    null,
    null,
    null,
    null,
    null,
  ];
  const referenceUseful = <int>[68, 20, 0, 84, 245, 15, 22, 18, 5, 190];
  const referenceWaste = <int>[35, 22, 9, 0, 4, 18, 14, 0, 12, 2];
  final days = <DemoDayTree>[];
  for (var day = 1; day <= dayCount; day++) {
    final date =
        '$year-${month.toString().padLeft(2, '0')}-${day.toString().padLeft(2, '0')}';
    final period = DemoDayPeriod(
      localDate: date,
      timezone: timezone,
      startUtc: tz.TZDateTime(location, year, month, day).toUtc(),
      endUtc: tz.TZDateTime(location, year, month, day + 1).toUtc(),
    );
    final rows = <DemoBranch>[];
    for (var i = 0; i < names.length; i++) {
      final useful = day == referenceDay
          ? (i < 10 ? referenceUseful[i] : 2)
          : switch (i) {
              3 => 105,
              4 => 155,
              0 => 65,
              _ => 5,
            };
      final waste = day == referenceDay
          ? (i < 10 ? referenceWaste[i] : 10)
          : switch (i) {
              3 => 4,
              4 => 4,
              _ => 2,
            };
      rows.add(
        DemoBranch(
          deviceId: 'demo-device-${(i + 1).toString().padLeft(2, '0')}',
          name: names[i],
          period: period,
          cost: DemoCost(
            usefulCents: useful,
            wasteCents: waste,
            unclassifiedCents: 0,
          ),
          origin: DemoValueOrigin.mock,
          sourceId: sourceId,
        ),
      );
    }
    days.add(
      DemoDayTree(
        homeId: homeId,
        period: period,
        devices: rows,
        unattributed: DemoBranch(
          deviceId: DemoDayTree.unattributedId,
          period: period,
          cost: DemoCost(
            usefulCents: day == referenceDay ? 13 : 0,
            wasteCents: day == referenceDay
                ? 92
                : (day == adjustmentDay ? 38 : 16),
            unclassifiedCents: 0,
          ),
          origin: DemoValueOrigin.mock,
          sourceId: sourceId,
        ),
      ),
    );
  }
  return DemoMonthTree(
    homeId: homeId,
    referenceLocalDate:
        '$year-${month.toString().padLeft(2, '0')}-${referenceDay.toString().padLeft(2, '0')}',
    days: days,
  );
}
