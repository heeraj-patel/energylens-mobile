import '../../core/cloud_api/cloud_household_energy.dart';
import 'dashboard_domain_repository.dart';
import 'design_context_coordinator.dart';
import 'design_page_bridge.dart';
import 'devices_domain_repository.dart';

/// Dormant native preparation only. A missing value stays unknown; no packaged
/// sample text is a fallback. This result is never sent to the DesignShell.
class DesignNumericBindings {
  const DesignNumericBindings(this.bindings, this.unknownBindingIds);

  final List<DesignTextBinding> bindings;
  final Set<String> unknownBindingIds;

  String encode() => encodeDesignTextBindings(bindings);
}

const _dashboardDailyIds = <String>{'dashboard_text_006', 'dashboard_text_009'};

// The Devices API currently has no tariff or waste policy. Its measured Wh
// buckets cannot fill these daily cost slots or any whole-device total.
const _devicesCostIds = <String>{
  'devices_text_006',
  'devices_text_009',
  'devices_text_026',
  'devices_text_028',
  'devices_text_033',
  'devices_text_035',
  'devices_text_040',
  'devices_text_042',
  'devices_text_047',
  'devices_text_049',
  'devices_text_054',
  'devices_text_056',
  'devices_text_061',
  'devices_text_063',
  'devices_text_068',
  'devices_text_070',
  'devices_text_075',
  'devices_text_077',
  'devices_text_082',
  'devices_text_084',
  'devices_text_089',
  'devices_text_091',
};

/// Maps only existing numeric cost slots that have matching source semantics.
/// The packaged weekly card says "This Week" and cannot be populated without
/// a verified current-week window; energy has no matching numeric text slot.
DesignNumericBindings prepareDesignNumericBindings(DesignContextRead read) {
  final value = read.value;
  if (read.page == 'devices' && value is DevicesDomainSnapshot) {
    if (value.homeId.toLowerCase() != read.homeId.toLowerCase() ||
        (value.isCurrent?.call() ?? false) == false ||
        value.isSample != (read.mode == DesignContextMode.sample)) {
      throw const FormatException('Devices binding context changed');
    }
    return DesignNumericBindings(const [], _devicesCostIds);
  }
  if (read.page != 'dashboard' || value is! DashboardDomainSnapshot) {
    throw ArgumentError.value(
      read.page,
      'page',
      'Unsupported numeric bindings',
    );
  }
  if (!value.matchesHomeAndSnapshot(read.homeId) ||
      (value.dataMode == 'sample') != (read.mode == DesignContextMode.sample)) {
    throw const FormatException('Dashboard binding context changed');
  }

  final dashboard = value.dashboard;
  final duration = dashboard.period.endExclusive.difference(
    dashboard.period.start,
  );
  if (dashboard.trendPeriod != 'day') {
    return DesignNumericBindings(const [], _dashboardDailyIds);
  }
  if (duration != const Duration(days: 1)) {
    throw const FormatException('Dashboard daily period changed');
  }

  final bindings = <DesignTextBinding>[];
  final unknown = <String>{};
  void add(String id, CloudEnergyMoney? money) {
    if (money == null || dashboard.totals.availability == 'unavailable') {
      unknown.add(id);
      return;
    }
    if (money.currency != 'USD' ||
        !RegExp(r'^(0|[1-9][0-9]*)(\.[0-9]+)?$').hasMatch(money.amount)) {
      throw const FormatException('Unsafe dashboard money value');
    }
    bindings.add(DesignTextBinding(id, '\$${money.amount}'));
  }

  add('dashboard_text_006', dashboard.totals.usefulCost);
  add('dashboard_text_009', dashboard.totals.wasteCost);
  return DesignNumericBindings(
    List.unmodifiable(bindings),
    Set.unmodifiable(unknown),
  );
}
