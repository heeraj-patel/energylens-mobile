import 'package:energylens_mobile/features/discovery/discovery_api.dart';
import 'package:energylens_mobile/features/discovery/discovery_credentials.dart';
import 'package:energylens_mobile/main.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

class _ConnectedCredentials extends DiscoveryCredentials {
  @override
  Future<(String?, String?)> read() async =>
      ('http://100.115.133.73:18787', 'test');

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
    assert(postalCode == '78732');
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
  }) async => const DeviceEnergy(
    status: 'measured',
    period: 'day',
    totalKwh: 0.125,
    coverageFraction: 0.75,
    coveredSecs: 64800,
    latestWatts: 100,
    observedCostUsd: 0.02,
    rateSourceLabel: 'Texas average (EIA)',
  );
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
    expect(find.text('Recent meter reading · 100.0 W'), findsOneWidget);
    expect(
      find.text('0.125 kWh measured today · 75% time coverage'),
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
