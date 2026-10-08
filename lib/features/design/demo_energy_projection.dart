import 'demo_energy_tree.dart';

import 'package:timezone/data/latest.dart' as tz_data;
import 'package:timezone/timezone.dart' as tz;

final bool _timeZonesReady = _initializeTimeZones();

bool _initializeTimeZones() {
  tz_data.initializeTimeZones();
  return true;
}

/// Cost for an explicit, complete range of home-local days. A caller chooses
/// the start of a week; the tree does not infer a billing or calendar week.
class DemoPeriodCost {
  const DemoPeriodCost({required this.source, required this.presentation});

  final DemoCost source;
  final DemoCost presentation;
}

/// One internally consistent view of a home-local month through its reference
/// day. All amounts retain USD micros until the presentation layer formats
/// them; unknown real cost remains in the unclassified component.
class DemoEnergyProjection {
  DemoEnergyProjection._({
    required this.tree,
    required this.referenceDay,
    required this.monthToDateCost,
  });

  final DemoMonthTree tree;
  final DemoDayTree referenceDay;
  final DemoCost monthToDateCost;

  String get homeId => tree.homeId;
  String get referenceLocalDate => tree.referenceLocalDate;
  String get localMonth => referenceLocalDate.substring(0, 7);
  DemoCost get homeDayCost => referenceDay.homeCost;
  DemoCost get devicesDayCost => referenceDay.devicesCost;
  DemoCost get unattributedDayCost => referenceDay.unattributed.cost;
  List<DemoBranch> get deviceDayLeaves => referenceDay.devices;

  /// Customer presentation totals include approved illustrative mapped splits.
  /// Source totals above retain unclassified measured costs for provenance.
  DemoCost get presentedDevicesDayCost => referenceDay.devices.fold(
    DemoCost.zero,
    (sum, leaf) => sum + leaf.presentationCost,
  );
  DemoCost get presentedHomeDayCost =>
      presentedDevicesDayCost + referenceDay.unattributed.presentationCost;
  DemoCost get presentedMonthToDateCost {
    var sum = DemoCost.zero;
    for (final day in tree.days) {
      if (day.period.localDate.compareTo(referenceLocalDate) > 0) break;
      sum =
          sum +
          day.devices.fold(
            DemoCost.zero,
            (daily, leaf) => daily + leaf.presentationCost,
          ) +
          day.unattributed.presentationCost;
    }
    return sum;
  }

  bool get hasUnknownPresentedDayCost =>
      presentedHomeDayCost.unclassifiedMicros > 0;

  /// Source-side unknown cost remains visible to internal provenance checks,
  /// even when a mapped leaf has an approved illustrative display split.
  bool get hasUnclassifiedMonthToDateCost =>
      monthToDateCost.unclassifiedMicros > 0;

  DemoPeriodCost costForLocalDateRange({
    required String startLocalDate,
    required String endExclusiveLocalDate,
  }) {
    final start = DateTime.tryParse(startLocalDate);
    final end = DateTime.tryParse(endExclusiveLocalDate);
    final reference = DateTime.parse(referenceLocalDate);
    final startDate = start == null
        ? null
        : DateTime.utc(start.year, start.month, start.day);
    final endDate = end == null
        ? null
        : DateTime.utc(end.year, end.month, end.day);
    final monthStart = DateTime.utc(reference.year, reference.month);
    final afterReference = DateTime.utc(
      reference.year,
      reference.month,
      reference.day + 1,
    );
    if (start == null ||
        end == null ||
        startDate == null ||
        endDate == null ||
        _localDate(start) != startLocalDate ||
        _localDate(end) != endExclusiveLocalDate ||
        !startDate.isBefore(endDate) ||
        startDate.isBefore(monthStart) ||
        endDate.isAfter(afterReference)) {
      throw const FormatException('Range is outside the demo reference month');
    }
    var source = DemoCost.zero;
    var presentation = DemoCost.zero;
    for (final day in tree.days) {
      if (day.period.localDate.compareTo(startLocalDate) < 0) continue;
      if (day.period.localDate.compareTo(endExclusiveLocalDate) >= 0) break;
      source = source + day.homeCost;
      presentation =
          presentation +
          day.devices.fold(
            DemoCost.zero,
            (sum, leaf) => sum + leaf.presentationCost,
          ) +
          day.unattributed.presentationCost;
    }
    return DemoPeriodCost(source: source, presentation: presentation);
  }

  static DemoEnergyProjection fromTree({
    required DemoMonthTree tree,
    required String homeId,
    required String referenceLocalDate,
  }) {
    if (tree.homeId.toLowerCase() != homeId.toLowerCase() ||
        tree.referenceLocalDate != referenceLocalDate ||
        !RegExp(r'^\d{4}-\d{2}-\d{2}$').hasMatch(referenceLocalDate)) {
      throw const FormatException('Demo projection context changed');
    }
    final reference = DateTime.tryParse(referenceLocalDate);
    if (reference == null ||
        !_timeZonesReady ||
        _localDate(reference) != referenceLocalDate ||
        tree.days.length !=
            DateTime.utc(reference.year, reference.month + 1, 0).day) {
      throw const FormatException('Incomplete demo calendar month');
    }
    late final tz.Location location;
    try {
      location = tz.getLocation(tree.days.first.period.timezone);
    } catch (_) {
      throw const FormatException('Unknown demo calendar timezone');
    }
    DemoCost monthToDate = DemoCost.zero;
    for (var index = 0; index < tree.days.length; index++) {
      final day = tree.days[index];
      if (day.period.localDate !=
              _localDate(
                DateTime.utc(reference.year, reference.month, index + 1),
              ) ||
          !day.period.startUtc.isUtc ||
          !day.period.endUtc.isUtc ||
          !day.period.endUtc.isAfter(day.period.startUtc) ||
          !day.period.startUtc.isAtSameMomentAs(
            tz.TZDateTime(
              location,
              reference.year,
              reference.month,
              index + 1,
            ).toUtc(),
          ) ||
          !day.period.endUtc.isAtSameMomentAs(
            tz.TZDateTime(
              location,
              reference.year,
              reference.month,
              index + 2,
            ).toUtc(),
          ) ||
          (index > 0 &&
              !tree.days[index - 1].period.endUtc.isAtSameMomentAs(
                day.period.startUtc,
              ))) {
        throw const FormatException('Inconsistent demo calendar day');
      }
      if (index < reference.day) monthToDate = monthToDate + day.homeCost;
    }
    return DemoEnergyProjection._(
      tree: tree,
      referenceDay: tree.days[reference.day - 1],
      monthToDateCost: monthToDate,
    );
  }
}

String _localDate(DateTime date) =>
    '${date.year.toString().padLeft(4, '0')}-'
    '${date.month.toString().padLeft(2, '0')}-'
    '${date.day.toString().padLeft(2, '0')}';
