import 'demo_energy_tree.dart';

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

  /// Any unclassified priced real leaf keeps the five approved aggregate
  /// slots on their packaged demo fallback until its display is approved.
  bool get hasUnclassifiedMonthToDateCost =>
      monthToDateCost.unclassifiedMicros > 0;

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
        _localDate(reference) != referenceLocalDate ||
        tree.days.length !=
            DateTime.utc(reference.year, reference.month + 1, 0).day) {
      throw const FormatException('Incomplete demo calendar month');
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
