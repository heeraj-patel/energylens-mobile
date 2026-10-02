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
      ('https://192.168.1.20:8787', 'test-token');
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
    expect(ocrText, 'MODEL NO: ABC1234');
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
      'energuide_family' => 'energuide_historical_family_tests',
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
  }) async {
    expect(rateUsdPerKwh, isNull);
    expect(postalCode, isNull);
    return EnergyEstimate(
      status: 'estimated',
      estimatedKwh: 10,
      estimatedCostUsd: 2,
      evidence: source,
    );
  }
}

class FakeCapture extends PhotoCaptureService {
  bool discarded = false;
  @override
  Future<CapturedPhoto?> capturePhoto() async => CapturedPhoto(
    path: '/tmp/label.jpg',
    bytes: Uint8List.fromList([1, 2, 3]),
  );
  @override
  Future<String?> extractTextHint(String path) async =>
      'Manufacturer: LG  Serial: PRIVATE123\nMODEL NO: ABC1234';
  @override
  Future<String?> detectUpc(String path) async => '123456789012';
  @override
  Future<void> discard(CapturedPhoto photo) async {
    discarded = true;
  }
}

class RetakeCapture extends PhotoCaptureService {
  int captures = 0;

  @override
  Future<CapturedPhoto?> capturePhoto() async {
    captures++;
    return CapturedPhoto(
      path: '/tmp/label-$captures.jpg',
      bytes: Uint8List.fromList([1, 2, 3]),
    );
  }

  @override
  Future<String?> extractTextHint(String path) async =>
      path.endsWith('label-1.jpg')
      ? 'Manufacturer: LG\nMODEL NO: ABC1234'
      : 'MODEL NO: DEF5678';

  @override
  Future<String?> detectUpc(String path) async => null;

  @override
  Future<void> discard(CapturedPhoto photo) async {}
}

class NoCandidatesApi extends FakeApi {
  @override
  Future<List<IdentificationCandidate>> identifyCandidates(
    String baseUrl,
    String token, {
    required String targetKind,
    String? ocrText,
    String? upc,
  }) async => const [];
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
    expect(
      manufacturerHintFromOcr(
        'LG Electronics\nMODEL NO: WM3070HWA\nSERIAL: 8249',
      ),
      'LG',
    );
    expect(
      manufacturerHintFromOcr(
        'Manufacturer: LG  Serial: 8249\nMODEL: WM3070HWA',
      ),
      'LG',
    );
    expect(manufacturerHintFromOcr('MODEL: WM3070HWA\nSERIAL: LG8249'), isNull);
    expect(
      manufacturerHintFromOcr('LG\nMODEL NO: WM3070HWA\nSERIAL: PRIVATE8249'),
      'LG',
    );
    expect(
      manufacturerHintFromOcr(
        'LG\nSafety instructions\nService center\nMODEL NO: WM3070HWA',
      ),
      isNull,
    );
    expect(manufacturerHintFromOcr('Samsung\nLG\nMODEL NO: WM3070HWA'), isNull);
    expect(manufacturerHintFromOcr('LG\nSERIAL: PRIVATE8249'), isNull);
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
    expect(find.textContaining('No energy rating was found'), findsOneWidget);
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
    await scrollTo(tester, find.byKey(const Key('delete-appliance-1')));
    await tester.tap(find.byKey(const Key('delete-appliance-1')));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Delete'));
    await tester.pumpAndSettle();
    expect(api.rows, isEmpty);
    expect(find.text('No appliances saved on this hub yet.'), findsOneWidget);
  });

  testWidgets('standalone save returns the saved appliance to its caller', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(800, 1000);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final api = FakeApi();
    SavedAppliance? returned;
    await tester.pumpWidget(
      MaterialApp(
        home: Builder(
          builder: (context) => Scaffold(
            body: Column(
              children: [
                const Text('Ask & Add'),
                FilledButton(
                  onPressed: () async {
                    returned = await Navigator.of(context).push<SavedAppliance>(
                      MaterialPageRoute(
                        builder: (_) => ApplianceOnboardingScreen(
                          method: 'manual',
                          api: api,
                          credentials: FakeCredentials(),
                          capture: FakeCapture(),
                        ),
                      ),
                    );
                  },
                  child: const Text('Open onboarding'),
                ),
              ],
            ),
          ),
        ),
      ),
    );
    await tester.tap(find.text('Open onboarding'));
    await tester.pumpAndSettle();
    await scrollTo(tester, find.byKey(const Key('applianceName')));
    await tester.enterText(find.byKey(const Key('applianceName')), 'Desk lamp');
    await scrollTo(tester, find.byKey(const Key('checkModelBeforeSave')));
    await tester.tap(find.byKey(const Key('checkModelBeforeSave')));
    await tester.pumpAndSettle();
    await scrollTo(tester, find.byKey(const Key('saveAppliance')), delta: 650);
    await tester.tap(find.byKey(const Key('saveAppliance')));
    await tester.pumpAndSettle();

    expect(find.text('Ask & Add'), findsOneWidget);
    expect(returned, isNotNull);
    expect(returned!.name, 'Desk lamp');
    expect(returned!.id, 1);
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
    await scrollTo(
      tester,
      find.textContaining('Manufacturer family test-profile cost:'),
    );
    expect(find.textContaining('\$2.00 · 10.0 kWh'), findsOneWidget);
    expect(
      find.text('Estimated · Manufacturer family test data'),
      findsOneWidget,
    );
  });

  testWidgets('manual model miss offers a web search with clear rating copy', (
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
    await tester.enterText(find.byKey(const Key('applianceName')), 'Dryer');
    await scrollTo(tester, find.byKey(const Key('applianceManufacturer')));
    await tester.enterText(
      find.byKey(const Key('applianceManufacturer')),
      'LG',
    );
    await tester.enterText(find.byKey(const Key('applianceModel')), 'DLGX5171');
    await scrollTo(tester, find.byKey(const Key('checkModelBeforeSave')));
    await tester.tap(find.byKey(const Key('checkModelBeforeSave')));
    await tester.pumpAndSettle();

    expect(find.textContaining('No energy rating was found'), findsOneWidget);
    expect(find.text('Search web'), findsOneWidget);
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
    expect(
      find.textContaining('Maker suggested from label: LG'),
      findsOneWidget,
    );
    await scrollTo(tester, find.byKey(const Key('applianceManufacturer')));
    final makerField = tester.widget<TextField>(
      find.byKey(const Key('applianceManufacturer')),
    );
    expect(makerField.controller!.text, 'LG');
    expect(find.textContaining('PRIVATE123'), findsNothing);
    await scrollTo(
      tester,
      find.byKey(const Key('photoCandidate-ABC1234')),
      delta: -300,
    );
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
    expect(api.lookupStatuses[api.rows.first.id], 'no_match');
    expect(find.byKey(const Key('delete-appliance-1')), findsNothing);
  });

  testWidgets('retaking a photo clears only the prior maker suggestion', (
    tester,
  ) async {
    final capture = RetakeCapture();
    await tester.pumpWidget(
      MaterialApp(
        home: ApplianceOnboardingScreen(
          method: 'photo',
          api: NoCandidatesApi(),
          credentials: FakeCredentials(),
          capture: capture,
        ),
      ),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.text('Take photo'));
    await tester.pumpAndSettle();
    await scrollTo(tester, find.byKey(const Key('applianceManufacturer')));
    final maker = tester
        .widget<TextField>(find.byKey(const Key('applianceManufacturer')))
        .controller!;
    expect(maker.text, 'LG');
    await scrollTo(tester, find.text('Take photo'), delta: -300);
    await tester.tap(find.text('Take photo'));
    await tester.pumpAndSettle();
    expect(maker.text, isEmpty);
    expect(find.textContaining('Maker suggested from label:'), findsNothing);

    await scrollTo(tester, find.byKey(const Key('applianceManufacturer')));
    await tester.enterText(
      find.byKey(const Key('applianceManufacturer')),
      'Bosch',
    );
    await scrollTo(tester, find.text('Take photo'), delta: -300);
    await tester.tap(find.text('Take photo'));
    await tester.pumpAndSettle();
    expect(maker.text, 'Bosch');
  });

  testWidgets('source label follows the actual EPA or OEM evidence', (
    tester,
  ) async {
    for (final kind in [
      'energy_star',
      'energy_star_archive',
      'oem',
      'oem_family',
      'energuide_family',
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
      await scrollTo(tester, find.text('Check energy data'));
      await tester.tap(find.text('Check energy data'));
      await tester.pumpAndSettle();
      final costLabel = kind == 'energy_star_archive'
          ? 'Historical test-profile cost'
          : kind == 'oem_family'
          ? 'Manufacturer family test-profile cost'
          : kind == 'energuide_family'
          ? 'Historical EnerGuide family test-profile cost'
          : 'Estimated monthly cost';
      await scrollTo(tester, find.textContaining('$costLabel:'));
      expect(find.textContaining('$costLabel: \$2.00'), findsOneWidget);
      final label = kind == 'energy_star'
          ? 'Estimated · ENERGY STAR data (EPA)'
          : kind == 'energy_star_archive'
          ? 'Estimated · Historical ENERGY STAR data (EPA)'
          : kind == 'oem_family'
          ? 'Estimated · Manufacturer family test data'
          : kind == 'energuide_family'
          ? 'Estimated · Historical EnerGuide family test data'
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
