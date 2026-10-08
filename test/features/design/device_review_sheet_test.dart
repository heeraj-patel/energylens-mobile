import 'dart:async';

import 'package:energylens_mobile/core/cloud_api/cloud_appliance.dart';
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
    CloudAuxiliaryDomainLifecycle lifecycle,
  ) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: Builder(
            builder: (context) => TextButton(
              onPressed: () => showDialog<bool>(
                context: context,
                builder: (_) => DeviceReviewSheet(
                  lifecycle: lifecycle,
                  accountId: account,
                  homeId: home,
                  homeName: 'Lake House',
                  name: 'Fridge',
                  manufacturer: 'Acme',
                  model: 'A123',
                ),
              ),
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
    await tester.tap(find.byKey(Key(key)));
    await tester.pumpAndSettle();
    await tester.tap(find.text(label).last);
    await tester.pumpAndSettle();
  }

  testWidgets(
    'review requires exact category and source before owner readback',
    (tester) async {
      final source = _Appliances();
      final lifecycle = _lifecycle(_Storage(), source);
      await lifecycle.selectVerifiedHome(account, home);
      await open(tester, lifecycle);
      expect(find.text('Review device'), findsOneWidget);
      expect(find.text('Save to Lake House'), findsOneWidget);
      expect(
        tester
            .widget<FilledButton>(find.byKey(const Key('reviewSave')))
            .onPressed,
        isNull,
      );
      expect(source.creates, 0);
      await choose(tester, 'reviewCategory', 'Refrigerator');
      await choose(tester, 'reviewEnergySource', 'Electricity');
      await tester.tap(find.byKey(const Key('reviewSave')));
      await tester.pumpAndSettle();
      expect(source.creates, 1);
      expect(source.details, 1);
      expect(source.inventories, 1);
      expect(source.input!.category, 'refrigerator');
      expect(source.input!.fuel, 'electricity');
      expect(source.input!.name, 'Fridge');
      expect(find.text('Review device'), findsNothing);
    },
  );

  testWidgets('uncertain save retries same draft key without fake success', (
    tester,
  ) async {
    final source = _Appliances()..failFirstCreate = true;
    final lifecycle = _lifecycle(_Storage(), source);
    await lifecycle.selectVerifiedHome(account, home);
    await open(tester, lifecycle);
    await choose(tester, 'reviewCategory', 'Refrigerator');
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
    await choose(tester, 'reviewCategory', 'Refrigerator');
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
}
