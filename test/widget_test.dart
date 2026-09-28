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
  const _ConnectedApi({this.sourceKind = 'user_label'});

  final String sourceKind;

  @override
  Future<List<SavedPlug>> saved(String baseUrl, String token) async => const [
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
  }) async {
    assert(applianceId == 1);
    assert(postalCode == '78732');
    return EnergyEstimate(
      status: 'estimated',
      estimatedKwh: 1.729,
      estimatedCostUsd: 0.2745652,
      rateSourceLabel: 'Texas average (EIA, published table)',
      evidence: EnergyEvidence(
        sourceKind: sourceKind,
        datasetId: sourceKind == 'energy_star' ? 'epa_test' : 'bulb_label',
        sourceUrl: '',
        matchedBrand: 'Philips Hue',
        matchedModel: '',
        annualKwh: 20.748,
        usageBasis: 'Two bulbs, 21 hours/week',
        retrievedAt: 1,
      ),
    );
  }
}

void main() {
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
    expect(find.text('Estimated total: \$0.27/month'), findsOneWidget);
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
    expect(find.textContaining('Waiting for a live reading'), findsOneWidget);

    await tester.tap(find.byKey(const Key('plug-expand-ks19')));
    await tester.pumpAndSettle();
    expect(find.text('Two-bulb Philips Hue White lamp'), findsOneWidget);
  });

  testWidgets('shows EPA attribution only for a verified ENERGY STAR source', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(390, 844);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await tester.pumpWidget(
      MaterialApp(
        home: HomeScreen(
          api: const _ConnectedApi(sourceKind: 'energy_star'),
          credentials: _ConnectedCredentials(),
        ),
      ),
    );
    await tester.pumpAndSettle();
    await tester.scrollUntilVisible(
      find.text('Living Room Lamp KS19 · HS103(US)'),
      200,
    );
    expect(find.text('Estimated total: \$0.27/month'), findsOneWidget);
    expect(find.text('ENERGY STAR data (EPA)'), findsOneWidget);
  });
}
