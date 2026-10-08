import 'demo_energy_projection.dart';
import 'demo_energy_tree.dart';
import 'design_page_bridge.dart';

/// Internal provenance for one displayed cost claim. A measured total can
/// still include an illustrative useful/waste allocation or demo leaves.
enum DemoCostClaimStatus { illustrative, measured, mixed, noValue }

class DemoCostClaimProvenance {
  const DemoCostClaimProvenance({
    required this.status,
    required this.referenceLocalDate,
    required this.hasUnclassifiedSourceCost,
  });

  final DemoCostClaimStatus status;
  final String referenceLocalDate;
  final bool hasUnclassifiedSourceCost;
}

enum _CostComponent { useful, waste, total }

DemoCostClaimProvenance _provenance(
  Iterable<DemoBranch> leaves,
  _CostComponent component,
  String referenceLocalDate,
) {
  var measured = false;
  var illustrative = false;
  var unknownSource = false;
  var hasContributingLeaf = false;
  for (final leaf in leaves) {
    final shown = leaf.presentationCost;
    final shownMicros = switch (component) {
      _CostComponent.useful => shown.usefulMicros,
      _CostComponent.waste => shown.wasteMicros,
      _CostComponent.total => shown.totalMicros,
    };
    if (shownMicros == 0) continue;
    hasContributingLeaf = true;
    unknownSource |= leaf.cost.unclassifiedMicros > 0;
    measured |= leaf.origin == DemoValueOrigin.measured;
    illustrative |=
        leaf.origin == DemoValueOrigin.mock ||
        leaf.illustrativePresentationCost != null ||
        (component != _CostComponent.useful && leaf.wasteProvenance != null);
  }
  // A verified zero is still a value. Use the available leaves to describe a
  // zero claim instead of treating the displayed $0.00 as unavailable.
  if (!hasContributingLeaf) {
    for (final leaf in leaves) {
      measured |= leaf.origin == DemoValueOrigin.measured;
      illustrative |=
          leaf.origin == DemoValueOrigin.mock ||
          leaf.illustrativePresentationCost != null ||
          (component != _CostComponent.useful && leaf.wasteProvenance != null);
      unknownSource |= leaf.cost.unclassifiedMicros > 0;
    }
  }
  return DemoCostClaimProvenance(
    status: measured && illustrative
        ? DemoCostClaimStatus.mixed
        : measured
        ? DemoCostClaimStatus.measured
        : illustrative
        ? DemoCostClaimStatus.illustrative
        : DemoCostClaimStatus.noValue,
    referenceLocalDate: referenceLocalDate,
    hasUnclassifiedSourceCost: unknownSource,
  );
}

/// Builds numeric bindings from a nonvisual monthly demo tree.
///
/// `period` is `day` for Dashboard and Devices, and `month` for Efficiency.
/// `localDate` is an ISO local date for day views or `YYYY-MM` for Efficiency.
/// `referenceLocalDate` is required for every binding call; Efficiency sums
/// from the first day of its month through this date, inclusive.
/// Values are always recalculated from the tree so measured leaf replacements
/// flow through to the corresponding aggregates.
class DemoEnergyBindings {
  const DemoEnergyBindings(this.bindings, this.provenanceByBindingId);

  final List<DesignTextBinding> bindings;
  final Map<String, DemoCostClaimProvenance> provenanceByBindingId;

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
        final leaves = [
          ...projection.deviceDayLeaves,
          projection.referenceDay.unattributed,
        ];
        return DemoEnergyBindings(
          List.unmodifiable([
            DesignTextBinding('dashboard_text_006', _money(cost.usefulCents)),
            DesignTextBinding('dashboard_text_009', _money(cost.wasteCents)),
          ]),
          Map.unmodifiable({
            'dashboard_text_006': _provenance(
              leaves,
              _CostComponent.useful,
              referenceLocalDate,
            ),
            'dashboard_text_009': _provenance(
              leaves,
              _CostComponent.waste,
              referenceLocalDate,
            ),
          }),
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
          Map.unmodifiable({
            'devices_text_006': _provenance(
              projection.deviceDayLeaves,
              _CostComponent.waste,
              referenceLocalDate,
            ),
            'devices_text_009': _provenance(
              projection.deviceDayLeaves,
              _CostComponent.useful,
              referenceLocalDate,
            ),
          }),
        );
      case 'efficiency':
        if (period != 'month' ||
            !_isLocalMonth(localDate) ||
            !_isLocalDate(referenceLocalDate) ||
            !referenceLocalDate.startsWith('$localDate-') ||
            projection.localMonth != localDate) {
          throw const FormatException('Efficiency demo month changed');
        }
        final monthLeaves = [
          for (final day in tree.days)
            if (day.period.localDate.compareTo(referenceLocalDate) <= 0) ...[
              ...day.devices,
              day.unattributed,
            ],
        ];
        return DemoEnergyBindings(
          List.unmodifiable([
            DesignTextBinding(
              'efficiency_text_009',
              _money(
                _roundMicrosToCents(
                  projection.presentedMonthToDateCost.totalMicros,
                ),
              ),
            ),
          ]),
          Map.unmodifiable({
            'efficiency_text_009': _provenance(
              monthLeaves,
              _CostComponent.total,
              referenceLocalDate,
            ),
          }),
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

int _roundMicrosToCents(int micros) => (micros + 5000) ~/ 10000;

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
