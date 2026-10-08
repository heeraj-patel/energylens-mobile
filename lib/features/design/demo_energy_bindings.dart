import 'demo_energy_projection.dart';
import 'demo_energy_tree.dart';
import 'design_page_bridge.dart';

/// Builds numeric bindings from a nonvisual monthly demo tree.
///
/// `period` is `day` for Dashboard and Devices, and `month` for Efficiency.
/// `localDate` is an ISO local date for day views or `YYYY-MM` for Efficiency.
/// `referenceLocalDate` is required for every binding call; Efficiency sums
/// from the first day of its month through this date, inclusive.
/// Values are always recalculated from the tree so measured leaf replacements
/// flow through to the corresponding aggregates.
class DemoEnergyBindings {
  const DemoEnergyBindings(this.bindings);

  final List<DesignTextBinding> bindings;

  static DemoEnergyBindings forPage({
    required DemoMonthTree tree,
    required String homeId,
    required String page,
    required String period,
    required String localDate,
    required String referenceLocalDate,
  }) {
    final projection = DemoEnergyProjection.fromTree(
      tree: tree,
      homeId: homeId,
      referenceLocalDate: referenceLocalDate,
    );

    switch (page) {
      case 'dashboard':
        if (period != 'day' ||
            !_isLocalDate(localDate) ||
            referenceLocalDate != localDate) {
          throw const FormatException('Dashboard demo day changed');
        }
        final cost = projection.presentedHomeDayCost;
        if (cost.unclassifiedMicros > 0) {
          throw const FormatException('Unclassified home day presentation');
        }
        return DemoEnergyBindings(
          List.unmodifiable([
            DesignTextBinding('dashboard_text_006', _money(cost.usefulCents)),
            DesignTextBinding('dashboard_text_009', _money(cost.wasteCents)),
          ]),
        );
      case 'devices':
        if (period != 'day' ||
            !_isLocalDate(localDate) ||
            referenceLocalDate != localDate) {
          throw const FormatException('Devices demo day changed');
        }
        final cost = projection.presentedDevicesDayCost;
        if (cost.unclassifiedMicros > 0) {
          throw const FormatException('Unclassified devices day presentation');
        }
        return DemoEnergyBindings(
          List.unmodifiable([
            DesignTextBinding('devices_text_006', _money(cost.wasteCents)),
            DesignTextBinding('devices_text_009', _money(cost.usefulCents)),
          ]),
        );
      case 'efficiency':
        if (period != 'month' ||
            !_isLocalMonth(localDate) ||
            !_isLocalDate(referenceLocalDate) ||
            !referenceLocalDate.startsWith('$localDate-') ||
            projection.localMonth != localDate) {
          throw const FormatException('Efficiency demo month changed');
        }
        return DemoEnergyBindings(
          List.unmodifiable([
            DesignTextBinding(
              'efficiency_text_009',
              _money(projection.presentedMonthToDateCost.totalCents),
            ),
          ]),
        );
      default:
        throw ArgumentError.value(
          page,
          'page',
          'Unsupported demo binding page',
        );
    }
  }
}

String _money(int cents) =>
    '\$${(cents ~/ 100)}.${(cents % 100).toString().padLeft(2, '0')}';

bool _isLocalDate(String value) {
  if (!RegExp(r'^\d{4}-\d{2}-\d{2}$').hasMatch(value)) return false;
  final parsed = DateTime.tryParse(value);
  return parsed != null &&
      '${parsed.year.toString().padLeft(4, '0')}-${parsed.month.toString().padLeft(2, '0')}-${parsed.day.toString().padLeft(2, '0')}' ==
          value;
}

bool _isLocalMonth(String value) {
  if (!RegExp(r'^\d{4}-\d{2}$').hasMatch(value)) return false;
  final month = int.tryParse(value.substring(5));
  return month != null && month >= 1 && month <= 12;
}
