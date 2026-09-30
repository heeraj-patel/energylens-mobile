import 'dart:async';

import 'package:energylens_mobile/features/discovery/discovery_api.dart';
import 'package:energylens_mobile/features/discovery/discovery_credentials.dart';
import 'package:energylens_mobile/features/discovery/discovery_screen.dart';
import 'package:energylens_mobile/features/discovery/electricity_settings_screen.dart';
import 'package:energylens_mobile/features/discovery/device_energy_detail_screen.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

class FakeDiscoveryApi extends DiscoveryApi {
  const FakeDiscoveryApi();

  @override
  Future<ElectricitySettings> electricitySettings(
    String baseUrl,
    String token,
  ) async => const ElectricitySettings();

  @override
  Future<ElectricitySettings> updateElectricitySettings(
    String baseUrl,
    String token, {
    required String? postalCode,
    required double? rateUsdPerKwh,
  }) async =>
      ElectricitySettings(postalCode: postalCode, rateUsdPerKwh: rateUsdPerKwh);

  @override
  Future<List<DiscoveredPlug>> scan(String baseUrl, String token) async => [
    const DiscoveredPlug(
      id: 'plug-1',
      ip: '192.168.1.42',
      model: 'HS103',
      alias: 'Desk plug',
      mac: '00:31:92:43:c5:28',
      localProtocol: 'http',
      httpPort: 80,
      meterStatus: 'absent',
      relayOn: true,
    ),
  ];
}

class PersistingSettingsApi extends FakeDiscoveryApi {
  ElectricitySettings settings = const ElectricitySettings();

  @override
  Future<ElectricitySettings> electricitySettings(
    String baseUrl,
    String token,
  ) async => settings;

  @override
  Future<ElectricitySettings> updateElectricitySettings(
    String baseUrl,
    String token, {
    required String? postalCode,
    required double? rateUsdPerKwh,
  }) async {
    settings = ElectricitySettings(
      postalCode: postalCode,
      rateUsdPerKwh: rateUsdPerKwh,
    );
    return settings;
  }
}

class FakeCredentials extends DiscoveryCredentials {
  String? address;
  String? token;

  @override
  Future<StoredPairingCredential?> readPairing() async => null;

  @override
  Future<(String?, String?)> read() async => (address, token);

  @override
  Future<void> save(String address, String token) async {
    this.address = address;
    this.token = token;
  }

  @override
  Future<String?> readPostalCode() async => null;

  @override
  Future<void> savePostalCode(String postalCode) async {}
}

class OfflinePairedCredentials extends FakeCredentials {
  @override
  Future<StoredPairingCredential?> readPairing() async =>
      const StoredPairingCredential(
        address: 'https://192.168.1.20:8787#sha256=aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa',
        hubId: 'hub-1',
        clientId: 'client-1',
        token: 'issued-token',
      );
}

class OfflinePairingApi extends FakeDiscoveryApi {
  int checks = 0;

  @override
  Future<void> verifyStoredPairing(StoredHubIdentity pairing) async {
    checks++;
    throw const PairingException('Hub temporarily unavailable.');
  }
}

class SavingApi extends FakeDiscoveryApi {
  SavedPlug? plug;
  int estimateCalls = 0;
  int statusRefreshCalls = 0;
  String refreshedStatus = 'connected';
  final appliance = const SavedAppliance(
    id: 7,
    name: 'Desk lamp',
    room: 'Office',
    category: 'lighting',
    manufacturer: 'Example',
    model: 'L123',
    loadKind: 'replaceable_bulb',
    onboardingMethod: 'manual',
  );

  @override
  Future<SavedPlug> adopt(
    String baseUrl,
    String token,
    DiscoveredPlug candidate,
    String name,
    String room,
    bool acknowledgeNoMeter,
  ) async {
    expect(acknowledgeNoMeter, isTrue);
    plug = SavedPlug(
      id: candidate.id,
      ip: candidate.ip,
      model: candidate.model,
      name: name,
      room: room,
      meterStatus: candidate.meterStatus,
      lastVerifiedAt: 100,
      mac: candidate.mac,
      localProtocol: candidate.localProtocol,
      httpPort: candidate.httpPort,
    );
    return plug!;
  }

  @override
  Future<List<SavedPlug>> saved(String baseUrl, String token) async =>
      plug == null ? [] : [plug!];

  @override
  Future<SavedPlug> refreshPlugStatus(
    String baseUrl,
    String token,
    String plugId,
  ) async {
    statusRefreshCalls++;
    final before = plug!;
    expect(plugId, before.id);
    plug = SavedPlug(
      id: before.id,
      ip: before.ip,
      model: before.model,
      name: before.name,
      room: before.room,
      meterStatus: before.meterStatus,
      lastVerifiedAt: before.lastVerifiedAt,
      connectionStatus: refreshedStatus,
      statusCheckedAt: 200,
      connectedAppliance: before.connectedAppliance,
    );
    return plug!;
  }

  @override
  Future<List<SavedAppliance>> appliances(String baseUrl, String token) async =>
      [appliance];

  @override
  Future<SavedPlug> attachAppliance(
    String baseUrl,
    String token,
    String plugId,
    int applianceId,
  ) async {
    expect(plugId, 'plug-1');
    expect(applianceId, 7);
    final before = plug!;
    plug = SavedPlug(
      id: before.id,
      ip: before.ip,
      model: before.model,
      name: before.name,
      room: before.room,
      meterStatus: before.meterStatus,
      lastVerifiedAt: before.lastVerifiedAt,
      mac: before.mac,
      localProtocol: before.localProtocol,
      httpPort: before.httpPort,
      connectedAppliance: appliance,
    );
    return plug!;
  }

  @override
  Future<EnergyEstimate> estimate(
    String baseUrl,
    String token,
    int applianceId, {
    double? rateUsdPerKwh,
    String? postalCode,
  }) async {
    estimateCalls++;
    return const EnergyEstimate(status: 'no_estimate', reason: 'not_checked');
  }
}

class FailingSettingsApi extends SavingApi {
  @override
  Future<ElectricitySettings> electricitySettings(
    String baseUrl,
    String token,
  ) async => throw StateError('settings unavailable');
}

class DeviceDetailApi extends FakeDiscoveryApi {
  int estimateCalls = 0;
  final appliance = const SavedAppliance(
    id: 31,
    name: 'Desk fan',
    room: 'Office',
    category: 'fan',
    manufacturer: 'Example',
    model: 'F100',
    loadKind: 'appliance',
    onboardingMethod: 'manual',
  );

  @override
  Future<List<SavedPlug>> saved(String baseUrl, String token) async => [
    SavedPlug(
      id: 'plug-detail',
      ip: '192.168.1.42',
      model: 'HS110',
      name: 'Office meter',
      room: 'Office',
      meterStatus: 'verified',
      lastVerifiedAt: 100,
      connectedAppliance: appliance,
    ),
  ];

  @override
  Future<EnergyEstimate> estimate(
    String baseUrl,
    String token,
    int applianceId, {
    double? rateUsdPerKwh,
    String? postalCode,
  }) async {
    estimateCalls++;
    return const EnergyEstimate(
      status: 'estimated',
      estimatedKwh: 18,
      estimatedCostUsd: 3.24,
      evidence: EnergyEvidence(
        sourceKind: 'epa_exact',
        datasetId: 'epa-ratings',
        sourceUrl: 'https://example.test/fan',
        matchedBrand: 'Example',
        matchedModel: 'F100',
        annualKwh: 200,
        usageBasis: 'rated',
        retrievedAt: 1,
      ),
    );
  }

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
    totalKwh: 0.2,
    coverageFraction: 0.5,
    coveredSecs: 43200,
    latestWatts: null,
    observedCostUsd: 0.04,
    rateSourceLabel: 'Your electricity rate',
    rateUsdPerKwh: 0.2,
    rateSource: 'user',
    readingCount: 2,
  );
}

class MeasuredEstimateApi extends DeviceDetailApi {
  @override
  Future<EnergyEstimate> estimate(
    String baseUrl,
    String token,
    int applianceId, {
    double? rateUsdPerKwh,
    String? postalCode,
  }) async {
    estimateCalls++;
    return const EnergyEstimate(
      status: 'measured',
      estimatedKwh: 12.5,
      estimatedCostUsd: 4.5,
      rateSource: 'utility',
      rateUsdPerKwh: 0.36,
      rateSourceLabel: 'Texas average',
      rateAsOf: '2026-01-01',
      rateStatus: 'stale',
      isStale: true,
      measurementCoverageFraction: 0.35,
    );
  }
}

class TimestampApi extends DeviceDetailApi {
  @override
  Future<DeviceEnergy> deviceEnergy(
    String baseUrl,
    String token,
    String plugId, {
    String period = 'day',
    String? postalCode,
    double? rateUsdPerKwh,
  }) async => DeviceEnergy(
    status: 'measured',
    period: period,
    totalKwh: 0.2,
    coverageFraction: 0.5,
    coveredSecs: 43200,
    latestWatts: 42,
    readingCount: 1,
    readings: [EnergyReading(ts: DateTime.utc(2026, 9, 29, 12), watts: 42)],
  );
}

class OfflineEstimateApi extends DeviceDetailApi {
  @override
  Future<EnergyEstimate> estimate(
    String baseUrl,
    String token,
    int applianceId, {
    double? rateUsdPerKwh,
    String? postalCode,
  }) async => throw StateError('hub unavailable');
}

class PeriodRaceApi extends DeviceDetailApi {
  final day = Completer<DeviceEnergy>();

  @override
  Future<DeviceEnergy> deviceEnergy(
    String baseUrl,
    String token,
    String plugId, {
    String period = 'day',
    String? postalCode,
    double? rateUsdPerKwh,
  }) async {
    if (period == 'day') return day.future;
    return const DeviceEnergy(
      status: 'measured',
      period: 'week',
      totalKwh: 0.7,
      coverageFraction: 0.5,
      coveredSecs: 302400,
      latestWatts: 70,
      readingCount: 2,
    );
  }
}

void main() {
  testWidgets('manual IPv4 field uses decimal keyboard and accepts dotted input', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(800, 1200);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);

    await tester.pumpWidget(
      MaterialApp(home: DiscoveryScreen(api: const FakeDiscoveryApi())),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.text('Enter a plug IP address'));
    await tester.pumpAndSettle();

    final ipField = find.byKey(const Key('manualPlugIp'));
    final field = tester.widget<TextField>(ipField);
    expect(
      field.keyboardType,
      const TextInputType.numberWithOptions(decimal: true),
    );

    // Entering a complete address here exercises the same unrestricted edit
    // path used by paste; validation remains with the hub.
    await tester.enterText(ipField, '192.168.1.42');
    expect(field.controller!.text, '192.168.1.42');
  });

  test('parses explicit stale regional rate metadata and readings', () {
    final energy = DeviceEnergy.fromJson({
      'status': 'measured',
      'period': 'day',
      'total_kwh': 0.1,
      'coverage_fraction': 0.4,
      'covered_secs': 34560,
      'latest_watts': null,
      'observed_cost_usd': 0.02,
      'rate_source_label': 'Regional rate',
      'rate_status': 'stale',
      'rate_source': 'utility',
      'rate_as_of': '2026-04-01',
      'rate_fetched_at': 1775000000,
      'rate_is_stale': true,
      'readings': [
        {'ts': '2026-09-29T12:00:00Z', 'watts': 42, 'kwh_cumulative': null},
      ],
    });
    expect(energy.rateStatus, 'stale');
    expect(energy.rateIsStale, isTrue);
    expect(energy.rateAsOf, '2026-04-01');
    expect(energy.rateFetchedAt, 1775000000);
    expect(energy.readingCount, 1);
  });

  testWidgets(
    'opens measured detail with coverage and separate sourced estimate',
    (tester) async {
      tester.view.physicalSize = const Size(800, 1200);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      final credentials = FakeCredentials()
        ..address = 'https://192.168.1.20:8787'
        ..token = 'test-token';
      await tester.pumpWidget(
        MaterialApp(
          home: DiscoveryScreen(
            api: DeviceDetailApi(),
            credentials: credentials,
          ),
        ),
      );
      await tester.pumpAndSettle();
      await tester.scrollUntilVisible(
        find.text('View energy details').first,
        300,
        scrollable: find.byType(Scrollable).first,
      );
      await tester.tap(find.text('View energy details').first);
      await tester.pumpAndSettle();
      expect(find.text('Live power unavailable'), findsOneWidget);
      expect(find.text('0.200 kWh'), findsOneWidget);
      expect(find.textContaining('50% coverage'), findsOneWidget);
      expect(find.textContaining('remaining 12h'), findsOneWidget);
      expect(find.textContaining('18.0 kWh'), findsOneWidget);
      expect(find.textContaining('EPA rated energy data'), findsOneWidget);
      expect(
        find.textContaining('Older meter data is available'),
        findsOneWidget,
      );
    },
  );

  testWidgets('fetches attached estimate and labels measured month coverage', (
    tester,
  ) async {
    final api = MeasuredEstimateApi();
    await tester.pumpWidget(
      MaterialApp(
        home: DeviceEnergyDetailScreen(
          plug: SavedPlug(
            id: 'plug-detail',
            ip: '192.168.1.42',
            model: 'HS110',
            name: 'Office meter',
            room: 'Office',
            meterStatus: 'verified',
            lastVerifiedAt: 100,
            connectedAppliance: api.appliance,
          ),
          api: api,
          hubAddress: 'https://192.168.1.20:8787',
          token: 'test-token',
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(api.estimateCalls, 1);
    await tester.scrollUntilVisible(
      find.text('Measured 30-day energy · 12.5 kWh'),
      300,
      scrollable: find.byType(Scrollable).first,
    );
    expect(find.text('Measured 30-day energy · 12.5 kWh'), findsOneWidget);
    expect(
      find.text('Measurement coverage · 35% of the 30-day window'),
      findsOneWidget,
    );
    expect(
      find.textContaining('Cached regional rate from 2026-01-01'),
      findsOneWidget,
    );
  });

  testWidgets('shows the timestamp of the latest live meter sample', (
    tester,
  ) async {
    await tester.pumpWidget(
      MaterialApp(
        home: DeviceEnergyDetailScreen(
          plug: const SavedPlug(
            id: 'plug-detail',
            ip: '192.168.1.42',
            model: 'HS110',
            name: 'Office meter',
            room: 'Office',
            meterStatus: 'verified',
            lastVerifiedAt: 100,
          ),
          api: TimestampApi(),
          hubAddress: 'https://192.168.1.20:8787',
          token: 'test-token',
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('42 W'), findsOneWidget);
    expect(find.textContaining('Sampled '), findsOneWidget);
    expect(find.textContaining('Sep 29'), findsOneWidget);
  });

  testWidgets('marks a retained estimate as cached when the hub is offline', (
    tester,
  ) async {
    await tester.pumpWidget(
      MaterialApp(
        home: DeviceEnergyDetailScreen(
          plug: SavedPlug(
            id: 'plug-detail',
            ip: '192.168.1.42',
            model: 'HS110',
            name: 'Office meter',
            room: 'Office',
            meterStatus: 'verified',
            lastVerifiedAt: 100,
            connectedAppliance: DeviceDetailApi().appliance,
          ),
          api: OfflineEstimateApi(),
          hubAddress: 'https://192.168.1.20:8787',
          token: 'test-token',
          estimate: const EnergyEstimate(
            status: 'estimated',
            estimatedKwh: 18,
            estimatedCostUsd: 3.24,
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.textContaining('18.0 kWh'), findsOneWidget);
    expect(
      find.text('Could not refresh · showing cached estimate'),
      findsOneWidget,
    );
  });

  testWidgets('ignores a slower response for an earlier selected period', (
    tester,
  ) async {
    final api = PeriodRaceApi();
    await tester.pumpWidget(
      MaterialApp(
        home: DeviceEnergyDetailScreen(
          plug: const SavedPlug(
            id: 'plug-detail',
            ip: '192.168.1.42',
            model: 'HS110',
            name: 'Office meter',
            room: 'Office',
            meterStatus: 'verified',
            lastVerifiedAt: 100,
          ),
          api: api,
          hubAddress: 'https://192.168.1.20:8787',
          token: 'test-token',
        ),
      ),
    );
    await tester.pump();
    await tester.tap(find.text('Week'));
    await tester.pumpAndSettle();
    expect(find.text('0.700 kWh'), findsOneWidget);

    api.day.complete(
      const DeviceEnergy(
        status: 'measured',
        period: 'day',
        totalKwh: 0.1,
        coverageFraction: 0.5,
        coveredSecs: 43200,
        latestWatts: 10,
        readingCount: 2,
      ),
    );
    await tester.pumpAndSettle();
    expect(find.text('0.700 kWh'), findsOneWidget);
    expect(find.text('0.100 kWh'), findsNothing);
  });

  test('formats electricity rate provenance and unavailable feedback', () {
    const source = EnergyEvidence(
      sourceKind: 'epa_exact',
      datasetId: 'epa-ratings',
      sourceUrl: 'https://example.test/record',
      matchedBrand: 'Example',
      matchedModel: 'Lamp 1',
      annualKwh: 20,
      usageBasis: 'rated',
      retrievedAt: 1,
    );
    expect(energySourceLabel(source), 'Estimated · EPA rated energy data');
    expect(energySourceHeading(source), 'EPA rated energy data');
    const manufacturerTest = EnergyEvidence(
      sourceKind: 'oem_exact',
      datasetId: 'manufacturer-pdf-ratings',
      sourceUrl: 'https://example.test/model-test',
      matchedBrand: 'Example',
      matchedModel: 'Lamp 1',
      annualKwh: 20,
      usageBasis: 'rated',
      retrievedAt: 1,
    );
    expect(
      energySourceLabel(manufacturerTest),
      'Estimated · Manufacturer model test data',
    );
    expect(
      energySourceHeading(manufacturerTest),
      'Manufacturer model test data',
    );
    expect(
      energyRateDescription(
        const EnergyEstimate(
          status: 'estimated',
          rateUsdPerKwh: 0.14,
          rateSourceLabel: 'Regional utility rate',
          rateAsOf: '2026-01-01',
        ),
      ),
      'Regional utility rate: \$0.1400/kWh · 2026-01-01',
    );
    expect(
      energyRateDescription(
        const EnergyEstimate(
          status: 'estimated',
          rateUsdPerKwh: 0.14,
          rateSourceLabel: 'Regional utility rate',
          rateAsOf: '2026-01-01',
          rateStatus: 'stale',
          isStale: true,
        ),
      ),
      'Regional utility rate: \$0.1400/kWh · Cached regional rate from 2026-01-01; fresh regional rate unavailable.',
    );
    expect(
      energyRateDescription(
        const EnergyEstimate(status: 'estimated', rateStatus: 'unavailable'),
      ),
      'Regional rate unavailable. Enter your bill rate for a cost estimate.',
    );
  });

  testWidgets('saves and reloads ZIP and optional household rate', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(800, 1000);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    final api = PersistingSettingsApi();
    final credentials = FakeCredentials()
      ..address = 'https://192.168.1.20:8787'
      ..token = 'test-token';
    await tester.pumpWidget(
      MaterialApp(
        home: ElectricitySettingsScreen(api: api, credentials: credentials),
      ),
    );
    await tester.pumpAndSettle();

    await tester.scrollUntilVisible(
      find.byKey(const Key('householdPostalCode')),
      300,
      scrollable: find.byType(Scrollable).first,
    );
    await tester.enterText(
      find.byKey(const Key('householdPostalCode')),
      '78732',
    );
    await tester.ensureVisible(
      find.byKey(const Key('householdElectricityRate')),
    );
    await tester.enterText(
      find.byKey(const Key('householdElectricityRate')),
      '0.14',
    );
    await tester.ensureVisible(find.text('Save settings'));
    await tester.tap(find.text('Save settings'));
    await tester.pumpAndSettle();

    expect(api.settings.postalCode, '78732');
    expect(api.settings.rateUsdPerKwh, 0.14);
    expect(
      find.text('Electricity settings saved on this hub.'),
      findsOneWidget,
    );

    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pumpWidget(
      MaterialApp(
        home: ElectricitySettingsScreen(api: api, credentials: credentials),
      ),
    );
    await tester.pumpAndSettle();
    await tester.scrollUntilVisible(
      find.byKey(const Key('householdElectricityRate')),
      300,
      scrollable: find.byType(Scrollable).first,
    );
    expect(
      tester
          .widget<TextField>(find.byKey(const Key('householdPostalCode')))
          .controller!
          .text,
      '78732',
    );
    expect(
      tester
          .widget<TextField>(find.byKey(const Key('householdElectricityRate')))
          .controller!
          .text,
      '0.14',
    );
  });

  testWidgets('settings screen shows pending edits and validates ZIP codes', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(800, 1000);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    final api = PersistingSettingsApi()
      ..settings = const ElectricitySettings(postalCode: '78732');
    final credentials = FakeCredentials()
      ..address = 'https://192.168.1.20:8787'
      ..token = 'test-token';
    await tester.pumpWidget(
      MaterialApp(
        home: ElectricitySettingsScreen(api: api, credentials: credentials),
      ),
    );
    await tester.pumpAndSettle();
    await tester.pumpAndSettle();
    expect(find.text('Settings loaded from this hub.'), findsOneWidget);
    await tester.enterText(find.byKey(const Key('householdPostalCode')), '123');
    await tester.pump();
    expect(find.textContaining('Unsaved changes.'), findsOneWidget);
    await tester.tap(find.text('Save settings'));
    await tester.pumpAndSettle();
    expect(find.text('Enter a five-digit US ZIP code.'), findsOneWidget);
  });

  testWidgets('clears old hub devices when the hub address changes', (
    tester,
  ) async {
    final api = SavingApi()
      ..plug = const SavedPlug(
        id: 'old-plug',
        ip: '192.168.1.42',
        model: 'HS103',
        name: 'Old hub plug',
        room: 'Office',
        meterStatus: 'absent',
        lastVerifiedAt: 100,
      );
    final credentials = FakeCredentials()
      ..address = 'https://192.168.1.20:8787'
      ..token = 'test-token';
    await tester.pumpWidget(
      MaterialApp(
        home: DiscoveryScreen(api: api, credentials: credentials),
      ),
    );
    await tester.pumpAndSettle();
    await tester.scrollUntilVisible(
      find.text('Old hub plug'),
      300,
      scrollable: find.byType(Scrollable).first,
    );
    expect(find.text('Old hub plug'), findsOneWidget);

    await tester.scrollUntilVisible(
      find.text('Connection details'),
      -300,
      scrollable: find.byType(Scrollable).first,
    );
    await tester.tap(find.text('Connection details'));
    await tester.pumpAndSettle();
    await tester.enterText(
      find.byKey(const Key('hubAddress')),
      'https://192.168.1.30:8787',
    );
    await tester.pumpAndSettle();

    expect(find.text('Old hub plug'), findsNothing);
  });

  testWidgets(
    'checks a saved plug on demand and keeps meter capability separate',
    (tester) async {
      final api = SavingApi()
        ..plug = const SavedPlug(
          id: 'plug-1',
          ip: '192.168.1.42',
          model: 'HS103',
          name: 'Living room plug',
          room: 'Living room',
          meterStatus: 'absent',
          lastVerifiedAt: 100,
        );
      final credentials = FakeCredentials()
        ..address = 'https://192.168.1.20:8787'
        ..token = 'test-token';
      await tester.pumpWidget(
        MaterialApp(
          home: DiscoveryScreen(api: api, credentials: credentials),
        ),
      );
      await tester.pumpAndSettle();
      await tester.scrollUntilVisible(
        find.text('Check plug connection'),
        300,
        scrollable: find.byType(Scrollable).first,
      );
      expect(find.text('Plug connection not checked'), findsOneWidget);
      await tester.tap(find.text('Check plug connection'));
      await tester.pumpAndSettle();
      expect(api.statusRefreshCalls, 1);
      expect(find.text('Plug connected'), findsOneWidget);
      expect(find.text('No energy monitoring'), findsOneWidget);

      api.refreshedStatus = 'identity_changed';
      await tester.tap(find.text('Check plug connection'));
      await tester.pumpAndSettle();
      expect(
        find.text('Needs verification · different plug at this address'),
        findsOneWidget,
      );
      expect(find.text('No energy monitoring'), findsOneWidget);
    },
  );

  testWidgets('shows a discovered HS103 separately from its unknown load', (
    tester,
  ) async {
    await tester.pumpWidget(
      const MaterialApp(home: DiscoveryScreen(api: FakeDiscoveryApi())),
    );
    await tester.enterText(
      find.byType(TextField).at(0),
      'https://192.168.1.20:8787',
    );
    await tester.enterText(find.byType(TextField).at(1), 'test-token');
    await tester.tap(find.text('Scan for plugs'));
    await tester.pumpAndSettle();
    await tester.scrollUntilVisible(
      find.text('Desk plug'),
      220,
      scrollable: find.byType(Scrollable).first,
    );
    await tester.pumpAndSettle();
    expect(find.textContaining('No energy monitoring'), findsWidgets);
    await tester.tap(find.text('Desk plug'));
    await tester.pumpAndSettle();

    expect(find.text('Desk plug'), findsOneWidget);
    expect(find.text('MAC 00:31:92:43:c5:28'), findsOneWidget);
    expect(find.text('Local API · HTTP 80'), findsOneWidget);
    expect(find.text('Detected · No energy monitoring'), findsOneWidget);
    expect(find.text('Connected appliance or lamp'), findsOneWidget);
    expect(find.textContaining('Not identified yet'), findsOneWidget);
    expect(find.textContaining('Not saved yet'), findsOneWidget);
    expect(
      find.textContaining('Switch on · This is not a power reading'),
      findsOneWidget,
    );
  });

  testWidgets('saves a verified plug and reloads it after screen restart', (
    tester,
  ) async {
    final api = SavingApi();
    final credentials = FakeCredentials();
    await tester.pumpWidget(
      MaterialApp(
        home: DiscoveryScreen(api: api, credentials: credentials),
      ),
    );
    await tester.enterText(
      find.byType(TextField).at(0),
      'https://192.168.1.20:8787',
    );
    await tester.enterText(find.byType(TextField).at(1), 'test-token');
    await tester.tap(find.text('Scan for plugs'));
    await tester.pumpAndSettle();
    await tester.scrollUntilVisible(
      find.text('Desk plug'),
      220,
      scrollable: find.byType(Scrollable).first,
    );
    await tester.tap(find.text('Desk plug'));
    await tester.pumpAndSettle();
    await tester.ensureVisible(find.text('Save this plug'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Save this plug'));
    await tester.pumpAndSettle();
    expect(find.text('Save plug'), findsOneWidget);
    await tester.tap(find.text('I understand this plug cannot measure energy'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Save plug'));
    await tester.pumpAndSettle();
    expect(api.plug?.name, 'Desk plug');
    expect(credentials.address, 'https://192.168.1.20:8787');

    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pumpWidget(
      MaterialApp(
        home: DiscoveryScreen(api: api, credentials: credentials),
      ),
    );
    await tester.pumpAndSettle();
    await tester.scrollUntilVisible(
      find.text('Smart plug · Saved'),
      220,
      scrollable: find.byType(Scrollable).first,
    );
    expect(find.text('Smart plug · Saved'), findsOneWidget);
    expect(find.text('No energy monitoring'), findsOneWidget);
    expect(
      find.text('Not identified yet · Estimate unavailable'),
      findsOneWidget,
    );
  });

  testWidgets('links a saved appliance to the plug without making it a meter', (
    tester,
  ) async {
    final api = SavingApi();
    api.plug = const SavedPlug(
      id: 'plug-1',
      ip: '192.168.1.42',
      model: 'HS103',
      name: 'Desk plug',
      room: 'Office',
      meterStatus: 'absent',
      lastVerifiedAt: 100,
    );
    final credentials = FakeCredentials()
      ..address = 'https://192.168.1.20:8787'
      ..token = 'test-token';
    await tester.pumpWidget(
      MaterialApp(
        home: DiscoveryScreen(api: api, credentials: credentials),
      ),
    );
    await tester.pumpAndSettle();
    await tester.scrollUntilVisible(
      find.text('Identify connected appliance'),
      250,
      scrollable: find.byType(Scrollable).first,
    );
    await tester.ensureVisible(find.text('Identify connected appliance'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Identify connected appliance'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Desk lamp · lighting'));
    await tester.pumpAndSettle();
    await tester.scrollUntilVisible(
      find.text('Connected load · No live readings'),
      250,
      scrollable: find.byType(Scrollable).first,
    );
    expect(find.text('Desk lamp'), findsOneWidget);
    expect(find.text('Connected load · No live readings'), findsOneWidget);
    expect(find.text('No energy monitoring'), findsOneWidget);
    expect(find.text('Change connected appliance'), findsOneWidget);
  });

  testWidgets('retains paired hub and retry when offline on restart', (
    tester,
  ) async {
    final api = OfflinePairingApi();
    await tester.pumpWidget(
      MaterialApp(
        home: DiscoveryScreen(
          api: api,
          credentials: OfflinePairedCredentials(),
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.text('Paired hub: hub-1'), findsOneWidget);
    expect(find.text('Hub temporarily unavailable.'), findsOneWidget);
    expect(find.text('Retry hub connection'), findsOneWidget);
    expect(api.checks, 1);
    await tester.tap(find.text('Retry hub connection'));
    await tester.pumpAndSettle();
    expect(api.checks, 2);
  });
}
