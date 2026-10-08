import 'dart:async';
import 'dart:typed_data';

import 'package:energylens_mobile/features/discovery/discovery_api.dart';
import 'package:energylens_mobile/features/discovery/discovery_credentials.dart';
import 'package:energylens_mobile/features/identify/appliance_onboarding_screen.dart';
import 'package:energylens_mobile/features/identify/photo_capture_service.dart';
import 'package:energylens_mobile/core/cloud_api/cloud_api_client.dart';
import 'package:energylens_mobile/core/cloud_api/cloud_catalog.dart';
import 'package:energylens_mobile/core/cloud_api/cloud_home.dart';
import 'package:energylens_mobile/core/cloud_auth/cloud_auth.dart';
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

const _cloudHome = CloudHome(
  id: '11111111-1111-4111-8111-111111111111',
  name: 'Home',
  timezone: 'America/Chicago',
  countryCode: 'US',
  postalCode: '60601',
);

const _cloudConfig = CloudAuthConfig(
  issuer: 'https://issuer.example',
  audience: 'energylens-cloud',
  clientId: 'client',
  redirectUrl: 'io.energylens.app://login-callback',
  apiUrl: 'https://api.example',
);

class _CloudStore implements CloudTokenStore {
  @override
  Future<void> clear() async {}

  @override
  Future<CloudTokens?> read() async => const CloudTokens(accessToken: 'owner');

  @override
  Future<void> save(CloudTokens value) async {}
}

class _CloudAuthenticator implements CloudAuthenticator {
  @override
  Future<CloudTokens> signIn(CloudAuthConfig config) async =>
      const CloudTokens(accessToken: 'owner');

  @override
  Future<CloudTokens> refresh(
    CloudAuthConfig config,
    String refreshToken,
  ) async => const CloudTokens(accessToken: 'owner');
}

class _CatalogApi extends CloudApiClient {
  _CatalogApi({required this.fail})
    : super(
        session: CloudSession(
          config: _cloudConfig,
          store: _CloudStore(),
          authenticator: _CloudAuthenticator(),
        ),
      );

  final bool fail;

  @override
  Future<List<CloudCatalogProduct>> searchCatalogModels({
    required String brand,
    required String model,
    required String fuel,
    String? region,
  }) async {
    if (fail) throw const CloudApiException(503, 'unavailable');
    return const [];
  }
}

class FakeApi extends DiscoveryApi {
  final rows = <SavedAppliance>[];
  final lookupStatuses = <int, String>{};
  String modelCheckStatus = 'no_match';

  @override
  Future<EnergyLookup> checkModel(
    String baseUrl,
    String token, {
    required String category,
    required String manufacturer,
    required String model,
  }) async => EnergyLookup(status: modelCheckStatus, evidence: null);

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

class AttachmentRetryApi extends FakeApi {
  int createCalls = 0;
  final attachedIds = <int>[];
  final attachmentAddresses = <String>[];
  final attachmentTokens = <String>[];

  @override
  Future<SavedAppliance> addAppliance(
    String baseUrl,
    String token,
    ApplianceInput input,
  ) async {
    createCalls++;
    return super.addAppliance(baseUrl, token, input);
  }

  @override
  Future<SavedPlug> attachAppliance(
    String baseUrl,
    String token,
    String plugId,
    int applianceId,
  ) async {
    attachmentAddresses.add(baseUrl);
    attachmentTokens.add(token);
    attachedIds.add(applianceId);
    expect(plugId, 'plug-1');
    if (attachedIds.length == 1) {
      throw StateError('Hub temporarily unavailable');
    }
    return SavedPlug(
      id: plugId,
      ip: '192.168.1.30',
      model: 'Kasa',
      name: 'Desk plug',
      room: 'Office',
      meterStatus: 'verified',
      lastVerifiedAt: 1,
      connectedAppliance: rows.singleWhere((row) => row.id == applianceId),
    );
  }
}

class PhotoPlugApi extends FakeApi {
  final attachedPlugIds = <String>[];
  int createCalls = 0;
  bool failFirstAttachment = false;

  @override
  Future<List<SavedPlug>> saved(String baseUrl, String token) async => const [
    SavedPlug(
      id: 'hs103',
      ip: '192.168.1.29',
      model: 'HS103',
      name: 'HS103',
      room: '',
      meterStatus: 'absent',
      lastVerifiedAt: 1,
    ),
    SavedPlug(
      id: 'kp115',
      ip: '192.168.1.30',
      model: 'KP115',
      name: 'KP115',
      room: '',
      meterStatus: 'verified',
      lastVerifiedAt: 1,
    ),
  ];

  @override
  Future<SavedAppliance> addAppliance(
    String baseUrl,
    String token,
    ApplianceInput input,
  ) async {
    createCalls++;
    return super.addAppliance(baseUrl, token, input);
  }

  @override
  Future<SavedPlug> attachAppliance(
    String baseUrl,
    String token,
    String plugId,
    int applianceId,
  ) async {
    attachedPlugIds.add(plugId);
    if (failFirstAttachment && attachedPlugIds.length == 1) {
      throw StateError('Hub temporarily unavailable');
    }
    return SavedPlug(
      id: plugId,
      ip: '192.168.1.30',
      model: 'KP115',
      name: 'KP115',
      room: '',
      meterStatus: 'verified',
      lastVerifiedAt: 1,
      connectedAppliance: rows.singleWhere((row) => row.id == applianceId),
    );
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
      : path.endsWith('label-2.jpg')
      ? 'MODEL NO: DEF5678'
      : 'LG Electronics Inc.\n120V 60Hz\nService center\nWater supply\nMODEL NO: DEF5678';

  @override
  Future<String?> detectUpc(String path) async => null;

  @override
  Future<void> discard(CapturedPhoto photo) async {}
}

class OrientationRetryCapture extends PhotoCaptureService {
  final readPaths = <String>[];

  @override
  Future<CapturedPhoto?> capturePhoto() async => CapturedPhoto(
    path: '/tmp/label-upside-down.jpg',
    bytes: Uint8List.fromList([1, 2, 3]),
  );

  @override
  Future<String?> extractTextHint(String path) async {
    readPaths.add(path);
    return path.endsWith('label-upright.jpg')
        ? 'Manufacturer: LG\nMODEL NO: WM3070HWA'
        : null;
  }

  @override
  Future<String?> detectUpc(String path) async => null;

  @override
  Future<CapturedPhoto> rotateClockwise(CapturedPhoto photo) async =>
      CapturedPhoto(
        path: '/tmp/label-upright.jpg',
        bytes: Uint8List.fromList([4, 5, 6]),
      );

  @override
  Future<void> discard(CapturedPhoto photo) async {}
}

class RotationCandidatesCapture extends OrientationRetryCapture {
  @override
  Future<String?> extractTextHint(String path) async {
    readPaths.add(path);
    return path.endsWith('label-upright.jpg')
        ? 'Manufacturer: Samsung\nMODEL NO: WM3070HWA'
        : 'Manufacturer: LG\nMODEL NO: ABC1234';
  }
}

class RotationCandidatesApi extends FakeApi {
  final requestedOcr = <String?>[];
  final rotatedLookup = Completer<List<IdentificationCandidate>>();

  @override
  Future<List<IdentificationCandidate>> identifyCandidates(
    String baseUrl,
    String token, {
    required String targetKind,
    String? ocrText,
    String? upc,
  }) {
    requestedOcr.add(ocrText);
    if (requestedOcr.length > 1) return rotatedLookup.future;
    return Future.value(const [
      IdentificationCandidate(
        manufacturer: 'LG',
        model: 'ABC1234',
        category: 'appliance',
        confidence: 0.8,
        source: 'ocr_text',
        matchedKinds: ['ocr'],
      ),
    ]);
  }
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
  testWidgets('direct photo can save to Hub and attach selected KP115', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(800, 1200);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final api = PhotoPlugApi();
    Object? returned;
    await tester.pumpWidget(
      MaterialApp(
        home: Builder(
          builder: (context) => Scaffold(
            body: FilledButton(
              onPressed: () async {
                returned = await Navigator.of(context).push<Object>(
                  MaterialPageRoute(
                    builder: (_) => ApplianceOnboardingScreen(
                      method: 'photo',
                      api: api,
                      credentials: FakeCredentials(),
                      capture: FakeCapture(),
                      cloudHome: _cloudHome,
                      cloudApi: _CatalogApi(fail: false),
                    ),
                  ),
                );
              },
              child: const Text('Open photo'),
            ),
          ),
        ),
      ),
    );
    await tester.tap(find.text('Open photo'));
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('photoSmartPlug')), findsOneWidget);
    expect(find.byKey(const Key('hubAddress')), findsNothing);
    await tester.tap(find.text('Take photo'));
    await tester.pumpAndSettle();
    await scrollTo(tester, find.byKey(const Key('photoCandidate-ABC1234')));
    await tester.tap(find.byKey(const Key('photoCandidate-ABC1234')));
    await tester.pumpAndSettle();
    await scrollTo(tester, find.byKey(const Key('applianceName')));
    await tester.enterText(
      find.byKey(const Key('applianceName')),
      'Office lamp',
    );
    await scrollTo(
      tester,
      find.text('I checked this full model and fuel against the label'),
    );
    await tester.tap(
      find.text('I checked this full model and fuel against the label'),
    );
    await scrollTo(tester, find.byKey(const Key('photoSmartPlug')));
    await tester.tap(find.byKey(const Key('photoSmartPlug')));
    await tester.pumpAndSettle();
    await tester.tap(find.text('KP115').last);
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('hubAddress')), findsOneWidget);
    await scrollTo(tester, find.text('I checked this model against the label'));
    await tester.tap(find.text('I checked this model against the label'));
    await scrollTo(tester, find.byKey(const Key('saveAppliance')));
    await tester.tap(find.byKey(const Key('saveAppliance')));
    await tester.pumpAndSettle();

    expect(api.createCalls, 1);
    expect(api.rows.single.onboardingMethod, 'photo');
    expect(api.attachedPlugIds, ['kp115']);
    expect(returned, isA<SavedPlug>());
    expect((returned as SavedPlug).connectedAppliance?.name, 'Office lamp');
  });

  testWidgets('direct photo attachment retry does not create a second device', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(800, 1200);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final api = PhotoPlugApi()..failFirstAttachment = true;
    await tester.pumpWidget(
      MaterialApp(
        home: ApplianceOnboardingScreen(
          method: 'photo',
          api: api,
          credentials: FakeCredentials(),
          capture: FakeCapture(),
          cloudHome: _cloudHome,
          cloudApi: _CatalogApi(fail: false),
        ),
      ),
    );
    await tester.pumpAndSettle();
    await scrollTo(tester, find.byKey(const Key('photoSmartPlug')));
    await tester.tap(find.byKey(const Key('photoSmartPlug')));
    await tester.pumpAndSettle();
    await tester.tap(find.text('KP115').last);
    await tester.pumpAndSettle();
    await scrollTo(tester, find.text('Take photo'), delta: -300);
    await tester.tap(find.text('Take photo'));
    await tester.pumpAndSettle();
    await scrollTo(tester, find.byKey(const Key('photoCandidate-ABC1234')));
    await tester.tap(find.byKey(const Key('photoCandidate-ABC1234')));
    await tester.pumpAndSettle();
    await scrollTo(tester, find.byKey(const Key('applianceName')));
    await tester.enterText(
      find.byKey(const Key('applianceName')),
      'Office lamp',
    );
    await scrollTo(tester, find.text('I checked this model against the label'));
    await tester.tap(find.text('I checked this model against the label'));
    await scrollTo(tester, find.byKey(const Key('saveAppliance')));
    await tester.tap(find.byKey(const Key('saveAppliance')));
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('attachmentPendingNotice')), findsOneWidget);
    expect(api.createCalls, 1);
    await tester.tap(find.byKey(const Key('saveAppliance')));
    await tester.pumpAndSettle();
    expect(api.createCalls, 1);
    expect(api.attachedPlugIds, ['kp115', 'kp115']);
  });

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
    expect(
      manufacturerHintFromOcr(
        'LG Electronics Inc.\n120V 60Hz\nService center\nWater supply\nRegulatory notice\nMODEL NO: WM3070HWA\nSERIAL: PRIVATE8249',
      ),
      'LG',
    );
    expect(
      manufacturerHintFromOcr(
        'Manufacturer: LG\n120V 60Hz\nService center\nWater supply\nMODEL NO: WM3070HWA',
      ),
      'LG',
    );
    expect(
      manufacturerHintFromOcr(
        'LG Electronics Inc.\n120V 60Hz\nSamsung Electronics Inc.\nWater supply\nMODEL NO: WM3070HWA',
      ),
      isNull,
    );
    expect(
      manufacturerHintFromOcr(
        'Samsung\nMODEL NO: WM3070HWA\nService center\nLG Electronics Inc.',
      ),
      isNull,
    );
    expect(
      manufacturerHintFromOcr(
        'SERIAL: LG Electronics Inc.\n120V 60Hz\nService center\nWater supply\nMODEL NO: WM3070HWA',
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

  testWidgets('failed plug attachment retries the saved appliance once', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(800, 1000);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final api = AttachmentRetryApi();
    SavedPlug? returned;
    await tester.pumpWidget(
      MaterialApp(
        home: Builder(
          builder: (context) => Scaffold(
            body: FilledButton(
              onPressed: () async {
                returned = await Navigator.of(context).push<SavedPlug>(
                  MaterialPageRoute(
                    builder: (_) => ApplianceOnboardingScreen(
                      method: 'manual',
                      plugId: 'plug-1',
                      api: api,
                      credentials: FakeCredentials(),
                    ),
                  ),
                );
              },
              child: const Text('Identify plug'),
            ),
          ),
        ),
      ),
    );
    await tester.tap(find.text('Identify plug'));
    await tester.pumpAndSettle();
    await scrollTo(tester, find.byKey(const Key('applianceName')));
    await tester.enterText(find.byKey(const Key('applianceName')), 'Desk lamp');
    await scrollTo(tester, find.byKey(const Key('checkModelBeforeSave')));
    await tester.tap(find.byKey(const Key('checkModelBeforeSave')));
    await tester.pumpAndSettle();
    await scrollTo(tester, find.byKey(const Key('saveAppliance')));
    await tester.tap(find.byKey(const Key('saveAppliance')));
    await tester.pumpAndSettle();

    expect(api.createCalls, 1);
    expect(api.rows, hasLength(1));
    expect(api.lookupStatuses[1], 'no_match');
    expect(api.attachedIds, [1]);
    expect(returned, isNull);
    expect(find.byKey(const Key('attachmentPendingNotice')), findsOneWidget);
    expect(
      find.textContaining('Device saved, attachment pending'),
      findsWidgets,
    );
    expect(find.text('Retry attachment'), findsOneWidget);

    // Changed details cannot turn an attachment retry into another create.
    await scrollTo(tester, find.byKey(const Key('applianceName')), delta: -300);
    await tester.enterText(
      find.byKey(const Key('applianceName')),
      'Edited lamp',
    );
    await scrollTo(tester, find.byKey(const Key('hubAddress')));
    await tester.enterText(
      find.byKey(const Key('hubAddress')),
      'https://other-hub',
    );
    await scrollTo(tester, find.byKey(const Key('saveAppliance')));
    await tester.tap(find.byKey(const Key('saveAppliance')));
    await tester.pumpAndSettle();
    expect(api.createCalls, 1);
    expect(api.attachedIds, [1]);
    expect(
      find.textContaining('original plug and hub address'),
      findsOneWidget,
    );

    await scrollTo(tester, find.byKey(const Key('hubAddress')), delta: -300);
    await tester.enterText(
      find.byKey(const Key('hubAddress')),
      'https://192.168.1.20:8787',
    );
    await scrollTo(tester, find.byKey(const Key('hubToken')));
    await tester.enterText(
      find.byKey(const Key('hubToken')),
      'replacement-token',
    );
    await scrollTo(tester, find.byKey(const Key('saveAppliance')));
    await tester.tap(find.byKey(const Key('saveAppliance')));
    await tester.pumpAndSettle();

    expect(api.createCalls, 1);
    expect(api.rows, hasLength(1));
    expect(api.rows.single.name, 'Desk lamp');
    expect(api.attachedIds, [1, 1]);
    expect(api.attachmentAddresses, everyElement('https://192.168.1.20:8787'));
    expect(api.attachmentTokens.last, 'replacement-token');
    expect(returned?.connectedAppliance?.id, 1);
    expect(find.text('Identify plug'), findsOneWidget);
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

  testWidgets('manual model miss offers an explicit unreviewed web search', (
    tester,
  ) async {
    final api = FakeApi();
    Uri? launchedUri;
    await tester.pumpWidget(
      MaterialApp(
        home: ApplianceOnboardingScreen(
          method: 'manual',
          api: api,
          credentials: FakeCredentials(),
          webSearchLauncher: (uri) async {
            launchedUri = uri;
            return true;
          },
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
    expect(
      find.textContaining('External search results are unreviewed'),
      findsOneWidget,
    );
    await tester.tap(find.byKey(const Key('searchWebForModel')));
    await tester.pumpAndSettle();
    expect(launchedUri, isNotNull);
    expect(launchedUri!.host, 'www.google.com');
    expect(launchedUri!.queryParameters.keys, {'q'});
    expect(launchedUri!.queryParameters['q'], 'computer LG DLGX5171');
  });

  testWidgets('source unavailable still offers a manual web search', (
    tester,
  ) async {
    final api = FakeApi()..modelCheckStatus = 'source_unavailable';
    Uri? launchedUri;
    await tester.pumpWidget(
      MaterialApp(
        home: ApplianceOnboardingScreen(
          method: 'manual',
          api: api,
          credentials: FakeCredentials(),
          webSearchLauncher: (uri) async {
            launchedUri = uri;
            return true;
          },
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
    expect(find.text('Search web'), findsOneWidget);
    await tester.tap(find.byKey(const Key('searchWebForModel')));
    await tester.pumpAndSettle();
    expect(launchedUri?.queryParameters['q'], 'computer LG DLGX5171');
  });

  for (final fails in [false, true]) {
    testWidgets(
      'empty or unavailable reviewed catalog offers unreviewed web search (fails: $fails)',
      (tester) async {
        Uri? launchedUri;
        await tester.pumpWidget(
          MaterialApp(
            home: ApplianceOnboardingScreen(
              method: 'manual',
              cloudHome: _cloudHome,
              cloudApi: _CatalogApi(fail: fails),
              webSearchLauncher: (uri) async {
                launchedUri = uri;
                return true;
              },
            ),
          ),
        );
        await tester.pumpAndSettle();
        await scrollTo(tester, find.byKey(const Key('applianceManufacturer')));
        await tester.enterText(
          find.byKey(const Key('applianceManufacturer')),
          'LG',
        );
        await tester.enterText(
          find.byKey(const Key('applianceModel')),
          'DLGX5171',
        );
        await scrollTo(tester, find.byKey(const Key('searchReviewedCatalog')));
        await tester.tap(find.byKey(const Key('searchReviewedCatalog')));
        await tester.pumpAndSettle();
        expect(find.byKey(const Key('catalogMessage')), findsOneWidget);
        await scrollTo(tester, find.byKey(const Key('searchWebForModel')));
        expect(find.byKey(const Key('searchWebForModel')), findsOneWidget);
        expect(
          find.textContaining('External search results are unreviewed'),
          findsOneWidget,
        );
        await tester.tap(find.byKey(const Key('searchWebForModel')));
        await tester.pumpAndSettle();
        expect(launchedUri?.queryParameters.keys, {'q'});
        expect(launchedUri?.queryParameters['q'], 'computer LG DLGX5171');
      },
    );
  }

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
    expect(capture.discarded, isFalse);
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

  testWidgets('rotating a photo updates its preview and reruns OCR', (
    tester,
  ) async {
    final capture = OrientationRetryCapture();
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
    expect(capture.readPaths, ['/tmp/label-upside-down.jpg']);
    expect(
      (tester.widget<Image>(find.byKey(const Key('photoPreview'))).image
              as MemoryImage)
          .bytes,
      [1, 2, 3],
    );

    await tester.tap(find.byTooltip('Rotate photo'));
    await tester.pumpAndSettle();
    expect(capture.readPaths, [
      '/tmp/label-upside-down.jpg',
      '/tmp/label-upright.jpg',
    ]);
    expect(
      (tester.widget<Image>(find.byKey(const Key('photoPreview'))).image
              as MemoryImage)
          .bytes,
      [4, 5, 6],
    );
    await scrollTo(tester, find.byKey(const Key('applianceManufacturer')));
    expect(
      tester
          .widget<TextField>(find.byKey(const Key('applianceManufacturer')))
          .controller!
          .text,
      'LG',
    );
    expect(
      tester
          .widget<TextField>(find.byKey(const Key('applianceModel')))
          .controller!
          .text,
      'WM3070HWA',
    );
  });

  testWidgets(
    'rotation replaces old hints before new candidate lookup returns',
    (tester) async {
      final capture = RotationCandidatesCapture();
      final api = RotationCandidatesApi();
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
      await scrollTo(tester, find.byKey(const Key('photoCandidate-ABC1234')));
      expect(find.byKey(const Key('photoCandidate-ABC1234')), findsOneWidget);

      await scrollTo(tester, find.byTooltip('Rotate photo'), delta: -300);
      await tester.tap(find.byTooltip('Rotate photo'));
      await tester.pumpAndSettle();
      expect(api.requestedOcr, ['MODEL NO: ABC1234', 'MODEL NO: WM3070HWA']);
      expect(find.byKey(const Key('photoCandidate-ABC1234')), findsNothing);
      await scrollTo(tester, find.byKey(const Key('applianceManufacturer')));
      expect(
        tester
            .widget<TextField>(find.byKey(const Key('applianceManufacturer')))
            .controller!
            .text,
        'Samsung',
      );
      expect(
        tester
            .widget<TextField>(find.byKey(const Key('applianceModel')))
            .controller!
            .text,
        'WM3070HWA',
      );

      api.rotatedLookup.complete(const [
        IdentificationCandidate(
          manufacturer: 'Samsung',
          model: 'WM3070HWA',
          category: 'appliance',
          confidence: 0.9,
          source: 'ocr_text',
          matchedKinds: ['ocr'],
        ),
      ]);
      await tester.pumpAndSettle();
      await scrollTo(tester, find.byTooltip('Rotate photo'), delta: -300);
      await scrollTo(tester, find.byKey(const Key('photoCandidate-WM3070HWA')));
      expect(find.byKey(const Key('photoCandidate-WM3070HWA')), findsOneWidget);
    },
  );

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
    expect(
      find.textContaining('Maker suggested from label: LG'),
      findsOneWidget,
    );
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
