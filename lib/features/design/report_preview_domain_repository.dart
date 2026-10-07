import '../../core/cloud_api/cloud_api_client.dart';
import '../../core/cloud_api/cloud_report_preview.dart';

/// Authenticated report preview operations used by nonvisual consumers.
/// Delivery is intentionally outside this interface.
abstract interface class ReportPreviewDomainSource {
  Future<CloudReportPreview> createReportPreview(
    String homeId,
    List<String> applianceIds,
    Set<String> ownedApplianceIds, {
    required String idempotencyKey,
  });

  Future<CloudReportPreview> reportPreview(
    String homeId,
    String previewId,
    Set<String> ownedApplianceIds,
  );
}

class CloudReportPreviewDomainSource implements ReportPreviewDomainSource {
  const CloudReportPreviewDomainSource(this.api);

  final CloudApiClient api;

  @override
  Future<CloudReportPreview> createReportPreview(
    String homeId,
    List<String> applianceIds,
    Set<String> ownedApplianceIds, {
    required String idempotencyKey,
  }) => api.createReportPreview(
    homeId,
    applianceIds,
    ownedApplianceIds,
    idempotencyKey: idempotencyKey,
  );

  @override
  Future<CloudReportPreview> reportPreview(
    String homeId,
    String previewId,
    Set<String> ownedApplianceIds,
  ) => api.reportPreview(homeId, previewId, ownedApplianceIds);
}

enum ReportPreviewStatus { current, stale, expired }

/// Typed owner-scoped report data. It contains no delivery or recipient state.
class ReportPreviewDomainSnapshot {
  const ReportPreviewDomainSnapshot({
    required this.homeId,
    required this.preview,
    required this.status,
  });

  final String homeId;
  final CloudReportPreview preview;
  final ReportPreviewStatus status;

  String get snapshotSha256 => preview.snapshotSha256;
  bool get requiresNewApproval => status != ReportPreviewStatus.current;
}

/// Read/create adapter for the existing authenticated preview APIs.
/// `clear` should be called on sign-out; changing homes also invalidates work.
/// A create response is reconciled with an owner GET before it is exposed.
class ReportPreviewDomainRepository {
  ReportPreviewDomainRepository(this.source, {DateTime Function()? now})
    : _now = now ?? DateTime.now;

  final ReportPreviewDomainSource source;
  final DateTime Function() _now;
  String? _homeId;
  int _generation = 0;

  void clear() {
    _homeId = null;
    _generation++;
  }

  Future<ReportPreviewDomainSnapshot?> create({
    required String homeId,
    required List<String> applianceIds,
    required Set<String> ownedApplianceIds,
    required String idempotencyKey,
  }) async {
    _validateHomeId(homeId);
    _activateHome(homeId);
    final generation = _generation;
    bool staleRequest() => generation != _generation || _homeId != homeId;
    try {
      final created = await source.createReportPreview(
        homeId,
        List.unmodifiable(applianceIds),
        Set.unmodifiable(ownedApplianceIds.map((id) => id.toLowerCase())),
        idempotencyKey: idempotencyKey,
      );
      if (staleRequest()) return null;
      final fresh = await source.reportPreview(
        homeId,
        created.id,
        Set.unmodifiable(ownedApplianceIds.map((id) => id.toLowerCase())),
      );
      if (staleRequest()) return null;
      if (created.homeId.toLowerCase() != homeId.toLowerCase() ||
          fresh.homeId.toLowerCase() != homeId.toLowerCase() ||
          fresh.id != created.id) {
        throw const FormatException('Report preview owner or ID changed');
      }
      return _snapshot(homeId, fresh);
    } catch (_) {
      if (staleRequest()) return null;
      rethrow;
    }
  }

  Future<ReportPreviewDomainSnapshot?> fetch({
    required String homeId,
    required String previewId,
    required Set<String> ownedApplianceIds,
  }) async {
    _validateHomeId(homeId);
    _activateHome(homeId);
    final generation = _generation;
    bool staleRequest() => generation != _generation || _homeId != homeId;
    try {
      final preview = await source.reportPreview(
        homeId,
        previewId,
        Set.unmodifiable(ownedApplianceIds.map((id) => id.toLowerCase())),
      );
      if (staleRequest()) return null;
      if (preview.homeId.toLowerCase() != homeId.toLowerCase() ||
          preview.id != previewId) {
        throw const FormatException('Report preview owner or ID changed');
      }
      return _snapshot(homeId, preview);
    } catch (_) {
      if (staleRequest()) return null;
      rethrow;
    }
  }

  void _activateHome(String homeId) {
    if (_homeId != homeId) {
      _homeId = homeId;
      _generation++;
    }
  }

  ReportPreviewDomainSnapshot _snapshot(
    String homeId,
    CloudReportPreview preview,
  ) {
    final status = preview.stale
        ? ReportPreviewStatus.stale
        : !_now().toUtc().isBefore(preview.expiresAt.toUtc())
        ? ReportPreviewStatus.expired
        : ReportPreviewStatus.current;
    return ReportPreviewDomainSnapshot(
      homeId: homeId,
      preview: preview,
      status: status,
    );
  }
}

final _homeUuid = RegExp(
  r'^[0-9a-fA-F]{8}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{12}$',
);

void _validateHomeId(String homeId) {
  if (!_homeUuid.hasMatch(homeId)) throw ArgumentError.value(homeId, 'homeId');
}
