import 'dart:collection';

import 'package:flutter/foundation.dart';

import '../cloud_api/cloud_api_client.dart';
import '../cloud_api/cloud_appliance.dart';
import '../cloud_api/cloud_report_preview.dart';
import '../cloud_api/cloud_report_delivery.dart';
import '../../features/design/report_preview_domain_repository.dart';
import '../../features/design/report_delivery_domain_adapter.dart';
import '../../features/identify/onboarding_draft_store.dart';
import '../../features/identify/onboarding_persistence_repository.dart';

/// Nonvisual operations scoped to a home verified by CloudEntryGate.
class CloudAuxiliaryDomainLifecycle {
  factory CloudAuxiliaryDomainLifecycle({
    required DurableOnboardingDrafts drafts,
    required ReportPreviewDomainRepository reports,
    required ReportDeliveryDomainAdapter deliveries,
  }) => CloudAuxiliaryDomainLifecycle._(drafts, reports, deliveries);

  CloudAuxiliaryDomainLifecycle._(this.drafts, this._reports, this._deliveries)
    : archiveAction = null;

  factory CloudAuxiliaryDomainLifecycle.forCloudApi(
    CloudApiClient api,
  ) => CloudAuxiliaryDomainLifecycle._withArchive(
    drafts: DurableOnboardingDrafts(
      const SecureOnboardingDraftStorage(),
      OnboardingPersistenceRepository(CloudOnboardingPersistenceSource(api)),
    ),
    reports: ReportPreviewDomainRepository(CloudReportPreviewDomainSource(api)),
    deliveries: ReportDeliveryDomainAdapter(
      CloudReportDeliveryDomainSource(api),
    ),
    archiveAction: (homeId, applianceId, idempotencyKey) async {
      final current = await api.appliance(homeId, applianceId);
      await api.archiveAppliance(
        homeId,
        applianceId,
        ifMatch: current.etag,
        idempotencyKey: idempotencyKey,
      );
    },
  );

  CloudAuxiliaryDomainLifecycle._withArchive({
    required this.drafts,
    required this._reports,
    required this._deliveries,
    required this.archiveAction,
  });

  final DurableOnboardingDrafts drafts;
  final ReportPreviewDomainRepository _reports;
  final ReportDeliveryDomainAdapter _deliveries;
  final Future<void> Function(
    String homeId,
    String applianceId,
    String idempotencyKey,
  )?
  archiveAction;

  /// Archives a household appliance after verifying the active native scope.
  Future<void> archiveAppliance(
    String accountId,
    String homeId,
    String applianceId,
    String idempotencyKey,
  ) async {
    _requireVerifiedScope(accountId, homeId);
    final archive = archiveAction;
    if (archive == null) throw StateError('Appliance archive is unavailable');
    final generation = _generation;
    await archive(homeId, applianceId, idempotencyKey);
    if (generation != _generation || !isVerifiedScope(accountId, homeId)) {
      throw StateError('Verified account or home changed while archiving');
    }
  }

  String? _accountId;
  String? _homeId;
  int _generation = 0;
  final Map<ReportPreviewDomainSnapshot, int> _reportReadScopes =
      HashMap.identity();
  final ValueNotifier<int> _scopeVersion = ValueNotifier<int>(0);

  ValueListenable<int> get scopeChanges => _scopeVersion;

  String? get verifiedHomeId => _homeId;
  String? get verifiedAccountId => _accountId;

  /// Whether an auxiliary operation is bound to this verified account/home.
  bool isVerifiedScope(String accountId, String homeId) =>
      _accountId == accountId && _homeId == homeId;

  /// Stages a device-local onboarding draft only inside the active verified
  /// scope. It deliberately does not call the appliance persistence source.
  Future<PendingOnboardingDraft> stageOnboardingDraft(
    String accountId,
    String homeId,
    OnboardingDraft draft,
  ) async {
    _requireVerifiedScope(accountId, homeId);
    final generation = _generation;
    final pending = await drafts.stage(draft);
    if (generation != _generation || !isVerifiedScope(accountId, homeId)) {
      throw StateError('Verified account or home changed while staging draft');
    }
    return pending;
  }

  Future<PendingOnboardingDraft?> restoreOnboardingDraft(
    String accountId,
    String homeId,
  ) async {
    _requireVerifiedScope(accountId, homeId);
    final generation = _generation;
    final pending = await drafts.restore();
    if (generation != _generation || !isVerifiedScope(accountId, homeId)) {
      return null;
    }
    return pending;
  }

  /// Saves a previously staged review only while its account/home is verified.
  Future<CloudAppliance?> commitOnboardingDraft(
    String accountId,
    String homeId,
    PendingOnboardingDraft pending, {
    required bool explicitlyApproved,
  }) async {
    _requireVerifiedScope(accountId, homeId);
    final generation = _generation;
    final result = await drafts.commit(
      pending,
      explicitlyApproved: explicitlyApproved,
    );
    return generation == _generation && isVerifiedScope(accountId, homeId)
        ? result
        : null;
  }

  /// Reads saved inventory only while the account and home remain verified.
  Future<List<CloudAppliance>?> refreshSavedAppliances(
    String accountId,
    String homeId,
  ) async {
    _requireVerifiedScope(accountId, homeId);
    final generation = _generation;
    final rows = await drafts.repository.refresh();
    return generation == _generation && isVerifiedScope(accountId, homeId)
        ? rows
        : null;
  }

  void _requireVerifiedScope(String accountId, String homeId) {
    if (!isVerifiedScope(accountId, homeId)) {
      throw StateError('No verified account and home for onboarding draft');
    }
  }

  /// Invalidate synchronous report work before asynchronous storage cleanup.
  Future<void> clear() {
    _generation++;
    _scopeVersion.value = _generation;
    _accountId = null;
    _homeId = null;
    drafts.invalidatePendingWork();
    _reports.clear();
    _deliveries.clear();
    _reportReadScopes.clear();
    return drafts.selectScope(null, null);
  }

  Future<bool> selectVerifiedHome(String accountId, String homeId) async {
    if (!_uuid.hasMatch(accountId) || !_uuid.hasMatch(homeId)) {
      clear().ignore();
      return false;
    }
    if (_accountId == accountId && _homeId == homeId) return true;
    final generation = ++_generation;
    _scopeVersion.value = _generation;
    _accountId = null;
    _homeId = null;
    drafts.invalidatePendingWork();
    _reports.clear();
    _deliveries.clear();
    _reportReadScopes.clear();
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
    if (generation != _generation || result == null) return null;
    _reportReadScopes[result] = generation;
    return result;
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
    if (generation != _generation || result == null) return null;
    _reportReadScopes[result] = generation;
    return result;
  }

  /// Queues a delivery request only after the caller explicitly approves it.
  /// The adapter revalidates the preview, hash, recipients, and retry key.
  Future<ReportDeliveryDomainResult> queueReportDelivery({
    required ReportPreviewDomainSnapshot preview,
    required bool explicitlyApproved,
    required String approvedSnapshotSha256,
    required String recipients,
    required Set<String> ownedApplianceIds,
    required String idempotencyKey,
  }) async {
    _requireVerifiedHome(preview.homeId);
    final generation = _generation;
    final result = await _deliveries.queue(
      preview: preview,
      explicitlyApproved: explicitlyApproved,
      approvedSnapshotSha256: approvedSnapshotSha256,
      recipients: recipients,
      ownedApplianceIds: ownedApplianceIds,
      idempotencyKey: idempotencyKey,
    );
    return generation == _generation
        ? result
        : const ReportDeliveryDomainResult(ReportDeliveryStatus.contextChanged);
  }

  /// Rechecks the current preview before exposing its latest request state.
  /// The optional ID distinguishes a known queued request from a later one.
  Future<ReportDeliveryReadbackResult> readReportDelivery({
    required ReportPreviewDomainSnapshot preview,
    required Set<String> ownedApplianceIds,
    String? expectedDeliveryId,
  }) async {
    _requireVerifiedHome(preview.homeId);
    final generation = _generation;
    if (_reportReadScopes[preview] != generation) {
      return const ReportDeliveryReadbackResult(
        ReportDeliveryReadbackStatus.contextChanged,
      );
    }
    final result = await _deliveries.readback(
      preview: preview,
      ownedApplianceIds: ownedApplianceIds,
      expectedDeliveryId: expectedDeliveryId,
    );
    return generation == _generation
        ? result
        : const ReportDeliveryReadbackResult(
            ReportDeliveryReadbackStatus.contextChanged,
          );
  }

  void _requireVerifiedHome(String homeId) {
    if (_accountId == null || _homeId != homeId) {
      throw StateError('No verified account and home for report preview');
    }
  }
}

class CloudReportDeliveryDomainSource implements ReportDeliveryDomainSource {
  const CloudReportDeliveryDomainSource(this.api);

  final CloudApiClient api;

  @override
  Future<CloudReportPreview> reportPreview(
    String homeId,
    String previewId,
    Set<String> ownedApplianceIds,
  ) => api.reportPreview(homeId, previewId, ownedApplianceIds);

  @override
  Future<CloudReportDelivery> queueReportDelivery(
    String homeId,
    String previewId,
    String approvedSnapshotSha256,
    List<String> recipients, {
    required String idempotencyKey,
  }) => api.queueReportDelivery(
    homeId,
    previewId,
    approvedSnapshotSha256,
    recipients,
    idempotencyKey: idempotencyKey,
  );
}

final _uuid = RegExp(
  r'^[0-9a-fA-F]{8}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{12}$',
);
