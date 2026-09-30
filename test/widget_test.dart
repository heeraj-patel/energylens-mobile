import 'package:energylens_mobile/features/discovery/discovery_api.dart';
import 'package:energylens_mobile/features/discovery/discovery_credentials.dart';
import 'package:energylens_mobile/main.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

class _ConnectedCredentials extends DiscoveryCredentials {
  @override
  Future<(String?, String?)> read() async =>
      ('https://100.115.133.73:18787', 'test');

  @override
  Future<String?> readPostalCode() async => '78732';
}

class _ConnectedApi extends DiscoveryApi {
  _ConnectedApi({this.sourceKind = 'user_label'});

  final String sourceKind;
  double hours = 21;

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
    assert(applianceId == 1);
    assert(postalCode == null);
    final active = 19 * hours * 52 / 12000 * 0.1588;
    final standby = sourceKind == 'energy_star'
        ? 0.2 * 2 * (168 - hours) * 52 / 12000 * 0.1588
        : null;
    return EnergyEstimate(
      status: 'estimated',
      estimatedKwh: (active + (standby ?? 0)) / 0.1588,
      estimatedCostUsd: active + (standby ?? 0),
      activeCostUsd: active,
      standbyCostUsd: standby,
      rateUsdPerKwh: 0.1588,
      rateSourceLabel: 'Texas average (EIA, published table)',
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

class _MeteredApi extends DiscoveryApi {
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
    String? postalCode,
    double? rateUsdPerKwh,
  }) async {
    requested.add(plugId);
    return super.deviceEnergy(
      baseUrl,
      token,
      plugId,
      period: period,
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
    devices.removeWhere((device) => device.id == applianceId);
  }
}

void main() {
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
    expect(find.text('Desk fan'), findsOneWidget);

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
    expect(find.text('Electricity settings'), findsOneWidget);
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
    final cta = find.byKey(const Key('setElectricityRateFromMeterPrompt'));
    await tester.scrollUntilVisible(cta, 300);
    expect(find.text('Enter ZIP code or bill rate'), findsOneWidget);
    await tester.tap(cta);
    await tester.pumpAndSettle();
    expect(find.text('Electricity settings'), findsOneWidget);
    expect(find.byKey(const Key('householdPostalCode')), findsOneWidget);
    expect(find.text('US ZIP code'), findsOneWidget);
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
  testWidgets('deletes a manual device from Ask & Add after confirmation', (
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
    expect(find.text('Desk fan'), findsOneWidget);
    expect(find.byKey(const Key('ask-delete-appliance-8')), findsNothing);
    await tester.tap(find.byKey(const Key('ask-delete-appliance-7')));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Cancel'));
    await tester.pumpAndSettle();
    expect(api.devices, hasLength(2));
    await tester.tap(find.byKey(const Key('ask-delete-appliance-7')));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Delete'));
    await tester.pumpAndSettle();
    expect(api.devices.map((device) => device.name), ['Photo lamp']);
    expect(find.byKey(const Key('ask-delete-appliance-7')), findsNothing);
  });

  testWidgets('shows the disconnected state without invented readings', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(390, 844);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await tester.pumpWidget(const EnergyLensApp());
    expect(find.text('Hub connection needed'), findsOneWidget);
    expect(find.textContaining('Waiting for a live reading'), findsOneWidget);

    await tester.tap(find.text('Stop Waste'));
    await tester.pumpAndSettle();
    expect(find.text('Find What’s Wasting Electricity'), findsOneWidget);
    expect(find.text('No findings yet'), findsOneWidget);

    await tester.tap(find.text('Sleep Check'));
    await tester.pumpAndSettle();
    expect(find.text('Sleep score unavailable'), findsOneWidget);

    await tester.tap(find.text('Ask & Add'));
    await tester.pumpAndSettle();
    expect(find.text('Answers need your home’s data'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

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

  testWidgets('shows the connected appliance as an expandable child row', (
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
    expect(find.text('HUB CONNECTED'), findsOneWidget);
    await tester.scrollUntilVisible(
      find.text('Living Room Lamp KS19 · HS103(US)'),
      200,
    );
    expect(find.text('Two-bulb Philips Hue White lamp'), findsOneWidget);
    expect(find.text('Estimated on-time: \$0.27/month'), findsOneWidget);
    expect(find.text('Bulb ratings you entered'), findsOneWidget);
    expect(find.text('ENERGY STAR data (EPA)'), findsNothing);
    expect(
      tester
          .getSemantics(find.byKey(const Key('plug-expand-ks19')))
          .getSemanticsData()
          .flagsCollection
          .isExpanded
          .toBoolOrNull(),
      isTrue,
    );

    await tester.tap(find.byKey(const Key('plug-expand-ks19')));
    await tester.pumpAndSettle();
    expect(find.text('Two-bulb Philips Hue White lamp'), findsNothing);
    expect(find.textContaining('No energy meter'), findsOneWidget);
    expect(find.text('ESTIMATED MONTHLY COST'), findsOneWidget);
    expect(find.text('\$0.27 from 1 of 1 load'), findsOneWidget);

    await tester.tap(find.byKey(const Key('plug-expand-ks19')));
    await tester.pumpAndSettle();
    expect(find.text('Two-bulb Philips Hue White lamp'), findsOneWidget);
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
    await tester.scrollUntilVisible(
      find.text('Living Room Lamp KS19 · HS103(US)'),
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
    await tester.tap(find.byKey(const Key('reset-appliance-hours-1')));
    await tester.pumpAndSettle();
    expect(api.hours, 21);
    expect(find.text('On time: 21 hours/week'), findsOneWidget);
    expect(find.text('Estimated total: \$0.32/month'), findsOneWidget);
  });

  testWidgets('shows measured power with its actual time coverage', (
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
    await tester.scrollUntilVisible(find.text('Office meter · HS110'), 200);
    expect(
      find.text(
        'Recent meter reading · 100.0 W · sampled 2026-09-29 12:34 UTC',
      ),
      findsOneWidget,
    );
    expect(
      find.text('0.125 kWh measured in the last 24 hours · 75% time coverage'),
      findsOneWidget,
    );
    expect(
      find.text(
        '\$0.02 observed cost during covered time · Texas average (EIA)',
      ),
      findsOneWidget,
    );
    expect(find.textContaining('No energy meter'), findsNothing);
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
    expect(
      find.textContaining('Plug connected · Last checked'),
      findsOneWidget,
    );
    expect(find.textContaining('No energy meter'), findsOneWidget);

    api.status = 'disconnected';
    await tester.pump(const Duration(seconds: 60));
    await tester.pumpAndSettle();
    expect(api.checks, 2);
    expect(
      find.textContaining('Plug disconnected · Last checked'),
      findsOneWidget,
    );
    expect(find.textContaining('No energy meter'), findsOneWidget);
  });

  testWidgets('labels retained Home estimates as cached during hub outage', (
    tester,
  ) async {
    final api = _OutageAfterFirstLoadApi();
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
    await tester.scrollUntilVisible(
      find.text('Estimated on-time: \$0.27/month'),
      200,
    );
    expect(find.text('Estimated on-time: \$0.27/month'), findsOneWidget);

    api.unavailable = true;
    await tester.pump(const Duration(seconds: 60));
    await tester.pumpAndSettle();

    expect(find.text('HUB DISCONNECTED'), findsOneWidget);
    expect(find.text('Estimated on-time: \$0.27/month'), findsOneWidget);
    await tester.drag(find.byType(Scrollable).first, const Offset(0, 1000));
    await tester.pumpAndSettle();
    expect(
      find.text('Hub disconnected · showing cached estimates'),
      findsOneWidget,
    );
    expect(
      find.text(
        'These amounts were saved from the last hub refresh and may be out of date.',
      ),
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

  testWidgets('keeps measured 30-day cost separate from sourced estimates', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(390, 844);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await tester.pumpWidget(
      MaterialApp(
        home: HomeScreen(
          api: _MeasuredLoadApi(),
          credentials: _ConnectedCredentials(),
        ),
      ),
    );
    await tester.pumpAndSettle();
    await tester.scrollUntilVisible(find.text('Desk lamp'), 200);
    expect(find.text('Observed last 30 days: \$2.00'), findsOneWidget);
    expect(
      find.text('Meter readings · 67% of the last 30 days covered'),
      findsOneWidget,
    );
    expect(find.text('OBSERVED LAST 30 DAYS'), findsOneWidget);
    expect(find.text('ESTIMATED MONTHLY COST'), findsNothing);
  });
}
