import 'dart:async';

import 'package:flutter/material.dart';

import 'core/cloud_auth/cloud_entry_gate.dart';
import 'core/cloud_auth/cloud_preferences_screen.dart';
import 'core/cloud_api/cloud_home.dart';
import 'core/cloud_api/cloud_api_client.dart';
import 'core/cloud_api/cloud_appliance.dart';

import 'features/discovery/discovery_screen.dart';
import 'features/discovery/discovery_api.dart';
import 'features/discovery/discovery_credentials.dart';
import 'features/discovery/electricity_settings_screen.dart';
import 'features/design/demo_report_preview_screen.dart';
import 'features/energy/daily_cost.dart';
import 'features/energy/power_now_daily_cost_table.dart';
import 'features/energy/power_now_visibility.dart';
import 'features/energy/cloud_metered_history_screen.dart';
import 'features/energy/cloud_estimates_section.dart';
import 'features/energy/cloud_cycle_comparison_screen.dart';
import 'features/energy/cloud_kasa_runtime_screen.dart';
import 'features/energy/cloud_metered_summary_screen.dart';
import 'features/energy/cloud_faq_screen.dart';
import 'features/energy/cloud_recommendations_screen.dart';
import 'features/energy/stop_waste_programs.dart';
import 'features/energy/local_pilot_programs.dart';
import 'features/energy/cloud_report_preview_screen.dart';
import 'features/identify/appliance_onboarding_screen.dart';
import 'features/identify/cloud_usage_questions_screen.dart';
import 'features/design/design_shell.dart';
import 'features/design/local_pilot_device_lifecycle.dart';

void main() => runApp(const EnergyLensApp());

const _green = Color(0xFF008F68);
const _ink = Color(0xFF0F172A);
const _muted = Color(0xFF61738B);
const _rose = Color(0xFFE11D48);
const _line = Color(0xFFE1E8EE);

class EnergyLensApp extends StatelessWidget {
  const EnergyLensApp({
    super.key,
    this.localPilot = const bool.fromEnvironment('ENERGYLENS_LOCAL_PILOT'),
    this.localDiscoveryApi = const DiscoveryApi(),
    this.localDiscoveryCredentials = const DiscoveryCredentials(),
  });

  final bool localPilot;
  final DiscoveryApi localDiscoveryApi;
  final DiscoveryCredentials localDiscoveryCredentials;
  static final GlobalKey<NavigatorState> _navigatorKey =
      GlobalKey<NavigatorState>();

  @override
  Widget build(BuildContext context) {
    ThemeData theme(Brightness brightness) {
      final dark = brightness == Brightness.dark;
      final scheme = ColorScheme.fromSeed(
        seedColor: _green,
        brightness: brightness,
      );
      return ThemeData(
        useMaterial3: true,
        fontFamily: 'Source Sans 3',
        colorScheme: scheme,
        scaffoldBackgroundColor: dark
            ? const Color(0xFF101B2D)
            : const Color(0xFFF8FAFC),
        appBarTheme: AppBarTheme(
          titleTextStyle: TextStyle(
            fontFamily: 'Manrope',
            fontSize: 20,
            fontWeight: FontWeight.w700,
            color: dark ? Colors.white : _ink,
          ),
          backgroundColor: dark ? const Color(0xFF172337) : Colors.white,
          foregroundColor: dark ? Colors.white : _ink,
          surfaceTintColor: Colors.transparent,
          elevation: 0,
        ),
        cardTheme: CardThemeData(
          color: dark ? const Color(0xFF1D2A3D) : Colors.white,
          elevation: 1,
          shadowColor: const Color(0x141C4761),
          shape: RoundedRectangleBorder(
            side: BorderSide(color: dark ? const Color(0xFF354558) : _line),
            borderRadius: BorderRadius.circular(22),
          ),
          margin: EdgeInsets.zero,
        ),
        navigationBarTheme: NavigationBarThemeData(
          backgroundColor: dark ? const Color(0xFF172337) : Colors.white,
          indicatorColor: dark
              ? const Color(0xFF174A42)
              : const Color(0xFFE3F5ED),
          labelTextStyle: WidgetStatePropertyAll(
            TextStyle(
              fontWeight: FontWeight.w600,
              color: dark ? Colors.white : _ink,
            ),
          ),
        ),
      );
    }

    return MaterialApp(
      navigatorKey: _navigatorKey,
      title: 'EnergyLens',
      debugShowCheckedModeBanner: false,
      theme: theme(Brightness.light),
      darkTheme: theme(Brightness.dark),
      home: localPilot
          ? DesignShell(
              localPilot: true,
              onReportPreview: () => _navigatorKey.currentState?.push(
                MaterialPageRoute<void>(
                  builder: (_) => const DemoReportPreviewScreen(),
                ),
              ),
              localDeviceLifecycle: LocalPilotDeviceLifecycle(
                api: localDiscoveryApi,
                credentials: localDiscoveryCredentials,
              ),
              designTour: const bool.fromEnvironment('ENERGYLENS_DESIGN_TOUR'),
              onDiscoverDevices: () async {
                await _navigatorKey.currentState?.push(
                  MaterialPageRoute<void>(
                    builder: (_) => DiscoveryScreen(
                      autoScan: true,
                      api: localDiscoveryApi,
                      credentials: localDiscoveryCredentials,
                    ),
                  ),
                );
              },
            )
          : CloudEntryGate(
              homeBuilder: (cloudHome, signOut, changeHome, cloudApi) =>
                  DesignShell(
                    homeName: cloudHome?.name ?? 'The Miller Home',
                    settingsApi: cloudApi,
                    onSignOut: signOut,
                    onChangeHome: changeHome,
                    onReportPreview: cloudHome == null
                        ? null
                        : () => _navigatorKey.currentState?.push(
                            MaterialPageRoute<void>(
                              builder: (_) => CloudReportPreviewScreen(
                                api: cloudApi,
                                home: cloudHome,
                              ),
                            ),
                          ),
                  ),
              verifiedDesignHomeBuilder:
                  (
                    cloudHome,
                    signOut,
                    changeHome,
                    cloudApi,
                    lifecycle,
                    designContextCoordinator,
                  ) => DesignShell(
                    homeName: cloudHome.name,
                    settingsApi: cloudApi,
                    onSignOut: signOut,
                    onChangeHome: changeHome,
                    designContextCoordinator: designContextCoordinator,
                    onboardingLifecycle: lifecycle,
                    onDiscoverDevices: () async {
                      final accountId = lifecycle.verifiedAccountId;
                      if (accountId == null ||
                          !lifecycle.isVerifiedScope(accountId, cloudHome.id)) {
                        return;
                      }
                      await _navigatorKey.currentState?.push(
                        MaterialPageRoute<void>(
                          builder: (_) => DiscoveryScreen(
                            autoScan: true,
                            cloudHome: cloudHome,
                            cloudApi: cloudApi,
                            accountId: accountId,
                          ),
                        ),
                      );
                    },
                    onReportPreview: () {
                      final accountId = lifecycle.verifiedAccountId;
                      if (accountId == null ||
                          !lifecycle.isVerifiedScope(accountId, cloudHome.id)) {
                        return;
                      }
                      _navigatorKey.currentState?.push(
                        MaterialPageRoute<void>(
                          builder: (_) => CloudReportPreviewScreen(
                            api: cloudApi,
                            home: cloudHome,
                            lifecycle: lifecycle,
                            accountId: accountId,
                          ),
                        ),
                      );
                    },
                  ),
            ),
    );
  }
}

class HomeScreen extends StatefulWidget {
  const HomeScreen({
    super.key,
    this.api = const DiscoveryApi(),
    this.credentials = const DiscoveryCredentials(),
    this.initialTabIndex = 0,
    this.autoScanDiscovery = false,
    this.startInConnectAppliance = false,
    this.onCloudSignOut,
    this.onCloudChangeHome,
    this.cloudHome,
    this.cloudApi,
    this.accountId,
    this.localPilotMode = false,
    this.visibilityStore = const PowerNowVisibilityStore(),
  });

  final DiscoveryApi api;
  final DiscoveryCredentials credentials;
  final int initialTabIndex;
  final bool autoScanDiscovery;
  final bool startInConnectAppliance;
  final VoidCallback? onCloudSignOut;
  final VoidCallback? onCloudChangeHome;
  final CloudHome? cloudHome;
  final CloudApiClient? cloudApi;
  final String? accountId;
  final bool localPilotMode;
  final PowerNowVisibilityStore visibilityStore;

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> with WidgetsBindingObserver {
  late int _index;
  bool _hubConnected = false;
  List<SavedPlug> _plugs = const [];
  List<SavedAppliance> _appliances = const [];
  Map<int, EnergyEstimate> _estimates = const {};
  Map<String, DeviceEnergy> _meterReadings = const {};
  Map<String, (int, DeviceEnergy)> _todayMeterReadings = const {};
  Map<String, DeviceBaselineCoverage> _baselineCoverage = const {};
  ElectricitySettings? _householdSettings;
  bool _zipPromptDismissed = false;
  int _refreshGeneration = 0;
  int _meterGeneration = 0;
  Timer? _meterRefreshTimer;
  Set<int> _hiddenPowerNowIds = {};
  (String, String?)? _visibilityScope;
  Future<void> _visibilityWrite = Future.value();
  int _visibilityRevision = 0;

  OwnedPairingScope? get _householdPreferenceScope {
    final cloud = widget.cloudApi;
    final home = widget.cloudHome;
    final account = widget.accountId;
    if (cloud == null || home == null || account == null) return null;
    return OwnedPairingScope(
      origin: cloud.session.config.apiUrl,
      profile: cloud.session.credentialMethod,
      accountId: account,
      homeId: home.id,
    );
  }

  void _setPowerNowVisible(int applianceId, bool visible) {
    final scope = _visibilityScope;
    if (scope == null) return;
    final next = {..._hiddenPowerNowIds};
    if (visible) {
      next.remove(applianceId);
    } else {
      next.add(applianceId);
    }
    ++_visibilityRevision;
    setState(() => _hiddenPowerNowIds = next);
    _visibilityWrite = _visibilityWrite
        .then((_) => widget.visibilityStore.write(scope.$1, scope.$2, next))
        .catchError((_) {
          // Keep the current session usable if device storage is unavailable.
        });
  }

  @override
  void initState() {
    super.initState();
    _index = widget.initialTabIndex.clamp(0, _destinations.length - 1).toInt();
    WidgetsBinding.instance.addObserver(this);
    _refreshHub();
    _meterRefreshTimer = Timer.periodic(
      const Duration(seconds: 60),
      (_) => unawaited(_refreshConnectivityAndMetering()),
    );
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _meterRefreshTimer?.cancel();
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) _refreshHub();
  }

  Future<void> _refreshHub() async {
    final generation = ++_refreshGeneration;
    // Legacy local-pilot credentials have no verified Cloud owner scope.
    if (widget.cloudHome != null) {
      if (mounted) setState(() => _hubConnected = false);
      return;
    }
    try {
      final (address, token) = await widget.credentials.read();
      if (address == null || token == null) {
        if (mounted && generation == _refreshGeneration) {
          setState(() {
            _hubConnected = false;
            _meterReadings = const {};
            _todayMeterReadings = const {};
            _baselineCoverage = const {};
            ++_meterGeneration;
          });
        }
        return;
      }
      final scope = (address, widget.cloudHome?.id);
      final loadVisibility = _visibilityScope != scope;
      final visibilityRevision = _visibilityRevision;
      final plugs = await widget.api.saved(address, token);
      List<SavedAppliance> appliances;
      try {
        appliances = await widget.api.appliances(address, token);
      } catch (_) {
        appliances = [for (final plug in plugs) ?plug.connectedAppliance];
      }
      if (mounted && generation == _refreshGeneration) {
        setState(() {
          _plugs = plugs;
          _appliances = appliances;
          _hubConnected = true;
          _householdSettings = null;
          _estimates = const {};
          _meterReadings = const {};
          _todayMeterReadings = const {};
          _baselineCoverage = const {};
          _visibilityScope = scope;
          if (loadVisibility) _hiddenPowerNowIds = {};
        });
      }
      if (loadVisibility) {
        unawaited(() async {
          try {
            final hiddenIds = await widget.visibilityStore.read(
              scope.$1,
              scope.$2,
            );
            if (mounted &&
                _visibilityScope == scope &&
                _visibilityRevision == visibilityRevision) {
              setState(() => _hiddenPowerNowIds = hiddenIds);
            }
          } catch (_) {
            // An unavailable preference store leaves every device visible.
          }
        }());
      }
      unawaited(_refreshHouseholdSettings(address, token, generation));
      unawaited(
        _refreshBaselineCoverage(
          plugs: plugs,
          address: address,
          token: token,
          generation: generation,
        ),
      );
      unawaited(_refreshMetering(plugs: plugs, address: address, token: token));
      unawaited(_refreshPlugStatuses(plugs, address, token, generation));
      await Future.wait([
        for (final appliance in appliances)
          if (!plugs.any(
            (plug) =>
                plug.connectedAppliance?.id == appliance.id &&
                plug.connectionStatus == 'identity_changed',
          ))
            () async {
              try {
                final estimate = await widget.api.estimate(
                  address,
                  token,
                  appliance.id,
                );
                if (mounted &&
                    generation == _refreshGeneration &&
                    !_plugs.any(
                      (current) =>
                          current.connectedAppliance?.id == appliance.id &&
                          current.connectionStatus == 'identity_changed',
                    )) {
                  setState(
                    () => _estimates = {..._estimates, appliance.id: estimate},
                  );
                }
              } catch (_) {
                // One unavailable estimate must not hide the saved plug.
              }
            }(),
      ]);
    } catch (_) {
      if (mounted && generation == _refreshGeneration) {
        setState(() {
          _hubConnected = false;
          _meterReadings = const {};
          _todayMeterReadings = const {};
          _baselineCoverage = const {};
          ++_meterGeneration;
        });
      }
    }
  }

  Future<void> _refreshHouseholdSettings(
    String address,
    String token,
    int generation,
  ) async {
    try {
      final settings = await widget.api.electricitySettings(address, token);
      final scope = _householdPreferenceScope;
      final dismissed = widget.cloudHome != null && scope == null
          ? false
          : await widget.credentials.readZipPromptDismissed(scope: scope);
      if (mounted && generation == _refreshGeneration) {
        setState(() {
          _householdSettings = settings;
          _zipPromptDismissed = dismissed;
        });
      }
    } catch (_) {
      // An unavailable profile must not be mistaken for a missing ZIP.
      if (mounted && generation == _refreshGeneration) {
        setState(() => _householdSettings = null);
      }
    }
  }

  Future<void> _dismissZipPrompt() async {
    setState(() => _zipPromptDismissed = true);
    try {
      final scope = _householdPreferenceScope;
      if (widget.cloudHome == null || scope != null) {
        await widget.credentials.dismissZipPrompt(scope: scope);
      }
    } catch (_) {
      // The current screen still honors the dismissal.
    }
  }

  Future<void> _refreshConnectivityAndMetering() async {
    final generation = ++_refreshGeneration;
    try {
      final (address, token) = await widget.credentials.read();
      if (address == null || token == null) {
        if (mounted && generation == _refreshGeneration) {
          setState(() {
            _hubConnected = false;
            _meterReadings = const {};
            _todayMeterReadings = const {};
            _baselineCoverage = const {};
            ++_meterGeneration;
          });
        }
        return;
      }
      final plugs = await widget.api.saved(address, token);
      List<SavedAppliance> appliances;
      try {
        appliances = await widget.api.appliances(address, token);
      } catch (_) {
        appliances = _appliances;
      }
      if (!mounted || generation != _refreshGeneration) return;
      setState(() {
        _hubConnected = true;
        _plugs = plugs;
        _appliances = appliances;
        _baselineCoverage = const {};
      });
      unawaited(
        _refreshBaselineCoverage(
          plugs: plugs,
          address: address,
          token: token,
          generation: generation,
        ),
      );
      await _refreshMetering(plugs: plugs, address: address, token: token);
      await _refreshPlugStatuses(plugs, address, token, generation);
    } catch (_) {
      if (mounted && generation == _refreshGeneration) {
        setState(() {
          _hubConnected = false;
          _meterReadings = const {};
          _todayMeterReadings = const {};
          _baselineCoverage = const {};
          ++_meterGeneration;
        });
      }
    }
  }

  Future<void> _refreshPlugStatuses(
    List<SavedPlug> plugs,
    String address,
    String token,
    int generation,
  ) async {
    for (final plug in plugs) {
      if (!mounted || generation != _refreshGeneration) return;
      try {
        final refreshed = await widget.api.refreshPlugStatus(
          address,
          token,
          plug.id,
        );
        if (!mounted || generation != _refreshGeneration) return;
        setState(() {
          _plugs = [
            for (final current in _plugs)
              if (current.id == refreshed.id) refreshed else current,
          ];
          if (refreshed.connectionStatus == 'identity_changed') {
            final today = {..._todayMeterReadings};
            today.remove(refreshed.id);
            _todayMeterReadings = today;
            final applianceId = refreshed.connectedAppliance?.id;
            if (applianceId != null) {
              final next = {..._estimates};
              next.remove(applianceId);
              _estimates = next;
            }
          }
        });
      } catch (_) {
        // A failed check leaves the previous timestamp and status intact.
      }
    }
  }

  Future<void> _refreshBaselineCoverage({
    required List<SavedPlug> plugs,
    required String address,
    required String token,
    required int generation,
  }) async {
    final computers = plugs.where(
      (plug) => plug.connectedAppliance?.category == 'computer',
    );
    await Future.wait([
      for (final plug in computers)
        () async {
          try {
            final coverage = await widget.api.deviceBaselineCoverage(
              address,
              token,
              plug.id,
            );
            if (mounted && generation == _refreshGeneration) {
              setState(
                () => _baselineCoverage = {
                  ..._baselineCoverage,
                  plug.id: coverage,
                },
              );
            }
          } catch (_) {
            // Keep missing coverage unavailable; never infer a state from it.
          }
        }(),
    ]);
  }

  Future<void> _refreshMetering({
    List<SavedPlug>? plugs,
    String? address,
    String? token,
  }) async {
    final generation = ++_meterGeneration;
    try {
      if (address == null || token == null) {
        (address, token) = await widget.credentials.read();
      }
      if (address == null || token == null) return;
      final hubAddress = address;
      final hubToken = token;
      final candidates = plugs ?? _plugs;
      if (mounted && generation == _meterGeneration) {
        setState(() => _todayMeterReadings = const {});
      }
      await Future.wait([
        for (final plug in candidates)
          if (plug.meterStatus == 'verified' &&
              const {
                'legacy_tcp',
                'http',
                'shelly_gen2',
                'tasmota',
              }.contains(plug.localProtocol))
            () async {
              await Future.wait([
                _refreshPlugEnergy(
                  hubAddress,
                  hubToken,
                  plug.id,
                  generation,
                  period: 'day',
                ),
                if (plug.connectedAppliance != null)
                  _refreshPlugEnergy(
                    hubAddress,
                    hubToken,
                    plug.id,
                    generation,
                    period: 'today',
                    attachedApplianceId: plug.connectedAppliance!.id,
                    timezone: widget.localPilotMode
                        ? null
                        : widget.cloudHome?.timezone,
                  ),
              ]);
            }(),
      ]);
    } catch (_) {
      // A meter API failure must not hide saved plugs or sourced estimates.
    }
  }

  Future<void> _refreshPlugEnergy(
    String address,
    String token,
    String plugId,
    int generation, {
    required String period,
    int? attachedApplianceId,
    String? timezone,
  }) async {
    final today = period == 'today';
    try {
      final reading = await widget.api.deviceEnergy(
        address,
        token,
        plugId,
        period: period,
        timezone: timezone,
      );
      if (mounted && generation == _meterGeneration) {
        setState(() {
          if (today) {
            final currentPlug = _plugs
                .where((plug) => plug.id == plugId)
                .firstOrNull;
            if (currentPlug?.connectedAppliance?.id == attachedApplianceId &&
                currentPlug?.connectionStatus != 'identity_changed') {
              _todayMeterReadings = {
                ..._todayMeterReadings,
                plugId: (attachedApplianceId!, reading),
              };
            }
          } else {
            _meterReadings = {..._meterReadings, plugId: reading};
          }
        });
      }
    } catch (_) {
      if (mounted && generation == _meterGeneration) {
        setState(() {
          if (today) {
            final next = {..._todayMeterReadings};
            next.remove(plugId);
            _todayMeterReadings = next;
          } else {
            final next = {..._meterReadings};
            next.remove(plugId);
            _meterReadings = next;
          }
        });
      }
    }
  }

  Future<void> _saveApplianceHours(int applianceId, double hoursPerWeek) async {
    final (address, token) = await widget.credentials.read();
    if (address == null || token == null) {
      throw StateError('Hub connection needed');
    }
    await widget.api.updateApplianceHours(
      address,
      token,
      applianceId,
      hoursPerWeek,
    );
    await _refreshHub();
  }

  Future<ApplianceUsageProfile> _loadApplianceUsage(int applianceId) async {
    final (address, token) = await widget.credentials.read();
    if (address == null || token == null) {
      throw StateError('Hub connection needed');
    }
    return widget.api.applianceUsageProfile(address, token, applianceId);
  }

  Future<ApplianceUsageProfile> _saveApplianceUsage(
    int applianceId,
    String usageKind,
    double value,
  ) async {
    final (address, token) = await widget.credentials.read();
    if (address == null || token == null) {
      throw StateError('Hub connection needed');
    }
    final saved = await widget.api.updateApplianceUsageProfile(
      address,
      token,
      applianceId,
      usageKind,
      value,
    );
    await _refreshHub();
    return saved;
  }

  static const _destinations = <NavigationDestination>[
    NavigationDestination(
      icon: Icon(Icons.bolt_outlined),
      selectedIcon: Icon(Icons.bolt),
      label: 'Power Now',
    ),
    NavigationDestination(
      icon: Icon(Icons.energy_savings_leaf_outlined),
      selectedIcon: Icon(Icons.energy_savings_leaf),
      label: 'Stop Waste',
    ),
    NavigationDestination(
      icon: Icon(Icons.nights_stay_outlined),
      selectedIcon: Icon(Icons.nights_stay),
      label: 'Sleep Check',
    ),
    NavigationDestination(
      icon: Icon(Icons.chat_bubble_outline),
      selectedIcon: Icon(Icons.chat_bubble),
      label: 'Ask & Add',
    ),
  ];

  Future<void> _openElectricitySettings() async {
    await Navigator.of(context).push<void>(
      MaterialPageRoute<void>(
        builder: (_) => ElectricitySettingsScreen(
          api: widget.api,
          credentials: widget.credentials,
          cloudHome: widget.cloudHome,
          cloudApi: widget.cloudApi,
          preferenceScope: _householdPreferenceScope,
          onSaved: _refreshHub,
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final wide = MediaQuery.sizeOf(context).width >= 720;
    final content = switch (_index) {
      0 => _PowerNow(
        plugs: _plugs,
        appliances: _appliances,
        hubConnected: _hubConnected,
        estimates: _estimates,
        estimatesStale: !_hubConnected && _estimates.isNotEmpty,
        meterReadings: _meterReadings,
        todayMeterReadings: _todayMeterReadings,
        hiddenApplianceIds: _hiddenPowerNowIds,
        onHideAppliance: (id) => _setPowerNowVisible(id, false),
        showZipPrompt:
            _hubConnected &&
            _householdSettings != null &&
            (_householdSettings!.postalCode?.isEmpty ?? true) &&
            !_zipPromptDismissed,
        onDismissZipPrompt: _dismissZipPrompt,
        onOpenElectricitySettings: _openElectricitySettings,
        onHoursChanged: _saveApplianceHours,
        onLoadUsage: _loadApplianceUsage,
        onUsageChanged: _saveApplianceUsage,
      ),
      1 =>
        widget.cloudHome != null && widget.cloudApi != null
            ? _CloudStopWaste(
                home: widget.cloudHome!,
                api: widget.cloudApi!,
                onViewEstimates: () => setState(() => _index = 0),
              )
            : _StopWaste(localPilotMode: widget.localPilotMode),
      2 => _SleepCheck(
        plugs: _plugs,
        baselineCoverage: _baselineCoverage,
        hubConnected: _hubConnected,
      ),
      _ => _AskAndAdd(
        api: widget.api,
        credentials: widget.credentials,
        appliances: _appliances,
        estimates: _estimates,
        hiddenPowerNowIds: _hiddenPowerNowIds,
        onShowOnPowerNow: (id) => _setPowerNowVisible(id, true),
        onHoursChanged: _saveApplianceHours,
        onLoadUsage: _loadApplianceUsage,
        onUsageChanged: _saveApplianceUsage,
        cloudHome: widget.cloudHome,
        cloudApi: widget.cloudApi,
        onDevicesChanged: _refreshHub,
        autoScanDiscovery: widget.autoScanDiscovery,
        startInConnectAppliance: widget.startInConnectAppliance,
      ),
    };
    return Scaffold(
      appBar: AppBar(
        toolbarHeight: 74,
        titleSpacing: 16,
        title: Row(
          children: [
            Container(
              width: 36,
              height: 36,
              decoration: BoxDecoration(
                color: const Color(0xFF101B2D),
                borderRadius: BorderRadius.circular(9),
              ),
              child: const Icon(Icons.bolt, color: Color(0xFF26DBBF)),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'EnergyLens Home',
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: Theme.of(context).textTheme.titleMedium
                        ?.copyWith(fontWeight: FontWeight.w700),
                  ),
                  Row(
                    children: [
                      const CircleAvatar(
                        radius: 3,
                        backgroundColor: Color(0xFF94A3B8),
                      ),
                      const SizedBox(width: 4),
                      Flexible(
                        child: Text(
                          _hubConnected ? 'HUB CONNECTED' : 'HUB DISCONNECTED',
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: Theme.of(context).textTheme.labelSmall
                              ?.copyWith(
                                color: _secondary(context),
                                letterSpacing: .7,
                                fontWeight: FontWeight.w700,
                              ),
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ],
        ),
        actions: [
          if (widget.cloudApi != null && widget.cloudHome != null)
            IconButton(
              tooltip: 'Cloud settings',
              onPressed: () => Navigator.of(context).push(
                MaterialPageRoute<void>(
                  builder: (_) => CloudPreferencesScreen(
                    api: widget.cloudApi!,
                    home: widget.cloudHome,
                  ),
                ),
              ),
              icon: const Icon(Icons.tune),
            ),
          if (widget.onCloudChangeHome != null)
            IconButton(
              tooltip: 'Change cloud home',
              onPressed: widget.onCloudChangeHome,
              icon: const Icon(Icons.home_outlined),
            ),
          if (widget.onCloudSignOut != null)
            IconButton(
              tooltip: 'Sign out',
              onPressed: widget.onCloudSignOut,
              icon: const Icon(Icons.logout),
            ),
          TextButton.icon(
            key: const Key('openElectricitySettings'),
            onPressed: _openElectricitySettings,
            icon: const Icon(Icons.person_outline),
            label: const Text('Profile'),
          ),
          Padding(
            padding: const EdgeInsets.only(right: 16),
            child: Center(
              child: Tooltip(
                message: _hubConnected ? 'Hub connected' : 'Hub disconnected',
                child: Semantics(
                  label: _hubConnected ? 'Hub connected' : 'Hub disconnected',
                  child: Container(
                    width: 36,
                    height: 36,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      color: Theme.of(context).colorScheme.surfaceContainerLow,
                      border: Border.all(
                        color: Theme.of(context).colorScheme.outlineVariant,
                      ),
                    ),
                    child: Icon(
                      _hubConnected
                          ? Icons.check_circle_outline
                          : Icons.power_off_outlined,
                      size: 20,
                    ),
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
      body: Row(
        children: [
          if (wide)
            NavigationRail(
              selectedIndex: _index,
              onDestinationSelected: (value) {
                setState(() => _index = value);
                _refreshHub();
              },
              labelType: NavigationRailLabelType.all,
              destinations: _destinations
                  .map(
                    (d) => NavigationRailDestination(
                      icon: d.icon,
                      selectedIcon: d.selectedIcon,
                      label: Text(d.label),
                    ),
                  )
                  .toList(),
            ),
          Expanded(
            child: Align(
              alignment: Alignment.topCenter,
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 780),
                child: SingleChildScrollView(
                  key: ValueKey(_index),
                  padding: const EdgeInsets.fromLTRB(16, 0, 16, 36),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      if (widget.localPilotMode) ...[
                        Card(
                          key: const Key('localPilotNotice'),
                          child: Padding(
                            padding: const EdgeInsets.all(16),
                            child: Text(
                              'Local photo pilot · No Cloud account is connected. Label recognition stays on this phone; saving a device needs a paired local hub. Cloud inventory, estimates, and recommendations are unavailable.',
                              style: Theme.of(context).textTheme.bodyMedium,
                            ),
                          ),
                        ),
                        const SizedBox(height: 16),
                      ],
                      if (widget.cloudHome != null) ...[
                        Card(
                          child: Padding(
                            padding: const EdgeInsets.all(12),
                            child: Text(
                              'Cloud home: ${widget.cloudHome!.name}. Local device data below has not synced to Cloud yet.',
                            ),
                          ),
                        ),
                        const SizedBox(height: 8),
                        if (_index == 0 && widget.cloudApi != null) ...[
                          CloudEstimatesSection(
                            api: widget.cloudApi!,
                            home: widget.cloudHome!,
                          ),
                          const SizedBox(height: 12),
                          OutlinedButton.icon(
                            onPressed: () => Navigator.of(context).push(
                              MaterialPageRoute<void>(
                                builder: (_) => CloudMeteredHistoryScreen(
                                  api: widget.cloudApi!,
                                  home: widget.cloudHome!,
                                ),
                              ),
                            ),
                            icon: const Icon(Icons.history),
                            label: const Text('View Cloud meter history'),
                          ),
                          const SizedBox(height: 12),
                          OutlinedButton.icon(
                            onPressed: () => Navigator.of(context).push(
                              MaterialPageRoute<void>(
                                builder: (_) => CloudMeteredSummaryScreen(
                                  api: widget.cloudApi!,
                                  home: widget.cloudHome!,
                                ),
                              ),
                            ),
                            icon: const Icon(Icons.bar_chart),
                            label: const Text('View Cloud meter summaries'),
                          ),
                          const SizedBox(height: 12),
                          OutlinedButton.icon(
                            key: const Key('openCloudCycleComparison'),
                            onPressed: () => Navigator.of(context).push(
                              MaterialPageRoute<void>(
                                builder: (_) => CloudCycleComparisonScreen(
                                  api: widget.cloudApi!,
                                  home: widget.cloudHome!,
                                ),
                              ),
                            ),
                            icon: const Icon(Icons.compare_arrows_outlined),
                            label: const Text('Compare a dishwasher cycle'),
                          ),
                          const SizedBox(height: 12),
                          OutlinedButton.icon(
                            onPressed: () => Navigator.of(context).push(
                              MaterialPageRoute<void>(
                                builder: (_) => CloudKasaRuntimeScreen(
                                  api: widget.cloudApi!,
                                  home: widget.cloudHome!,
                                ),
                              ),
                            ),
                            icon: const Icon(Icons.timer_outlined),
                            label: const Text('View Cloud Kasa runtime'),
                          ),
                          const SizedBox(height: 12),
                        ],
                        if (_index == 3 && widget.cloudApi != null) ...[
                          OutlinedButton.icon(
                            key: const Key('openCloudReportPreview'),
                            onPressed: () => Navigator.of(context).push(
                              MaterialPageRoute<void>(
                                builder: (_) => CloudReportPreviewScreen(
                                  api: widget.cloudApi!,
                                  home: widget.cloudHome!,
                                ),
                              ),
                            ),
                            icon: const Icon(Icons.description_outlined),
                            label: const Text('Private report preview'),
                          ),
                          const SizedBox(height: 12),
                          OutlinedButton.icon(
                            key: const Key('openCloudRecommendations'),
                            onPressed: () => Navigator.of(context).push(
                              MaterialPageRoute<void>(
                                builder: (_) => CloudRecommendationsScreen(
                                  api: widget.cloudApi!,
                                  home: widget.cloudHome!,
                                ),
                              ),
                            ),
                            icon: const Icon(Icons.lightbulb_outline),
                            label: const Text('Actions to consider'),
                          ),
                          const SizedBox(height: 12),
                          OutlinedButton.icon(
                            key: const Key('openCloudFaq'),
                            onPressed: () => Navigator.of(context).push(
                              MaterialPageRoute<void>(
                                builder: (_) => CloudFaqScreen(
                                  api: widget.cloudApi!,
                                  home: widget.cloudHome!,
                                ),
                              ),
                            ),
                            icon: const Icon(Icons.question_answer_outlined),
                            label: const Text('Ask about this cloud home'),
                          ),
                          const SizedBox(height: 12),
                        ],
                      ],
                      content,
                    ],
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
      bottomNavigationBar: wide
          ? null
          : NavigationBar(
              selectedIndex: _index,
              onDestinationSelected: (value) {
                setState(() => _index = value);
                _refreshHub();
              },
              destinations: _destinations,
            ),
    );
  }
}

bool _isDark(BuildContext context) =>
    Theme.of(context).brightness == Brightness.dark;

Color _softSurface(BuildContext context) => _isDark(context)
    ? Theme.of(context).colorScheme.surfaceContainerHigh
    : const Color(0xFFF8FAFC);

Color _secondary(BuildContext context) =>
    _isDark(context) ? Theme.of(context).colorScheme.onSurfaceVariant : _muted;

class _Surface extends StatelessWidget {
  const _Surface({required this.child});
  final Widget child;

  @override
  Widget build(BuildContext context) => Card(
    child: Padding(padding: const EdgeInsets.all(16), child: child),
  );
}

class _IconWell extends StatelessWidget {
  const _IconWell(this.icon, {this.color = _green});
  final IconData icon;
  final Color color;

  @override
  Widget build(BuildContext context) => Container(
    width: 42,
    height: 42,
    decoration: BoxDecoration(
      color: color.withValues(alpha: _isDark(context) ? .2 : .09),
      shape: BoxShape.circle,
    ),
    child: Icon(icon, color: color, size: 22),
  );
}

class _Setup extends StatelessWidget {
  const _Setup();

  @override
  Widget build(BuildContext context) => _Surface(
    child: Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const _IconWell(Icons.power_outlined, color: Color(0xFF007FBE)),
        const SizedBox(width: 12),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'Connect a monitored computer',
                style: Theme.of(context).textTheme.titleMedium
                    ?.copyWith(fontWeight: FontWeight.w700),
              ),
              const SizedBox(height: 5),
              Text(
                'Pair a supported energy-monitoring plug with a local hub. Live readings will appear when the EnergyLens hub connection is available.',
                style: Theme.of(context).textTheme.bodyMedium
                    ?.copyWith(color: _secondary(context)),
              ),
              const SizedBox(height: 7),
              ExpansionTile(
                tilePadding: EdgeInsets.zero,
                childrenPadding: EdgeInsets.zero,
                dense: true,
                title: const Text('What you’ll need'),
                children: const [
                  ListTile(
                    leading: Text('1'),
                    title: Text(
                      'A compatible energy-monitoring plug on your computer’s power connection.',
                    ),
                  ),
                  ListTile(
                    leading: Text('2'),
                    title: Text(
                      'A local EnergyLens hub to collect timestamped readings.',
                    ),
                  ),
                  ListTile(
                    leading: Text('3'),
                    title: Text(
                      'Use Ask & Add to find a plug through the hub, or enter its local IP address.',
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      ],
    ),
  );
}

class _SectionTitle extends StatelessWidget {
  const _SectionTitle(this.title, this.aside);
  final String title;
  final String aside;

  @override
  Widget build(BuildContext context) => Row(
    crossAxisAlignment: CrossAxisAlignment.end,
    children: [
      Expanded(
        child: Text(
          title,
          style: Theme.of(context).textTheme.titleLarge
              ?.copyWith(fontWeight: FontWeight.w700),
        ),
      ),
      const SizedBox(width: 8),
      Text(
        aside,
        textAlign: TextAlign.right,
        style: Theme.of(context).textTheme.labelSmall
            ?.copyWith(color: _secondary(context)),
      ),
    ],
  );
}

class _InfoRow extends StatelessWidget {
  const _InfoRow(
    this.icon,
    this.title,
    this.detail, {
    this.color = const Color(0xFF007FBE),
    this.action,
  });
  final IconData icon;
  final String title;
  final String detail;
  final Color color;
  final Widget? action;

  @override
  Widget build(BuildContext context) => _Surface(
    child: Row(
      children: [
        _IconWell(icon, color: color),
        const SizedBox(width: 12),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                title,
                style: Theme.of(context).textTheme.titleSmall
                    ?.copyWith(fontWeight: FontWeight.w700),
              ),
              const SizedBox(height: 3),
              Text(
                detail,
                style: Theme.of(context).textTheme.bodySmall
                    ?.copyWith(color: _secondary(context)),
              ),
              if (action != null) ...[const SizedBox(height: 8), action!],
            ],
          ),
        ),
      ],
    ),
  );
}

class _ConnectedLoadRow extends StatefulWidget {
  const _ConnectedLoadRow({
    super.key,
    required this.appliance,
    required this.estimate,
    required this.onHoursChanged,
    required this.onLoadUsage,
    required this.onUsageChanged,
  });

  final SavedAppliance appliance;
  final EnergyEstimate? estimate;
  final Future<void> Function(int, double) onHoursChanged;
  final Future<ApplianceUsageProfile> Function(int) onLoadUsage;
  final Future<ApplianceUsageProfile> Function(int, String, double)
  onUsageChanged;

  @override
  State<_ConnectedLoadRow> createState() => _ConnectedLoadRowState();
}

class _ConnectedLoadRowState extends State<_ConnectedLoadRow> {
  double? _previewHours;
  double? _previewCycles;
  ApplianceUsageProfile? _usageProfile;
  bool _saving = false;
  String? _saveError;

  @override
  void initState() {
    super.initState();
    _loadUsage();
  }

  Future<void> _loadUsage() async {
    try {
      final profile = await widget.onLoadUsage(widget.appliance.id);
      if (mounted && profile.applianceId == widget.appliance.id) {
        setState(() => _usageProfile = profile);
      }
    } catch (_) {
      // Older hubs have no usage-profile route; keep the existing hours view.
    }
  }

  @override
  void didUpdateWidget(covariant _ConnectedLoadRow oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.appliance.id != oldWidget.appliance.id) {
      _usageProfile = null;
      _previewCycles = null;
      _loadUsage();
    }
    if (widget.appliance.hoursPerWeek != oldWidget.appliance.hoursPerWeek) {
      _previewHours = null;
      _saveError = null;
    }
  }

  Future<void> _commitCycles(double value) async {
    if (_saving || value == _usageProfile?.value) {
      setState(() => _previewCycles = null);
      return;
    }
    setState(() {
      _saving = true;
      _saveError = null;
    });
    try {
      final saved = await widget.onUsageChanged(
        widget.appliance.id,
        'cycles_per_week',
        value,
      );
      if (mounted) {
        setState(() {
          _usageProfile = saved;
          _previewCycles = null;
        });
      }
    } catch (_) {
      if (mounted) {
        setState(() {
          _previewCycles = null;
          _saveError = 'Could not save cycles. Try again.';
        });
      }
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  Future<void> _commitHours(double value) async {
    if (_saving || value == widget.appliance.hoursPerWeek) {
      setState(() => _previewHours = null);
      return;
    }
    setState(() {
      _saving = true;
      _saveError = null;
    });
    try {
      await widget.onHoursChanged(widget.appliance.id, value);
      if (mounted) setState(() => _previewHours = null);
    } catch (_) {
      if (mounted) {
        setState(() {
          _previewHours = null;
          _saveError = 'Could not save hours. Try again.';
        });
      }
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  Future<void> _commitProfileHours(double value) async {
    if (_saving || value == _usageProfile?.value) {
      setState(() => _previewHours = null);
      return;
    }
    setState(() {
      _saving = true;
      _saveError = null;
    });
    try {
      final saved = await widget.onUsageChanged(
        widget.appliance.id,
        'hours_per_week',
        value,
      );
      if (mounted) {
        setState(() {
          _usageProfile = saved;
          _previewHours = null;
        });
      }
    } catch (_) {
      if (mounted) {
        setState(() {
          _previewHours = null;
          _saveError = 'Could not save hours. Try again.';
        });
      }
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final appliance = widget.appliance;
    final estimate = widget.estimate;
    final measured = estimate?.status == 'measured';
    final hours = _previewHours ?? appliance.hoursPerWeek;
    final initialHours = appliance.initialHoursPerWeek;
    final showProfileHours =
        _usageProfile?.usageKind == 'hours_per_week' &&
        !measured &&
        !(appliance.category == 'lighting' &&
            appliance.loadKind == 'replaceable_bulb');
    final cost = estimate?.estimatedCostUsd;
    return _Surface(
      child: Row(
        children: [
          const _IconWell(Icons.lightbulb_outline),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  appliance.name,
                  style: Theme.of(context).textTheme.titleSmall
                      ?.copyWith(fontWeight: FontWeight.w700),
                ),
                const SizedBox(height: 4),
                Text(measured ? 'Last 30 days' : 'Per month'),
                if (estimate?.estimatedKwh != null)
                  Text(
                    'Energy · ${estimate!.estimatedKwh!.toStringAsFixed(1)} kWh',
                  ),
                Text(
                  cost != null
                      ? 'Cost · \$${cost.toStringAsFixed(2)}'
                      : 'Energy data is not available yet.',
                  style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                    color: cost == null ? _secondary(context) : _green,
                    fontWeight: cost == null
                        ? FontWeight.normal
                        : FontWeight.w700,
                  ),
                ),
                if (appliance.category == 'lighting' &&
                    appliance.loadKind == 'replaceable_bulb' &&
                    hours != null) ...[
                  const SizedBox(height: 8),
                  Text(
                    'On time: ${hours.toStringAsFixed(0)} hours/week',
                    style: Theme.of(context).textTheme.bodySmall
                        ?.copyWith(color: _secondary(context)),
                  ),
                  Slider(
                    key: Key('appliance-hours-${appliance.id}'),
                    value: hours.clamp(0, 168),
                    min: 0,
                    max: 168,
                    divisions: 168,
                    label: '${hours.toStringAsFixed(0)} hours/week',
                    semanticFormatterCallback: (value) =>
                        '${value.toStringAsFixed(0)} hours per week',
                    onChanged: _saving
                        ? null
                        : (value) => setState(() {
                            _previewHours = value;
                            _saveError = null;
                          }),
                    onChangeEnd: _saving ? null : _commitHours,
                  ),
                  if (initialHours != null)
                    Align(
                      alignment: Alignment.centerRight,
                      child: TextButton.icon(
                        key: Key('reset-appliance-hours-${appliance.id}'),
                        onPressed: _saving || hours == initialHours
                            ? null
                            : () => _commitHours(initialHours),
                        icon: const Icon(Icons.restore),
                        label: Text(
                          'Reset to ${initialHours.toStringAsFixed(0)} hours/week',
                        ),
                      ),
                    ),
                  if (_saving) const LinearProgressIndicator(),
                  if (_saveError != null)
                    Text(
                      _saveError!,
                      style: Theme.of(context).textTheme.bodySmall?.copyWith(
                        color: Theme.of(context).colorScheme.error,
                      ),
                    ),
                ],
                if (showProfileHours) ...[
                  const SizedBox(height: 8),
                  Text(
                    'Use: ${(_previewHours ?? _usageProfile!.value).toStringAsFixed(0)} hours/week',
                    style: Theme.of(context).textTheme.bodySmall
                        ?.copyWith(color: _secondary(context)),
                  ),
                  Slider(
                    key: Key('appliance-profile-hours-${appliance.id}'),
                    value: (_previewHours ?? _usageProfile!.value).clamp(
                      _usageProfile!.min,
                      _usageProfile!.max,
                    ),
                    min: _usageProfile!.min,
                    max: _usageProfile!.max,
                    divisions:
                        ((_usageProfile!.max - _usageProfile!.min) /
                                _usageProfile!.step)
                            .round(),
                    label:
                        '${(_previewHours ?? _usageProfile!.value).toStringAsFixed(0)} hours/week',
                    onChanged: _saving
                        ? null
                        : (value) => setState(() {
                            _previewHours = value;
                            _saveError = null;
                          }),
                    onChangeEnd: _saving ? null : _commitProfileHours,
                  ),
                  Align(
                    alignment: Alignment.centerRight,
                    child: TextButton.icon(
                      key: Key('reset-appliance-profile-hours-${appliance.id}'),
                      onPressed:
                          _saving ||
                              _usageProfile!.value ==
                                  _usageProfile!.initialValue
                          ? null
                          : () => _commitProfileHours(
                              _usageProfile!.initialValue,
                            ),
                      icon: const Icon(Icons.restore),
                      label: Text(
                        'Reset to ${_usageProfile!.initialValue.toStringAsFixed(0)} hours/week',
                      ),
                    ),
                  ),
                  if (_saving) const LinearProgressIndicator(),
                  if (_saveError != null)
                    Text(
                      _saveError!,
                      style: Theme.of(context).textTheme.bodySmall?.copyWith(
                        color: Theme.of(context).colorScheme.error,
                      ),
                    ),
                ],
                if (_usageProfile?.usageKind == 'cycles_per_week' &&
                    !measured) ...[
                  const SizedBox(height: 8),
                  Text(
                    'Use: ${(_previewCycles ?? _usageProfile!.value).toStringAsFixed(1)} cycles/week',
                    style: Theme.of(context).textTheme.bodySmall
                        ?.copyWith(color: _secondary(context)),
                  ),
                  Slider(
                    key: Key('appliance-cycles-${appliance.id}'),
                    value: (_previewCycles ?? _usageProfile!.value).clamp(
                      _usageProfile!.min,
                      _usageProfile!.max,
                    ),
                    min: _usageProfile!.min,
                    max: _usageProfile!.max,
                    divisions:
                        ((_usageProfile!.max - _usageProfile!.min) /
                                _usageProfile!.step)
                            .round(),
                    label:
                        '${(_previewCycles ?? _usageProfile!.value).toStringAsFixed(1)} cycles/week',
                    onChanged: _saving
                        ? null
                        : (value) => setState(() {
                            _previewCycles = value;
                            _saveError = null;
                          }),
                    onChangeEnd: _saving ? null : _commitCycles,
                  ),
                  Align(
                    alignment: Alignment.centerRight,
                    child: TextButton.icon(
                      key: Key('reset-appliance-cycles-${appliance.id}'),
                      onPressed:
                          _saving ||
                              _usageProfile!.value ==
                                  _usageProfile!.initialValue
                          ? null
                          : () => _commitCycles(_usageProfile!.initialValue),
                      icon: const Icon(Icons.restore),
                      label: Text(
                        'Reset to ${_usageProfile!.initialValue.toStringAsFixed(1)} cycles/week',
                      ),
                    ),
                  ),
                  if (_saving) const LinearProgressIndicator(),
                  if (_saveError != null)
                    Text(
                      _saveError!,
                      style: Theme.of(context).textTheme.bodySmall?.copyWith(
                        color: Theme.of(context).colorScheme.error,
                      ),
                    ),
                ],
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _PowerNow extends StatelessWidget {
  const _PowerNow({
    required this.plugs,
    required this.appliances,
    required this.hubConnected,
    required this.estimates,
    required this.estimatesStale,
    required this.meterReadings,
    required this.todayMeterReadings,
    required this.hiddenApplianceIds,
    required this.onHideAppliance,
    required this.showZipPrompt,
    required this.onDismissZipPrompt,
    required this.onOpenElectricitySettings,
    required this.onHoursChanged,
    required this.onLoadUsage,
    required this.onUsageChanged,
  });

  final List<SavedPlug> plugs;
  final List<SavedAppliance> appliances;
  final bool hubConnected;
  final Map<int, EnergyEstimate> estimates;
  final bool estimatesStale;
  final Map<String, DeviceEnergy> meterReadings;
  final Map<String, (int, DeviceEnergy)> todayMeterReadings;
  final Set<int> hiddenApplianceIds;
  final ValueChanged<int> onHideAppliance;
  final bool showZipPrompt;
  final VoidCallback onDismissZipPrompt;
  final VoidCallback onOpenElectricitySettings;
  final Future<void> Function(int, double) onHoursChanged;
  final Future<ApplianceUsageProfile> Function(int) onLoadUsage;
  final Future<ApplianceUsageProfile> Function(int, String, double)
  onUsageChanged;

  List<PowerNowDailyCostRow> get _rows {
    final attachedPlugByAppliance = <int, SavedPlug>{};
    for (final plug in plugs) {
      if (plug.connectedAppliance case final appliance?) {
        attachedPlugByAppliance.putIfAbsent(appliance.id, () => plug);
      }
    }
    final all = <int, SavedAppliance>{
      for (final appliance in appliances) appliance.id: appliance,
    };
    for (final plug in plugs) {
      if (plug.connectedAppliance case final appliance?) {
        all.putIfAbsent(appliance.id, () => appliance);
      }
    }
    return [
      for (final appliance in all.values)
        if (!hiddenApplianceIds.contains(appliance.id))
          () {
            final plug = attachedPlugByAppliance[appliance.id];
            final estimate = estimates[appliance.id];
            final sourcedCost = sourceDailyCostUsd(estimate);
            final todayRecord =
                plug == null || plug.connectionStatus == 'identity_changed'
                ? null
                : todayMeterReadings[plug.id];
            final todayReading = todayRecord?.$1 == appliance.id
                ? todayRecord?.$2
                : null;
            final meteredTodayCost = freshMeteredTodayCostUsd(todayReading);
            return PowerNowDailyCostRow(
              applianceId: appliance.id,
              deviceName: appliance.name,
              plugName: plug?.name,
              usedTodayUsd: meteredTodayCost ?? sourcedCost,
              wastedTodayUsd: null,
              meteredTodayUsd: todayReading?.observedCostUsd,
              meterCoverageFraction: todayReading?.coverageFraction,
            );
          }(),
    ];
  }

  @override
  Widget build(BuildContext context) => Column(
    crossAxisAlignment: CrossAxisAlignment.stretch,
    children: [
      if (estimatesStale) ...[
        const _InfoRow(
          Icons.cloud_off_outlined,
          'Hub disconnected · showing cached estimates',
          'These amounts were saved from the last hub refresh and may be out of date.',
        ),
        const SizedBox(height: 12),
      ],
      if (showZipPrompt) ...[
        _InfoRow(
          Icons.location_on_outlined,
          'Add your home ZIP code',
          'Save it once in your profile to use a regional electricity rate for all devices.',
          action: Wrap(
            spacing: 8,
            children: [
              TextButton(
                key: const Key('setHouseholdZip'),
                onPressed: onOpenElectricitySettings,
                child: const Text('Open profile'),
              ),
              TextButton(
                key: const Key('dismissHouseholdZip'),
                onPressed: onDismissZipPrompt,
                child: const Text('Later'),
              ),
            ],
          ),
        ),
        const SizedBox(height: 12),
      ],
      _Surface(
        child: PowerNowDailyCostTable(rows: _rows, onRemove: onHideAppliance),
      ),
    ],
  );
}

class _StopWaste extends StatelessWidget {
  const _StopWaste({required this.localPilotMode});

  final bool localPilotMode;

  @override
  Widget build(BuildContext context) => Column(
    crossAxisAlignment: CrossAxisAlignment.stretch,
    children: [
      _Surface(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
              decoration: BoxDecoration(
                color: const Color(0xFFFFF1F2),
                border: Border.all(color: const Color(0xFFFECBD4)),
                borderRadius: BorderRadius.circular(99),
              ),
              child: Text(
                'MONITORING NOT CONNECTED',
                style: Theme.of(context).textTheme.labelSmall?.copyWith(
                  color: const Color(0xFFC2414C),
                  fontWeight: FontWeight.w700,
                ),
              ),
            ),
            const SizedBox(height: 10),
            Text(
              'Find What’s Wasting Electricity',
              style: Theme.of(context).textTheme.headlineSmall
                  ?.copyWith(fontWeight: FontWeight.w700, height: 1.12),
            ),
            const SizedBox(height: 5),
            Text(
              'EnergyLens needs measured readings and device context before it can identify avoidable use.',
              style: Theme.of(context).textTheme.bodyMedium
                  ?.copyWith(color: _secondary(context)),
            ),
            const SizedBox(height: 14),
            Container(
              padding: const EdgeInsets.all(10),
              decoration: BoxDecoration(
                color: _softSurface(context),
                borderRadius: BorderRadius.circular(12),
              ),
              child: Row(
                children: [
                  const Icon(Icons.schedule_outlined, size: 18, color: _muted),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      'Findings and savings will appear after monitoring starts.',
                      style: Theme.of(context).textTheme.bodySmall
                          ?.copyWith(color: _secondary(context)),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
      const SizedBox(height: 18),
      const _InfoRow(
        Icons.energy_savings_leaf_outlined,
        'No findings yet',
        'When a device shows avoidable draw, its evidence and next step will appear here.',
        color: _green,
      ),
      const SizedBox(height: 18),
      const _Setup(),
      const SizedBox(height: 18),
      const _InfoRow(
        Icons.verified_outlined,
        'Wins will live here',
        'Compare observed use before and after an action to see the result.',
        color: _green,
      ),
      const SizedBox(height: 18),
      Text('Programs', style: Theme.of(context).textTheme.titleLarge),
      if (localPilotMode) const LocalPilotPrograms(),
    ],
  );
}

class _CloudStopWaste extends StatelessWidget {
  const _CloudStopWaste({
    required this.home,
    required this.api,
    required this.onViewEstimates,
  });

  final CloudHome home;
  final CloudApiClient api;
  final VoidCallback onViewEstimates;

  @override
  Widget build(BuildContext context) => Column(
    crossAxisAlignment: CrossAxisAlignment.stretch,
    children: [
      _Surface(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Explore ways to reduce use',
              style: Theme.of(context).textTheme.headlineSmall
                  ?.copyWith(fontWeight: FontWeight.w700),
            ),
            const SizedBox(height: 8),
            Text(
              'For ${home.name}, review suggested actions and ask questions using saved appliance details and reviewed evidence when available.',
            ),
            const SizedBox(height: 8),
            const Text(
              'Waste is not yet assessed. Suggestions and modeled costs are not measured savings or proof of avoidable use.',
            ),
          ],
        ),
      ),
      const SizedBox(height: 16),
      OutlinedButton.icon(
        key: const Key('stopWasteCloudActions'),
        onPressed: () => Navigator.of(context).push(
          MaterialPageRoute<void>(
            builder: (_) => CloudRecommendationsScreen(api: api, home: home),
          ),
        ),
        icon: const Icon(Icons.lightbulb_outline),
        label: const Text('Actions to consider'),
      ),
      const SizedBox(height: 8),
      OutlinedButton.icon(
        key: const Key('stopWasteCloudFaq'),
        onPressed: () => Navigator.of(context).push(
          MaterialPageRoute<void>(
            builder: (_) => CloudFaqScreen(api: api, home: home),
          ),
        ),
        icon: const Icon(Icons.question_answer_outlined),
        label: const Text('Ask about this cloud home'),
      ),
      const SizedBox(height: 8),
      TextButton.icon(
        key: const Key('stopWasteCloudEstimates'),
        onPressed: onViewEstimates,
        icon: const Icon(Icons.calculate_outlined),
        label: const Text('Review modeled estimates in Power Now'),
      ),
      const SizedBox(height: 18),
      StopWastePrograms(api: api, home: home),
    ],
  );
}

class _SleepMetric extends StatelessWidget {
  const _SleepMetric(this.title, this.detail, {this.color});
  final String title;
  final String detail;
  final Color? color;

  @override
  Widget build(BuildContext context) => Expanded(
    child: Container(
      constraints: const BoxConstraints(minHeight: 95),
      padding: const EdgeInsets.all(9),
      decoration: BoxDecoration(
        color: color == null
            ? _softSurface(context)
            : color!.withValues(alpha: .05),
        border: Border.all(
          color: color == null
              ? Theme.of(context).colorScheme.outlineVariant
              : color!.withValues(alpha: .18),
        ),
        borderRadius: BorderRadius.circular(16),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            title,
            style: Theme.of(context).textTheme.labelMedium?.copyWith(
              color: color ?? _secondary(context),
              fontWeight: FontWeight.w700,
            ),
          ),
          const SizedBox(height: 4),
          Text(
            '—',
            style: Theme.of(context).textTheme.titleLarge
                ?.copyWith(color: color, fontWeight: FontWeight.w700),
          ),
          Text(
            detail,
            style: Theme.of(context).textTheme.labelSmall
                ?.copyWith(color: _secondary(context)),
          ),
        ],
      ),
    ),
  );
}

class _SleepCheck extends StatelessWidget {
  const _SleepCheck({
    required this.plugs,
    required this.baselineCoverage,
    required this.hubConnected,
  });

  final List<SavedPlug> plugs;
  final Map<String, DeviceBaselineCoverage> baselineCoverage;
  final bool hubConnected;

  String _coverageDetail(DeviceBaselineCoverage? coverage) {
    if (coverage == null) {
      return hubConnected
          ? 'Meter coverage is unavailable. The hub could not confirm the coverage window.'
          : 'Meter coverage is unavailable while the hub is disconnected.';
    }
    if (coverage.status == 'sufficient_meter_coverage') {
      return '${coverage.coveredDays}/${coverage.requiredDays} covered days · '
          '${(coverage.coverageFraction * 100).round()}% of the seven-day window. '
          'Coverage describes sampled time only; it does not identify computer activity or savings.';
    }
    if (coverage.status == 'collecting') {
      return 'Collecting meter history · ${coverage.coveredDays}/${coverage.requiredDays} '
          'covered days · ${(coverage.coverageFraction * 100).round()}% of the seven-day window. '
          'Coverage does not identify computer activity or savings.';
    }
    final reason = switch (coverage.reason) {
      'meter_required' => 'This device does not have a supported energy meter.',
      'computer_required' =>
        'Attach a computer to this meter to check its coverage.',
      'attachment_required' || 'attach_a_computer' =>
        'Attach this meter to a computer to check coverage.',
      'stale_meter_stream' =>
        'The meter stream is stale, so coverage is unavailable.',
      _ => 'The hub cannot confirm meter coverage for this device.',
    };
    return '$reason Coverage does not identify computer activity or savings.';
  }

  Widget _computerCoverage(BuildContext context, SavedPlug plug) {
    final coverage = baselineCoverage[plug.id];
    final status = switch (coverage?.status) {
      'sufficient_meter_coverage' => 'Sufficient meter coverage',
      'collecting' => 'Collecting meter history',
      _ => 'Meter coverage unavailable',
    };
    final color = coverage?.status == 'sufficient_meter_coverage'
        ? _green
        : coverage?.status == 'collecting'
        ? const Color(0xFF007FBE)
        : _secondary(context);
    return _InfoRow(
      Icons.sensors_outlined,
      '${plug.connectedAppliance!.name} · $status',
      _coverageDetail(coverage),
      color: color,
    );
  }

  @override
  Widget build(BuildContext context) => Column(
    crossAxisAlignment: CrossAxisAlignment.stretch,
    children: [
      _Surface(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                const Icon(
                  Icons.nights_stay_outlined,
                  color: Color(0xFF008BC1),
                  size: 28,
                ),
                const SizedBox(width: 9),
                Expanded(
                  child: Text(
                    'Last Night’s Summary',
                    style: Theme.of(context).textTheme.headlineSmall
                        ?.copyWith(fontWeight: FontWeight.w700),
                  ),
                ),
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 9,
                    vertical: 7,
                  ),
                  decoration: BoxDecoration(
                    color: _softSurface(context),
                    borderRadius: BorderRadius.circular(99),
                  ),
                  child: Text(
                    'No night tracked',
                    style: Theme.of(context).textTheme.labelSmall
                        ?.copyWith(color: _secondary(context)),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 18),
            Container(
              padding: const EdgeInsets.all(13),
              decoration: BoxDecoration(
                color: _softSurface(context),
                border: Border.all(
                  color: Theme.of(context).colorScheme.outlineVariant,
                ),
                borderRadius: BorderRadius.circular(17),
              ),
              child: Row(
                children: [
                  Container(
                    width: 66,
                    height: 66,
                    alignment: Alignment.center,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      border: Border.all(
                        color: const Color(0xFFCBD9DF),
                        width: 5,
                      ),
                    ),
                    child: Text(
                      '—',
                      style: Theme.of(context).textTheme.titleLarge,
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'Sleep score unavailable',
                          style: Theme.of(context).textTheme.titleMedium
                              ?.copyWith(
                                color: _green,
                                fontWeight: FontWeight.w700,
                              ),
                        ),
                        const SizedBox(height: 4),
                        Text(
                          'Connect a monitored device to understand its overnight draw.',
                          style: Theme.of(context).textTheme.bodySmall
                              ?.copyWith(color: _secondary(context)),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 18),
            const Row(
              children: [
                _SleepMetric('Total spent', 'No readings'),
                SizedBox(width: 7),
                _SleepMetric('Necessary', 'Not classified'),
                SizedBox(width: 7),
                _SleepMetric('Keepable', 'Not measured', color: _rose),
              ],
            ),
          ],
        ),
      ),
      const SizedBox(height: 18),
      const _InfoRow(
        Icons.nights_stay_outlined,
        'Night Sleep Mode',
        'Automatic overnight controls will appear when device control is available.',
        color: _green,
      ),
      const SizedBox(height: 24),
      _SectionTitle(
        'Meter Coverage',
        plugs.any((plug) => plug.connectedAppliance?.category == 'computer')
            ? 'Attached computers'
            : 'No attached computer',
      ),
      const SizedBox(height: 10),
      if (plugs.any((plug) => plug.connectedAppliance?.category == 'computer'))
        for (final plug in plugs.where(
          (plug) => plug.connectedAppliance?.category == 'computer',
        )) ...[_computerCoverage(context, plug), const SizedBox(height: 10)]
      else
        const _InfoRow(
          Icons.schedule_outlined,
          'No attached computer',
          'Attach a computer to a monitored meter to check whether enough meter history has been collected.',
        ),
      const SizedBox(height: 8),
      const _InfoRow(
        Icons.schedule_outlined,
        'No overnight activity summary',
        'Meter coverage shows data continuity only. Computer activity and avoidable use are not classified.',
      ),
      const SizedBox(height: 18),
      const _Setup(),
    ],
  );
}

enum _AskMode { ask, connect }

class _AskAndAdd extends StatefulWidget {
  const _AskAndAdd({
    required this.api,
    required this.credentials,
    required this.appliances,
    required this.estimates,
    required this.hiddenPowerNowIds,
    required this.onShowOnPowerNow,
    required this.onHoursChanged,
    required this.onLoadUsage,
    required this.onUsageChanged,
    required this.onDevicesChanged,
    required this.autoScanDiscovery,
    required this.startInConnectAppliance,
    this.cloudHome,
    this.cloudApi,
  });

  final DiscoveryApi api;
  final DiscoveryCredentials credentials;
  final List<SavedAppliance> appliances;
  final Map<int, EnergyEstimate> estimates;
  final Set<int> hiddenPowerNowIds;
  final ValueChanged<int> onShowOnPowerNow;
  final Future<void> Function(int, double) onHoursChanged;
  final Future<ApplianceUsageProfile> Function(int) onLoadUsage;
  final Future<ApplianceUsageProfile> Function(int, String, double)
  onUsageChanged;
  final VoidCallback onDevicesChanged;
  final bool autoScanDiscovery;
  final bool startInConnectAppliance;
  final CloudHome? cloudHome;
  final CloudApiClient? cloudApi;

  @override
  State<_AskAndAdd> createState() => _AskAndAddState();
}

class _AskAndAddState extends State<_AskAndAdd> {
  late _AskMode mode;
  List<SavedAppliance> _savedHubDevices = const [];
  List<SavedAppliance> get _hubDevices {
    final byId = <int, SavedAppliance>{
      for (final device in widget.appliances) device.id: device,
      for (final device in _savedHubDevices) device.id: device,
    };
    return byId.values.toList(growable: false);
  }

  List<CloudAppliance> _cloudDevices = const [];
  String? _cloudInventoryError;
  bool _cloudInventoryLoading = false;
  String? _deleteError;
  int? _deletingId;

  Future<void> _openPhotoOnboarding() async {
    final saved = await Navigator.of(context).push<Object>(
      MaterialPageRoute<Object>(
        builder: (_) => ApplianceOnboardingScreen(
          method: 'photo',
          api: widget.api,
          credentials: widget.credentials,
          cloudHome: widget.cloudHome,
          cloudApi: widget.cloudApi,
        ),
      ),
    );
    if (!mounted) return;
    if (saved != null) setState(() => mode = _AskMode.connect);
    _loadHubDevices();
    _loadCloudDevices();
    widget.onDevicesChanged();
  }

  @override
  void initState() {
    super.initState();
    mode = widget.startInConnectAppliance ? _AskMode.connect : _AskMode.ask;
    if (mode == _AskMode.connect) unawaited(_loadHubDevices());
    if (widget.cloudHome != null && widget.cloudApi != null) {
      unawaited(_loadCloudDevices());
    }
  }

  Future<void> _loadCloudDevices() async {
    final home = widget.cloudHome;
    final api = widget.cloudApi;
    if (home == null || api == null) return;
    if (mounted) {
      setState(() {
        _cloudInventoryLoading = true;
        _cloudInventoryError = null;
      });
    }
    try {
      final devices = await api.appliances(home.id);
      if (mounted) {
        setState(() {
          _cloudDevices = devices;
          _cloudInventoryError = null;
        });
      }
    } catch (_) {
      if (mounted) {
        setState(() {
          _cloudDevices = const [];
          _cloudInventoryError =
              'Could not load Cloud inventory. Refresh to try again.';
        });
      }
    } finally {
      if (mounted) setState(() => _cloudInventoryLoading = false);
    }
  }

  Future<void> _loadHubDevices() async {
    try {
      final (address, token) = await widget.credentials.read();
      if (address == null || token == null) return;
      final devices = await widget.api.appliances(address, token);
      if (mounted) {
        setState(() => _savedHubDevices = devices);
      }
    } catch (_) {
      if (mounted) {
        setState(
          () => _deleteError = 'Could not load saved devices from the hub.',
        );
      }
    }
  }

  Future<void> _deleteHubDevice(SavedAppliance device) async {
    if (_deletingId != null) return;
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Delete device?'),
        content: Text(
          'Delete “${device.name}” from this hub? This cannot be undone.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Delete'),
          ),
        ],
      ),
    );
    if (confirmed != true || !mounted) return;
    setState(() {
      _deletingId = device.id;
      _deleteError = null;
    });
    try {
      final (address, token) = await widget.credentials.read();
      if (address == null || token == null) {
        throw StateError('Hub connection needed');
      }
      await widget.api.deleteManualAppliance(address, token, device.id);
      if (!mounted) return;
      setState(
        () => _savedHubDevices = _savedHubDevices
            .where((item) => item.id != device.id)
            .toList(),
      );
      widget.onDevicesChanged();
      await _loadHubDevices();
    } catch (error) {
      if (mounted) {
        setState(
          () => _deleteError = error is StateError
              ? error.message
              : 'Could not delete the device. Check the hub connection.',
        );
      }
    } finally {
      if (mounted) setState(() => _deletingId = null);
    }
  }

  @override
  Widget build(BuildContext context) => Column(
    crossAxisAlignment: CrossAxisAlignment.stretch,
    children: [
      const SizedBox(height: 2),
      SegmentedButton<_AskMode>(
        showSelectedIcon: false,
        segments: const [
          ButtonSegment(
            value: _AskMode.ask,
            icon: Icon(Icons.chat_bubble_outline),
            label: Text('Ask Your Home'),
          ),
          ButtonSegment(
            value: _AskMode.connect,
            icon: Icon(Icons.add_circle_outline),
            label: Text('Connect Appliance'),
          ),
        ],
        selected: {mode},
        onSelectionChanged: (selection) {
          setState(() => mode = selection.first);
          if (mode == _AskMode.connect) _loadHubDevices();
        },
      ),
      const SizedBox(height: 20),
      if (mode == _AskMode.ask) ...[
        FilledButton.icon(
          key: const Key('searchUsingPhoto'),
          onPressed: _openPhotoOnboarding,
          icon: const Icon(Icons.photo_camera_outlined),
          label: const Text('Search using a photo'),
        ),
        const SizedBox(height: 6),
        Text(
          'Choose the label photo you took or take a new one. EnergyLens reads the model and checks reviewed suggestions.',
          style: Theme.of(context).textTheme.bodySmall
              ?.copyWith(color: _secondary(context)),
        ),
        const SizedBox(height: 18),
        _Surface(
          child: Row(
            children: [
              const _IconWell(Icons.chat_bubble_outline),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Ask your home',
                      style: Theme.of(context).textTheme.titleLarge
                          ?.copyWith(fontWeight: FontWeight.w700),
                    ),
                    Text(
                      'Questions about power and your electric bill will work when measured data is available.',
                      style: Theme.of(context).textTheme.bodyMedium
                          ?.copyWith(color: _secondary(context)),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: 18),
        _Surface(
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const _IconWell(Icons.bolt_outlined),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'ENERGYLENS ASSISTANT',
                      style: Theme.of(context).textTheme.labelSmall?.copyWith(
                        color: _green,
                        letterSpacing: .7,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    const SizedBox(height: 7),
                    Text(
                      'Answers need your home’s data',
                      style: Theme.of(context).textTheme.titleMedium
                          ?.copyWith(fontWeight: FontWeight.w700),
                    ),
                    const SizedBox(height: 6),
                    Text(
                      'The assistant is not connected yet. Connect a monitored device to make answers specific to your home.',
                      style: Theme.of(context).textTheme.bodyMedium
                          ?.copyWith(color: _secondary(context)),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: 18),
        const _InfoRow(
          Icons.help_outline,
          'Questions become available after connection',
          'Measured readings will make answers specific to your home.',
        ),
      ] else ...[
        _Surface(
          child: Row(
            children: [
              const _IconWell(Icons.power_outlined),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Connect an appliance',
                      style: Theme.of(context).textTheme.titleLarge
                          ?.copyWith(fontWeight: FontWeight.w700),
                    ),
                    Text(
                      'Find a supported plug through your local hub. Kasa HS103 has no energy meter; choose a metering model for measured power.',
                      style: Theme.of(context).textTheme.bodyMedium
                          ?.copyWith(color: _secondary(context)),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: 12),
        FilledButton.icon(
          onPressed: () async {
            await Navigator.of(context).push(
              MaterialPageRoute<void>(
                builder: (_) => DiscoveryScreen(
                  autoScan: widget.autoScanDiscovery,
                  cloudHome: widget.cloudHome,
                  cloudApi: widget.cloudApi,
                ),
              ),
            );
            if (!mounted) return;
            _loadHubDevices();
            widget.onDevicesChanged();
          },
          icon: const Icon(Icons.radar),
          label: const Text('Find a smart plug'),
        ),
        const SizedBox(height: 8),
        OutlinedButton.icon(
          onPressed: () async {
            await Navigator.of(context).push<Object>(
              MaterialPageRoute<Object>(
                builder: (_) => ApplianceOnboardingScreen(
                  method: 'manual',
                  cloudHome: widget.cloudHome,
                  cloudApi: widget.cloudApi,
                ),
              ),
            );
            if (!mounted) return;
            _loadHubDevices();
            _loadCloudDevices();
            widget.onDevicesChanged();
          },
          icon: const Icon(Icons.edit_outlined),
          label: const Text('Enter device details'),
        ),
        const SizedBox(height: 8),
        OutlinedButton.icon(
          onPressed: _openPhotoOnboarding,
          icon: const Icon(Icons.photo_camera_outlined),
          label: const Text('Identify from a photo'),
        ),
        if (_hubDevices.isNotEmpty || _deleteError != null) ...[
          const SizedBox(height: 18),
          Text(
            'Devices saved on this hub',
            style: Theme.of(context).textTheme.titleMedium,
          ),
          if (_deleteError != null)
            Text(
              _deleteError!,
              style: TextStyle(color: Theme.of(context).colorScheme.error),
            ),
          for (final device in _hubDevices) ...[
            Card(
              child: ListTile(
                title: Text(device.name),
                subtitle: Text(
                  '${device.onboardingMethod == 'photo'
                      ? 'Added from photo · '
                      : device.onboardingMethod == 'manual'
                      ? 'Manually added · '
                      : ''}'
                  '${device.room.isEmpty ? device.category : '${device.room} · ${device.category}'}',
                ),
                trailing:
                    device.onboardingMethod == 'manual' ||
                        device.onboardingMethod == 'photo'
                    ? IconButton(
                        key: Key('ask-delete-appliance-${device.id}'),
                        tooltip: 'Delete ${device.name}',
                        onPressed: _deletingId == null
                            ? () => _deleteHubDevice(device)
                            : null,
                        icon: const Icon(Icons.delete_outline),
                      )
                    : null,
              ),
            ),
            if (widget.hiddenPowerNowIds.contains(device.id))
              Align(
                alignment: Alignment.centerRight,
                child: TextButton(
                  key: Key('ask-show-power-now-${device.id}'),
                  onPressed: () => widget.onShowOnPowerNow(device.id),
                  child: const Text('Show on Power Now'),
                ),
              ),
            _ConnectedLoadRow(
              key: ValueKey('ask-usage-${device.id}'),
              appliance: device,
              estimate: widget.estimates[device.id],
              onHoursChanged: widget.onHoursChanged,
              onLoadUsage: widget.onLoadUsage,
              onUsageChanged: widget.onUsageChanged,
            ),
            const SizedBox(height: 8),
          ],
        ],
      ],
      if (widget.cloudHome != null && widget.cloudApi != null) ...[
        const SizedBox(height: 18),
        Text(
          'Cloud inventory · ${widget.cloudHome!.name}',
          style: Theme.of(context).textTheme.titleMedium,
        ),
        const Text(
          'These records belong to this cloud home. Local hub devices are separate until an explicit import or attachment sync is available.',
        ),
        TextButton.icon(
          onPressed: _cloudInventoryLoading ? null : _loadCloudDevices,
          icon: const Icon(Icons.refresh),
          label: const Text('Refresh Cloud inventory'),
        ),
        if (_cloudInventoryLoading) const LinearProgressIndicator(),
        if (_cloudInventoryError != null)
          Text(_cloudInventoryError!, key: const Key('cloudInventoryError')),
        if (!_cloudInventoryLoading &&
            _cloudInventoryError == null &&
            _cloudDevices.isEmpty)
          const Text('No cloud appliances saved yet.'),
        for (final device in _cloudDevices)
          Card(
            child: ListTile(
              key: Key('cloudAppliance-${device.id}'),
              title: Text(device.name),
              subtitle: Text(
                '${device.brand} ${device.fullModel} · ${device.category}${device.room == null ? '' : ' · ${device.room}'}',
              ),
              trailing: const Icon(Icons.chevron_right),
              onTap: () => Navigator.of(context).push(
                MaterialPageRoute<void>(
                  builder: (_) => CloudUsageQuestionsScreen(
                    home: widget.cloudHome!,
                    appliance: device,
                    api: widget.cloudApi!,
                  ),
                ),
              ),
            ),
          ),
      ],
      const SizedBox(height: 18),
      const _Setup(),
    ],
  );
}
