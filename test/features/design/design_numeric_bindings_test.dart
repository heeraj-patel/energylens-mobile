import 'dart:convert';

import 'package:energylens_mobile/core/cloud_api/cloud_appliance_list.dart';
import 'package:energylens_mobile/core/cloud_api/cloud_appliance.dart';
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

DesignContextRead _weekRead({
  String? cost = '4.123',
  void Function(Map<String, dynamic>)? alterWeek,
}) {
  final daily = _dashboardRead(useful: '1.00', waste: '0.20');
  final snapshot = daily.value as DashboardDomainSnapshot;
  final weekJson = _body('energy_trends', useful: '3.12', waste: '0.50');
  weekJson['granularity'] = 'day';
  weekJson['period'] = {
    'start_local': '2026-10-05T00:00:00-05:00',
    'end_exclusive_local': '2026-10-12T00:00:00-05:00',
  };
  weekJson['totals']['cost'] = cost == null
      ? null
      : {'amount': cost, 'currency': 'USD'};
  alterWeek?.call(weekJson);
  return DesignContextRead(
    accountId: daily.accountId,
    homeId: daily.homeId,
    mode: daily.mode,
    page: daily.page,
    value: DashboardDomainSnapshot(
      snapshot.dashboard,
      snapshot.trends,
      weekToDateTrends: CloudHouseholdEnergyTrends.fromJson(
        weekJson,
        expectedHomeId: homeA,
      ),
      isCurrent: () => true,
    ),
  );
}

void main() {
  test('binds only the validated week-to-date useful and waste split', () {
    final result = prepareDesignNumericBindings(_weekRead());
    expect(result.bindings.map((row) => row.id), [
      'dashboard_text_006',
      'dashboard_text_009',
      'dashboard_text_026',
      'dashboard_text_027',
    ]);
    expect(result.bindings.map((row) => row.text), [
      '\$1.00',
      '\$0.20',
      '\$3.12 Useful',
      '\$0.50 Waste',
    ]);
  });

  test('weekly split stays unavailable for absent price or wrong period', () {
    for (final read in [
      _weekRead(cost: null),
      _weekRead(
        alterWeek: (json) {
          json['period']['start_local'] = '2026-10-06T00:00:00-05:00';
        },
      ),
    ]) {
      final result = prepareDesignNumericBindings(read);
      expect(result.bindings.map((row) => row.id), [
        'dashboard_text_006',
        'dashboard_text_009',
      ]);
      expect(result.unknownBindingIds, isNot(contains('dashboard_text_025')));
    }
  });

  test('uses only exact daily cost IDs and rounds display once', () {
    final result = prepareDesignNumericBindings(
      _dashboardRead(useful: '6.9600', waste: '0.020'),
    );
    expect(result.bindings.map((b) => b.id), [
      'dashboard_text_006',
      'dashboard_text_009',
    ]);
    expect(result.bindings.map((b) => b.text), ['\$6.96', '\$0.02']);
    expect(result.unknownBindingIds, isEmpty);
    expect(jsonDecode(result.encode()), {
      'version': 1,
      'bindings': [
        {'id': 'dashboard_text_006', 'text': '\$6.96'},
        {'id': 'dashboard_text_009', 'text': '\$0.02'},
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

  test('withholds household cost claims without supported typed evidence', () {
    for (final basis in [
      'unavailable',
      'synthetic',
      'inferred',
      'user_supplied',
    ]) {
      for (final field in ['evidence_basis', 'totals']) {
        final result = prepareDesignNumericBindings(
          _dashboardRead(
            useful: '1.00',
            waste: '0.50',
            alterDashboard: (json) {
              if (field == 'totals') {
                json['totals']['evidence_basis'] = basis;
              } else {
                json['evidence_basis'] = basis;
              }
            },
            alterTrends: (json) {
              if (field == 'totals') {
                json['totals']['evidence_basis'] = basis;
              } else {
                json['evidence_basis'] = basis;
              }
            },
          ),
        );
        expect(result.bindings, isEmpty, reason: '$field: $basis');
        expect(result.unknownBindingIds, {
          'dashboard_text_006',
          'dashboard_text_009',
        });
      }
    }
    for (final field in ['availability', 'totals']) {
      final result = prepareDesignNumericBindings(
        _dashboardRead(
          useful: '1.00',
          waste: '0.50',
          alterDashboard: (json) {
            if (field == 'totals') {
              json['totals']['availability'] = 'unavailable';
            } else {
              json['availability'] = 'unavailable';
            }
          },
          alterTrends: (json) {
            if (field == 'totals') {
              json['totals']['availability'] = 'unavailable';
            } else {
              json['availability'] = 'unavailable';
            }
          },
        ),
      );
      expect(result.bindings, isEmpty, reason: field);
      expect(result.unknownBindingIds, {
        'dashboard_text_006',
        'dashboard_text_009',
      });
    }
  });

  test('withholds a full-day sample claim without its matching day bucket', () {
    final dashboardJson = _body('dashboard', useful: '6.96', waste: '2.88');
    final trendsJson = _body('energy_trends', useful: '6.96', waste: '2.88');
    for (final json in [dashboardJson, trendsJson]) {
      json['data_mode'] = 'sample';
      json['fixture_revision'] = 'sample-v1';
      json['evidence_basis'] = 'synthetic';
      json['totals']['evidence_basis'] = 'synthetic';
    }
    final read = DesignContextRead(
      accountId: 'sample',
      homeId: homeA,
      mode: DesignContextMode.sample,
      page: 'dashboard',
      value: DashboardDomainSnapshot(
        CloudHouseholdDashboard.fromJson(dashboardJson, expectedHomeId: homeA),
        CloudHouseholdEnergyTrends.fromJson(trendsJson, expectedHomeId: homeA),
        isCurrent: () => true,
      ),
    );

    final result = prepareDesignNumericBindings(read);

    expect(result.bindings, isEmpty);
    expect(result.unknownBindingIds, {
      'dashboard_text_006',
      'dashboard_text_009',
    });
    expect(result.encode(), isNot(contains('synthetic')));
  });

  test(
    'sample weekly card excludes unattributed cost and uses full day split',
    () {
      final dashboardJson = _body('dashboard', useful: '0.01', waste: '0.01');
      final hourlyJson = _body('energy_trends', useful: '0.01', waste: '0.01');
      final dayJson = _body('energy_trends', useful: '0.20', waste: '0.40');
      for (final json in [dashboardJson, hourlyJson, dayJson]) {
        json['data_mode'] = 'sample';
        json['fixture_revision'] = 'db-demo-v1';
        json['scope'] = 'whole_home_including_unattributed_load';
        json['evidence_basis'] = 'synthetic';
        json['totals']['evidence_basis'] = 'synthetic';
      }
      dayJson['granularity'] = 'day';
      dayJson['period'] = {
        'start_local': '2026-10-05T00:00:00-05:00',
        'end_exclusive_local': '2026-10-12T00:00:00-05:00',
      };
      dayJson['totals']['cost'] = {'amount': '0.60', 'currency': 'USD'};
      dayJson['buckets'] = [
        {
          'start_local': '2026-10-06T00:00:00-05:00',
          'end_exclusive_local': '2026-10-07T00:00:00-05:00',
          'coverage_fraction': '1',
          'allocation': {
            ...(_body('dashboard')['totals'] as Map<String, dynamic>),
            'useful_cost': {'amount': '0.20', 'currency': 'USD'},
            'waste_cost': {'amount': '0.40', 'currency': 'USD'},
            'evidence_basis': 'synthetic',
          },
          'device_allocations': [
            for (var i = 1; i <= 18; i++)
              {
                'device_id': 'demo-device-${i.toString().padLeft(2, '0')}',
                'name': i <= 10 ? 'Existing device' : null,
                'allocation': {
                  ...(_body('dashboard')['totals'] as Map<String, dynamic>),
                  'cost': {'amount': '0.03', 'currency': 'USD'},
                  'useful_cost': {'amount': '0.01', 'currency': 'USD'},
                  'waste_cost': {'amount': '0.02', 'currency': 'USD'},
                  'evidence_basis': 'synthetic',
                },
              },
          ],
        },
      ];
      final dashboard = CloudHouseholdDashboard.fromJson(
        dashboardJson,
        expectedHomeId: homeA,
      );
      final hourly = CloudHouseholdEnergyTrends.fromJson(
        hourlyJson,
        expectedHomeId: homeA,
      );
      final day = CloudHouseholdEnergyTrends.fromJson(
        dayJson,
        expectedHomeId: homeA,
      );
      final result = prepareDesignNumericBindings(
        DesignContextRead(
          accountId: 'sample',
          homeId: homeA,
          mode: DesignContextMode.sample,
          page: 'dashboard',
          value: DashboardDomainSnapshot(
            dashboard,
            hourly,
            weekToDateTrends: day,
            isCurrent: () => true,
          ),
        ),
      );
      final byId = {for (final row in result.bindings) row.id: row.text};
      expect(byId['dashboard_text_006'], '\$0.20');
      expect(byId['dashboard_text_009'], '\$0.40');
      expect(byId['dashboard_text_026'], '\$0.18 Useful');
      expect(byId['dashboard_text_027'], '\$0.36 Waste');
    },
  );

  test('binds ten named sample cards from eighteen Cloud cost rows', () {
    const names = [
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
    ];
    final rows = [
      for (var i = 1; i <= 18; i++)
        {
          'device_id': 'demo-device-${i.toString().padLeft(2, '0')}',
          'name': i <= 10 ? names[i - 1] : null,
          'allocation': {
            'energy': null,
            'cost': {'amount': '0.03', 'currency': 'USD'},
            'useful_energy': null,
            'useful_cost': {'amount': '0.01', 'currency': 'USD'},
            'waste_energy': null,
            'waste_cost': {'amount': '0.02', 'currency': 'USD'},
            'unclassified_energy': null,
            'unclassified_cost': null,
            'availability': 'partial',
            'evidence_basis': 'synthetic',
          },
        },
    ];
    final json = _body('energy_trends')
      ..['data_mode'] = 'sample'
      ..['fixture_revision'] = 'db-demo-v1'
      ..['evidence_basis'] = 'synthetic'
      ..['granularity'] = 'day'
      ..['period'] = {
        'start_local': '2026-10-05T00:00:00-05:00',
        'end_exclusive_local': '2026-10-12T00:00:00-05:00',
      }
      ..['buckets'] = [
        {
          'start_local': '2026-10-06T00:00:00-05:00',
          'end_exclusive_local': '2026-10-07T00:00:00-05:00',
          'coverage_fraction': '1',
          'allocation': {
            ...(_body('dashboard')['totals'] as Map<String, dynamic>),
            'evidence_basis': 'synthetic',
          },
          'device_allocations': rows,
        },
      ];
    final inventory = DevicesDomainSnapshot(
      homeId: homeA,
      items: [
        for (var i = 1; i <= 10; i++)
          DeviceInventoryItem(
            appliance: CloudAppliance(
              id: '10000000-0000-4000-8000-${i.toString().padLeft(12, '0')}',
              homeId: homeA,
              name: names[i - 1],
              category: '',
              room: null,
              brand: '',
              fullModel: '',
              fuel: '',
              matchQuality: 'unresolved',
              demoDeviceId: 'demo-device-${i.toString().padLeft(2, '0')}',
            ),
            activeAttachmentIds: const [],
            measuredBuckets: const [],
          ),
      ],
      hasMoreMeteredPages: false,
      dataMode: CloudApplianceDataMode.sample,
      fixtureRevision: 'db-demo-v1',
      sampleDayCosts: CloudHouseholdEnergyTrends.fromJson(
        json,
        expectedHomeId: homeA,
      ),
      isCurrent: () => true,
    );
    final result = prepareDesignNumericBindings(
      DesignContextRead(
        accountId: 'sample',
        homeId: homeA,
        mode: DesignContextMode.sample,
        page: 'devices',
        value: inventory,
      ),
    );
    expect(result.bindings, hasLength(32));
    expect(result.bindings.first.text, '\$0.36/day');
    expect(result.bindings[1].text, '\$0.18/day');
    expect(result.bindings[2].text, names.first);
    expect(result.bindings[3].text, '\$0.01');
    expect(result.unknownBindingIds, isEmpty);

    json['data_mode'] = 'mixed';
    json['evidence_basis'] = 'mixed';
    (json['buckets'] as List).single['device_allocations'].add({
      'appliance_id': '99999999-9999-4999-8999-999999999999',
      'allocation': {
        ...((rows.first['allocation'] as Map<String, dynamic>)),
        'useful_cost': null,
        'waste_cost': null,
        'unclassified_cost': {'amount': '0.03', 'currency': 'USD'},
        'evidence_basis': 'measured',
      },
    });
    final mixedInventory = DevicesDomainSnapshot(
      homeId: homeA,
      items: inventory.items,
      hasMoreMeteredPages: false,
      dataMode: CloudApplianceDataMode.mixed,
      fixtureRevision: 'db-demo-v1',
      sampleDayCosts: CloudHouseholdEnergyTrends.fromJson(
        json,
        expectedHomeId: homeA,
      ),
      isCurrent: () => true,
    );
    final mixed = prepareDesignNumericBindings(
      DesignContextRead(
        accountId: 'owner',
        homeId: homeA,
        mode: DesignContextMode.household,
        page: 'devices',
        value: mixedInventory,
      ),
    );
    expect(mixed.bindings, hasLength(32));
    expect(mixed.bindings[3].text, '\$0.01');
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

  group('Dashboard gas line (G-C8)', () {
    void withGas(Map<String, dynamic> json, String? cost) {
      json['totals']['fuel'] = null;
      json['totals']['gas_cost'] = cost == null
          ? null
          : {'amount': cost, 'currency': 'USD'};
    }

    test('shows the separate gas total with the cost card period suffix', () {
      final result = prepareDesignNumericBindings(
        _dashboardRead(
          useful: '6.96',
          waste: '0.02',
          alterDashboard: (json) => withGas(json, '1.2345'),
          alterTrends: (json) => withGas(json, '1.2345'),
        ),
      );
      expect(result.gasLine, 'Gas appliances: \$1.23/day');
      expect(dashboardPeriodSuffix, '/day');
      expect(result.bindings.map((b) => b.text), ['\$6.96', '\$0.02']);
    });

    test('is absent for an electric-only home and electric totals match', () {
      final electric = prepareDesignNumericBindings(
        _dashboardRead(useful: '6.96', waste: '0.02'),
      );
      final gas = prepareDesignNumericBindings(
        _dashboardRead(
          useful: '6.96',
          waste: '0.02',
          alterDashboard: (json) => withGas(json, '2.00'),
          alterTrends: (json) => withGas(json, '2.00'),
        ),
      );
      expect(electric.gasLine, isNull);
      expect(
        gas.bindings.map((b) => '${b.id}=${b.text}'),
        electric.bindings.map((b) => '${b.id}=${b.text}'),
      );
    });

    test('is absent when gas appliances have no priced gas', () {
      final result = prepareDesignNumericBindings(
        _dashboardRead(
          useful: '6.96',
          waste: '0.02',
          alterDashboard: (json) => withGas(json, null),
        ),
      );
      expect(result.gasLine, isNull);
    });
  });
}
