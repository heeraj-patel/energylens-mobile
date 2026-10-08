import 'demo_energy_projection.dart';
import 'demo_energy_tree.dart';

/// A complete trailing window of home-local calendar days ending on the
/// reference day. Amounts retain USD micros; unclassified cost stays unknown.
class DemoRollingCostWindow {
  const DemoRollingCostWindow._({
    required this.homeId,
    required this.timezone,
    required this.referenceLocalDate,
    required this.startLocalDate,
    required this.endExclusiveLocalDate,
    required this.dayCount,
    required this.source,
    required this.presentation,
  });

  final String homeId;
  final String timezone;
  final String referenceLocalDate;
  final String startLocalDate;
  final String endExclusiveLocalDate;
  final int dayCount;
  final DemoCost source;
  final DemoCost presentation;

  bool get hasUnknownSourceCost => source.unclassifiedMicros > 0;
  bool get hasUnknownPresentationCost => presentation.unclassifiedMicros > 0;

  static DemoRollingCostWindow fromTrees({
    required Iterable<DemoMonthTree> trees,
    required String homeId,
    required String referenceLocalDate,
    required int dayCount,
  }) {
    if (dayCount != 7 && dayCount != 30) {
      throw ArgumentError.value(dayCount, 'dayCount', 'Expected 7 or 30');
    }
    final reference = _parseLocalDate(referenceLocalDate);
    if (reference == null) {
      throw const FormatException('Invalid rolling reference day');
    }
    final endExclusive = reference.add(const Duration(days: 1));
    final start = endExclusive.subtract(Duration(days: dayCount));
    final startText = _localDate(start);
    final endText = _localDate(endExclusive);
    final months = <String, DemoMonthTree>{};
    String? timezone;
    for (final tree in trees) {
      if (tree.homeId.toLowerCase() != homeId.toLowerCase()) {
        throw const FormatException('Rolling window belongs to another home');
      }
      final treeReference = _parseLocalDate(tree.referenceLocalDate);
      if (treeReference == null) {
        throw const FormatException('Invalid rolling month reference');
      }
      final month = tree.referenceLocalDate.substring(0, 7);
      if (months.containsKey(month)) {
        throw const FormatException('Duplicate rolling calendar month');
      }
      if (month != referenceLocalDate.substring(0, 7) &&
          treeReference.day !=
              DateTime.utc(
                treeReference.year,
                treeReference.month + 1,
                0,
              ).day) {
        throw const FormatException('Previous rolling month is incomplete');
      }
      if (month == referenceLocalDate.substring(0, 7) &&
          tree.referenceLocalDate != referenceLocalDate) {
        throw const FormatException('Current rolling month changed');
      }
      DemoEnergyProjection.fromTree(
        tree: tree,
        homeId: homeId,
        referenceLocalDate: tree.referenceLocalDate,
      );
      final treeTimezone = tree.days.first.period.timezone;
      if (timezone != null && timezone != treeTimezone) {
        throw const FormatException('Rolling timezone changed');
      }
      timezone = treeTimezone;
      months[month] = tree;
    }

    var source = DemoCost.zero;
    var presentation = DemoCost.zero;
    DemoDayPeriod? priorPeriod;
    for (var index = 0; index < dayCount; index++) {
      final date = start.add(Duration(days: index));
      final dateText = _localDate(date);
      final tree = months[dateText.substring(0, 7)];
      if (tree == null) {
        throw const FormatException('Rolling window has a missing month');
      }
      final day = tree.day(dateText);
      if (priorPeriod != null &&
          !priorPeriod.endUtc.isAtSameMomentAs(day.period.startUtc)) {
        throw const FormatException('Rolling days are not contiguous');
      }
      priorPeriod = day.period;
      source = source + day.homeCost;
      presentation =
          presentation +
          day.devices.fold(
            DemoCost.zero,
            (sum, leaf) => sum + leaf.presentationCost,
          ) +
          day.unattributed.presentationCost;
    }
    if (timezone == null) {
      throw const FormatException('Rolling window has no calendar');
    }
    return DemoRollingCostWindow._(
      homeId: homeId,
      timezone: timezone,
      referenceLocalDate: referenceLocalDate,
      startLocalDate: startText,
      endExclusiveLocalDate: endText,
      dayCount: dayCount,
      source: source,
      presentation: presentation,
    );
  }
}

DateTime? _parseLocalDate(String value) {
  if (!RegExp(r'^\d{4}-\d{2}-\d{2}$').hasMatch(value)) return null;
  final parsed = DateTime.tryParse(value);
  if (parsed == null || _localDate(parsed) != value) return null;
  return DateTime.utc(parsed.year, parsed.month, parsed.day);
}

String _localDate(DateTime date) =>
    '${date.year.toString().padLeft(4, '0')}-'
    '${date.month.toString().padLeft(2, '0')}-'
    '${date.day.toString().padLeft(2, '0')}';
