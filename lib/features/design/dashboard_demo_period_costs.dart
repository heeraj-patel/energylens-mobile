import 'package:timezone/data/latest.dart' as tz_data;
import 'package:timezone/timezone.dart' as tz;

/// The approved, illustrative device-cost schedule. Values are cents per local
/// calendar day; the chart never interprets them as measured usage or idle duration.
class DashboardDemoPeriodCosts {
  const DashboardDemoPeriodCosts._();

  static final referenceDate = DateTime.utc(2026, 9, 30);
  static final adjustmentDate = DateTime.utc(2026, 9, 29);
  // The fixture is anchored to September 30 in Chicago, regardless of the
  // device clock. Its final day is shown as a complete illustrative day.
  static final referenceAsOfUtc = DateTime.utc(2026, 10, 1, 4, 59, 59);

  static const _referenceUseful = <int>[
    68,
    20,
    0,
    84,
    245,
    15,
    22,
    18,
    5,
    190,
    2,
    2,
    2,
    2,
    2,
    2,
    2,
    2,
  ];
  static const _referenceWaste = <int>[
    35,
    22,
    9,
    0,
    4,
    18,
    14,
    0,
    12,
    2,
    10,
    10,
    10,
    10,
    10,
    10,
    10,
    10,
  ];
  static const _defaultUseful = <int>[
    65,
    5,
    5,
    105,
    155,
    5,
    5,
    5,
    5,
    5,
    5,
    5,
    5,
    5,
    5,
    5,
    5,
    5,
  ];
  static const _defaultWaste = <int>[
    2,
    2,
    2,
    4,
    4,
    2,
    2,
    2,
    2,
    2,
    2,
    2,
    2,
    2,
    2,
    2,
    2,
    2,
  ];

  /// Five occurrences through [asOfUtc] in the approved fixture's Chicago
  /// timezone. The final week/month includes only elapsed local days.
  static List<DashboardDemoCostBucket> lastFive(
    String granularity, {
    DateTime? asOfUtc,
  }) {
    if (!const {'day', 'week', 'month'}.contains(granularity)) {
      throw ArgumentError.value(granularity, 'granularity');
    }
    final effectiveAsOfUtc = asOfUtc ?? referenceAsOfUtc;
    if (!effectiveAsOfUtc.isUtc) {
      throw ArgumentError.value(asOfUtc, 'asOfUtc');
    }
    tz_data.initializeTimeZones();
    final local = tz.TZDateTime.from(
      effectiveAsOfUtc,
      tz.getLocation('America/Chicago'),
    );
    final asOfDate = DateTime.utc(local.year, local.month, local.day);
    final currentStart = switch (granularity) {
      'day' => asOfDate,
      'week' => _day(asOfDate, -(asOfDate.weekday - 1)),
      _ => DateTime.utc(asOfDate.year, asOfDate.month, 1),
    };
    return List.unmodifiable([
      for (var index = 4; index >= 0; index--)
        _bucket(
          granularity == 'day'
              ? _day(currentStart, -index)
              : granularity == 'week'
              ? _day(currentStart, -7 * index)
              : DateTime.utc(currentStart.year, currentStart.month - index, 1),
          granularity,
          asOfDate,
        ),
    ]);
  }

  static DashboardDemoCostBucket _bucket(
    DateTime start,
    String granularity,
    DateTime asOfDate,
  ) {
    final end = switch (granularity) {
      'day' => _day(start, 1),
      'week' => _day(start, 7),
      _ => DateTime.utc(start.year, start.month + 1, 1),
    };
    var useful = 0;
    var waste = 0;
    for (
      var day = start;
      day.isBefore(end) && !day.isAfter(asOfDate);
      day = _day(day, 1)
    ) {
      final isReference = day.isAtSameMomentAs(referenceDate);
      final deviceUseful = isReference ? _referenceUseful : _defaultUseful;
      final deviceWaste = isReference ? _referenceWaste : _defaultWaste;
      for (var i = 0; i < 18; i++) {
        useful += deviceUseful[i];
        waste += deviceWaste[i];
      }
      if (isReference) {
        useful += 13;
        waste += 92;
      } else if (day.isAtSameMomentAs(adjustmentDate)) {
        waste += 38;
      } else {
        waste += 16;
      }
    }
    return DashboardDemoCostBucket(
      startLocalDate: start,
      usefulCents: useful,
      wasteCents: waste,
    );
  }

  static DateTime _day(DateTime date, int offset) =>
      DateTime.utc(date.year, date.month, date.day + offset);
}

class DashboardDemoCostBucket {
  const DashboardDemoCostBucket({
    required this.startLocalDate,
    required this.usefulCents,
    required this.wasteCents,
  });

  final DateTime startLocalDate;
  final int usefulCents;
  final int wasteCents;
}
