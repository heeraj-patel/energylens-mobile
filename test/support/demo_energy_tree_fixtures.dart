import 'package:energylens_mobile/features/design/demo_energy_tree.dart';
import 'package:timezone/data/latest.dart' as tz_data;
import 'package:timezone/timezone.dart' as tz;

const _fixtureId = 'mobile_demo_september_2026_v1';
final bool _timeZonesReady = _initializeTimeZones();

bool _initializeTimeZones() {
  tz_data.initializeTimeZones();
  return true;
}

/// Test-only copy of the fixed illustrative reference tree.
DemoMonthTree buildSeptember2026DemoTree({required String homeId}) =>
    buildDemoMonthTree(
      homeId: homeId,
      year: 2026,
      month: 9,
      timezone: 'America/Chicago',
      referenceDay: 30,
    );

/// Builds synthetic leaves for domain and projection tests only.
DemoMonthTree buildDemoMonthTree({
  required String homeId,
  required int year,
  required int month,
  required String timezone,
  required int referenceDay,
}) {
  if (!RegExp(
    r'^[0-9a-fA-F]{8}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{12}$',
  ).hasMatch(homeId)) {
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
