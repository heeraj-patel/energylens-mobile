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

  @override
  Future<EnergyEstimate> estimate(
    String baseUrl,
    String token,
    int id, {
    double? rateUsdPerKwh,
    String? postalCode,
  }) async => const EnergyEstimate(
    status: 'no_estimate',
    estimatedKwh: null,
    estimatedCostUsd: null,
    evidence: null,
    reason: 'not_checked',
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
}

class SourceApi extends FakeApi {
  SourceApi(this.kind) {
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
  final String kind;

  EnergyEvidence get source => EnergyEvidence(
    sourceKind: kind,
    datasetId: kind == 'energy_star' ? 'rxdj-2c88' : 'curated_oem',
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
    expect(api.rows, hasLength(1));
    expect(api.rows.first.onboardingMethod, 'manual');
    expect(api.rows.first.model, 'ABC1234');
    await scrollTo(tester, find.text('No live readings'));
    expect(
      find.text('Estimate unavailable · Check energy data'),
      findsOneWidget,
    );
    expect(find.text('computer · Manually added'), findsOneWidget);
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
  });

  testWidgets('source label follows the actual EPA or OEM evidence', (
    tester,
  ) async {
    for (final kind in ['energy_star', 'oem']) {
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
      await scrollTo(tester, find.textContaining('Estimated monthly cost:'));
      expect(
        find.textContaining('Estimated monthly cost: \$2.00'),
        findsOneWidget,
      );
      final label = kind == 'energy_star'
          ? 'Estimated · ENERGY STAR data (EPA)'
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
    await scrollTo(tester, find.byKey(const Key('saveAppliance')));
    await tester.tap(find.byKey(const Key('saveAppliance')));
    await tester.pumpAndSettle();
    expect(api.rows, hasLength(1));
    expect(api.rows.first.bulbCount, 2);
    expect(api.rows.first.combinedInputWatts, 19);
    expect(api.rows.first.hoursPerWeek, 21);
  });
}
