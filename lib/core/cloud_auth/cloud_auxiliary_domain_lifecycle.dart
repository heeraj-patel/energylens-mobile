import '../cloud_api/cloud_api_client.dart';
import '../../features/design/report_preview_domain_repository.dart';
import '../../features/identify/onboarding_draft_store.dart';
import '../../features/identify/onboarding_persistence_repository.dart';

/// Nonvisual operations scoped to a home verified by CloudEntryGate.
class CloudAuxiliaryDomainLifecycle {
  factory CloudAuxiliaryDomainLifecycle({
    required DurableOnboardingDrafts drafts,
    required ReportPreviewDomainRepository reports,
  }) => CloudAuxiliaryDomainLifecycle._(drafts, reports);

  CloudAuxiliaryDomainLifecycle._(this.drafts, this._reports);

  factory CloudAuxiliaryDomainLifecycle.forCloudApi(
    CloudApiClient api,
  ) => CloudAuxiliaryDomainLifecycle(
    drafts: DurableOnboardingDrafts(
      const SecureOnboardingDraftStorage(),
      OnboardingPersistenceRepository(CloudOnboardingPersistenceSource(api)),
    ),
    reports: ReportPreviewDomainRepository(CloudReportPreviewDomainSource(api)),
  );

  final DurableOnboardingDrafts drafts;
  final ReportPreviewDomainRepository _reports;
  String? _accountId;
  String? _homeId;
  int _generation = 0;

  String? get verifiedHomeId => _homeId;

  /// Invalidate synchronous report work before asynchronous storage cleanup.
  Future<void> clear() {
    _generation++;
    _accountId = null;
    _homeId = null;
    _reports.clear();
    return drafts.selectScope(null, null);
  }

  Future<bool> selectVerifiedHome(String accountId, String homeId) async {
    if (!_uuid.hasMatch(accountId) || !_uuid.hasMatch(homeId)) {
      clear().ignore();
      return false;
    }
    if (_accountId == accountId && _homeId == homeId) return true;
    final generation = ++_generation;
    _accountId = null;
    _homeId = null;
    _reports.clear();
    await drafts.selectScope(accountId, homeId);
    if (generation != _generation) return false;
    _accountId = accountId;
    _homeId = homeId;
    return true;
  }

  Future<ReportPreviewDomainSnapshot?> createReportPreview({
    required String homeId,
    required List<String> applianceIds,
    required Set<String> ownedApplianceIds,
    required String idempotencyKey,
  }) async {
    _requireVerifiedHome(homeId);
    final generation = _generation;
    final result = await _reports.create(
      homeId: homeId,
      applianceIds: applianceIds,
      ownedApplianceIds: ownedApplianceIds,
      idempotencyKey: idempotencyKey,
    );
    return generation == _generation ? result : null;
  }

  Future<ReportPreviewDomainSnapshot?> reportPreview({
    required String homeId,
    required String previewId,
    required Set<String> ownedApplianceIds,
  }) async {
    _requireVerifiedHome(homeId);
    final generation = _generation;
    final result = await _reports.fetch(
      homeId: homeId,
      previewId: previewId,
      ownedApplianceIds: ownedApplianceIds,
    );
    return generation == _generation ? result : null;
  }

  void _requireVerifiedHome(String homeId) {
    if (_accountId == null || _homeId != homeId) {
      throw StateError('No verified account and home for report preview');
    }
  }
}

final _uuid = RegExp(
  r'^[0-9a-fA-F]{8}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{12}$',
);
