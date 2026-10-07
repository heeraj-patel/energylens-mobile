import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:energylens_mobile/core/cloud_api/cloud_report_delivery.dart';
import 'package:energylens_mobile/core/cloud_api/cloud_report_preview.dart';
import 'package:energylens_mobile/features/design/report_delivery_domain_adapter.dart';
import 'package:energylens_mobile/features/design/report_preview_domain_repository.dart';

const home = '11111111-1111-4111-8111-111111111111';
const appliance = '33333333-3333-4333-8333-333333333333';
const previewId = '55555555-5555-4555-8555-555555555555';
const requestId = '66666666-6666-4666-8666-666666666666';
const deliveryId = '77777777-7777-4777-8777-777777777777';
final hash = 'a' * 64;
final clockNow = DateTime.utc(2026, 10, 6);

CloudReportPreview makePreview({
  String homeId = home,
  String id = previewId,
  String? digest,
  bool stale = false,
  DateTime? expires,
}) => CloudReportPreview(
  id,
  digest ?? hash,
  homeId,
  clockNow.subtract(const Duration(minutes: 1)),
  expires ?? clockNow.add(const Duration(hours: 1)),
  stale,
  const [],
  const [],
);

ReportPreviewDomainSnapshot snapshot({
  ReportPreviewStatus status = ReportPreviewStatus.current,
  CloudReportPreview? value,
}) {
  final report = value ?? makePreview();
  return ReportPreviewDomainSnapshot(
    homeId: report.homeId,
    preview: report,
    status: status,
  );
}

class FakeSource implements ReportDeliveryDomainSource {
  Future<CloudReportPreview> Function(String, String, Set<String>)? read;
  Future<CloudReportDelivery> Function(
    String,
    String,
    String,
    List<String>,
    String,
  )?
  queue;
  int readCount = 0;
  int queueCount = 0;
  String? queuedKey;
  String? queuedHash;
  List<String>? queuedRecipients;

  @override
  Future<CloudReportPreview> reportPreview(
    String homeId,
    String previewId,
    Set<String> ownedApplianceIds,
  ) {
    readCount++;
    return read?.call(homeId, previewId, ownedApplianceIds) ??
        Future.value(makePreview(homeId: homeId, id: previewId));
  }

  @override
  Future<CloudReportDelivery> queueReportDelivery(
    String homeId,
    String previewId,
    String approvedSnapshotSha256,
    List<String> recipients, {
    required String idempotencyKey,
  }) {
    queueCount++;
    queuedKey = idempotencyKey;
    queuedHash = approvedSnapshotSha256;
    queuedRecipients = recipients;
    return queue?.call(
          homeId,
          previewId,
          approvedSnapshotSha256,
          recipients,
          idempotencyKey,
        ) ??
        Future.value(
          CloudReportDelivery(
            deliveryId,
            previewId,
            recipients,
            'pending',
            clockNow,
          ),
        );
  }
}

void main() {
  DateTime now() => clockNow;

  test(
    'requires explicit approval of the exact current preview and recipients',
    () async {
      final source = FakeSource();
      final adapter = ReportDeliveryDomainAdapter(source, now: now);
      final result = await adapter.queue(
        preview: snapshot(),
        explicitlyApproved: true,
        approvedSnapshotSha256: hash,
        recipients: ' User@Example.com,second@example.com ',
        ownedApplianceIds: {appliance},
        idempotencyKey: requestId,
      );

      expect(result.status, ReportDeliveryStatus.queued);
      expect(source.queuedHash, hash);
      expect(source.queuedRecipients, [
        'second@example.com',
        'user@example.com',
      ]);
      expect(source.queuedKey, requestId);
    },
  );

  test('rejects missing approval, changed hash, invalid recipients, and noncurrent snapshot', () async {
    final source = FakeSource();
    final adapter = ReportDeliveryDomainAdapter(source, now: now);
    Future<ReportDeliveryDomainResult> submit({
      bool approved = true,
      String? approvedHash,
      String recipientInput = 'user@example.com',
      ReportPreviewStatus status = ReportPreviewStatus.current,
    }) => adapter.queue(
      preview: snapshot(status: status),
      explicitlyApproved: approved,
      approvedSnapshotSha256: approvedHash ?? hash,
      recipients: recipientInput,
      ownedApplianceIds: {appliance},
      idempotencyKey: requestId,
    );

    expect(
      (await submit(approved: false)).status,
      ReportDeliveryStatus.rejected,
    );
    expect(
      (await submit(approvedHash: 'b' * 64)).status,
      ReportDeliveryStatus.rejected,
    );
    expect(
      (await submit(recipientInput: 'bad-address')).status,
      ReportDeliveryStatus.rejected,
    );
    expect(
      (await submit(status: ReportPreviewStatus.stale)).status,
      ReportDeliveryStatus.rejected,
    );
    expect(source.readCount, 0);
    expect(source.queueCount, 0);
  });

  test(
    'rejects a preview that became stale, expired, or changed before queueing',
    () async {
      final source = FakeSource();
      final adapter = ReportDeliveryDomainAdapter(source, now: now);
      for (final current in [
        makePreview(stale: true),
        makePreview(expires: clockNow),
        makePreview(digest: 'b' * 64),
      ]) {
        source.read = (_, id, _) async => makePreview(
          id: id,
          stale: current.stale,
          expires: current.expiresAt,
          digest: current.snapshotSha256,
        );
        final result = await adapter.queue(
          preview: snapshot(),
          explicitlyApproved: true,
          approvedSnapshotSha256: hash,
          recipients: 'user@example.com',
          ownedApplianceIds: {appliance},
          idempotencyKey: requestId,
        );
        expect(result.status, ReportDeliveryStatus.rejected);
      }
      expect(source.queueCount, 0);
    },
  );

  test('drops an in flight read after home switch or sign out', () async {
    for (final signOut in [false, true]) {
      final source = FakeSource();
      final pending = Completer<CloudReportPreview>();
      source.read = (_, id, _) => pending.future;
      final adapter = ReportDeliveryDomainAdapter(source, now: now);
      final request = adapter.queue(
        preview: snapshot(),
        explicitlyApproved: true,
        approvedSnapshotSha256: hash,
        recipients: 'user@example.com',
        ownedApplianceIds: {appliance},
        idempotencyKey: requestId,
      );
      if (signOut) {
        adapter.clear();
      } else {
        await adapter.queue(
          preview: snapshot(
            value: makePreview(homeId: '22222222-2222-4222-8222-222222222222'),
          ),
          explicitlyApproved: false,
          approvedSnapshotSha256: hash,
          recipients: 'user@example.com',
          ownedApplianceIds: {appliance},
          idempotencyKey: requestId,
        );
      }
      pending.complete(makePreview());
      expect((await request).status, ReportDeliveryStatus.contextChanged);
      expect(source.queueCount, 0);
    }
  });

  test(
    'drops queued response after sign out and preserves retry idempotency key',
    () async {
      final source = FakeSource();
      final pending = Completer<CloudReportDelivery>();
      source.queue = (_, id, _, recipients, _) => pending.future;
      final adapter = ReportDeliveryDomainAdapter(source, now: now);
      final request = adapter.queue(
        preview: snapshot(),
        explicitlyApproved: true,
        approvedSnapshotSha256: hash,
        recipients: 'user@example.com',
        ownedApplianceIds: {appliance},
        idempotencyKey: requestId,
      );
      await Future<void>.delayed(Duration.zero);
      adapter.clear();
      pending.complete(
        CloudReportDelivery(
          deliveryId,
          previewId,
          const ['user@example.com'],
          'pending',
          clockNow,
        ),
      );
      expect((await request).status, ReportDeliveryStatus.contextChanged);

      final retrySource = FakeSource();
      final retryAdapter = ReportDeliveryDomainAdapter(retrySource, now: now);
      await retryAdapter.queue(
        preview: snapshot(),
        explicitlyApproved: true,
        approvedSnapshotSha256: hash,
        recipients: 'user@example.com',
        ownedApplianceIds: {appliance},
        idempotencyKey: requestId,
      );
      expect(retrySource.queuedKey, requestId);
    },
  );

  test(
    'uncertain queue retry binds key to exact hash and recipients',
    () async {
      final source = FakeSource();
      var failOnce = true;
      source.queue = (_, id, _, recipients, _) async {
        if (failOnce) {
          failOnce = false;
          throw StateError('response lost');
        }
        return CloudReportDelivery(
          deliveryId,
          id,
          recipients,
          'pending',
          clockNow,
        );
      };
      final adapter = ReportDeliveryDomainAdapter(source, now: now);
      Future<ReportDeliveryDomainResult> submit({
        String recipients = 'user@example.com',
        CloudReportPreview? value,
      }) => adapter.queue(
        preview: snapshot(value: value),
        explicitlyApproved: true,
        approvedSnapshotSha256: value?.snapshotSha256 ?? hash,
        recipients: recipients,
        ownedApplianceIds: {appliance},
        idempotencyKey: requestId,
      );
      await expectLater(submit(), throwsStateError);
      expect(
        (await submit(recipients: 'other@example.com')).status,
        ReportDeliveryStatus.rejected,
      );
      expect(
        (await submit(value: makePreview(digest: 'b' * 64))).status,
        ReportDeliveryStatus.rejected,
      );
      expect(source.queueCount, 1);
      expect((await submit()).status, ReportDeliveryStatus.queued);
      expect(source.queueCount, 2);
      expect(source.queuedKey, requestId);
    },
  );

  test('rejects mismatched delivery response after queue', () async {
    final source = FakeSource();
    source.queue = (_, _, _, _, _) async => CloudReportDelivery(
      deliveryId,
      '88888888-8888-4888-8888-888888888888',
      const ['other@example.com'],
      'pending',
      clockNow,
    );
    final adapter = ReportDeliveryDomainAdapter(source, now: now);
    await expectLater(
      adapter.queue(
        preview: snapshot(),
        explicitlyApproved: true,
        approvedSnapshotSha256: hash,
        recipients: 'user@example.com',
        ownedApplianceIds: {appliance},
        idempotencyKey: requestId,
      ),
      throwsFormatException,
    );
  });

  test('concurrent same-key requests cannot change recipients', () async {
    final source = FakeSource();
    final read = Completer<CloudReportPreview>();
    source.read = (_, _, _) => read.future;
    final adapter = ReportDeliveryDomainAdapter(source, now: now);
    Future<ReportDeliveryDomainResult> submit(String recipients) =>
        adapter.queue(
          preview: snapshot(),
          explicitlyApproved: true,
          approvedSnapshotSha256: hash,
          recipients: recipients,
          ownedApplianceIds: {appliance},
          idempotencyKey: requestId,
        );
    final first = submit('user@example.com');
    final second = await submit('other@example.com');
    expect(second.status, ReportDeliveryStatus.rejected);
    expect(source.readCount, 1);
    read.complete(makePreview());
    expect((await first).status, ReportDeliveryStatus.queued);
    expect(source.queuedRecipients, ['user@example.com']);
  });
}
