import 'dart:async';

import 'package:energylens_mobile/core/cloud_api/cloud_report_preview.dart';
import 'package:energylens_mobile/core/cloud_api/cloud_report_delivery.dart';
import 'package:energylens_mobile/core/cloud_auth/cloud_auxiliary_domain_lifecycle.dart';
import 'package:energylens_mobile/features/design/report_preview_domain_repository.dart';
import 'package:energylens_mobile/features/design/report_delivery_domain_adapter.dart';
import 'package:energylens_mobile/features/identify/onboarding_draft_store.dart';
import 'package:energylens_mobile/features/identify/onboarding_persistence_repository.dart';
import 'package:flutter_test/flutter_test.dart';

const accountA = 'aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa';
const accountB = 'bbbbbbbb-bbbb-4bbb-8bbb-bbbbbbbbbbbb';
const homeA = '11111111-1111-4111-8111-111111111111';
const homeB = '22222222-2222-4222-8222-222222222222';
const previewId = '55555555-5555-4555-8555-555555555555';
const retryKey = '66666666-6666-4666-8666-666666666666';
const deliveryId = '77777777-7777-4777-8777-777777777777';
final digest = 'a' * 64;
const draft = OnboardingDraft(
  name: 'Fridge',
  category: 'refrigerator',
  brand: 'Acme',
  fullModel: 'A123',
  fuel: 'electricity',
);

class _Storage implements OnboardingDraftStorage {
  String? value;
  @override
  Future<String?> read() async => value;
  @override
  Future<void> write(String data) async => value = data;
  @override
  Future<void> clear() async => value = null;
}

class _PersistenceSource implements OnboardingPersistenceSource {
  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _ReportSource implements ReportPreviewDomainSource {
  Completer<CloudReportPreview>? pending;
  int calls = 0;
  CloudReportPreview preview(String homeId, String id) => CloudReportPreview(
    id,
    digest,
    homeId,
    DateTime.utc(2026, 10, 6),
    DateTime.utc(2027, 10, 6),
    false,
    const [],
    const [],
  );
  @override
  Future<CloudReportPreview> createReportPreview(
    String homeId,
    List<String> applianceIds,
    Set<String> ownedApplianceIds, {
    required String idempotencyKey,
  }) async => preview(homeId, previewId);
  @override
  Future<CloudReportPreview> reportPreview(
    String homeId,
    String id,
    Set<String> ownedApplianceIds,
  ) {
    calls++;
    return pending?.future ?? Future.value(preview(homeId, id));
  }
}

class _DeliverySource implements ReportDeliveryDomainSource {
  Completer<CloudReportPreview>? pendingRead;
  int reads = 0;
  int queues = 0;
  String? lastKey;
  @override
  Future<CloudReportPreview> reportPreview(
    String homeId,
    String id,
    Set<String> owned,
  ) {
    reads++;
    return pendingRead?.future ??
        Future.value(_ReportSource().preview(homeId, id));
  }

  @override
  Future<CloudReportDelivery> queueReportDelivery(
    String homeId,
    String id,
    String sha,
    List<String> recipients, {
    required String idempotencyKey,
  }) async {
    queues++;
    lastKey = idempotencyKey;
    return CloudReportDelivery(
      deliveryId,
      id,
      recipients,
      'pending',
      DateTime.utc(2026, 10, 6),
    );
  }
}

CloudAuxiliaryDomainLifecycle _lifecycle(
  _Storage storage,
  _ReportSource source, [
  _DeliverySource? deliverySource,
]) => CloudAuxiliaryDomainLifecycle(
  drafts: DurableOnboardingDrafts(
    storage,
    OnboardingPersistenceRepository(_PersistenceSource()),
  ),
  reports: ReportPreviewDomainRepository(source),
  deliveries: ReportDeliveryDomainAdapter(
    deliverySource ?? _DeliverySource(),
    now: () => DateTime.utc(2026, 10, 6),
  ),
);

void main() {
  test(
    'verified same-home restart preserves draft and operation key',
    () async {
      final storage = _Storage();
      final first = _lifecycle(storage, _ReportSource());
      expect(await first.selectVerifiedHome(accountA, homeA), isTrue);
      final key = (await first.drafts.stage(draft)).operationKey;
      final restarted = _lifecycle(storage, _ReportSource());
      expect(await restarted.selectVerifiedHome(accountA, homeA), isTrue);
      expect((await restarted.drafts.restore())?.operationKey, key);
    },
  );

  test('home, account, and sign-out transitions clear draft', () async {
    final storage = _Storage();
    final service = _lifecycle(storage, _ReportSource());
    await service.selectVerifiedHome(accountA, homeA);
    await service.drafts.stage(draft);
    await service.selectVerifiedHome(accountA, homeB);
    expect(await service.drafts.restore(), isNull);
    await service.drafts.stage(draft);
    await service.selectVerifiedHome(accountB, homeB);
    expect(await service.drafts.restore(), isNull);
    await service.drafts.stage(draft);
    await service.clear();
    expect(storage.value, isNull);
    expect(() => service.drafts.restore(), throwsStateError);
  });

  test('unowned home cannot start a report read', () async {
    final source = _ReportSource();
    final service = _lifecycle(_Storage(), source);
    await service.selectVerifiedHome(accountA, homeA);
    await expectLater(
      service.reportPreview(
        homeId: homeB,
        previewId: previewId,
        ownedApplianceIds: const {},
      ),
      throwsStateError,
    );
    expect(source.calls, 0);
  });

  test('home change and sign-out invalidate pending report reads', () async {
    final source = _ReportSource()..pending = Completer<CloudReportPreview>();
    final service = _lifecycle(_Storage(), source);
    await service.selectVerifiedHome(accountA, homeA);
    final stale = service.reportPreview(
      homeId: homeA,
      previewId: previewId,
      ownedApplianceIds: const {},
    );
    await service.selectVerifiedHome(accountA, homeB);
    source.pending!.complete(source.preview(homeA, previewId));
    expect(await stale, isNull);
    source.pending = Completer<CloudReportPreview>();
    final afterSwitch = service.reportPreview(
      homeId: homeB,
      previewId: previewId,
      ownedApplianceIds: const {},
    );
    await service.clear();
    source.pending!.complete(source.preview(homeB, previewId));
    expect(await afterSwitch, isNull);
  });

  test('delivery requires verified scope and explicit approval, preserving retry key', () async {
    final deliveries = _DeliverySource();
    final service = _lifecycle(_Storage(), _ReportSource(), deliveries);
    final preview = ReportPreviewDomainSnapshot(
      homeId: homeA,
      preview: _ReportSource().preview(homeA, previewId),
      status: ReportPreviewStatus.current,
    );
    Future<ReportDeliveryDomainResult> submit(bool approved) =>
        service.queueReportDelivery(
          preview: preview,
          explicitlyApproved: approved,
          approvedSnapshotSha256: digest,
          recipients: 'owner@example.com',
          ownedApplianceIds: const {},
          idempotencyKey: retryKey,
        );
    await expectLater(submit(true), throwsStateError);
    await service.selectVerifiedHome(accountA, homeA);
    expect((await submit(false)).status, ReportDeliveryStatus.rejected);
    expect(deliveries.reads, 0);
    expect((await submit(true)).status, ReportDeliveryStatus.queued);
    expect(deliveries.lastKey, retryKey);
  });

  test('home switch suppresses a pending delivery before queueing', () async {
    final deliveries = _DeliverySource()
      ..pendingRead = Completer<CloudReportPreview>();
    final service = _lifecycle(_Storage(), _ReportSource(), deliveries);
    await service.selectVerifiedHome(accountA, homeA);
    final preview = ReportPreviewDomainSnapshot(
      homeId: homeA,
      preview: _ReportSource().preview(homeA, previewId),
      status: ReportPreviewStatus.current,
    );
    final pending = service.queueReportDelivery(
      preview: preview,
      explicitlyApproved: true,
      approvedSnapshotSha256: digest,
      recipients: 'owner@example.com',
      ownedApplianceIds: const {},
      idempotencyKey: retryKey,
    );
    await service.selectVerifiedHome(accountA, homeB);
    deliveries.pendingRead!.complete(_ReportSource().preview(homeA, previewId));
    expect((await pending).status, ReportDeliveryStatus.contextChanged);
    expect(deliveries.queues, 0);
  });
}
