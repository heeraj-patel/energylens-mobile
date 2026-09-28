import 'package:energylens_mobile/features/discovery/discovery_api.dart';
import 'package:energylens_mobile/features/discovery/discovery_credentials.dart';
import 'package:energylens_mobile/features/discovery/discovery_screen.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

class FakeDiscoveryApi extends DiscoveryApi {
  const FakeDiscoveryApi();

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

class FakeCredentials extends DiscoveryCredentials {
  String? address;
  String? token;

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

class SavingApi extends FakeDiscoveryApi {
  SavedPlug? plug;
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
  }) async =>
      const EnergyEstimate(status: 'no_estimate', reason: 'not_checked');
}

void main() {
  testWidgets('shows a discovered HS103 separately from its unknown load', (
    tester,
  ) async {
    await tester.pumpWidget(
      const MaterialApp(home: DiscoveryScreen(api: FakeDiscoveryApi())),
    );
    await tester.enterText(
      find.byType(TextField).at(0),
      'http://192.168.1.20:8787',
    );
    await tester.enterText(find.byType(TextField).at(1), 'test-token');
    await tester.tap(find.text('Scan for plugs'));
    await tester.pumpAndSettle();
    await tester.scrollUntilVisible(
      find.text('Smart plug'),
      220,
      scrollable: find.byType(Scrollable).first,
    );
    await tester.pumpAndSettle();

    expect(find.text('Smart plug'), findsOneWidget);
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
      'http://192.168.1.20:8787',
    );
    await tester.enterText(find.byType(TextField).at(1), 'test-token');
    await tester.tap(find.text('Scan for plugs'));
    await tester.pumpAndSettle();
    await tester.scrollUntilVisible(
      find.text('Save this plug'),
      220,
      scrollable: find.byType(Scrollable).first,
    );
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
    expect(credentials.address, 'http://192.168.1.20:8787');

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
      ..address = 'http://192.168.1.20:8787'
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
}
