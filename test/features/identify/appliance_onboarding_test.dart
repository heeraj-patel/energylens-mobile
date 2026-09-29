import 'dart:typed_data';

import 'package:energylens_mobile/features/discovery/discovery_api.dart';
import 'package:energylens_mobile/features/discovery/discovery_credentials.dart';
import 'package:energylens_mobile/features/identify/appliance_onboarding_screen.dart';
import 'package:energylens_mobile/features/identify/photo_capture_service.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

class FakeCredentials extends DiscoveryCredentials {
  @override
  Future<(String?, String?)> read() async =>
      ('http://192.168.1.20:8787', 'test-token');
  @override
  Future<void> save(String address, String token) async {}

  @override
  Future<String?> readPostalCode() async => null;

  @override
  Future<void> savePostalCode(String postalCode) async {}
}

class FakeApi extends DiscoveryApi {
  final rows = <SavedAppliance>[];
  final lookupStatuses = <int, String>{};

  @override
  Future<EnergyLookup> checkModel(
    String baseUrl,
    String token, {
    required String category,
    required String manufacturer,
    required String model,
  }) async => const EnergyLookup(status: 'no_match', evidence: null);

  @override
  Future<EnergyLookup> lookupEnergy(
    String baseUrl,
    String token,
    int applianceId,
  ) async {
    lookupStatuses[applianceId] = 'no_match';
    return const EnergyLookup(status: 'no_match', evidence: null);
  }

  @override
  Future<List<IdentificationCandidate>> identifyCandidates(
    String baseUrl,
    String token, {
    required String targetKind,
    String? ocrText,
    String? upc,
  }) async {
    expect(targetKind, 'appliance');
    expect(ocrText, contains('MODEL NO: ABC1234'));
    expect(upc, '123456789012');
    return const [
      IdentificationCandidate(
        manufacturer: 'Example',
        model: 'ABC1234',
        category: 'computer',
        confidence: 0.95,
        source: 'upc_exact',
        matchedKinds: ['upc'],
      ),
    ];
  }

  @override
  Future<EnergyEstimate> estimate(
    String baseUrl,
    String token,
    int id, {
    double? rateUsdPerKwh,
    String? postalCode,
  }) async => EnergyEstimate(
    status: 'no_estimate',
    estimatedKwh: null,
    estimatedCostUsd: null,
    evidence: null,
    reason: lookupStatuses[id] ?? 'not_checked',
  );

  @override
  Future<List<SavedAppliance>> appliances(String baseUrl, String token) async =>
      rows;

  @override
  Future<SavedAppliance> addAppliance(
    String baseUrl,
    String token,
    ApplianceInput input,
  ) async {
    final item = SavedAppliance(
      id: rows.length + 1,
      name: input.name,
      room: input.room,
      category: input.category,
      manufacturer: input.manufacturer,
      model: input.model,
      loadKind: input.loadKind,
      onboardingMethod: input.onboardingMethod,
      hoursPerWeek: input.hoursPerWeek,
      bulbCount: input.bulbCount,
      combinedInputWatts: input.combinedInputWatts,
    );
    rows.add(item);
    return item;
  }

  @override
  Future<void> deleteManualAppliance(
    String baseUrl,
    String token,
    int applianceId,
  ) async {
    rows.removeWhere((item) => item.id == applianceId);
  }
}

class SourceApi extends FakeApi {
  SourceApi(this.kind, {bool seedSaved = true}) {
    if (seedSaved) {
      rows.add(
        const SavedAppliance(
          id: 1,
          name: 'Office computer',
          room: 'Office',
          category: 'computer',
          manufacturer: 'Dell',
          model: 'XPS16',
          loadKind: 'appliance',
          onboardingMethod: 'manual',
        ),
      );
    }
  }
  final String kind;

  @override
  Future<EnergyLookup> checkModel(
    String baseUrl,
    String token, {
    required String category,
    required String manufacturer,
    required String model,
  }) async => EnergyLookup(status: 'matched', evidence: source);

  EnergyEvidence get source => EnergyEvidence(
    sourceKind: kind,
    datasetId: switch (kind) {
      'energy_star' => 'rxdj-2c88',
      'energy_star_archive' => 'computers_v6_2018_archive',
      'oem_family' => 'lenovo_t14_gen2_20xl_ecodeclaration_2021',
      _ => 'curated_oem',
    },
    sourceUrl: 'https://example.com/source',
    matchedBrand: 'Dell',
    matchedModel: 'XPS16',
    annualKwh: 120,
    usageBasis: 'Published annual use',
    retrievedAt: 100,
  );

  @override
  Future<EnergyLookup> lookupEnergy(
    String baseUrl,
    String token,
    int applianceId,
  ) async => EnergyLookup(status: 'matched', evidence: source);

  @override
  Future<EnergyEstimate> estimate(
    String baseUrl,
    String token,
    int id, {
    double? rateUsdPerKwh,
    String? postalCode,
  }) async => EnergyEstimate(
    status: 'estimated',
    estimatedKwh: 10,
    estimatedCostUsd: rateUsdPerKwh == null ? null : 10 * rateUsdPerKwh,
    evidence: source,
  );
}

class FakeCapture extends PhotoCaptureService {
  bool discarded = false;
  @override
  Future<CapturedPhoto?> capturePhoto() async => CapturedPhoto(
    path: '/tmp/label.jpg',
    bytes: Uint8List.fromList([1, 2, 3]),
  );
  @override
  Future<String?> extractTextHint(String path) async => 'MODEL NO: ABC1234';
  @override
  Future<String?> detectUpc(String path) async => '123456789012';
  @override
  Future<void> discard(CapturedPhoto photo) async {
    discarded = true;
  }
}

Future<void> scrollTo(
  WidgetTester tester,
  Finder finder, {
  double delta = 300,
}) async {
  await tester.scrollUntilVisible(
    finder,
    delta,
    scrollable: find.byType(Scrollable).first,
  );
  await tester.ensureVisible(finder);
  await tester.pumpAndSettle();
}

void main() {
  test('only labeled OCR model text creates a suggestion', () {
    expect(modelHintFromOcr('MODEL NO: ABC1234'), 'ABC1234');
    expect(modelHintFromOcr('SERIAL: ABC1234'), isNull);
    expect(modelHintFromOcr('MODEL:\nSERIAL: ABC1234'), isNull);
    expect(modelHintFromOcr('MODEL: NO\nMODEL NO: ABC1234'), 'ABC1234');
    expect(modelHintFromOcr(null), isNull);
  });

  testWidgets('manual appliance saves without a live-reading claim', (
    tester,
  ) async {
    final api = FakeApi();
    await tester.pumpWidget(
      MaterialApp(
        home: ApplianceOnboardingScreen(
          method: 'manual',
          api: api,
          credentials: FakeCredentials(),
        ),
      ),
    );
    await tester.pumpAndSettle();
    await scrollTo(tester, find.byKey(const Key('applianceName')));
    await tester.enterText(
      find.byKey(const Key('applianceName')),
      'Office computer',
    );
    await scrollTo(tester, find.byKey(const Key('applianceModel')));
    await tester.enterText(find.byKey(const Key('applianceModel')), 'ABC1234');
    await scrollTo(tester, find.byKey(const Key('saveAppliance')));
    await tester.tap(find.byKey(const Key('saveAppliance')));
    await tester.pumpAndSettle();
    expect(api.rows, isEmpty);
    expect(
      find.text('Check this model before saving the device.'),
      findsOneWidget,
    );
    await scrollTo(
      tester,
      find.byKey(const Key('checkModelBeforeSave')),
      delta: -250,
    );
    await tester.tap(find.byKey(const Key('checkModelBeforeSave')));
    await tester.pumpAndSettle();
    expect(find.textContaining('No exact energy model found'), findsOneWidget);
    await scrollTo(
      tester,
      find.byKey(const Key('applianceModel')),
      delta: -250,
    );
    await tester.enterText(find.byKey(const Key('applianceModel')), 'ABC1235');
    await scrollTo(tester, find.byKey(const Key('saveAppliance')));
    await tester.tap(find.byKey(const Key('saveAppliance')));
    await tester.pumpAndSettle();
    expect(api.rows, isEmpty);
    await scrollTo(
      tester,
      find.byKey(const Key('checkModelBeforeSave')),
      delta: -250,
    );
    await tester.tap(find.byKey(const Key('checkModelBeforeSave')));
    await tester.pumpAndSettle();
    await scrollTo(tester, find.byKey(const Key('saveAppliance')));
    await tester.tap(find.byKey(const Key('saveAppliance')));
    await tester.pumpAndSettle();
    expect(api.rows, hasLength(1));
    expect(api.rows.first.onboardingMethod, 'manual');
    expect(api.rows.first.model, 'ABC1235');
    await scrollTo(tester, find.text('No live readings'));
    expect(
      find.text('Estimate unavailable · No exact source model match'),
      findsOneWidget,
    );
    expect(find.text('Check energy data'), findsNothing);
    expect(find.text('computer · Manually added'), findsOneWidget);
    await scrollTo(tester, find.byKey(const Key('delete-appliance-1')));
    await tester.tap(find.byKey(const Key('delete-appliance-1')));
    await tester.pumpAndSettle();
    expect(find.text('Delete device?'), findsOneWidget);
    await tester.tap(find.text('Cancel'));
    await tester.pumpAndSettle();
    expect(api.rows, hasLength(1));
    await tester.tap(find.byKey(const Key('delete-appliance-1')));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Delete'));
    await tester.pumpAndSettle();
    expect(api.rows, isEmpty);
    expect(find.text('No appliances saved on this hub yet.'), findsOneWidget);
  });

  testWidgets('no-match energy check hides the link after reload', (
    tester,
  ) async {
    final api = FakeApi()
      ..rows.add(
        const SavedAppliance(
          id: 1,
          name: 'Office computer',
          room: 'Office',
          category: 'computer',
          manufacturer: 'Example',
          model: 'ABC1234',
          loadKind: 'appliance',
          onboardingMethod: 'manual',
        ),
      );
    Widget screen() => MaterialApp(
      home: ApplianceOnboardingScreen(
        method: 'manual',
        api: api,
        credentials: FakeCredentials(),
      ),
    );

    await tester.pumpWidget(screen());
    await tester.pumpAndSettle();
    await scrollTo(tester, find.text('Check energy data'));
    await tester.tap(find.text('Check energy data'));
    await tester.pumpAndSettle();
    expect(
      find.text('Estimate unavailable · No exact source model match'),
      findsOneWidget,
    );
    expect(find.text('Check energy data'), findsNothing);
    expect(
      find.textContaining('Try again when the hub is online'),
      findsNothing,
    );

    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pumpWidget(screen());
    await tester.pumpAndSettle();
    await scrollTo(
      tester,
      find.text('Estimate unavailable · No exact source model match'),
    );
    expect(find.text('Check energy data'), findsNothing);
  });

  testWidgets('matched manual model shows sourced energy after save', (
    tester,
  ) async {
    final api = SourceApi('oem_family', seedSaved: false);
    await tester.pumpWidget(
      MaterialApp(
        home: ApplianceOnboardingScreen(
          method: 'manual',
          api: api,
          credentials: FakeCredentials(),
        ),
      ),
    );
    await tester.pumpAndSettle();
    await scrollTo(tester, find.byKey(const Key('applianceName')));
    await tester.enterText(find.byKey(const Key('applianceName')), 'ThinkPad');
    await scrollTo(tester, find.byKey(const Key('applianceManufacturer')));
    await tester.enterText(
      find.byKey(const Key('applianceManufacturer')),
      'Lenovo',
    );
    await scrollTo(tester, find.byKey(const Key('applianceModel')));
    await tester.enterText(
      find.byKey(const Key('applianceModel')),
      '20XLS1H500',
    );
    await scrollTo(
      tester,
      find.byKey(const Key('checkModelBeforeSave')),
      delta: -250,
    );
    await tester.tap(find.byKey(const Key('checkModelBeforeSave')));
    await tester.pumpAndSettle();
    await scrollTo(tester, find.byKey(const Key('saveAppliance')));
    await tester.tap(find.byKey(const Key('saveAppliance')));
    await tester.pumpAndSettle();
    expect(api.rows, hasLength(1));
    await scrollTo(tester, find.text('Estimated monthly energy: 10.0 kWh'));
    expect(find.text('Estimated monthly energy: 10.0 kWh'), findsOneWidget);
    expect(
      find.text('Estimated · Manufacturer family test data'),
      findsOneWidget,
    );
  });

  testWidgets('photo model needs user confirmation before saving', (
    tester,
  ) async {
    final api = FakeApi();
    final capture = FakeCapture();
    await tester.pumpWidget(
      MaterialApp(
        home: ApplianceOnboardingScreen(
          method: 'photo',
          api: api,
          credentials: FakeCredentials(),
          capture: capture,
        ),
      ),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.text('Take photo'));
    await tester.pumpAndSettle();
    expect(capture.discarded, isTrue);
    await scrollTo(tester, find.byKey(const Key('photoCandidate-ABC1234')));
    expect(
      find.textContaining('Reviewed catalog · exact barcode'),
      findsOneWidget,
    );
    await tester.tap(find.byKey(const Key('photoCandidate-ABC1234')));
    await tester.pumpAndSettle();
    await scrollTo(tester, find.byKey(const Key('applianceName')));
    await tester.enterText(find.byKey(const Key('applianceName')), 'Desk lamp');
    await scrollTo(tester, find.byKey(const Key('applianceModel')));
    expect(find.widgetWithText(TextField, 'Exact model'), findsOneWidget);
    expect(find.text('ABC1234'), findsWidgets);
    await scrollTo(tester, find.byKey(const Key('saveAppliance')));
    await tester.tap(find.byKey(const Key('saveAppliance')));
    await tester.pumpAndSettle();
    expect(api.rows, isEmpty);
    await scrollTo(
      tester,
      find.text('I checked this model against the label'),
      delta: -300,
    );
    await tester.tap(find.text('I checked this model against the label'));
    await scrollTo(tester, find.byKey(const Key('saveAppliance')));
    await tester.tap(find.byKey(const Key('saveAppliance')));
    await tester.pumpAndSettle();
    expect(api.rows, hasLength(1));
    expect(api.rows.first.onboardingMethod, 'photo');
    expect(api.rows.first.model, 'ABC1234');
    expect(find.byKey(const Key('delete-appliance-1')), findsNothing);
  });

  testWidgets('source label follows the actual EPA or OEM evidence', (
    tester,
  ) async {
    for (final kind in [
      'energy_star',
      'energy_star_archive',
      'oem',
      'oem_family',
    ]) {
      await tester.pumpWidget(const SizedBox.shrink());
      await tester.pumpWidget(
        MaterialApp(
          home: ApplianceOnboardingScreen(
            method: 'manual',
            api: SourceApi(kind),
            credentials: FakeCredentials(),
          ),
        ),
      );
      await tester.pumpAndSettle();
      await scrollTo(tester, find.byKey(const Key('electricityRate')));
      await tester.enterText(find.byKey(const Key('electricityRate')), '0.20');
      await scrollTo(tester, find.text('Check energy data'));
      await tester.tap(find.text('Check energy data'));
      await tester.pumpAndSettle();
      final costLabel = kind == 'energy_star_archive'
          ? 'Historical test-profile cost'
          : kind == 'oem_family'
          ? 'Manufacturer family test-profile cost'
          : 'Estimated monthly cost';
      await scrollTo(tester, find.textContaining('$costLabel:'));
      expect(find.textContaining('$costLabel: \$2.00'), findsOneWidget);
      final label = kind == 'energy_star'
          ? 'Estimated · ENERGY STAR data (EPA)'
          : kind == 'energy_star_archive'
          ? 'Estimated · Historical ENERGY STAR data (EPA)'
          : kind == 'oem_family'
          ? 'Estimated · Manufacturer family test data'
          : 'Estimated · Manufacturer data';
      await scrollTo(tester, find.text(label));
      expect(find.text(label), findsOneWidget);
      if (kind == 'oem') {
        expect(find.text('Estimated · ENERGY STAR data (EPA)'), findsNothing);
      }
    }
  });

  testWidgets('two bulb lamp saves combined labeled watts and weekly use', (
    tester,
  ) async {
    final api = FakeApi();
    await tester.pumpWidget(
      MaterialApp(
        home: ApplianceOnboardingScreen(
          method: 'manual',
          api: api,
          credentials: FakeCredentials(),
        ),
      ),
    );
    await tester.pumpAndSettle();
    await scrollTo(tester, find.byKey(const Key('applianceName')));
    await tester.enterText(find.byKey(const Key('applianceName')), 'Hue lamp');
    await tester.tap(find.text('Computer').first);
    await tester.pumpAndSettle();
    await tester.tap(find.text('Lamp or bulb').last);
    await tester.pumpAndSettle();
    await scrollTo(tester, find.byKey(const Key('bulbCount')));
    await tester.enterText(find.byKey(const Key('bulbCount')), '2');
    await scrollTo(tester, find.byKey(const Key('combinedBulbWatts')));
    await tester.enterText(find.byKey(const Key('combinedBulbWatts')), '19');
    await scrollTo(tester, find.byKey(const Key('applianceHours')));
    await tester.enterText(find.byKey(const Key('applianceHours')), '21');
    await scrollTo(
      tester,
      find.byKey(const Key('checkModelBeforeSave')),
      delta: -250,
    );
    await tester.tap(find.byKey(const Key('checkModelBeforeSave')));
    await tester.pumpAndSettle();
    await scrollTo(tester, find.byKey(const Key('saveAppliance')));
    await tester.tap(find.byKey(const Key('saveAppliance')));
    await tester.pumpAndSettle();
    expect(api.rows, hasLength(1));
    expect(api.rows.first.bulbCount, 2);
    expect(api.rows.first.combinedInputWatts, 19);
    expect(api.rows.first.hoursPerWeek, 21);
  });
}
