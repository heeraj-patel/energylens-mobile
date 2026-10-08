import '../../core/cloud_api/cloud_report_delivery.dart';
import '../../core/cloud_api/cloud_report_preview.dart';
import 'report_preview_domain_repository.dart';

/// The delivery adapter can only queue a request against a freshly read
/// preview. It does not send email or claim that delivery completed.
abstract interface class ReportDeliveryDomainSource {
  Future<CloudReportPreview> reportPreview(
    String homeId,
    String previewId,
    Set<String> ownedApplianceIds,
  );

  Future<CloudReportDelivery> queueReportDelivery(
    String homeId,
    String previewId,
    String approvedSnapshotSha256,
    List<String> recipients, {
    required String idempotencyKey,
  });
}

enum ReportDeliveryStatus { queued, rejected, contextChanged }

enum ReportDeliveryReadbackStatus {
  available,
  noRequest,
  previewChanged,
  contextChanged,
}

class ReportDeliveryReadbackResult {
  const ReportDeliveryReadbackResult(this.status, {this.delivery});

  final ReportDeliveryReadbackStatus status;
  final CloudReportDeliveryStatus? delivery;
}

class ReportDeliveryDomainResult {
  const ReportDeliveryDomainResult(this.status, {this.delivery});

  final ReportDeliveryStatus status;
  final CloudReportDelivery? delivery;
}

/// Explicit, nonvisual approval gate for queuing a report delivery request.
class ReportDeliveryDomainAdapter {
  ReportDeliveryDomainAdapter(this.source, {DateTime Function()? now})
    : _now = now ?? DateTime.now;

  final ReportDeliveryDomainSource source;
  final DateTime Function() _now;
  String? _homeId;
  int _generation = 0;
  final Map<String, String> _operations = {};

  void clear() {
    _homeId = null;
    _generation++;
    _operations.clear();
  }

  /// Reads the latest recipient-free request state for this exact preview.
  /// An optional ID binds the read to a request previously returned by queue.
  /// Without one, the result represents only the latest request on the preview.
  /// A stale or expired preview can still carry a terminal delivery state.
  Future<ReportDeliveryReadbackResult> readback({
    required ReportPreviewDomainSnapshot preview,
    required Set<String> ownedApplianceIds,
    String? expectedDeliveryId,
  }) async {
    final homeId = preview.homeId;
    if (_homeId != homeId) {
      _homeId = homeId;
      _generation++;
      _operations.clear();
    }
    final generation = _generation;
    bool contextChanged() => generation != _generation || _homeId != homeId;
    if (preview.preview.homeId.toLowerCase() != homeId.toLowerCase()) {
      return const ReportDeliveryReadbackResult(
        ReportDeliveryReadbackStatus.previewChanged,
      );
    }

    try {
      final current = await source.reportPreview(
        homeId,
        preview.preview.id,
        Set.unmodifiable(ownedApplianceIds.map((id) => id.toLowerCase())),
      );
      if (contextChanged()) {
        return const ReportDeliveryReadbackResult(
          ReportDeliveryReadbackStatus.contextChanged,
        );
      }
      if (current.homeId.toLowerCase() != homeId.toLowerCase() ||
          current.id != preview.preview.id ||
          current.snapshotSha256 != preview.snapshotSha256 ||
          !_sameReportSelection(current, preview.preview)) {
        return const ReportDeliveryReadbackResult(
          ReportDeliveryReadbackStatus.previewChanged,
        );
      }
      final delivery = current.latestDelivery;
      if (delivery == null) {
        return const ReportDeliveryReadbackResult(
          ReportDeliveryReadbackStatus.noRequest,
        );
      }
      if (expectedDeliveryId != null && delivery.id != expectedDeliveryId) {
        return const ReportDeliveryReadbackResult(
          ReportDeliveryReadbackStatus.previewChanged,
        );
      }
      return ReportDeliveryReadbackResult(
        ReportDeliveryReadbackStatus.available,
        delivery: delivery,
      );
    } catch (_) {
      if (contextChanged()) {
        return const ReportDeliveryReadbackResult(
          ReportDeliveryReadbackStatus.contextChanged,
        );
      }
      rethrow;
    }
  }

  Future<ReportDeliveryDomainResult> queue({
    required ReportPreviewDomainSnapshot preview,
    required bool explicitlyApproved,
    required String approvedSnapshotSha256,
    required String recipients,
    required Set<String> ownedApplianceIds,
    required String idempotencyKey,
  }) async {
    final homeId = preview.homeId;
    if (_homeId != homeId) {
      _homeId = homeId;
      _generation++;
      _operations.clear();
    }
    final generation = _generation;
    bool contextChanged() => generation != _generation || _homeId != homeId;

    final normalizedRecipients = validatedReportRecipients(recipients);
    if (!explicitlyApproved ||
        preview.status != ReportPreviewStatus.current ||
        preview.preview.homeId.toLowerCase() != homeId.toLowerCase() ||
        !_now().toUtc().isBefore(preview.preview.expiresAt.toUtc()) ||
        approvedSnapshotSha256 != preview.snapshotSha256 ||
        normalizedRecipients == null ||
        !_uuidV4.hasMatch(idempotencyKey)) {
      return const ReportDeliveryDomainResult(ReportDeliveryStatus.rejected);
    }
    final operation = [
      homeId.toLowerCase(),
      preview.preview.id.toLowerCase(),
      approvedSnapshotSha256,
      ...normalizedRecipients,
    ].join('\u0000');
    if (_operations[idempotencyKey] case final prior? when prior != operation) {
      return const ReportDeliveryDomainResult(ReportDeliveryStatus.rejected);
    }
    _operations[idempotencyKey] = operation;

    try {
      final current = await source.reportPreview(
        homeId,
        preview.preview.id,
        Set.unmodifiable(ownedApplianceIds.map((id) => id.toLowerCase())),
      );
      if (contextChanged()) {
        return const ReportDeliveryDomainResult(
          ReportDeliveryStatus.contextChanged,
        );
      }
      if (current.homeId.toLowerCase() != homeId.toLowerCase() ||
          current.id != preview.preview.id ||
          current.stale ||
          !_now().toUtc().isBefore(current.expiresAt.toUtc()) ||
          current.snapshotSha256 != preview.snapshotSha256 ||
          !_sameReportSelection(current, preview.preview) ||
          current.snapshotSha256 != approvedSnapshotSha256) {
        return const ReportDeliveryDomainResult(ReportDeliveryStatus.rejected);
      }

      final delivery = await source.queueReportDelivery(
        homeId,
        current.id,
        approvedSnapshotSha256,
        List.unmodifiable(normalizedRecipients),
        idempotencyKey: idempotencyKey,
      );
      if (contextChanged()) {
        return const ReportDeliveryDomainResult(
          ReportDeliveryStatus.contextChanged,
        );
      }
      if (delivery.previewId != current.id ||
          delivery.state != 'pending' ||
          delivery.recipients.length != normalizedRecipients.length ||
          !Set<String>.from(delivery.recipients)
              .containsAll(normalizedRecipients)) {
        throw const FormatException('Report delivery readback differs');
      }
      return ReportDeliveryDomainResult(
        ReportDeliveryStatus.queued,
        delivery: delivery,
      );
    } catch (_) {
      if (contextChanged()) {
        return const ReportDeliveryDomainResult(
          ReportDeliveryStatus.contextChanged,
        );
      }
      rethrow;
    }
  }
}

bool _sameReportSelection(
  CloudReportPreview current,
  CloudReportPreview approved,
) {
  final currentIds = current.items
      .map((item) => item.applianceId.toLowerCase())
      .toSet();
  final approvedIds = approved.items
      .map((item) => item.applianceId.toLowerCase())
      .toSet();
  return currentIds.length == current.items.length &&
      approvedIds.length == approved.items.length &&
      currentIds.length == approvedIds.length &&
      currentIds.containsAll(approvedIds);
}

final _uuidV4 = RegExp(
  r'^[0-9a-fA-F]{8}-[0-9a-fA-F]{4}-4[0-9a-fA-F]{3}-[89abAB][0-9a-fA-F]{3}-[0-9a-fA-F]{12}$',
);
