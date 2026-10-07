import '../../core/cloud_api/cloud_appliance_list.dart';
import '../../core/cloud_api/cloud_api_client.dart';
import 'dashboard_domain_repository.dart';
import 'devices_domain_repository.dart';
import 'efficiency_domain_repository.dart';
import 'knowledge_domain_repository.dart';
import 'manage_devices_domain_repository.dart';
import 'settings_domain_repository.dart';
import 'tips_domain_repository.dart';

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
  Future<EfficiencyDomainSnapshot?> efficiency(
    String homeId,
    EfficiencyPage page,
  );
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
    required this.efficiencyRepository,
    required this.tipsRepository,
    required this.settingsRepository,
    required this.manageDevicesRepository,
    required this.knowledgeRepository,
  });

  final DashboardDomainRepository dashboardRepository;
  final DevicesDomainRepository devicesRepository;
  final EfficiencyDomainRepository efficiencyRepository;
  final TipsDomainRepository tipsRepository;
  final SettingsDomainRepository settingsRepository;
  final ManageDevicesDomainRepository manageDevicesRepository;
  final KnowledgeDomainRepository knowledgeRepository;

  @override
  void clear() {
    dashboardRepository.clear();
    devicesRepository.clear();
    efficiencyRepository.clear();
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
  Future<EfficiencyDomainSnapshot?> efficiency(
    String homeId,
    EfficiencyPage page,
  ) => efficiencyRepository.fetch(homeId, page);
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
  DesignContextCoordinator(this.adapters);

  /// Uses the same authenticated native client as CloudEntryGate. Nothing in
  /// this assembly is exposed to the WebView or visible shell.
  factory DesignContextCoordinator.forCloudApi(CloudApiClient api) =>
      DesignContextCoordinator(
        RepositoryDesignContextAdapters(
          dashboardRepository: DashboardDomainRepository(
            CloudDashboardDomainSource(api),
          ),
          devicesRepository: DevicesDomainRepository(
            CloudDevicesDomainSource(api),
          ),
          efficiencyRepository: EfficiencyDomainRepository(
            CloudEfficiencyDomainSource(api),
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
      );

  final DesignContextAdapters adapters;
  VerifiedDesignContext? _context;
  int _generation = 0;

  VerifiedDesignContext? get context => _context;

  void useVerifiedContext(VerifiedDesignContext context) {
    final previous = _context;
    if (previous?.accountId == context.accountId &&
        previous?.homeId == context.homeId &&
        previous?.mode == context.mode) {
      return;
    }
    _generation++;
    adapters.clear();
    _context = context;
  }

  void signOut() {
    _generation++;
    _context = null;
    adapters.clear();
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
        'efficiency_away' => await adapters.efficiency(
          context.homeId,
          EfficiencyPage.away,
        ),
        'efficiency_habits' => await adapters.efficiency(
          context.homeId,
          EfficiencyPage.habits,
        ),
        'efficiency_peak_rates' => await adapters.efficiency(
          context.homeId,
          EfficiencyPage.peak,
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
  'efficiency_peak_rates',
  'settings_manage_devices',
  'settings_manual_device_entry',
  'settings_photo_scan_onboarding',
};

final _uuid = RegExp(
  r'^[0-9a-fA-F]{8}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{12}$',
);
