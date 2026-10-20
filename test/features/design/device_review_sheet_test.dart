import 'dart:async';

import 'package:energylens_mobile/core/cloud_api/cloud_appliance.dart';
import 'package:energylens_mobile/core/cloud_api/cloud_api_client.dart';
import 'package:energylens_mobile/core/cloud_api/cloud_catalog.dart';
import 'package:energylens_mobile/core/cloud_api/cloud_energy_categories.dart';
import 'package:energylens_mobile/core/cloud_api/cloud_question.dart';
import 'package:energylens_mobile/core/cloud_api/cloud_report_delivery.dart';
import 'package:energylens_mobile/core/cloud_api/cloud_report_preview.dart';
import 'package:energylens_mobile/core/cloud_auth/cloud_auxiliary_domain_lifecycle.dart';
import 'package:energylens_mobile/features/design/device_review_sheet.dart';
import 'package:energylens_mobile/features/design/report_delivery_domain_adapter.dart';
import 'package:energylens_mobile/features/design/report_preview_domain_repository.dart';
import 'package:energylens_mobile/features/identify/onboarding_draft_store.dart';
import 'package:energylens_mobile/features/identify/onboarding_persistence_repository.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

const account = '11111111-1111-4111-8111-111111111111';
const home = '22222222-2222-4222-8222-222222222222';
const applianceId = '33333333-3333-4333-8333-333333333333';
const catalogIdA = '44444444-4444-4444-8444-444444444444';
const catalogIdB = '55555555-5555-4555-8555-555555555555';

CloudCatalogProduct catalogProduct({
  required String id,
  required String category,
  required String brand,
  required String model,
  String matchQuality = 'confirmed_exact',
}) => CloudCatalogProduct(
  id: id,
  category: category,
  brand: brand,
  fullModel: model,
  variant: null,
  region: null,
  fuel: 'electricity',
  matchQuality: matchQuality,
  facts: const [],
);

CloudQuestion choiceQuestion(
  String id,
  String prompt,
  Map<String, num> options,
) => CloudQuestion(
  id: id,
  purpose: 'onboarding',
  version: 2,
  applianceId: applianceId,
  identityRevision: 1,
  prompt: prompt,
  answerKind: 'choice',
  unit: 'hours/week',
  optional: true,
  options: [
    for (final e in options.entries)
      CloudQuestionOption(key: e.key, value: e.value),
  ],
);

class _CategoryApi implements CloudApiClient {
  _CategoryApi([this.rows = const []]);

  final List<CloudQuestion> rows;
  final submitted = <CloudAnswerCreate>[];

  @override
  Future<List<CloudQuestion>> onboardingQuestions(
    String homeId,
    String applianceId,
  ) async => rows;

  @override
  Future<List<CloudSavedAnswer>> currentQuestionAnswers(
    String homeId,
    String applianceId,
  ) async => const [];

  @override
  Future<void> submitQuestionAnswers(
    String homeId,
    List<CloudAnswerCreate> answers, {
    required String idempotencyKey,
  }) async => submitted.addAll(answers);

  @override
  Future<EnergyCategories?> energyCategories({
    String? etag,
  }) async => const EnergyCategories(
    version: 1,
    etag: '"1"',
    groups: [
      EnergyCategoryGroup(
        key: 'kitchen',
        label: 'Kitchen',
        types: [EnergyCategoryType(key: 'refrigerator', label: 'Refrigerator')],
      ),
      EnergyCategoryGroup(
        key: 'home',
        label: 'Home',
        types: [
          EnergyCategoryType(key: 'water_heater', label: 'Water Heater'),
          EnergyCategoryType(key: 'new_server_type', label: 'New server type'),
        ],
      ),
    ],
  );

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _Storage implements OnboardingDraftStorage {
  String? value;
  @override
  Future<String?> read() async => value;
  @override
  Future<void> write(String next) async => value = next;
  @override
  Future<void> clear() async => value = null;
}

class _Appliances implements OnboardingPersistenceSource {
  int creates = 0;
  int details = 0;
  int inventories = 0;
  bool failFirstCreate = false;
  Completer<CloudAppliance>? pendingCreate;
  final keys = <String>[];
  CloudApplianceCreate? input;

  CloudAppliance row(String homeId) => CloudAppliance(
    id: applianceId,
    homeId: homeId,
    name: input!.name,
    category: input!.category,
    room: input!.room,
    brand: input!.brand,
    fullModel: input!.fullModel,
    fuel: input!.fuel,
    matchQuality: input!.matchQuality,
    variant: input!.variant,
    region: input!.region,
    catalogProductId: input!.catalogProductId,
    serialNumber: input!.serialNumber,
    fccId: input!.fccId,
    icId: input!.icId,
    upc: input!.upc,
  );

  @override
  Future<CloudAppliance> create(
    String homeId,
    CloudApplianceCreate value,
    String key,
  ) async {
    creates++;
    keys.add(key);
    input = value;
    if (failFirstCreate && creates == 1) throw StateError('response lost');
    if (pendingCreate case final pending?) return pending.future;
    return row(homeId);
  }

  @override
  Future<CloudAppliance> detail(String homeId, String id) async {
    details++;
    return row(homeId);
  }

  @override
  Future<List<CloudAppliance>> inventory(String homeId) async {
    inventories++;
    return [row(homeId)];
  }

  @override
  Future<String> version(String homeId, String id) =>
      throw UnimplementedError();
  @override
  Future<void> archive(String homeId, String id, String etag, String key) =>
      throw UnimplementedError();
}

class _Reports implements ReportPreviewDomainSource {
  @override
  Future<CloudReportPreview> createReportPreview(
    String homeId,
    List<String> ids,
    Set<String> owned, {
    required String idempotencyKey,
  }) => throw UnimplementedError();
  @override
  Future<CloudReportPreview> reportPreview(
    String homeId,
    String id,
    Set<String> owned,
  ) => throw UnimplementedError();
}

class _Deliveries implements ReportDeliveryDomainSource {
  @override
  Future<CloudReportPreview> reportPreview(
    String homeId,
    String id,
    Set<String> owned,
  ) => throw UnimplementedError();
  @override
  Future<CloudReportDelivery> queueReportDelivery(
    String homeId,
    String id,
    String digest,
    List<String> recipients, {
    required String idempotencyKey,
  }) => throw UnimplementedError();
}

CloudAuxiliaryDomainLifecycle _lifecycle(
  _Storage storage,
  _Appliances source,
) => CloudAuxiliaryDomainLifecycle(
  drafts: DurableOnboardingDrafts(
    storage,
    OnboardingPersistenceRepository(source),
  ),
  reports: ReportPreviewDomainRepository(_Reports()),
  deliveries: ReportDeliveryDomainAdapter(_Deliveries()),
);

void main() {
  Future<void> open(
    WidgetTester tester,
    CloudAuxiliaryDomainLifecycle lifecycle, {
    void Function(CloudAppliance?)? onResult,
    String? initialCategory,
    String initialRoom = '',
    List<CloudCatalogProduct> catalogResults = const [],
    bool catalogSearchFailed = false,
    bool modelNotFoundOnLabel = false,
    String? serialNumber,
    String? fccId,
    String? icId,
    String? upc,
    _CategoryApi? api,
  }) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: Builder(
            builder: (context) => TextButton(
              onPressed: () async {
                final saved = await showDialog<CloudAppliance>(
                  context: context,
                  builder: (_) => DeviceReviewSheet(
                    lifecycle: lifecycle,
                    api: api ?? _CategoryApi(),
                    accountId: account,
                    homeId: home,
                    homeName: 'Lake House',
                    name: 'Fridge',
                    manufacturer: 'Acme',
                    model: 'A123',
                    serialNumber: serialNumber,
                    fccId: fccId,
                    icId: icId,
                    upc: upc,
                    initialCategory: initialCategory,
                    initialRoom: initialRoom,
                    catalogResults: catalogResults,
                    catalogSearchFailed: catalogSearchFailed,
                    modelNotFoundOnLabel: modelNotFoundOnLabel,
                  ),
                );
                onResult?.call(saved);
              },
              child: const Text('Open'),
            ),
          ),
        ),
      ),
    );
    await tester.tap(find.text('Open'));
    await tester.pumpAndSettle();
  }

  Future<void> choose(WidgetTester tester, String key, String label) async {
    await tester.ensureVisible(find.byKey(Key(key)));
    await tester.tap(find.byKey(Key(key)));
    await tester.pumpAndSettle();
    await tester.tap(find.text(label).last);
    await tester.pumpAndSettle();
  }

  testWidgets('all catalog results appear with approved match copy', (
    tester,
  ) async {
    final lifecycle = _lifecycle(_Storage(), _Appliances());
    await lifecycle.selectVerifiedHome(account, home);
    await open(
      tester,
      lifecycle,
      catalogResults: [
        catalogProduct(
          id: catalogIdA,
          category: 'refrigerator',
          brand: 'Acme',
          model: 'A123',
        ),
        catalogProduct(
          id: catalogIdB,
          category: 'water_heater',
          brand: 'Beta',
          model: 'B456',
          matchQuality: 'documented_variant_family',
        ),
      ],
    );
    expect(
      find.text('Found in catalog. Pick your model or edit below.'),
      findsOneWidget,
    );
    expect(find.text('Catalog matches'), findsOneWidget);
    expect(find.text('Acme A123'), findsOneWidget);
    expect(find.text('Beta B456'), findsOneWidget);
  });

  testWidgets('scan identifiers prefill, edit and reach Cloud identity', (
    tester,
  ) async {
    final source = _Appliances()..failFirstCreate = true;
    final storage = _Storage();
    final lifecycle = _lifecycle(storage, source);
    await lifecycle.selectVerifiedHome(account, home);
    await open(
      tester,
      lifecycle,
      serialNumber: 'ORIGINAL123',
      fccId: 'A3LWRF555',
      icId: '649E-WRF555',
      upc: '012345678905',
    );
    expect(find.text('Barcode 012345678905'), findsOneWidget);
    for (final (key, value) in [
      ('reviewSerialNumber', 'ORIGINAL123'),
      ('reviewFccId', 'A3LWRF555'),
      ('reviewIcId', '649E-WRF555'),
      ('reviewUpc', '012345678905'),
    ]) {
      expect(
        tester.widget<TextField>(find.byKey(Key(key))).controller!.text,
        value,
      );
    }
    await tester.enterText(
      find.byKey(const Key('reviewSerialNumber')),
      'CORRECTED123',
    );
    await choose(tester, 'reviewCategory', 'Kitchen');
    await choose(tester, 'reviewDeviceType', 'Refrigerator');
    await choose(tester, 'reviewEnergySource', 'Electricity');
    await tester.ensureVisible(find.byKey(const Key('reviewSave')));
    await tester.tap(find.byKey(const Key('reviewSave')));
    await tester.pumpAndSettle();
    expect(source.creates, 1);
    expect(storage.value, isNotNull);
    await tester.tap(find.byKey(const Key('reviewSave')));
    await tester.pumpAndSettle();
    expect(source.creates, 2);
    expect(source.keys, [source.keys.first, source.keys.first]);
    final identity = source.input!.toJson()['identity'] as Map<String, dynamic>;
    expect(identity['serial_number'], 'CORRECTED123');
    expect(identity['fcc_id'], 'A3LWRF555');
    expect(identity['ic_id'], '649E-WRF555');
    expect(identity['upc'], '012345678905');
    expect(storage.value, isNull);
  });

  testWidgets('catalog selection fills fields and edited values keep link', (
    tester,
  ) async {
    final source = _Appliances();
    final lifecycle = _lifecycle(_Storage(), source);
    await lifecycle.selectVerifiedHome(account, home);
    await open(
      tester,
      lifecycle,
      catalogResults: [
        catalogProduct(
          id: catalogIdB,
          category: 'water_heater',
          brand: 'Beta',
          model: 'B456',
          matchQuality: 'documented_variant_family',
        ),
      ],
    );
    await tester.tap(find.byKey(const Key('catalogProduct-$catalogIdB')));
    await tester.pumpAndSettle();
    expect(
      tester
          .widget<TextField>(find.byKey(const Key('reviewManufacturer')))
          .controller!
          .text,
      'Beta',
    );
    expect(
      tester
          .widget<TextField>(find.byKey(const Key('reviewModel')))
          .controller!
          .text,
      'B456',
    );
    expect(find.text('Water Heater'), findsOneWidget);
    await tester.enterText(
      find.byKey(const Key('reviewManufacturer')),
      'My brand',
    );
    await tester.enterText(find.byKey(const Key('reviewModel')), 'My model');
    await choose(tester, 'reviewCategory', 'Kitchen');
    await choose(tester, 'reviewDeviceType', 'Refrigerator');
    await choose(tester, 'reviewEnergySource', 'Electricity');
    await tester.ensureVisible(find.byKey(const Key('reviewSave')));
    await tester.tap(find.byKey(const Key('reviewSave')));
    await tester.pumpAndSettle();
    expect(source.input!.category, 'refrigerator');
    expect(source.input!.brand, 'My brand');
    expect(source.input!.fullModel, 'My model');
    expect(source.input!.catalogProductId, catalogIdB);
    expect(source.input!.matchQuality, 'documented_variant_family');
  });

  testWidgets('zero and failed search states allow unresolved save', (
    tester,
  ) async {
    for (final failed in [false, true]) {
      final source = _Appliances();
      final lifecycle = _lifecycle(_Storage(), source);
      await lifecycle.selectVerifiedHome(account, home);
      await open(
        tester,
        lifecycle,
        catalogSearchFailed: failed,
        modelNotFoundOnLabel: !failed,
      );
      expect(
        find.text(
          failed
              ? 'Internal Error, Try again later'
              : 'No catalog match. Check the details and save.',
        ),
        findsOneWidget,
      );
      if (!failed) {
        expect(
          find.text('No model found on the label. Enter it below.'),
          findsOneWidget,
        );
      }
      await choose(tester, 'reviewCategory', 'Kitchen');
      await choose(tester, 'reviewDeviceType', 'Refrigerator');
      await choose(tester, 'reviewEnergySource', 'Electricity');
      await tester.tap(find.byKey(const Key('reviewSave')));
      await tester.pumpAndSettle();
      expect(source.input!.catalogProductId, isNull);
      expect(source.input!.matchQuality, 'unresolved');
    }
  });

  testWidgets(
    'review requires exact category and source before owner readback',
    (tester) async {
      final source = _Appliances();
      final lifecycle = _lifecycle(_Storage(), source);
      await lifecycle.selectVerifiedHome(account, home);
      CloudAppliance? returned;
      await open(tester, lifecycle, onResult: (value) => returned = value);
      expect(find.text('Review device'), findsOneWidget);
      expect(find.text('Save to Lake House'), findsOneWidget);
      expect(
        tester
            .widget<FilledButton>(find.byKey(const Key('reviewSave')))
            .onPressed,
        isNull,
      );
      expect(source.creates, 0);
      await choose(tester, 'reviewCategory', 'Kitchen');
      await choose(tester, 'reviewDeviceType', 'Refrigerator');
      await choose(tester, 'reviewEnergySource', 'Electricity');
      await tester.tap(find.byKey(const Key('reviewSave')));
      await tester.pumpAndSettle();
      expect(source.creates, 1);
      expect(source.details, 1);
      expect(source.inventories, 1);
      expect(source.input!.category, 'refrigerator');
      expect(source.input!.fuel, 'electricity');
      expect(source.input!.name, 'Fridge');
      expect(returned?.id, applianceId);
      expect(returned?.brand, 'Acme');
      expect(
        (await lifecycle.refreshSavedAppliances(account, home))?.single.id,
        applianceId,
      );
      await expectLater(
        lifecycle.refreshSavedAppliances(account, account),
        throwsStateError,
      );
      expect(find.text('Review device'), findsNothing);
    },
  );

  testWidgets('water heater category stays selected through native review', (
    tester,
  ) async {
    final source = _Appliances();
    final lifecycle = _lifecycle(_Storage(), source);
    await lifecycle.selectVerifiedHome(account, home);
    await open(tester, lifecycle, initialCategory: 'water_heater');
    expect(find.text('Water Heater'), findsOneWidget);
    await choose(tester, 'reviewEnergySource', 'Electricity');
    await tester.tap(find.byKey(const Key('reviewSave')));
    await tester.pumpAndSettle();
    expect(source.input!.category, 'water_heater');
    expect(source.input!.fuel, 'electricity');
  });

  testWidgets('new API type and Room save as separate fields', (tester) async {
    final source = _Appliances();
    final lifecycle = _lifecycle(_Storage(), source);
    await lifecycle.selectVerifiedHome(account, home);
    await open(
      tester,
      lifecycle,
      initialCategory: 'new_server_type',
      initialRoom: 'Basement',
    );
    expect(find.text('New server type'), findsOneWidget);
    await tester.enterText(find.byKey(const Key('reviewRoom')), '  Garage  ');
    await choose(tester, 'reviewEnergySource', 'Electricity');
    await tester.tap(find.byKey(const Key('reviewSave')));
    await tester.pumpAndSettle();
    expect(source.input!.category, 'new_server_type');
    expect(source.input!.room, 'Garage');
  });

  testWidgets('uncertain save retries same draft key without fake success', (
    tester,
  ) async {
    final source = _Appliances()..failFirstCreate = true;
    final lifecycle = _lifecycle(_Storage(), source);
    await lifecycle.selectVerifiedHome(account, home);
    await open(tester, lifecycle);
    await choose(tester, 'reviewCategory', 'Kitchen');
    await choose(tester, 'reviewDeviceType', 'Refrigerator');
    await choose(tester, 'reviewEnergySource', 'Electricity');
    await tester.tap(find.byKey(const Key('reviewSave')));
    await tester.pumpAndSettle();
    expect(find.text('Review device'), findsOneWidget);
    expect(source.details, 0);
    await tester.tap(find.byKey(const Key('reviewSave')));
    await tester.pumpAndSettle();
    expect(source.keys, hasLength(2));
    expect(source.keys.first, source.keys.last);
    expect(source.details, 1);
    expect(find.text('Review device'), findsNothing);
  });

  testWidgets('sign-out during create does not display saved state', (
    tester,
  ) async {
    final source = _Appliances()..pendingCreate = Completer<CloudAppliance>();
    final lifecycle = _lifecycle(_Storage(), source);
    await lifecycle.selectVerifiedHome(account, home);
    await open(tester, lifecycle);
    await choose(tester, 'reviewCategory', 'Kitchen');
    await choose(tester, 'reviewDeviceType', 'Refrigerator');
    await choose(tester, 'reviewEnergySource', 'Electricity');
    await tester.tap(find.byKey(const Key('reviewSave')));
    await tester.pump();
    expect(source.creates, 1);
    final clearing = lifecycle.clear();
    source.pendingCreate!.complete(source.row(home));
    await clearing;
    await tester.pumpAndSettle();
    expect(find.text('Review device'), findsOneWidget);
    expect(source.details, 0);
  });

  group('usage questions step', () {
    const tvHours = 'television.hours_per_week';
    const season = 'space_heater.season_share';
    final hours = choiceQuestion(
      tvHours,
      'About how many hours a day is this TV on?',
      {'lt_1h': 3.5, '1_3h': 14, '3_5h': 28, '5_8h': 45.5, 'gt_8h': 70},
    );
    final share = choiceQuestion(
      season,
      'How much of the year do you use it?',
      {'all_year': 1, '6_months': 0.5, '3_months': 0.25, '1_month': 0.083},
    );

    Future<(CloudAppliance? Function(), _CategoryApi)> reachStep(
      WidgetTester tester,
      List<CloudQuestion> questions,
    ) async {
      final lifecycle = _lifecycle(_Storage(), _Appliances());
      await lifecycle.selectVerifiedHome(account, home);
      final api = _CategoryApi(questions);
      CloudAppliance? returned;
      await open(
        tester,
        lifecycle,
        api: api,
        onResult: (value) => returned = value,
      );
      await choose(tester, 'reviewCategory', 'Kitchen');
      await choose(tester, 'reviewDeviceType', 'Refrigerator');
      await choose(tester, 'reviewEnergySource', 'Electricity');
      await tester.tap(find.byKey(const Key('reviewSave')));
      await tester.pumpAndSettle();
      return (() => returned, api);
    }

    testWidgets('shows approved copy and options, skip answers nothing', (
      tester,
    ) async {
      final (returned, api) = await reachStep(tester, [hours]);
      expect(find.text('Review device'), findsNothing);
      expect(
        find.text('Optional: a few answers make this estimate more accurate.'),
        findsOneWidget,
      );
      expect(
        find.text('About how many hours a day is this TV on?'),
        findsOneWidget,
      );
      for (final label in [
        'Less than 1 hour',
        '1-3 hours',
        '3-5 hours',
        '5-8 hours',
        'More than 8 hours',
        'Not sure',
        'Skip',
      ]) {
        expect(find.text(label), findsOneWidget);
      }
      await tester.tap(find.byKey(const Key('skipUsageQuestions')));
      await tester.pumpAndSettle();
      expect(api.submitted, isEmpty);
      expect(returned()?.id, applianceId);
      expect(find.text('Skip'), findsNothing);
    });

    testWidgets('a choice submits the option value and closes when done', (
      tester,
    ) async {
      final (returned, api) = await reachStep(tester, [hours]);
      await tester.tap(find.text('1-3 hours'));
      await tester.pumpAndSettle();
      expect(api.submitted, hasLength(1));
      final json = api.submitted.single.toJson();
      expect(json['question_id'], tvHours);
      expect(json['status'], 'confirmed');
      expect(json['value'], 14);
      expect(returned()?.id, applianceId);
    });

    testWidgets('Not sure submits unknown and leaves other questions open', (
      tester,
    ) async {
      final (returned, api) = await reachStep(tester, [hours, share]);
      await tester.tap(find.byKey(const Key('usageOption-$season-unsure')));
      await tester.pumpAndSettle();
      final json = api.submitted.single.toJson();
      expect(json['question_id'], season);
      expect(json['status'], 'unknown');
      expect(json['value'], isNull);
      expect(returned(), isNull);
      expect(find.text('Skip'), findsOneWidget);
      await tester.tap(find.text('Skip'));
      await tester.pumpAndSettle();
      expect(api.submitted, hasLength(1));
      expect(returned()?.id, applianceId);
    });

    testWidgets('no questions for the category closes straight away', (
      tester,
    ) async {
      final (returned, api) = await reachStep(tester, const []);
      expect(returned()?.id, applianceId);
      expect(api.submitted, isEmpty);
      expect(find.text('Skip'), findsNothing);
    });

    testWidgets('questions with unlabelled options are not shown', (
      tester,
    ) async {
      final (returned, _) = await reachStep(tester, [
        choiceQuestion('x.hours_per_week', 'Unlabelled?', {'odd_key': 1}),
      ]);
      expect(find.text('Unlabelled?'), findsNothing);
      expect(returned()?.id, applianceId);
    });
  });
}
