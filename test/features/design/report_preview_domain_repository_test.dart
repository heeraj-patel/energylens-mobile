import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:energylens_mobile/core/cloud_api/cloud_report_preview.dart';
import 'package:energylens_mobile/features/design/report_preview_domain_repository.dart';

const homeA = '11111111-1111-4111-8111-111111111111';
const homeB = '22222222-2222-4222-8222-222222222222';
const applianceId = '33333333-3333-4333-8333-333333333333';
const previewId = '55555555-5555-4555-8555-555555555555';
final hashA = 'a' * 64;
final hashB = 'b' * 64;
final now = DateTime.utc(2026, 10, 6);

CloudReportPreview preview({
  String home = homeA,
  String? hash,
  bool stale = false,
  DateTime? expires,
  String id = previewId,
  CloudReportDeliveryStatus? latestDelivery,
}) => CloudReportPreview(
  id,
  hash ?? hashA,
  home,
  now.subtract(const Duration(minutes: 1)),
  expires ?? now.add(const Duration(hours: 1)),
  stale,
  const [],
  const [],
  latestDelivery: latestDelivery,
);

class Source implements ReportPreviewDomainSource {
  CloudReportPreview? createResult;
  Future<CloudReportPreview> Function(String, String, Set<String>)? fetchResult;
  String? fetchedHome;
  String? fetchedId;

  @override
  Future<CloudReportPreview> createReportPreview(
    String homeId,
    List<String> applianceIds,
    Set<String> ownedApplianceIds, {
    required String idempotencyKey,
  }) async => createResult ?? preview(home: homeId);

  @override
  Future<CloudReportPreview> reportPreview(
    String homeId,
    String previewId,
    Set<String> ownedApplianceIds,
  ) {
    fetchedHome = homeId;
    fetchedId = previewId;
    return fetchResult?.call(homeId, previewId, ownedApplianceIds) ??
        Future.value(preview(home: homeId, id: previewId));
  }
}

ReportPreviewDomainRepository repository(Source source) =>
    ReportPreviewDomainRepository(source, now: () => now);

void main() {
  test(
    'create reconciles through owner GET and preserves returned hash',
    () async {
      final source = Source()..createResult = preview(hash: hashA);
      final result = await repository(source).create(
        homeId: homeA,
        applianceIds: const [applianceId],
        ownedApplianceIds: {applianceId},
        idempotencyKey: 'request-key',
      );

      expect(source.fetchedHome, homeA);
      expect(source.fetchedId, previewId);
      expect(result!.snapshotSha256, hashA);
      expect(result.status, ReportPreviewStatus.current);
    },
  );

  test(
    'reports server stale and local expiry as requiring new approval',
    () async {
      final source = Source();
      final repo = repository(source);
      source.fetchResult = (_, id, _) async => preview(id: id, stale: true);
      final stale = await repo.fetch(
        homeId: homeA,
        previewId: previewId,
        ownedApplianceIds: {applianceId},
      );
      expect(stale!.status, ReportPreviewStatus.stale);
      expect(stale.requiresNewApproval, isTrue);

      source.fetchResult = (_, id, _) async => preview(id: id, expires: now);
      final expired = await repo.fetch(
        homeId: homeA,
        previewId: previewId,
        ownedApplianceIds: {applianceId},
      );
      expect(expired!.status, ReportPreviewStatus.expired);
      expect(expired.requiresNewApproval, isTrue);
    },
  );

  test(
    'readback carries latest delivery without changing approval state',
    () async {
      final source = Source();
      final delivery = CloudReportDeliveryStatus(
        id: '66666666-6666-4666-8666-666666666666',
        state: 'sent',
        createdAt: now.subtract(const Duration(minutes: 2)),
        sentAt: now.subtract(const Duration(minutes: 1)),
      );
      source.fetchResult = (_, id, _) async =>
          preview(id: id, latestDelivery: delivery, hash: hashA);

      final result = await repository(source).fetch(
        homeId: homeA,
        previewId: previewId,
        ownedApplianceIds: {applianceId},
      );

      expect(result!.preview.latestDelivery, same(delivery));
      expect(result.snapshotSha256, hashA);
      expect(result.status, ReportPreviewStatus.current);
      expect(result.requiresNewApproval, isFalse);
    },
  );

  test(
    'home switch prevents previous home response from being returned',
    () async {
      final source = Source();
      final pending = Completer<CloudReportPreview>();
      source.fetchResult = (home, id, _) => home == homeA
          ? pending.future
          : Future.value(preview(home: home, id: id));
      final repo = repository(source);
      final first = repo.fetch(
        homeId: homeA,
        previewId: previewId,
        ownedApplianceIds: {applianceId},
      );
      final second = await repo.fetch(
        homeId: homeB,
        previewId: previewId,
        ownedApplianceIds: {applianceId},
      );
      pending.complete(preview(home: homeA));

      expect(second!.homeId, homeB);
      expect(await first, isNull);
    },
  );

  test('clear invalidates an in-flight response after sign-out', () async {
    final source = Source();
    final pending = Completer<CloudReportPreview>();
    source.fetchResult = (_, _, _) => pending.future;
    final repo = repository(source);
    final result = repo.fetch(
      homeId: homeA,
      previewId: previewId,
      ownedApplianceIds: {applianceId},
    );
    repo.clear();
    pending.complete(preview());
    expect(await result, isNull);
  });

  test(
    'rejects cross-home readback and changed preview hash is retained',
    () async {
      final source = Source();
      final repo = repository(source);
      source.fetchResult = (_, id, _) async => preview(home: homeB, id: id);
      await expectLater(
        repo.fetch(
          homeId: homeA,
          previewId: previewId,
          ownedApplianceIds: {applianceId},
        ),
        throwsFormatException,
      );

      source.fetchResult = (_, id, _) async => preview(id: id, hash: hashB);
      final changed = await repo.fetch(
        homeId: homeA,
        previewId: previewId,
        ownedApplianceIds: {applianceId},
      );
      expect(changed!.snapshotSha256, hashB);
      expect(changed.status, ReportPreviewStatus.current);
    },
  );
}
