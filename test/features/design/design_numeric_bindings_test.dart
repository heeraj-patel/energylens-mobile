import 'dart:convert';

import 'package:energylens_mobile/core/cloud_api/cloud_appliance_list.dart';
import 'package:energylens_mobile/core/cloud_api/cloud_household_energy.dart';
import 'package:energylens_mobile/features/design/dashboard_domain_repository.dart';
import 'package:energylens_mobile/features/design/design_context_coordinator.dart';
import 'package:energylens_mobile/features/design/design_numeric_bindings.dart';
import 'package:energylens_mobile/features/design/devices_domain_repository.dart';
import 'package:flutter_test/flutter_test.dart';

const homeA = '11111111-1111-4111-8111-111111111111';
const homeB = '22222222-2222-4222-8222-222222222222';

Map<String, dynamic> _body(String view, {String? useful, String? waste}) => {
  'schema_revision': 'household_energy_v1',
  'content_revision': 'v1',
  'home_id': homeA,
  'data_mode': 'household',
  'snapshot_id': 'snapshot-1',
  'generated_at': '2026-10-06T18:00:00Z',
  'as_of': null,
  'timezone': 'America/Chicago',
  'period': {
    'start_local': '2026-10-06T00:00:00-05:00',
    'end_exclusive_local': '2026-10-07T00:00:00-05:00',
  },
  'scope': 'attributed_devices',
  'availability': 'partial',
  'evidence_basis': 'estimated',
  'view': view,
  'totals': {
    'energy': null,
    'cost': null,
    'useful_energy': null,
    'useful_cost': useful == null
        ? null
        : {'amount': useful, 'currency': 'USD'},
    'waste_energy': null,
    'waste_cost': waste == null ? null : {'amount': waste, 'currency': 'USD'},
    'unclassified_energy': null,
    'unclassified_cost': null,
    'availability': 'partial',
    'evidence_basis': 'estimated',
  },
  if (view == 'dashboard') ...{
    'trend_period': 'day',
    'top_recommendation_id': null,
    'assistant_intent_id': null,
  } else ...{
    'granularity': 'hour',
    'buckets': <Object>[],
  },
};

DesignContextRead _dashboardRead({
  String? useful,
  String? waste,
  String home = homeA,
  bool Function()? isCurrent,
  void Function(Map<String, dynamic>)? alterTrends,
  void Function(Map<String, dynamic>)? alterDashboard,
}) {
  final dashboardJson = _body('dashboard', useful: useful, waste: waste);
  final trendsJson = _body('energy_trends', useful: useful, waste: waste);
  alterDashboard?.call(dashboardJson);
  alterTrends?.call(trendsJson);
  return DesignContextRead(
    accountId: 'account',
    homeId: home,
    mode: DesignContextMode.household,
    page: 'dashboard',
    value: DashboardDomainSnapshot(
      CloudHouseholdDashboard.fromJson(dashboardJson, expectedHomeId: homeA),
      CloudHouseholdEnergyTrends.fromJson(trendsJson, expectedHomeId: homeA),
      isCurrent: isCurrent ?? () => true,
    ),
  );
}

void main() {
  test('uses only exact daily cost IDs and preserves decimal strings', () {
    final result = prepareDesignNumericBindings(
      _dashboardRead(useful: '6.9600', waste: '0.020'),
    );
    expect(result.bindings.map((b) => b.id), [
      'dashboard_text_006',
      'dashboard_text_009',
    ]);
    expect(result.bindings.map((b) => b.text), ['\$6.9600', '\$0.020']);
    expect(result.unknownBindingIds, isEmpty);
    expect(jsonDecode(result.encode()), {
      'version': 1,
      'bindings': [
        {'id': 'dashboard_text_006', 'text': '\$6.9600'},
        {'id': 'dashboard_text_009', 'text': '\$0.020'},
      ],
    });
  });

  test('accepts home-local spring and fall DST calendar days', () {
    for (final window in <(String, String)>[
      ('2026-03-08T00:00:00-06:00', '2026-03-09T00:00:00-05:00'),
      ('2026-11-01T00:00:00-05:00', '2026-11-02T00:00:00-06:00'),
    ]) {
      final result = prepareDesignNumericBindings(
        _dashboardRead(
          useful: '1.00',
          alterDashboard: (json) {
            json['period']['start_local'] = window.$1;
            json['period']['end_exclusive_local'] = window.$2;
          },
          alterTrends: (json) {
            json['period']['start_local'] = window.$1;
            json['period']['end_exclusive_local'] = window.$2;
          },
        ),
      );

      expect(result.bindings.single.text, '\$1.00');
    }
  });

  test('rejects non-midnight or multi-day dashboard periods', () {
    for (final window in <(String, String)>[
      ('2026-03-08T00:00:00-06:00', '2026-03-09T01:00:00-05:00'),
      ('2026-03-08T00:00:00-06:00', '2026-03-10T00:00:00-05:00'),
    ]) {
      expect(
        () => prepareDesignNumericBindings(
          _dashboardRead(
            useful: '1.00',
            alterDashboard: (json) {
              json['period']['start_local'] = window.$1;
              json['period']['end_exclusive_local'] = window.$2;
            },
            alterTrends: (json) {
              json['period']['start_local'] = window.$1;
              json['period']['end_exclusive_local'] = window.$2;
            },
          ),
        ),
        throwsFormatException,
      );
    }
  });

  test('omits unknown costs and never fills weekly or savings slots', () {
    final result = prepareDesignNumericBindings(_dashboardRead(useful: '1.00'));
    expect(result.bindings.map((b) => b.id), ['dashboard_text_006']);
    expect(result.unknownBindingIds, {'dashboard_text_009'});
    expect(result.encode(), isNot(contains('dashboard_text_025')));
    expect(result.encode(), isNot(contains('dashboard_text_014')));
  });

  test('unclassified cost alone leaves useful and waste slots unknown', () {
    final read = _dashboardRead(
      alterDashboard: (json) {
        json['totals']['energy'] = {'value': '24', 'unit': 'kWh'};
        json['totals']['unclassified_energy'] = {'value': '24', 'unit': 'kWh'};
        json['totals']['unclassified_cost'] = {
          'amount': '4.800000000000000001',
          'currency': 'USD',
        };
      },
      alterTrends: (json) {
        json['totals']['energy'] = {'value': '24', 'unit': 'kWh'};
        json['totals']['unclassified_energy'] = {'value': '24', 'unit': 'kWh'};
        json['totals']['unclassified_cost'] = {
          'amount': '4.800000000000000001',
          'currency': 'USD',
        };
      },
    );

    final result = prepareDesignNumericBindings(read);

    expect(result.bindings, isEmpty);
    expect(result.unknownBindingIds, {
      'dashboard_text_006',
      'dashboard_text_009',
    });
    expect(result.encode(), isNot(contains('4.800000000000000001')));
  });

  test('rejects unsafe value, mismatched snapshot, mode, and period', () {
    expect(
      () => prepareDesignNumericBindings(
        _dashboardRead(useful: '<script>alert(1)</script>'),
      ),
      throwsFormatException,
    );
    for (final alter in <void Function(Map<String, dynamic>)>[
      (json) => json['snapshot_id'] = 'other',
      (json) => json['data_mode'] = 'sample',
      (json) => json['period']['start_local'] = '2026-10-05T00:00:00-05:00',
    ]) {
      expect(
        () => prepareDesignNumericBindings(
          _dashboardRead(useful: '1.00', alterTrends: alter),
        ),
        throwsFormatException,
      );
    }
    final household = _dashboardRead(useful: '1.00');
    expect(
      () => prepareDesignNumericBindings(
        DesignContextRead(
          accountId: household.accountId,
          homeId: household.homeId,
          mode: DesignContextMode.sample,
          page: household.page,
          value: household.value,
        ),
      ),
      throwsFormatException,
    );
    expect(
      () => prepareDesignNumericBindings(
        _dashboardRead(
          useful: '1.00',
          alterDashboard: (json) => json['period']['end_exclusive_local'] =
              '2026-10-08T00:00:00-05:00',
          alterTrends: (json) => json['period']['end_exclusive_local'] =
              '2026-10-08T00:00:00-05:00',
        ),
      ),
      throwsFormatException,
    );
    expect(
      prepareDesignNumericBindings(
        _dashboardRead(
          useful: '1.00',
          alterDashboard: (json) => json['trend_period'] = 'week',
        ),
      ).bindings,
      isEmpty,
    );
  });

  test('home switch invalidates dashboard and devices bindings', () {
    var current = true;
    final read = _dashboardRead(useful: '1.00', isCurrent: () => current);
    current = false;
    expect(() => prepareDesignNumericBindings(read), throwsFormatException);
    expect(
      () => prepareDesignNumericBindings(_dashboardRead(home: homeB)),
      throwsFormatException,
    );
    final devices = DesignContextRead(
      accountId: 'account',
      homeId: homeA,
      mode: DesignContextMode.household,
      page: 'devices',
      value: DevicesDomainSnapshot(
        homeId: homeA,
        items: const [],
        hasMoreMeteredPages: false,
        dataMode: CloudApplianceDataMode.household,
        fixtureRevision: null,
        isCurrent: () => current,
      ),
    );
    expect(() => prepareDesignNumericBindings(devices), throwsFormatException);
    current = true;
    final prepared = prepareDesignNumericBindings(devices);
    expect(prepared.bindings, isEmpty);
    expect(prepared.unknownBindingIds, contains('devices_text_006'));
    expect(prepared.unknownBindingIds, contains('devices_text_091'));
  });
}
