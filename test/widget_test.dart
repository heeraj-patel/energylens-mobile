import 'package:energylens_mobile/features/discovery/discovery_api.dart';
import 'package:energylens_mobile/features/discovery/discovery_credentials.dart';
import 'package:energylens_mobile/main.dart';
import 'package:energylens_mobile/core/cloud_api/cloud_home.dart';
import 'package:energylens_mobile/features/energy/power_now_visibility.dart';
import 'package:energylens_mobile/features/energy/power_now_daily_cost_table.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

class _ConnectedCredentials extends DiscoveryCredentials {
  String? postalCode = '78732';
  bool zipPromptDismissed = false;

  @override
  Future<(String?, String?)> read() async =>
      ('https://100.115.133.73:18787', 'test');

  @override
  Future<String?> readPostalCode({OwnedPairingScope? scope}) async =>
      postalCode;

  @override
  Future<void> savePostalCode(
    String postalCode, {
    OwnedPairingScope? scope,
  }) async {
    this.postalCode = postalCode;
  }

  @override
  Future<void> clearPostalCode({OwnedPairingScope? scope}) async {
    postalCode = null;
  }

  @override
  Future<bool> readZipPromptDismissed({OwnedPairingScope? scope}) async =>
      zipPromptDismissed;

  @override
  Future<void> dismissZipPrompt({OwnedPairingScope? scope}) async {
    zipPromptDismissed = true;
  }
}

class _MemoryVisibilityStore extends PowerNowVisibilityStore {
  final values = <(String, String?), Set<int>>{};

  @override
  Future<Set<int>> read(String hubAddress, String? cloudHomeId) async => {
    ...?values[(hubAddress, cloudHomeId)],
  };

  @override
  Future<void> write(
    String hubAddress,
    String? cloudHomeId,
    Set<int> applianceIds,
  ) async {
    values[(hubAddress, cloudHomeId)] = {...applianceIds};
  }
}

class _ConnectedApi extends DiscoveryApi {
  _ConnectedApi({
    this.sourceKind = 'user_label',
    this.withoutRate = false,
    this.postalOnly = false,
  });

  final String sourceKind;
  bool withoutRate;
  final bool postalOnly;
  double hours = 21;
  int estimateCalls = 0;

  @override
  Future<ElectricitySettings> electricitySettings(
    String baseUrl,
    String token,
  ) async => ElectricitySettings(
    postalCode: withoutRate && !postalOnly ? null : '78732',
    rateUsdPerKwh: withoutRate ? null : 0.1588,
  );

  @override
  Future<ElectricitySettings> updateElectricitySettings(
    String baseUrl,
    String token, {
    required String? postalCode,
    required double? rateUsdPerKwh,
  }) async {
    withoutRate = postalCode == null && rateUsdPerKwh == null;
    return ElectricitySettings(
      postalCode: postalCode,
      rateUsdPerKwh: rateUsdPerKwh,
    );
  }

  @override
  Future<List<SavedPlug>> saved(String baseUrl, String token) async => [
    SavedPlug(
      id: 'ks19',
      ip: '192.168.68.92',
      model: 'HS103(US)',
      name: 'Living Room Lamp KS19',
      room: 'Living Room',
      meterStatus: 'absent',
      lastVerifiedAt: 1,
      connectedAppliance: SavedAppliance(
        id: 1,
        name: 'Two-bulb Philips Hue White lamp',
        room: '',
        category: 'lighting',
        manufacturer: 'Philips Hue',
        model: '',
        loadKind: 'replaceable_bulb',
        onboardingMethod: 'manual',
        hoursPerWeek: hours,
        initialHoursPerWeek: 21,
        bulbCount: 2,
        combinedInputWatts: 19,
      ),
    ),
  ];

  @override
  Future<SavedAppliance> updateApplianceHours(
    String baseUrl,
    String token,
    int applianceId,
    double hoursPerWeek,
  ) async {
    hours = hoursPerWeek;
    return SavedAppliance(
      id: applianceId,
      name: 'Two-bulb Philips Hue White lamp',
      room: '',
      category: 'lighting',
      manufacturer: 'Philips Hue',
      model: '9290011369B',
      loadKind: 'replaceable_bulb',
      onboardingMethod: 'manual',
      hoursPerWeek: hours,
      initialHoursPerWeek: 21,
      bulbCount: 2,
      combinedInputWatts: 19,
    );
  }

  @override
  Future<EnergyEstimate> estimate(
    String baseUrl,
    String token,
    int applianceId, {
    String? postalCode,
    double? rateUsdPerKwh,
  }) async {
    estimateCalls++;
    assert(applianceId == 1);
    assert(postalCode == null);
    final active = 19 * hours * 52 / 12000 * 0.1588;
    final standby = sourceKind == 'energy_star'
        ? 0.2 * 2 * (168 - hours) * 52 / 12000 * 0.1588
        : null;
    return EnergyEstimate(
      status: 'estimated',
      estimatedKwh: (active + (standby ?? 0)) / 0.1588,
      estimatedCostUsd: withoutRate ? null : active + (standby ?? 0),
      activeCostUsd: withoutRate ? null : active,
      standbyCostUsd: withoutRate ? null : standby,
      rateUsdPerKwh: withoutRate ? null : 0.1588,
      rateSourceLabel: withoutRate
          ? null
          : 'Texas average (EIA, published table)',
      evidence: EnergyEvidence(
        sourceKind: sourceKind,
        datasetId: sourceKind == 'energy_star' ? 'msj5-kqfv' : 'bulb_label',
        sourceUrl: '',
        matchedBrand: 'Philips Hue',
        matchedModel: '',
        annualKwh: sourceKind == 'energy_star' ? 10.374 : 20.748,
        standbyWatts: sourceKind == 'energy_star' ? 0.2 : null,
        usageBasis: 'Two bulbs, 21 hours/week',
        retrievedAt: 1,
      ),
    );
  }
}

class _OutageAfterFirstLoadApi extends _ConnectedApi {
  bool unavailable = false;

  @override
  Future<List<SavedPlug>> saved(String baseUrl, String token) async {
    if (unavailable) throw StateError('hub offline');
    return super.saved(baseUrl, token);
  }
}

class _StandaloneCostApi extends _ConnectedApi {
  @override
  Future<List<SavedAppliance>> appliances(String baseUrl, String token) async =>
      [
        (await saved(baseUrl, token)).single.connectedAppliance!,
        const SavedAppliance(
          id: 2,
          name: 'KitchenAid refrigerator',
          room: 'Kitchen',
          category: 'refrigerator',
          manufacturer: 'KitchenAid',
          model: 'KSSC48QTS00',
          loadKind: 'appliance',
          onboardingMethod: 'manual',
        ),
      ];

  @override
  Future<EnergyEstimate> estimate(
    String baseUrl,
    String token,
    int applianceId, {
    String? postalCode,
    double? rateUsdPerKwh,
  }) async {
    if (applianceId == 1) {
      return super.estimate(baseUrl, token, applianceId);
    }
    return const EnergyEstimate(
      status: 'estimated',
      estimatedKwh: 54.9,
      estimatedCostUsd: 8.72,
      rateUsdPerKwh: 0.1588,
      rateSourceLabel: 'Texas average',
    );
  }
}

class _TodayMeterApi extends _ConnectedApi {
  _TodayMeterApi({this.todayCoverage = 0.35});

  final double todayCoverage;
  final requests = <(String, String, String?)>[];

  @override
  Future<List<SavedPlug>> saved(String baseUrl, String token) async {
    final appliance = (await super.saved(
      baseUrl,
      token,
    )).single.connectedAppliance;
    return [
      SavedPlug(
        id: 'attached-meter',
        ip: '192.168.68.50',
        model: 'HS110',
        name: 'Living Room Lamp KS19',
        room: '',
        meterStatus: 'verified',
        localProtocol: 'legacy_tcp',
        lastVerifiedAt: 1,
        connectedAppliance: appliance,
      ),
      const SavedPlug(
        id: 'unattached-meter',
        ip: '192.168.68.51',
        model: 'HS110',
        name: 'Unattached meter',
        room: '',
        meterStatus: 'verified',
        localProtocol: 'legacy_tcp',
        lastVerifiedAt: 1,
      ),
    ];
  }

  @override
  Future<DeviceEnergy> deviceEnergy(
    String baseUrl,
    String token,
    String plugId, {
    String period = 'day',
    String? timezone,
    String? postalCode,
    double? rateUsdPerKwh,
  }) async {
    requests.add((plugId, period, timezone));
    return DeviceEnergy(
      status: 'measured',
      period: period,
      totalKwh: 0.25,
      coverageFraction: period == 'today' ? todayCoverage : 0.8,
      coveredSecs: period == 'today' ? 12600 : 69120,
      latestWatts: period == 'today' ? 35 : null,
      observedCostUsd: period == 'today' ? 0.04 : 0.12,
      readings: period == 'today'
          ? [EnergyReading(ts: DateTime.now().toUtc(), watts: 35)]
          : const [],
    );
  }
}

class _IdentityDriftTodayMeterApi extends _TodayMeterApi {
  @override
  Future<SavedPlug> refreshPlugStatus(
    String baseUrl,
    String token,
    String plugId,
  ) async {
    final plug = (await saved(
      baseUrl,
      token,
    )).firstWhere((item) => item.id == plugId);
    return SavedPlug(
      id: plug.id,
      ip: plug.ip,
      model: plug.model,
      name: plug.name,
      room: plug.room,
      meterStatus: plug.meterStatus,
      lastVerifiedAt: plug.lastVerifiedAt,
      localProtocol: plug.localProtocol,
      connectedAppliance: plug.connectedAppliance,
      connectionStatus: 'identity_changed',
    );
  }
}

class _MeteredApi extends DiscoveryApi {
  @override
  Future<ElectricitySettings> electricitySettings(
    String baseUrl,
    String token,
  ) async => const ElectricitySettings();

  @override
  Future<List<SavedPlug>> saved(String baseUrl, String token) async => const [
    SavedPlug(
      id: 'meter-1',
      ip: '192.168.68.50',
      model: 'HS110',
      name: 'Office meter',
      room: 'Office',
      meterStatus: 'verified',
      localProtocol: 'legacy_tcp',
      lastVerifiedAt: 1,
    ),
  ];

  @override
  Future<DeviceEnergy> deviceEnergy(
    String baseUrl,
    String token,
    String plugId, {
    String period = 'day',
    String? timezone,
    String? postalCode,
    double? rateUsdPerKwh,
  }) async {
    assert(postalCode == null);
    return DeviceEnergy.fromJson({
      'status': 'measured',
      'period': 'day',
      'device_id': plugId,
      'total_kwh': 0.125,
      'coverage_fraction': 0.75,
      'covered_secs': 64800,
      'latest_watts': 100,
      'observed_cost_usd': 0.02,
      'rate_source_label': 'Texas average (EIA)',
      'readings': [
        {'ts': '2026-09-29T12:34:00Z', 'watts': 100, 'kwh_cumulative': 1.25},
      ],
    });
  }
}

class _StatusRefreshApi extends DiscoveryApi {
  int checks = 0;
  String status = 'connected';

  @override
  Future<List<SavedPlug>> saved(String baseUrl, String token) async => const [
    SavedPlug(
      id: 'living-room-plug',
      ip: '192.168.1.42',
      model: 'HS103',
      name: 'Living room plug',
      room: 'Living room',
      meterStatus: 'absent',
      lastVerifiedAt: 100,
    ),
  ];

  @override
  Future<SavedPlug> refreshPlugStatus(
    String baseUrl,
    String token,
    String plugId,
  ) async {
    checks++;
    expect(plugId, 'living-room-plug');
    return SavedPlug(
      id: plugId,
      ip: '192.168.1.42',
      model: 'HS103',
      name: 'Living room plug',
      room: 'Living room',
      meterStatus: 'absent',
      lastVerifiedAt: 100,
      connectionStatus: status,
      statusCheckedAt: 200 + checks,
    );
  }
}

class _ComputerCoverageApi extends DiscoveryApi {
  _ComputerCoverageApi(this.status);
  final String status;
  final requestedDevices = <String>[];

  @override
  Future<List<SavedPlug>> saved(String baseUrl, String token) async => const [
    SavedPlug(
      id: 'computer-meter',
      ip: '192.168.68.51',
      model: 'Meter plug',
      name: 'Office meter',
      room: 'Office',
      meterStatus: 'verified',
      lastVerifiedAt: 1,
      connectedAppliance: SavedAppliance(
        id: 42,
        name: 'Workstation',
        room: 'Office',
        category: 'computer',
        manufacturer: 'Example',
        model: 'Desktop',
        loadKind: 'computer',
        onboardingMethod: 'manual',
      ),
    ),
  ];

  @override
  Future<DeviceBaselineCoverage> deviceBaselineCoverage(
    String baseUrl,
    String token,
    String deviceId,
  ) async {
    requestedDevices.add(deviceId);
    return DeviceBaselineCoverage.fromJson({
      'device_id': deviceId,
      'appliance_id': 42,
      'window_start': '2026-09-22T12:00:00Z',
      'window_end': '2026-09-29T12:00:00Z',
      'latest_sample_at': '2026-09-29T11:59:00Z',
      'sample_count': 10081,
      'covered_secs': status == 'collecting' ? 250000 : 475200,
      'coverage_fraction': status == 'collecting' ? 0.41 : 0.79,
      'covered_days': status == 'collecting' ? 2 : 5,
      'required_days': 5,
      'status': status,
      'reason': status == 'collecting'
          ? 'needs_more_covered_days'
          : 'coverage_gate_met',
    });
  }
}

class _MultiProtocolApi extends _MeteredApi {
  final requested = <String>[];
  bool unavailable = false;

  @override
  Future<List<SavedPlug>> saved(String baseUrl, String token) async {
    if (unavailable) throw StateError('hub offline');
    return const [
      SavedPlug(
        id: 'kasa',
        ip: '',
        model: 'Kasa',
        name: 'Kasa',
        room: '',
        meterStatus: 'verified',
        localProtocol: 'legacy_tcp',
        lastVerifiedAt: 1,
      ),
      SavedPlug(
        id: 'kasa-http',
        ip: '',
        model: 'Kasa KLAP meter',
        name: 'Kasa HTTP',
        room: '',
        meterStatus: 'verified',
        localProtocol: 'http',
        lastVerifiedAt: 1,
      ),
      SavedPlug(
        id: 'unverified-http',
        ip: '',
        model: 'Kasa KLAP unverified',
        name: 'Unverified HTTP',
        room: '',
        meterStatus: 'unknown',
        localProtocol: 'http',
        lastVerifiedAt: 1,
      ),
      SavedPlug(
        id: 'shelly',
        ip: '',
        model: 'Shelly',
        name: 'Shelly',
        room: '',
        meterStatus: 'verified',
        localProtocol: 'shelly_gen2',
        lastVerifiedAt: 1,
      ),
      SavedPlug(
        id: 'tasmota',
        ip: '',
        model: 'Tasmota',
        name: 'Tasmota',
        room: '',
        meterStatus: 'verified',
        localProtocol: 'tasmota',
        lastVerifiedAt: 1,
      ),
      SavedPlug(
        id: 'absent',
        ip: '',
        model: 'No meter',
        name: 'No meter',
        room: '',
        meterStatus: 'absent',
        localProtocol: 'tasmota',
        lastVerifiedAt: 1,
      ),
    ];
  }

  @override
  Future<DeviceEnergy> deviceEnergy(
    String baseUrl,
    String token,
    String plugId, {
    String period = 'day',
    String? timezone,
    String? postalCode,
    double? rateUsdPerKwh,
  }) async {
    requested.add(plugId);
    return super.deviceEnergy(
      baseUrl,
      token,
      plugId,
      period: period,
      timezone: timezone,
      postalCode: postalCode,
      rateUsdPerKwh: rateUsdPerKwh,
    );
  }
}

class _CycleApi extends _ConnectedApi {
  double cycles = 4.5;

  @override
  Future<List<SavedPlug>> saved(String baseUrl, String token) async => const [
    SavedPlug(
      id: 'ks19',
      ip: '192.168.68.92',
      model: 'HS103(US)',
      name: 'Laundry plug',
      room: 'Laundry',
      meterStatus: 'absent',
      lastVerifiedAt: 1,
      connectedAppliance: SavedAppliance(
        id: 1,
        name: 'Washer',
        room: 'Laundry',
        category: 'washer',
        manufacturer: '',
        model: '',
        loadKind: 'appliance',
        onboardingMethod: 'manual',
      ),
    ),
  ];

  @override
  Future<ApplianceUsageProfile> applianceUsageProfile(
    String baseUrl,
    String token,
    int applianceId,
  ) async => ApplianceUsageProfile(
    applianceId: applianceId,
    usageKind: 'cycles_per_week',
    value: cycles,
    initialValue: 4.5,
    min: 0,
    max: 21,
    step: 0.5,
  );

  @override
  Future<ApplianceUsageProfile> updateApplianceUsageProfile(
    String baseUrl,
    String token,
    int applianceId,
    String usageKind,
    double value,
  ) async {
    cycles = value;
    return applianceUsageProfile(baseUrl, token, applianceId);
  }

  @override
  Future<EnergyEstimate> estimate(
    String baseUrl,
    String token,
    int applianceId, {
    String? postalCode,
    double? rateUsdPerKwh,
  }) async => EnergyEstimate(
    status: 'estimated',
    estimatedKwh: cycles * 52 * 0.4 / 12,
    estimatedCostUsd: cycles * 52 * 0.4 / 12 * 0.2,
    activeCostUsd: cycles * 52 * 0.4 / 12 * 0.2,
    rateUsdPerKwh: 0.2,
    evidence: const EnergyEvidence(
      sourceKind: 'category_typical',
      datasetId: 'energy_profiles_1.2.0',
      sourceUrl: '',
      matchedBrand: '',
      matchedModel: 'Washer',
      annualKwh: 93.6,
      usageBasis: 'Category estimate',
      retrievedAt: 1,
    ),
  );
}

class _HoursApi extends _CycleApi {
  double hoursPerWeek = 35;

  @override
  Future<List<SavedPlug>> saved(String baseUrl, String token) async => const [
    SavedPlug(
      id: 'ks19',
      ip: '192.168.68.92',
      model: 'HS103(US)',
      name: 'TV plug',
      room: 'Living Room',
      meterStatus: 'absent',
      lastVerifiedAt: 1,
      connectedAppliance: SavedAppliance(
        id: 1,
        name: 'TV',
        room: 'Living Room',
        category: 'tv',
        manufacturer: '',
        model: '',
        loadKind: 'appliance',
        onboardingMethod: 'manual',
      ),
    ),
  ];

  @override
  Future<ApplianceUsageProfile> applianceUsageProfile(
    String baseUrl,
    String token,
    int applianceId,
  ) async => ApplianceUsageProfile(
    applianceId: applianceId,
    usageKind: 'hours_per_week',
    value: hoursPerWeek,
    initialValue: 35,
    min: 0,
    max: 168,
    step: 1,
  );

  @override
  Future<ApplianceUsageProfile> updateApplianceUsageProfile(
    String baseUrl,
    String token,
    int applianceId,
    String usageKind,
    double value,
  ) async {
    hoursPerWeek = value;
    return applianceUsageProfile(baseUrl, token, applianceId);
  }
}

class _MeasuredLoadApi extends _MeteredApi {
  @override
  Future<List<SavedPlug>> saved(String baseUrl, String token) async => const [
    SavedPlug(
      id: 'meter-1',
      ip: '192.168.68.50',
      model: 'HS110',
      name: 'Office meter',
      room: 'Office',
      meterStatus: 'verified',
      localProtocol: 'legacy_tcp',
      lastVerifiedAt: 1,
      connectedAppliance: SavedAppliance(
        id: 9,
        name: 'Desk lamp',
        room: 'Office',
        category: 'lighting',
        manufacturer: 'Example',
        model: 'L1',
        loadKind: 'replaceable_bulb',
        onboardingMethod: 'manual',
        hoursPerWeek: 21,
        initialHoursPerWeek: 21,
        bulbCount: 1,
        combinedInputWatts: 10,
      ),
    ),
  ];

  @override
  Future<EnergyEstimate> estimate(
    String baseUrl,
    String token,
    int applianceId, {
    String? postalCode,
    double? rateUsdPerKwh,
  }) async => const EnergyEstimate(
    status: 'measured',
    estimatedKwh: 10,
    estimatedCostUsd: 2,
    rateUsdPerKwh: 0.2,
    rateSourceLabel: 'Your electricity rate',
    measurementCoverageFraction: 2 / 3,
  );
}

class _ManualDevicesApi extends DiscoveryApi {
  final devices = <SavedAppliance>[
    const SavedAppliance(
      id: 7,
      name: 'Desk fan',
      room: 'Office',
      category: 'fan',
      manufacturer: '',
      model: '',
      loadKind: 'appliance',
      onboardingMethod: 'manual',
    ),
    const SavedAppliance(
      id: 8,
      name: 'Photo lamp',
      room: 'Living Room',
      category: 'lighting',
      manufacturer: '',
      model: '',
      loadKind: 'integrated_lamp',
      onboardingMethod: 'photo',
    ),
  ];

  @override
  Future<List<SavedPlug>> saved(String baseUrl, String token) async => [];

  @override
  Future<List<SavedAppliance>> appliances(String baseUrl, String token) async =>
      devices;

  @override
  Future<void> deleteManualAppliance(
    String baseUrl,
    String token,
    int applianceId,
  ) async {
    final device = devices.where((item) => item.id == applianceId).first;
    if (device.onboardingMethod != 'manual' &&
        device.onboardingMethod != 'photo') {
      throw StateError('Only manually added devices can be deleted here');
    }
    devices.removeWhere((device) => device.id == applianceId);
  }
}

class _PhotoAttachedApi extends _ManualDevicesApi {
  bool attached = false;

  @override
  Future<List<SavedPlug>> saved(String baseUrl, String token) async => attached
      ? const [
          SavedPlug(
            id: 'kp115',
            ip: '192.168.1.30',
            model: 'KP115',
            name: 'KP115',
            room: '',
            meterStatus: 'verified',
            lastVerifiedAt: 1,
            connectedAppliance: SavedAppliance(
              id: 8,
              name: 'Photo lamp',
              room: 'Living Room',
              category: 'lighting',
              manufacturer: '',
              model: '',
              loadKind: 'integrated_lamp',
              onboardingMethod: 'photo',
            ),
          ),
        ]
      : [];
}

void main() {
  testWidgets('photo search is reachable from the default Ask screen', (
    tester,
  ) async {
    await tester.pumpWidget(
      MaterialApp(
        home: HomeScreen(
          api: _ManualDevicesApi(),
          credentials: _ConnectedCredentials(),
          initialTabIndex: 3,
        ),
      ),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('searchUsingPhoto')));
    await tester.pumpAndSettle();
    expect(find.text('Choose photo'), findsOneWidget);
    expect(find.text('Take photo'), findsOneWidget);
  });

  testWidgets('saved photo returns to the visible hub device list', (
    tester,
  ) async {
    await tester.pumpWidget(
      MaterialApp(
        home: HomeScreen(
          api: _ManualDevicesApi(),
          credentials: _ConnectedCredentials(),
          initialTabIndex: 3,
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.text('Photo lamp'), findsNothing);
    await tester.tap(find.byKey(const Key('searchUsingPhoto')));
    await tester.pumpAndSettle();
    Navigator.of(tester.element(find.text('Choose photo'))).pop(
      const SavedAppliance(
        id: 8,
        name: 'Photo lamp',
        room: 'Living Room',
        category: 'lighting',
        manufacturer: 'LG',
        model: 'WM3070HWA',
        loadKind: 'appliance',
        onboardingMethod: 'photo',
      ),
    );
    await tester.pumpAndSettle();
    expect(find.text('Photo lamp'), findsWidgets);
    expect(find.textContaining('Added from photo'), findsOneWidget);
  });

  testWidgets('attached photo returns through Ask & Add to Power Now', (
    tester,
  ) async {
    final api = _PhotoAttachedApi();
    await tester.pumpWidget(
      MaterialApp(
        home: HomeScreen(
          api: api,
          credentials: _ConnectedCredentials(),
          initialTabIndex: 3,
        ),
      ),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('searchUsingPhoto')));
    await tester.pumpAndSettle();
    api.attached = true;
    Navigator.of(tester.element(find.text('Choose photo'))).pop(
      const SavedPlug(
        id: 'kp115',
        ip: '192.168.1.30',
        model: 'KP115',
        name: 'KP115',
        room: '',
        meterStatus: 'verified',
        lastVerifiedAt: 1,
      ),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.text('Power Now'));
    await tester.pumpAndSettle();
    expect(find.text('Photo lamp'), findsOneWidget);
    expect(find.text('KP115'), findsOneWidget);
  });

  testWidgets('legacy local pilot reaches phone-only photo entry', (
    tester,
  ) async {
    await tester.pumpWidget(
      const MaterialApp(
        home: HomeScreen(
          localPilotMode: true,
          initialTabIndex: 3,
          startInConnectAppliance: true,
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('localPilotNotice')), findsOneWidget);
    expect(
      find.textContaining('No Cloud account is connected'),
      findsOneWidget,
    );
    await tester.ensureVisible(find.text('Identify from a photo'));
    await tester.tap(find.text('Identify from a photo'));
    await tester.pumpAndSettle();
    expect(find.text('Take photo'), findsOneWidget);
    expect(find.text('Choose photo'), findsOneWidget);
    expect(
      find.textContaining('This does not add it to a Cloud home'),
      findsOneWidget,
    );
  });

  testWidgets('discovery preview starts in Ask & Add with home navigation', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(390, 844);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await tester.pumpWidget(
      MaterialApp(
        home: HomeScreen(
          api: _ManualDevicesApi(),
          credentials: _ConnectedCredentials(),
          initialTabIndex: 3,
          startInConnectAppliance: true,
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('Ask & Add'), findsWidgets);
    expect(find.byType(NavigationBar), findsOneWidget);
    expect(find.text('Find a smart plug'), findsOneWidget);
    expect(find.text('Enter device details'), findsOneWidget);
    expect(find.text('Desk fan'), findsWidgets);

    await tester.tap(find.text('Power Now'));
    await tester.pumpAndSettle();
    expect(find.text('Find a smart plug'), findsNothing);
    expect(find.byType(NavigationBar), findsOneWidget);
  });

  testWidgets('category hours control saves and resets', (tester) async {
    final api = _HoursApi();
    tester.view.physicalSize = const Size(390, 844);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await tester.pumpWidget(
      MaterialApp(
        home: HomeScreen(api: api, credentials: _ConnectedCredentials()),
      ),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.text('Ask & Add'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Connect Appliance'));
    await tester.pumpAndSettle();
    await tester.scrollUntilVisible(
      find.byKey(const Key('appliance-profile-hours-1')),
      200,
    );
    final slider = tester.widget<Slider>(
      find.byKey(const Key('appliance-profile-hours-1')),
    );
    slider.onChangeEnd!(40);
    await tester.pumpAndSettle();
    expect(api.hoursPerWeek, 40);
    await tester.ensureVisible(
      find.byKey(const Key('reset-appliance-profile-hours-1')),
    );
    await tester.tap(find.byKey(const Key('reset-appliance-profile-hours-1')));
    await tester.pumpAndSettle();
    expect(api.hoursPerWeek, 35);
  });
  testWidgets('electricity settings are reachable from the home app bar', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(390, 844);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await tester.pumpWidget(
      MaterialApp(
        home: HomeScreen(
          api: _ConnectedApi(),
          credentials: _ConnectedCredentials(),
        ),
      ),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('openElectricitySettings')));
    await tester.pumpAndSettle();
    expect(find.text('Home profile'), findsOneWidget);
    expect(find.byKey(const Key('householdPostalCode')), findsOneWidget);
  });

  testWidgets('meter readings cost prompt opens electricity settings', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(390, 844);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await tester.pumpWidget(
      MaterialApp(
        home: HomeScreen(
          api: _MeteredApi(),
          credentials: _ConnectedCredentials(),
        ),
      ),
    );
    await tester.pumpAndSettle();
    final cta = find.byKey(const Key('setHouseholdZip'));
    await tester.scrollUntilVisible(cta, 300);
    expect(find.text('Add your home ZIP code'), findsOneWidget);
    await tester.tap(cta);
    await tester.pumpAndSettle();
    expect(find.text('Home profile'), findsOneWidget);
    expect(find.byKey(const Key('householdPostalCode')), findsOneWidget);
    expect(find.text('US ZIP code'), findsOneWidget);
  });

  testWidgets('one household ZIP prompt opens profile and clears after save', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(390, 844);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final api = _ConnectedApi(withoutRate: true);
    await tester.pumpWidget(
      MaterialApp(
        home: HomeScreen(api: api, credentials: _ConnectedCredentials()),
      ),
    );
    await tester.pumpAndSettle();
    final cta = find.byKey(const Key('setHouseholdZip'));
    await tester.scrollUntilVisible(cta, 200);
    expect(find.text('Add your home ZIP code'), findsOneWidget);
    expect(
      find.byKey(const Key('setElectricityRateFromEstimate-1')),
      findsNothing,
    );
    await tester.tap(cta);
    await tester.pumpAndSettle();
    expect(find.text('Home profile'), findsOneWidget);
    expect(find.byKey(const Key('householdPostalCode')), findsOneWidget);
    await tester.enterText(
      find.byKey(const Key('householdPostalCode')),
      '78732',
    );
    tester.testTextInput.hide();
    await tester.tap(find.text('Save settings'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 100));
    expect(
      find.text('Electricity settings saved on this hub.'),
      findsOneWidget,
    );
    await tester.pageBack();
    for (var i = 0; i < 5; i++) {
      await tester.pump(const Duration(milliseconds: 100));
    }
    expect(api.withoutRate, isFalse);
    expect(api.estimateCalls, greaterThan(1));
    final refreshedCta = find.byKey(const Key('setHouseholdZip'));
    expect(refreshedCta, findsNothing);
    expect(find.text('\$0.01'), findsOneWidget);
  });

  testWidgets(
    'saved profile ZIP does not prompt even when cost is unavailable',
    (tester) async {
      await tester.pumpWidget(
        MaterialApp(
          home: HomeScreen(
            api: _ConnectedApi(withoutRate: true, postalOnly: true),
            credentials: _ConnectedCredentials(),
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(find.byKey(const Key('setHouseholdZip')), findsNothing);
      expect(
        find.byKey(const Key('setElectricityRateFromEstimate-1')),
        findsNothing,
      );
    },
  );

  testWidgets('dismissed household ZIP prompt stays dismissed on reopen', (
    tester,
  ) async {
    final credentials = _ConnectedCredentials();
    final api = _ConnectedApi(withoutRate: true);
    Widget home() => MaterialApp(
      home: HomeScreen(api: api, credentials: credentials),
    );
    await tester.pumpWidget(home());
    await tester.pumpAndSettle();
    final dismiss = find.byKey(const Key('dismissHouseholdZip'));
    await tester.scrollUntilVisible(dismiss, 200);
    await tester.tap(dismiss);
    await tester.pumpAndSettle();
    expect(credentials.zipPromptDismissed, isTrue);
    expect(find.byKey(const Key('setHouseholdZip')), findsNothing);
    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pumpWidget(home());
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('setHouseholdZip')), findsNothing);
  });

  testWidgets('cycles control saves and resets to initial value', (
    tester,
  ) async {
    final api = _CycleApi();
    tester.view.physicalSize = const Size(390, 844);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await tester.pumpWidget(
      MaterialApp(
        home: HomeScreen(api: api, credentials: _ConnectedCredentials()),
      ),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.text('Ask & Add'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Connect Appliance'));
    await tester.pumpAndSettle();
    await tester.scrollUntilVisible(
      find.byKey(const Key('appliance-cycles-1')),
      200,
    );
    expect(find.text('Use: 4.5 cycles/week'), findsOneWidget);
    final slider = tester.widget<Slider>(
      find.byKey(const Key('appliance-cycles-1')),
    );
    slider.onChangeEnd!(6.0);
    await tester.pumpAndSettle();
    expect(api.cycles, 6.0);
    expect(find.text('Use: 6.0 cycles/week'), findsOneWidget);
    await tester.ensureVisible(
      find.byKey(const Key('reset-appliance-cycles-1')),
    );
    await tester.tap(find.byKey(const Key('reset-appliance-cycles-1')));
    await tester.pumpAndSettle();
    expect(api.cycles, 4.5);
  });
  testWidgets('lists and deletes manual and photo devices in Ask & Add', (
    tester,
  ) async {
    final api = _ManualDevicesApi();
    await tester.pumpWidget(
      MaterialApp(
        home: HomeScreen(api: api, credentials: _ConnectedCredentials()),
      ),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.text('Ask & Add'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Connect Appliance'));
    await tester.pumpAndSettle();
    await tester.scrollUntilVisible(
      find.byKey(const Key('ask-delete-appliance-7')),
      200,
    );
    expect(find.text('Desk fan'), findsWidgets);
    await tester.scrollUntilVisible(
      find.byKey(const Key('ask-delete-appliance-8')),
      200,
    );
    expect(find.text('Photo lamp'), findsWidgets);
    expect(find.byKey(const Key('ask-delete-appliance-8')), findsOneWidget);
    await tester.ensureVisible(find.byKey(const Key('ask-delete-appliance-7')));
    await tester.tap(find.byKey(const Key('ask-delete-appliance-7')));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Cancel'));
    await tester.pumpAndSettle();
    expect(api.devices, hasLength(2));
    await tester.ensureVisible(find.byKey(const Key('ask-delete-appliance-7')));
    await tester.tap(find.byKey(const Key('ask-delete-appliance-7')));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Delete'));
    await tester.pumpAndSettle();
    expect(api.devices.map((device) => device.name), ['Photo lamp']);
    expect(find.byKey(const Key('ask-delete-appliance-7')), findsNothing);
    await tester.scrollUntilVisible(
      find.byKey(const Key('ask-delete-appliance-8')),
      200,
    );
    await tester.tap(find.byKey(const Key('ask-delete-appliance-8')));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Delete'));
    await tester.pumpAndSettle();
    expect(api.devices, isEmpty);
  });

  testWidgets(
    'does not offer deletion for hub records outside manual and photo',
    (tester) async {
      final api = _ManualDevicesApi();
      api.devices.add(
        const SavedAppliance(
          id: 9,
          name: 'Discovered device',
          room: '',
          category: 'fan',
          manufacturer: '',
          model: '',
          loadKind: 'appliance',
          onboardingMethod: 'discovered',
        ),
      );
      await tester.pumpWidget(
        MaterialApp(
          home: HomeScreen(api: api, credentials: _ConnectedCredentials()),
        ),
      );
      await tester.pumpAndSettle();
      await tester.tap(find.text('Ask & Add'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Connect Appliance'));
      await tester.pumpAndSettle();
      expect(find.text('Discovered device'), findsWidgets);
      expect(find.byKey(const Key('ask-delete-appliance-9')), findsNothing);
    },
  );

  testWidgets(
    'legacy home shows disconnected state without invented readings',
    (tester) async {
      tester.view.physicalSize = const Size(390, 844);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      await tester.pumpWidget(const MaterialApp(home: HomeScreen()));
      expect(find.text('Device'), findsOneWidget);
      expect(find.text('Used today'), findsOneWidget);

      await tester.tap(find.text('Stop Waste'));
      await tester.pumpAndSettle();
      expect(find.text('Find What’s Wasting Electricity'), findsOneWidget);
      expect(find.text('No findings yet'), findsOneWidget);
      expect(find.text('Programs'), findsOneWidget);

      await tester.tap(find.text('Sleep Check'));
      await tester.pumpAndSettle();
      expect(find.text('Sleep score unavailable'), findsOneWidget);

      await tester.tap(find.text('Ask & Add'));
      await tester.pumpAndSettle();
      expect(find.text('Answers need your home’s data'), findsOneWidget);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'Sleep Check reports meter coverage without classifying activity',
    (tester) async {
      final api = _ComputerCoverageApi('collecting');
      tester.view.physicalSize = const Size(390, 844);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      await tester.pumpWidget(
        MaterialApp(
          home: HomeScreen(api: api, credentials: _ConnectedCredentials()),
        ),
      );
      await tester.pumpAndSettle();
      await tester.tap(find.text('Sleep Check'));
      await tester.pumpAndSettle();
      await tester.scrollUntilVisible(
        find.textContaining('Workstation ·'),
        200,
      );

      expect(api.requestedDevices, isNotEmpty);
      expect(api.requestedDevices.toSet(), {'computer-meter'});
      expect(
        find.textContaining('Workstation · Collecting meter history'),
        findsOneWidget,
      );
      expect(find.textContaining('2/5 covered days'), findsOneWidget);
      expect(
        find.textContaining(
          'Coverage does not identify computer activity or savings.',
        ),
        findsOneWidget,
      );
      expect(find.textContaining('active'), findsNothing);
      expect(find.textContaining('idle'), findsNothing);
      expect(find.textContaining('standby'), findsNothing);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets('shows the connected appliance with its plug in Power Now', (
    tester,
  ) async {
    await tester.pumpWidget(
      MaterialApp(
        home: HomeScreen(
          api: _ConnectedApi(),
          credentials: _ConnectedCredentials(),
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.text('Two-bulb Philips Hue White lamp'), findsOneWidget);
    expect(find.text('Living Room Lamp KS19'), findsOneWidget);
    expect(find.text('Used today'), findsOneWidget);
    expect(find.text('Wasted today'), findsOneWidget);
    expect(find.byKey(const Key('power-now-selection-action')), findsOneWidget);
    expect(find.text('Estimated on-time: \$0.27/month'), findsNothing);
  });

  testWidgets('local calendar-day meter data stays on the attached row', (
    tester,
  ) async {
    final api = _TodayMeterApi();
    await tester.pumpWidget(
      MaterialApp(
        home: HomeScreen(api: api, credentials: _ConnectedCredentials()),
      ),
    );
    await tester.pumpAndSettle();

    expect(api.requests, contains(('attached-meter', 'day', null)));
    expect(api.requests, contains(('attached-meter', 'today', null)));
    expect(api.requests, contains(('unattached-meter', 'day', null)));
    expect(
      api.requests.where(
        (request) => request.$1 == 'unattached-meter' && request.$2 == 'today',
      ),
      isEmpty,
    );
    final row = tester
        .widget<PowerNowDailyCostTable>(find.byType(PowerNowDailyCostTable))
        .rows
        .single;
    expect(row.meteredTodayUsd, 0.04);
    expect(row.meterCoverageFraction, 0.35);
    expect(row.usedTodayUsd, isNot(0.04));
  });

  testWidgets('uses fresh today meter cost when coverage reaches 80%', (
    tester,
  ) async {
    await tester.pumpWidget(
      MaterialApp(
        home: HomeScreen(
          api: _TodayMeterApi(todayCoverage: 0.8),
          credentials: _ConnectedCredentials(),
        ),
      ),
    );
    await tester.pumpAndSettle();

    final row = tester
        .widget<PowerNowDailyCostTable>(find.byType(PowerNowDailyCostTable))
        .rows
        .single;
    expect(row.usedTodayUsd, 0.04);
  });

  testWidgets('local pilot omits the cloud timezone for today metering', (
    tester,
  ) async {
    final api = _TodayMeterApi();
    await tester.pumpWidget(
      MaterialApp(
        home: HomeScreen(
          api: api,
          credentials: _ConnectedCredentials(),
          localPilotMode: true,
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(api.requests, contains(('attached-meter', 'today', null)));
  });

  testWidgets('authenticated Cloud home does not restore a global hub token', (
    tester,
  ) async {
    final api = _TodayMeterApi();
    await tester.pumpWidget(
      MaterialApp(
        home: HomeScreen(
          api: api,
          credentials: _ConnectedCredentials(),
          cloudHome: const CloudHome(
            id: 'home-1',
            name: 'Home',
            timezone: 'America/Chicago',
            countryCode: 'US',
            postalCode: '60601',
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(api.requests, isEmpty);
    expect(find.text('Two-bulb Philips Hue White lamp'), findsNothing);
  });

  testWidgets('identity drift invalidates calendar-day appliance metering', (
    tester,
  ) async {
    final api = _IdentityDriftTodayMeterApi();
    await tester.pumpWidget(
      MaterialApp(
        home: HomeScreen(api: api, credentials: _ConnectedCredentials()),
      ),
    );
    await tester.pumpAndSettle();
    final row = tester
        .widget<PowerNowDailyCostTable>(find.byType(PowerNowDailyCostTable))
        .rows
        .single;
    expect(api.requests, contains(('attached-meter', 'today', null)));
    expect(row.meteredTodayUsd, isNull);
    expect(row.meterCoverageFraction, isNull);
  });

  testWidgets('Sleep Check labels sufficient and unavailable coverage states', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(390, 844);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    for (final status in ['sufficient_meter_coverage', 'unavailable']) {
      final api = _ComputerCoverageApi(status);
      await tester.pumpWidget(
        MaterialApp(
          home: HomeScreen(api: api, credentials: _ConnectedCredentials()),
        ),
      );
      await tester.pumpAndSettle();
      await tester.tap(find.text('Sleep Check'));
      await tester.pumpAndSettle();
      final label = status == 'sufficient_meter_coverage'
          ? 'Workstation · Sufficient meter coverage'
          : 'Workstation · Meter coverage unavailable';
      await tester.scrollUntilVisible(find.text(label), 200);
      expect(find.text(label), findsOneWidget);
      expect(
        find.textContaining('computer activity or savings'),
        findsOneWidget,
      );
    }
    expect(tester.takeException(), isNull);
  });

  testWidgets('shows EPA attribution only for a verified ENERGY STAR source', (
    tester,
  ) async {
    final api = _ConnectedApi(sourceKind: 'energy_star');
    tester.view.physicalSize = const Size(390, 844);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await tester.pumpWidget(
      MaterialApp(
        home: HomeScreen(api: api, credentials: _ConnectedCredentials()),
      ),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.text('Ask & Add'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Connect Appliance'));
    await tester.pumpAndSettle();
    await tester.scrollUntilVisible(
      find.byKey(const Key('appliance-hours-1')),
      200,
    );
    expect(find.text('Estimated total: \$0.32/month'), findsOneWidget);
    expect(find.text('On-time use: \$0.27/month'), findsOneWidget);
    expect(find.text('Standby use: \$0.04/month'), findsOneWidget);
    expect(find.text('ENERGY STAR data (EPA)'), findsOneWidget);
    expect(find.text('On time: 21 hours/week'), findsOneWidget);
    final slider = tester.widget<Slider>(
      find.byKey(const Key('appliance-hours-1')),
    );
    slider.onChanged!(42);
    slider.onChangeEnd!(42);
    await tester.pumpAndSettle();
    expect(api.hours, 42);
    expect(find.text('On time: 42 hours/week'), findsOneWidget);
    expect(find.text('Estimated total: \$0.58/month'), findsOneWidget);
    await tester.ensureVisible(
      find.byKey(const Key('reset-appliance-hours-1')),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('reset-appliance-hours-1')));
    await tester.pumpAndSettle();
    expect(api.hours, 21);
    expect(find.text('On time: 21 hours/week'), findsOneWidget);
    expect(find.text('Estimated total: \$0.32/month'), findsOneWidget);
  });

  testWidgets('does not label rolling meter history as today', (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        home: HomeScreen(
          api: _MeasuredLoadApi(),
          credentials: _ConnectedCredentials(),
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.text('Desk lamp'), findsOneWidget);
    expect(find.text('Office meter'), findsOneWidget);
    expect(find.text('N/A'), findsNWidgets(2));
    expect(
      find.textContaining('observed cost during covered time'),
      findsNothing,
    );
  });

  testWidgets(
    'refreshes all hub metering protocols and clears stale connection badge',
    (tester) async {
      final api = _MultiProtocolApi();
      await tester.pumpWidget(
        MaterialApp(
          home: HomeScreen(api: api, credentials: _ConnectedCredentials()),
        ),
      );
      await tester.pumpAndSettle();
      expect(api.requested.toSet(), {'kasa', 'kasa-http', 'shelly', 'tasmota'});
      expect(find.text('HUB CONNECTED'), findsOneWidget);

      api.unavailable = true;
      await tester.pump(const Duration(seconds: 60));
      await tester.pump();
      expect(find.text('HUB DISCONNECTED'), findsOneWidget);
    },
  );

  testWidgets('refreshes saved plug status on startup and each minute', (
    tester,
  ) async {
    final api = _StatusRefreshApi();
    await tester.pumpWidget(
      MaterialApp(
        home: HomeScreen(api: api, credentials: _ConnectedCredentials()),
      ),
    );
    await tester.pumpAndSettle();
    expect(api.checks, 1);

    api.status = 'disconnected';
    await tester.pump(const Duration(seconds: 60));
    await tester.pumpAndSettle();
    expect(api.checks, 2);
    expect(find.text('Used today'), findsOneWidget);
  });

  testWidgets('labels retained daily estimates as cached during hub outage', (
    tester,
  ) async {
    final api = _OutageAfterFirstLoadApi();
    await tester.pumpWidget(
      MaterialApp(
        home: HomeScreen(api: api, credentials: _ConnectedCredentials()),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.text('\$0.01'), findsOneWidget);

    api.unavailable = true;
    await tester.pump(const Duration(seconds: 60));
    await tester.pumpAndSettle();
    expect(find.text('HUB DISCONNECTED'), findsOneWidget);
    expect(find.text('\$0.01'), findsOneWidget);
    expect(
      find.text('Hub disconnected · showing cached estimates'),
      findsOneWidget,
    );
  });

  test('preserves meter sample times, watts, and counter values', () {
    final energy = DeviceEnergy.fromJson({
      'status': 'measured',
      'period': 'day',
      'device_id': 'meter-1',
      'total_kwh': 0.1,
      'coverage_fraction': 0.5,
      'covered_secs': 43200,
      'readings': [
        {'ts': '2026-09-29T12:00:00Z', 'watts': 82, 'kwh_cumulative': 3.2},
        {'ts': '2026-09-29T12:01:00Z', 'watts': 84, 'kwh_cumulative': 3.201},
      ],
    });
    expect(energy.deviceId, 'meter-1');
    expect(energy.readingCount, 2);
    expect(energy.readings.first.ts.toUtc(), DateTime.utc(2026, 9, 29, 12));
    expect(energy.latestSample!.watts, 84);
    expect(energy.latestSample!.kwhCumulative, 3.201);
  });

  testWidgets('never converts a measured 30-day estimate to a daily amount', (
    tester,
  ) async {
    await tester.pumpWidget(
      MaterialApp(
        home: HomeScreen(
          api: _MeasuredLoadApi(),
          credentials: _ConnectedCredentials(),
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.text('Desk lamp'), findsOneWidget);
    expect(find.text('N/A'), findsNWidgets(2));
    expect(find.text('Observed last 30 days: \$2.00'), findsNothing);
  });

  testWidgets('includes standalone appliances even without a sourced cost', (
    tester,
  ) async {
    await tester.pumpWidget(
      MaterialApp(
        home: HomeScreen(
          api: _StandaloneCostApi(),
          credentials: _ConnectedCredentials(),
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.text('KitchenAid refrigerator'), findsOneWidget);
    expect(find.text('Two-bulb Philips Hue White lamp'), findsOneWidget);
    expect(find.text('N/A'), findsNWidgets(3));
    expect(find.text('Waste cost'), findsNothing);
  });

  testWidgets(
    'local Power Now visibility persists and Ask & Add restores a device',
    (tester) async {
      final store = _MemoryVisibilityStore();
      final api = _ManualDevicesApi();
      Widget app() => MaterialApp(
        home: HomeScreen(
          api: api,
          credentials: _ConnectedCredentials(),
          visibilityStore: store,
        ),
      );

      await tester.pumpWidget(app());
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('power-now-selection-action')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('power-now-select-7')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('power-now-selection-action')));
      await tester.pumpAndSettle();
      expect(find.text('Desk fan'), findsNothing);
      expect(find.text('Photo lamp'), findsOneWidget);

      await tester.tap(find.text('Ask & Add'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Connect Appliance'));
      await tester.pumpAndSettle();
      expect(find.text('Desk fan'), findsWidgets);
      await tester.ensureVisible(find.byKey(const Key('ask-show-power-now-7')));
      await tester.tap(find.byKey(const Key('ask-show-power-now-7')));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Power Now'));
      await tester.pumpAndSettle();
      expect(find.text('Desk fan'), findsOneWidget);

      await tester.tap(find.byKey(const Key('power-now-selection-action')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('power-now-select-8')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('power-now-selection-action')));
      await tester.pumpAndSettle();
      await tester.pumpWidget(const SizedBox.shrink());
      await tester.pumpWidget(app());
      await tester.pumpAndSettle();
      expect(find.text('Photo lamp'), findsNothing);
      expect(find.text('Desk fan'), findsOneWidget);

      expect(store.values[('https://100.115.133.73:18787', null)], contains(8));
    },
  );
}
