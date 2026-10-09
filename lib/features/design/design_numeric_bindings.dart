import 'package:timezone/data/latest.dart' as tz_data;
import 'package:timezone/timezone.dart' as tz;

import '../../core/cloud_api/cloud_household_energy.dart';
import 'dashboard_domain_repository.dart';
import 'dashboard_chart_projection.dart';
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

final bool _timeZonesReady = _initializeTimeZones();

bool _initializeTimeZones() {
  tz_data.initializeTimeZones();
  return true;
}

bool _isOneHomeLocalDay(CloudHouseholdDashboard dashboard) {
  if (!_timeZonesReady) return false;
  try {
    final location = tz.getLocation(dashboard.timezone);
    final start = tz.TZDateTime.from(dashboard.period.start, location);
    final end = tz.TZDateTime.from(dashboard.period.endExclusive, location);
    final startIsMidnight =
        start.hour == 0 &&
        start.minute == 0 &&
        start.second == 0 &&
        start.millisecond == 0 &&
        start.microsecond == 0;
    final endIsMidnight =
        end.hour == 0 &&
        end.minute == 0 &&
        end.second == 0 &&
        end.millisecond == 0 &&
        end.microsecond == 0;
    final nextDate = DateTime.utc(start.year, start.month, start.day + 1);
    return startIsMidnight &&
        endIsMidnight &&
        end.year == nextDate.year &&
        end.month == nextDate.month &&
        end.day == nextDate.day;
  } catch (_) {
    return false;
  }
}

bool _isMatchingWeek(
  CloudHouseholdEnergyTrends week,
  CloudHouseholdDashboard daily,
) {
  if (week.granularity != 'day' ||
      week.homeId.toLowerCase() != daily.homeId.toLowerCase() ||
      week.dataMode != daily.dataMode ||
      week.fixtureRevision != daily.fixtureRevision ||
      week.timezone != daily.timezone ||
      (week.scope != 'attributed_devices' &&
          !(week.dataMode == 'sample' &&
              week.scope == 'whole_home_including_unattributed_load')) ||
      week.generatedAt.difference(daily.generatedAt).abs() >
          const Duration(minutes: 5)) {
    return false;
  }
  try {
    final location = tz.getLocation(week.timezone);
    final start = tz.TZDateTime.from(week.period.start, location);
    final end = tz.TZDateTime.from(week.period.endExclusive, location);
    final nextMonday = DateTime.utc(start.year, start.month, start.day + 7);
    return start.weekday == DateTime.monday &&
        start.hour == 0 &&
        start.minute == 0 &&
        end.year == nextMonday.year &&
        end.month == nextMonday.month &&
        end.day == nextMonday.day &&
        end.hour == 0 &&
        end.minute == 0 &&
        !daily.generatedAt.isBefore(week.period.start) &&
        daily.generatedAt.isBefore(week.period.endExclusive);
  } catch (_) {
    return false;
  }
}

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
    final costs = value.sampleDayCosts;
    if (!value.hasSeededRows || costs == null) {
      return DesignNumericBindings(const [], _devicesCostIds);
    }
    final bindings = _sampleDevicesBindings(value, costs);
    return DesignNumericBindings(
      bindings ?? const [],
      bindings == null ? _devicesCostIds : const {},
    );
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
  if (dashboard.trendPeriod != 'day') {
    return DesignNumericBindings(const [], _dashboardDailyIds);
  }
  if (!_isOneHomeLocalDay(dashboard)) {
    throw const FormatException('Dashboard daily period changed');
  }

  final bindings = <DesignTextBinding>[];
  final unknown = <String>{};
  const supportedHouseholdEvidence = <String>{'measured', 'estimated', 'mixed'};
  final supportedEvidence = read.mode == DesignContextMode.sample
      ? dashboard.evidenceBasis == 'synthetic' &&
            dashboard.totals.evidenceBasis == 'synthetic'
      : supportedHouseholdEvidence.contains(dashboard.evidenceBasis) &&
            supportedHouseholdEvidence.contains(dashboard.totals.evidenceBasis);
  final week = value.weekToDateTrends;
  CloudEnergyAllocation? daily = read.mode == DesignContextMode.sample
      ? null
      : dashboard.totals;
  if (read.mode == DesignContextMode.sample &&
      week != null &&
      _isMatchingWeek(week, dashboard) &&
      week.evidenceBasis == 'synthetic') {
    try {
      final location = tz.getLocation(week.timezone);
      final now = tz.TZDateTime.from(week.generatedAt, location);
      final currentDays = week.buckets.where((row) {
        final start = tz.TZDateTime.from(row.period.start, location);
        return start.year == now.year &&
            start.month == now.month &&
            start.day == now.day;
      }).toList();
      if (currentDays.length == 1 &&
          currentDays.single.allocation.evidenceBasis == 'synthetic') {
        daily = currentDays.single.allocation;
      }
    } catch (_) {
      // An invalid sample day cannot be shown as a full-day amount.
    }
  }
  void add(String id, CloudEnergyMoney? money) {
    if (money == null ||
        !supportedEvidence ||
        dashboard.availability == 'unavailable' ||
        dashboard.totals.availability == 'unavailable') {
      unknown.add(id);
      return;
    }
    if (money.currency != 'USD' ||
        !RegExp(r'^(0|[1-9][0-9]*)(\.[0-9]+)?$').hasMatch(money.amount)) {
      throw const FormatException('Unsafe dashboard money value');
    }
    final text = formatDashboardUsd(money);
    if (text == null) {
      throw const FormatException('Unsafe dashboard money value');
    }
    bindings.add(DesignTextBinding(id, text));
  }

  add('dashboard_text_006', daily?.usefulCost);
  add('dashboard_text_009', daily?.wasteCost);
  if (week != null) {
    final supportedWeekEvidence = read.mode == DesignContextMode.sample
        ? week.evidenceBasis == 'synthetic' &&
              week.totals.evidenceBasis == 'synthetic'
        : supportedHouseholdEvidence.contains(week.evidenceBasis) &&
              supportedHouseholdEvidence.contains(week.totals.evidenceBasis);
    final sampleDeviceCost = read.mode == DesignContextMode.sample
        ? _sampleWeekDeviceCosts(week)
        : null;
    final cost =
        _isMatchingWeek(week, dashboard) &&
            supportedWeekEvidence &&
            week.availability != 'unavailable' &&
            week.totals.availability != 'unavailable'
        ? read.mode == DesignContextMode.sample
              ? sampleDeviceCost == null
                    ? null
                    : _microsText(sampleDeviceCost.$1)
              : formatDashboardUsd(week.totals.cost)
        : null;
    if (cost == null) {
      bindings.add(const DesignTextBinding('dashboard_text_025', 'N/A'));
      unknown.add('dashboard_text_025');
    } else {
      bindings.add(DesignTextBinding('dashboard_text_025', cost));
      final useful = read.mode == DesignContextMode.sample
          ? sampleDeviceCost == null
                ? null
                : _microsText(sampleDeviceCost.$2)
          : formatDashboardUsd(week.totals.usefulCost);
      final waste = read.mode == DesignContextMode.sample
          ? sampleDeviceCost == null
                ? null
                : _microsText(sampleDeviceCost.$3)
          : formatDashboardUsd(week.totals.wasteCost);
      if (useful != null && waste != null) {
        bindings.add(DesignTextBinding('dashboard_text_026', '$useful Useful'));
        bindings.add(DesignTextBinding('dashboard_text_027', '$waste Waste'));
      }
    }
  }
  return DesignNumericBindings(
    List.unmodifiable(bindings),
    Set.unmodifiable(unknown),
  );
}

(BigInt, BigInt, BigInt)? _sampleWeekDeviceCosts(
  CloudHouseholdEnergyTrends week,
) {
  if (week.dataMode != 'sample' && week.dataMode != 'mixed' ||
      week.scope != 'whole_home_including_unattributed_load') {
    return null;
  }
  var total = BigInt.zero;
  var useful = BigInt.zero;
  var waste = BigInt.zero;
  var observed = 0;
  for (final bucket in week.buckets) {
    if (bucket.period.start.isAfter(week.generatedAt)) continue;
    final seededRows = bucket.deviceAllocations
        .where((device) => device.deviceId != null)
        .toList();
    if (seededRows.length != 18) {
      return null;
    }
    final ids = <String>{};
    for (final device in seededRows) {
      if (device.deviceId == null ||
          !ids.add(device.deviceId!) ||
          device.applianceId != null ||
          device.allocation.evidenceBasis != 'synthetic') {
        return null;
      }
      final rowTotal = _usdMicros(device.allocation.cost);
      final rowUseful = _usdMicros(device.allocation.usefulCost);
      final rowWaste = _usdMicros(device.allocation.wasteCost);
      if (rowTotal == null ||
          rowUseful == null ||
          rowWaste == null ||
          rowUseful + rowWaste > rowTotal) {
        return null;
      }
      total += rowTotal;
      useful += rowUseful;
      waste += rowWaste;
    }
    observed++;
  }
  return observed == 0 ? null : (total, useful, waste);
}

List<DesignTextBinding>? _sampleDevicesBindings(
  DevicesDomainSnapshot inventory,
  CloudHouseholdEnergyTrends costs,
) {
  if (costs.homeId.toLowerCase() != inventory.homeId.toLowerCase() ||
      costs.dataMode != inventory.dataMode.name ||
      costs.fixtureRevision != inventory.fixtureRevision ||
      costs.granularity != 'day' ||
      !const {'synthetic', 'mixed', 'measured'}.contains(costs.evidenceBasis)) {
    return null;
  }
  tz.Location location;
  try {
    location = tz.getLocation(costs.timezone);
  } catch (_) {
    return null;
  }
  final now = tz.TZDateTime.from(costs.generatedAt, location);
  final today = costs.buckets.where((bucket) {
    final start = tz.TZDateTime.from(bucket.period.start, location);
    return start.year == now.year &&
        start.month == now.month &&
        start.day == now.day;
  }).toList();
  if (today.length != 1) {
    return null;
  }
  final seededRows = today.single.deviceAllocations
      .where((row) => row.deviceId != null)
      .toList();
  if (seededRows.length != 18) return null;
  final rows = <String, CloudDeviceEnergyAllocation>{};
  var usefulMicros = BigInt.zero;
  var wasteMicros = BigInt.zero;
  for (final row in seededRows) {
    if (row.deviceId == null ||
        row.applianceId != null ||
        row.allocation.evidenceBasis != 'synthetic' ||
        row.allocation.energy != null ||
        row.allocation.usefulEnergy != null ||
        row.allocation.wasteEnergy != null ||
        row.allocation.unclassifiedEnergy != null ||
        rows.containsKey(row.deviceId)) {
      return null;
    }
    final useful = _usdMicros(row.allocation.usefulCost);
    final waste = _usdMicros(row.allocation.wasteCost);
    if (useful == null || waste == null) return null;
    usefulMicros += useful;
    wasteMicros += waste;
    rows[row.deviceId!] = row;
  }
  if (rows.length != 18) return null;
  final bindings = <DesignTextBinding>[
    DesignTextBinding('devices_text_006', '${_microsText(wasteMicros)}/day'),
    DesignTextBinding('devices_text_009', '${_microsText(usefulMicros)}/day'),
  ];
  const nameIds = [22, 29, 36, 43, 50, 57, 64, 71, 78, 85];
  for (var i = 0; i < nameIds.length; i++) {
    final id = 'demo-device-${(i + 1).toString().padLeft(2, '0')}';
    final row = rows[id];
    if (row == null ||
        row.name == null ||
        inventory.items
                .where(
                  (item) =>
                      item.appliance.demoDeviceId == id &&
                      item.appliance.name == row.name,
                )
                .length !=
            1) {
      return null;
    }
    final useful = _usdMicros(row.allocation.usefulCost)!;
    final waste = _usdMicros(row.allocation.wasteCost)!;
    final stem = nameIds[i].toString().padLeft(3, '0');
    final usefulId = (nameIds[i] + 4).toString().padLeft(3, '0');
    final wasteId = (nameIds[i] + 6).toString().padLeft(3, '0');
    bindings.add(DesignTextBinding('devices_text_$stem', row.name!));
    bindings.add(
      DesignTextBinding('devices_text_$usefulId', _microsText(useful)),
    );
    bindings.add(
      DesignTextBinding('devices_text_$wasteId', _microsText(waste)),
    );
  }
  return List.unmodifiable(bindings);
}

BigInt? _usdMicros(CloudEnergyMoney? value) {
  if (value == null ||
      value.currency != 'USD' ||
      !RegExp(r'^(0|[1-9][0-9]*)(\.[0-9]{1,6})?$').hasMatch(value.amount)) {
    return null;
  }
  final parts = value.amount.split('.');
  return BigInt.parse(parts[0]) * BigInt.from(1000000) +
      BigInt.parse((parts.length == 1 ? '' : parts[1]).padRight(6, '0'));
}

String _microsText(BigInt micros) {
  final cents = (micros + BigInt.from(5000)) ~/ BigInt.from(10000);
  return '\$${cents ~/ BigInt.from(100)}.${(cents % BigInt.from(100)).toString().padLeft(2, '0')}';
}
