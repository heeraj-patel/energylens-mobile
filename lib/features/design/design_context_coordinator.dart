import 'dart:async';

import '../../core/cloud_api/cloud_appliance_list.dart';
import '../../core/cloud_api/cloud_api_client.dart';
import '../identify/cloud_device_reference_resolver.dart';
import '../identify/device_reference_inventory_observer.dart';
import 'dashboard_domain_repository.dart';
import 'devices_domain_repository.dart';
import 'efficiency_away_domain_adapter.dart';
import 'efficiency_domain_repository.dart';
import 'efficiency_habits_domain_adapter.dart';
import 'efficiency_peak_rates_adapter.dart';
import 'knowledge_domain_repository.dart';
import 'manage_devices_domain_repository.dart';
import 'settings_domain_repository.dart';
import 'tips_domain_repository.dart';
import '../discovery/discovery_credentials.dart';
import 'identification_candidates_domain_adapter.dart';
import 'devices_runtime_evidence_adapter.dart';
import 'devices_consistency_snapshot.dart';
import 'settings_regional_rate_adapter.dart';

/// Supplied only after the native auth layer verifies account ownership of the
/// selected home. This value contains no bearer token or WebView state.
class VerifiedDesignContext {
  VerifiedDesignContext({
    required this.accountId,
    required this.homeId,
    required this.mode,
  }) {
    if (accountId.isEmpty || !_uuid.hasMatch(homeId)) {
      throw ArgumentError('Invalid verified design context');
    }
  }

  final String accountId;
  final String homeId;
  final DesignContextMode mode;
}

enum DesignContextMode { household, sample }

/// Native, typed adapter boundary. Implementations must use the authenticated
/// cloud client for the verified account; no transport or credential is passed
/// to the renderer.
abstract interface class DesignContextAdapters {
  void clear();
  Future<DashboardDomainSnapshot?> dashboard(String homeId);
  Future<DevicesDomainSnapshot?> devices(String homeId);
  Future<DevicesRuntimeEvidenceSnapshot?> devicesRuntimeEvidence(String homeId);
  Future<EfficiencyDomainSnapshot?> efficiency(
    String homeId,
    EfficiencyPage page,
  );
  Future<EfficiencyAwayDomainSnapshot?> efficiencyAway(String homeId);
  Future<EfficiencyHabitsSnapshot?> efficiencyHabits(String homeId);
  Future<EfficiencyPeakRatesSnapshot?> efficiencyPeakRates(String homeId);
  Future<TipsDomainSnapshot?> tips(String homeId, TipsPage page);
  Future<SettingsDomainSnapshot?> settings(String homeId);
  Future<ManageDevicesDomainSnapshot?> manageDevices(String homeId);
  Future<KnowledgeAnswerResult?> knowledge(
    String homeId,
    String questionId, {
    String? applianceId,
  });
}

class RepositoryDesignContextAdapters implements DesignContextAdapters {
  const RepositoryDesignContextAdapters({
    required this.dashboardRepository,
    required this.devicesRepository,
    required this.devicesRuntimeEvidenceAdapter,
    required this.efficiencyRepository,
    required this.efficiencyAwayAdapter,
    required this.efficiencyHabitsAdapter,
    required this.efficiencyPeakRatesAdapter,
    required this.tipsRepository,
    required this.settingsRepository,
    required this.manageDevicesRepository,
    required this.knowledgeRepository,
  });

  final DashboardDomainRepository dashboardRepository;
  final DevicesDomainRepository devicesRepository;
  final DevicesRuntimeEvidenceAdapter devicesRuntimeEvidenceAdapter;
  final EfficiencyDomainRepository efficiencyRepository;
  final EfficiencyAwayDomainAdapter efficiencyAwayAdapter;
  final EfficiencyHabitsDomainAdapter efficiencyHabitsAdapter;
  final EfficiencyPeakRatesAdapter efficiencyPeakRatesAdapter;
  final TipsDomainRepository tipsRepository;
  final SettingsDomainRepository settingsRepository;
  final ManageDevicesDomainRepository manageDevicesRepository;
  final KnowledgeDomainRepository knowledgeRepository;

  @override
  void clear() {
    dashboardRepository.clear();
    devicesRepository.clear();
    devicesRuntimeEvidenceAdapter.invalidate();
    efficiencyRepository.clear();
    efficiencyAwayAdapter.clear();
    tipsRepository.clear();
    settingsRepository.clear();
    manageDevicesRepository.clear();
    knowledgeRepository.clear();
  }

  @override
  Future<DashboardDomainSnapshot?> dashboard(String homeId) =>
      dashboardRepository.fetch(homeId);
  @override
  Future<DevicesDomainSnapshot?> devices(String homeId) =>
      devicesRepository.fetch(homeId);
  @override
  Future<DevicesRuntimeEvidenceSnapshot?> devicesRuntimeEvidence(
    String homeId,
  ) => devicesRuntimeEvidenceAdapter.fetch(homeId);
  @override
  Future<EfficiencyDomainSnapshot?> efficiency(
    String homeId,
    EfficiencyPage page,
  ) => efficiencyRepository.fetch(homeId, page);
  @override
  Future<EfficiencyAwayDomainSnapshot?> efficiencyAway(String homeId) =>
      efficiencyAwayAdapter.fetch(homeId);
  @override
  Future<EfficiencyHabitsSnapshot?> efficiencyHabits(String homeId) =>
      efficiencyHabitsAdapter.fetch(homeId);
  @override
  Future<EfficiencyPeakRatesSnapshot?> efficiencyPeakRates(String homeId) =>
      efficiencyPeakRatesAdapter.fetch(homeId);
  @override
  Future<TipsDomainSnapshot?> tips(String homeId, TipsPage page) =>
      tipsRepository.fetch(homeId, page);
  @override
  Future<SettingsDomainSnapshot?> settings(String homeId) =>
      settingsRepository.fetch(homeId);
  @override
  Future<ManageDevicesDomainSnapshot?> manageDevices(String homeId) =>
      manageDevicesRepository.fetch(homeId);
  @override
  Future<KnowledgeAnswerResult?> knowledge(
    String homeId,
    String questionId, {
    String? applianceId,
  }) =>
      knowledgeRepository.answer(homeId, questionId, applianceId: applianceId);
}

class DesignContextRead {
  const DesignContextRead({
    required this.accountId,
    required this.homeId,
    required this.mode,
    required this.page,
    required this.value,
  });

  final String accountId;
  final String homeId;
  final DesignContextMode mode;
  final String page;
  final Object value;
}

/// Owns native read lifetime across all adapters. Every context change and
/// sign-out invalidates outstanding reads, including errors that arrive late.
/// A null result means the read was invalidated or the adapter had no result.
class DesignContextCoordinator {
  DesignContextCoordinator(
    this.adapters, {
    this.identificationCandidates,
    this.settingsRegionalRate,
    this.deviceReferenceObserver,
  });

  final IdentificationCandidatesDomainAdapter? identificationCandidates;
  final SettingsRegionalRateAdapter? settingsRegionalRate;
  final DeviceReferenceInventoryObserver? deviceReferenceObserver;

  /// Uses the same authenticated native client as CloudEntryGate. Nothing in
  /// this assembly is exposed to the WebView or visible shell.
  factory DesignContextCoordinator.forCloudApi(
    CloudApiClient api, {
    DiscoveryCredentials credentials = const DiscoveryCredentials(),
  }) {
    final efficiencyRepository = EfficiencyDomainRepository(
      CloudEfficiencyDomainSource(api),
    );
    return DesignContextCoordinator(
      RepositoryDesignContextAdapters(
        dashboardRepository: DashboardDomainRepository(
          CloudDashboardDomainSource(api),
        ),
        devicesRepository: DevicesDomainRepository(
          CloudDevicesDomainSource(api),
        ),
        devicesRuntimeEvidenceAdapter: DevicesRuntimeEvidenceAdapter(
          CloudDevicesRuntimeEvidenceSource(api),
        ),
        efficiencyRepository: efficiencyRepository,
        efficiencyAwayAdapter: EfficiencyAwayDomainAdapter(
          efficiencyRepository,
        ),
        efficiencyHabitsAdapter: EfficiencyHabitsDomainAdapter(
          efficiencyRepository,
        ),
        efficiencyPeakRatesAdapter: EfficiencyPeakRatesAdapter(
          CloudEfficiencyPeakRatesSource(api),
        ),
        tipsRepository: TipsDomainRepository(CloudTipsDomainSource(api)),
        settingsRepository: SettingsDomainRepository(
          CloudSettingsDomainSource(api),
        ),
        manageDevicesRepository: ManageDevicesDomainRepository(
          CloudManageDevicesDomainSource(api),
        ),
        knowledgeRepository: KnowledgeDomainRepository(
          CloudKnowledgeDomainSource(api),
        ),
      ),
      identificationCandidates: IdentificationCandidatesDomainAdapter(
        DiscoveryIdentificationCandidatesSource(credentials: credentials),
      ),
      settingsRegionalRate: SettingsRegionalRateAdapter(
        CloudSettingsRegionalRateSource(api),
      ),
      deviceReferenceObserver: DeviceReferenceInventoryObserver(
        CloudDeviceReferenceResolver(api),
      ),
    );
  }

  final DesignContextAdapters adapters;
  VerifiedDesignContext? _context;
  int _generation = 0;

  VerifiedDesignContext? get context => _context;
  int get generation => _generation;

  bool supportsPageRead(String page) {
    final context = _context;
    return context != null &&
        _readablePages.contains(page) &&
        (context.mode != DesignContextMode.sample ||
            _sampleModeReadablePages.contains(page));
  }

  void useVerifiedContext(VerifiedDesignContext context) {
    final previous = _context;
    if (previous?.accountId == context.accountId &&
        previous?.homeId == context.homeId &&
        previous?.mode == context.mode) {
      return;
    }
    _generation++;
    adapters.clear();
    identificationCandidates?.useVerifiedContext(context);
    settingsRegionalRate?.clear();
    deviceReferenceObserver?.clear();
    _context = context;
  }

  void signOut() {
    _generation++;
    _context = null;
    adapters.clear();
    identificationCandidates?.clear();
    settingsRegionalRate?.clear();
    deviceReferenceObserver?.clear();
  }

  /// Native-only regional estimate read for a verified household. Public rate
  /// data is scoped by the home's owned location before it reaches Settings.
  Future<DesignContextRead?> readSettingsRegionalRate() async {
    final context = _context;
    if (context == null) throw StateError('No verified design context');
    if (context.mode != DesignContextMode.household) {
      throw StateError('Regional rate is unavailable in sample context');
    }
    final adapter = settingsRegionalRate;
    if (adapter == null) throw StateError('Regional rate read unavailable');
    final generation = _generation;
    bool stale() => generation != _generation || !identical(context, _context);
    try {
      final value = await adapter.fetch(context.homeId);
      if (stale() || value == null || !value.isCurrent()) return null;
      if (value.homeId.toLowerCase() != context.homeId.toLowerCase()) {
        throw const FormatException('Settings regional rate context changed');
      }
      return DesignContextRead(
        accountId: context.accountId,
        homeId: context.homeId,
        mode: context.mode,
        page: 'settings_regional_rate',
        value: value,
      );
    } catch (_) {
      if (stale()) return null;
      rethrow;
    }
  }

  Future<DesignContextRead?> read(String page) async {
    final context = _context;
    if (context == null) throw StateError('No verified design context');
    // These pages have no approved read adapter. Knowledge requires a
    // specific FAQ question and is read through answerKnowledge instead.
    if (!_readablePages.contains(page) ||
        (context.mode == DesignContextMode.sample &&
            !_sampleModeReadablePages.contains(page))) {
      throw ArgumentError.value(page, 'page', 'Unsupported design read');
    }
    final generation = _generation;
    bool stale() => generation != _generation || !identical(context, _context);
    try {
      final Object? value = switch (page) {
        'dashboard' => await adapters.dashboard(context.homeId),
        'devices' => await adapters.devices(context.homeId),
        'efficiency' => await adapters.efficiency(
          context.homeId,
          EfficiencyPage.overview,
        ),
        'efficiency_away' => await adapters.efficiencyAway(context.homeId),
        'efficiency_habits' => await adapters.efficiencyHabits(context.homeId),
        'efficiency_peak_rates' => await adapters.efficiencyPeakRates(
          context.homeId,
        ),
        'perks_tips' => await adapters.tips(context.homeId, TipsPage.perksTips),
        'tips_efficiency' => await adapters.tips(
          context.homeId,
          TipsPage.efficiency,
        ),
        'tips_care_upgrades' => await adapters.tips(
          context.homeId,
          TipsPage.careUpgrades,
        ),
        'settings' => await adapters.settings(context.homeId),
        'settings_manage_devices' ||
        'settings_manual_device_entry' ||
        'settings_photo_scan_onboarding' => await adapters.manageDevices(
          context.homeId,
        ),
        _ => throw StateError('Unreachable design read'),
      };
      if (stale() || value == null) return null;
      _validateValue(context, value);
      if (page == 'devices' &&
          context.mode == DesignContextMode.household &&
          value is DevicesDomainSnapshot) {
        final observer = deviceReferenceObserver;
        if (observer != null) unawaited(observer.observe(value));
      }
      return DesignContextRead(
        accountId: context.accountId,
        homeId: context.homeId,
        mode: context.mode,
        page: page,
        value: value,
      );
    } catch (_) {
      if (stale()) return null;
      rethrow;
    }
  }

  Future<IdentificationCandidatesSnapshot?> lookupIdentificationCandidates({
    required String targetKind,
    String? ocrText,
    String? upc,
  }) async {
    if (_context == null) throw StateError('No verified design context');
    final candidates = identificationCandidates;
    if (candidates == null) {
      throw StateError('Identification lookup is not configured');
    }
    return candidates.lookup(
      targetKind: targetKind,
      ocrText: ocrText,
      upc: upc,
    );
  }

  Future<DesignContextRead?> answerKnowledge(
    String questionId, {
    String? applianceId,
  }) async {
    final context = _context;
    if (context == null) throw StateError('No verified design context');
    if (context.mode == DesignContextMode.sample) {
      throw StateError('Knowledge reads have no sample provenance');
    }
    final generation = _generation;
    bool stale() => generation != _generation || !identical(context, _context);
    try {
      final value = await adapters.knowledge(
        context.homeId,
        questionId,
        applianceId: applianceId,
      );
      if (stale() || value == null) return null;
      return DesignContextRead(
        accountId: context.accountId,
        homeId: context.homeId,
        mode: context.mode,
        page: 'tips_knowledge',
        value: value,
      );
    } catch (_) {
      if (stale()) return null;
      rethrow;
    }
  }

  /// Runtime is an independent optional read. It is never folded into the
  /// device inventory snapshot or displayed by the static shell.
  Future<DesignContextRead?> readDevicesRuntimeEvidence() async {
    final context = _context;
    if (context == null) throw StateError('No verified design context');
    if (context.mode != DesignContextMode.household) {
      throw StateError('Runtime evidence is unavailable in sample context');
    }
    final generation = _generation;
    bool stale() => generation != _generation || !identical(context, _context);
    try {
      final value = await adapters.devicesRuntimeEvidence(context.homeId);
      if (stale() || value == null) return null;
      if (value.homeId.toLowerCase() != context.homeId.toLowerCase() ||
          value.isSample) {
        throw const FormatException('Runtime evidence context changed');
      }
      return DesignContextRead(
        accountId: context.accountId,
        homeId: context.homeId,
        mode: context.mode,
        page: 'devices_runtime_evidence',
        value: value,
      );
    } catch (_) {
      if (stale()) return null;
      rethrow;
    }
  }

  /// Keeps inventory and Kasa runtime separate while accepting both only for
  /// one verified household context generation. Their source reads have no
  /// common revision token, so callers must not infer an atomic measurement.
  Future<DesignContextRead?> readDevicesConsistency() async {
    final context = _context;
    if (context == null) throw StateError('No verified design context');
    if (context.mode != DesignContextMode.household) {
      throw StateError('Devices consistency is unavailable in sample context');
    }
    final generation = _generation;
    bool stale() => generation != _generation || !identical(context, _context);
    try {
      final results = await Future.wait<Object?>([
        adapters.devices(context.homeId),
        adapters.devicesRuntimeEvidence(context.homeId),
      ]);
      if (stale() || results.any((result) => result == null)) return null;
      final inventory = results[0] as DevicesDomainSnapshot;
      final runtime = results[1] as DevicesRuntimeEvidenceSnapshot;
      if (inventory.isCurrent == null ||
          !inventory.isCurrent!() ||
          !runtime.isCurrent()) {
        return null;
      }
      _validateValue(context, inventory);
      if (runtime.homeId.toLowerCase() != context.homeId.toLowerCase() ||
          runtime.isSample ||
          inventory.items.length > DevicesDomainSnapshot.maxLocalInventory ||
          runtime.evidence.length > DevicesRuntimeEvidenceAdapter.maxRows) {
        throw const FormatException(
          'Devices consistency context or bound changed',
        );
      }
      final active = <String, String>{};
      final applianceIds = <String>{};
      for (final item in inventory.items) {
        if (!applianceIds.add(item.appliance.id) ||
            item.appliance.homeId.toLowerCase() !=
                context.homeId.toLowerCase()) {
          throw const FormatException('Ambiguous Devices inventory');
        }
        for (final attachmentId in item.activeAttachmentIds) {
          if (active.containsKey(attachmentId)) {
            throw const FormatException('Ambiguous Devices attachment');
          }
          active[attachmentId] = item.appliance.id;
        }
      }
      final snapshotIds = <String>{};
      for (final evidence in runtime.evidence) {
        if (!snapshotIds.add(evidence.snapshotId) ||
            active[evidence.attachmentId] != evidence.applianceId) {
          throw const FormatException('Ambiguous Devices runtime evidence');
        }
      }
      if (stale() || !inventory.isCurrent!() || !runtime.isCurrent()) {
        return null;
      }
      return DesignContextRead(
        accountId: context.accountId,
        homeId: context.homeId,
        mode: context.mode,
        page: 'devices_consistency',
        value: DevicesConsistencySnapshot(
          inventory,
          runtime,
          isCurrent: () =>
              !stale() && inventory.isCurrent!() && runtime.isCurrent(),
        ),
      );
    } catch (_) {
      if (stale()) return null;
      rethrow;
    }
  }
}

void _validateValue(VerifiedDesignContext context, Object value) {
  String? homeId;
  DesignContextMode? mode;
  if (value is DashboardDomainSnapshot) {
    homeId = value.homeId;
    mode = value.dataMode == 'sample'
        ? DesignContextMode.sample
        : DesignContextMode.household;
  } else if (value is EfficiencyDomainSnapshot) {
    homeId = value.homeId;
    mode = value.energy.dataMode == 'sample'
        ? DesignContextMode.sample
        : DesignContextMode.household;
  } else if (value is EfficiencyAwayDomainSnapshot) {
    homeId = value.homeId;
    mode = value.dataMode == 'sample'
        ? DesignContextMode.sample
        : DesignContextMode.household;
  } else if (value is EfficiencyHabitsSnapshot) {
    homeId = value.homeId;
    mode = value.energy.dataMode == 'sample'
        ? DesignContextMode.sample
        : DesignContextMode.household;
  } else if (value is EfficiencyPeakRatesSnapshot) {
    homeId = value.homeId;
    mode = DesignContextMode.household;
  } else if (value is DevicesDomainSnapshot) {
    homeId = value.homeId;
    mode = value.dataMode == CloudApplianceDataMode.sample
        ? DesignContextMode.sample
        : DesignContextMode.household;
  } else if (value is ManageDevicesDomainSnapshot) {
    homeId = value.homeId;
    mode = value.dataMode == CloudApplianceDataMode.sample
        ? DesignContextMode.sample
        : DesignContextMode.household;
  } else if (value is SettingsDomainSnapshot) {
    homeId = value.home.id;
    if (value.account.id != context.accountId) {
      throw const FormatException('Design account changed');
    }
  } else if (value is TipsDomainSnapshot) {
    homeId = value.homeId;
  }
  if (homeId == null ||
      homeId.toLowerCase() != context.homeId.toLowerCase() ||
      (mode != null && mode != context.mode)) {
    throw const FormatException('Design context changed');
  }
}

const _readablePages = <String>{
  'dashboard',
  'devices',
  'efficiency',
  'efficiency_away',
  'efficiency_habits',
  'efficiency_peak_rates',
  'perks_tips',
  'tips_efficiency',
  'tips_care_upgrades',
  'settings',
  'settings_manage_devices',
  'settings_manual_device_entry',
  'settings_photo_scan_onboarding',
};

// Only adapters with typed sample provenance may enter sample context.
const _sampleModeReadablePages = <String>{
  'dashboard',
  'devices',
  'efficiency',
  'efficiency_away',
  'efficiency_habits',
  'settings_manage_devices',
  'settings_manual_device_entry',
  'settings_photo_scan_onboarding',
};

final _uuid = RegExp(
  r'^[0-9a-fA-F]{8}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{12}$',
);
