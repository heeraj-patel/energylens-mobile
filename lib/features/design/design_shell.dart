import 'dart:async';
import 'dart:convert';
import 'dart:io' show HandshakeException, SocketException, TlsException;

import 'package:flutter/foundation.dart'
    show TargetPlatform, defaultTargetPlatform, kIsWeb;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart' show PlatformException;
import 'package:http/http.dart' show ClientException;
import 'package:url_launcher/url_launcher.dart';
import 'package:webview_flutter/webview_flutter.dart';

import '../../core/backend_error.dart';
import '../../core/cloud_api/cloud_appliance.dart';
import '../../core/cloud_api/cloud_energy_categories.dart';
import '../../core/cloud_api/cloud_appliance_list.dart';
import '../../core/cloud_api/cloud_api_client.dart';
import '../../core/cloud_api/cloud_catalog.dart';
import '../../core/cloud_api/cloud_household_energy.dart'
    show CloudEfficiencyTrailing30Days;
import '../../core/cloud_api/cloud_home.dart' show newCloudIdempotencyKey;
import '../../core/cloud_auth/cloud_auxiliary_domain_lifecycle.dart';
import '../identify/appliance_onboarding_screen.dart'
    show identityFieldsFromOcr, manufacturerHintFromOcr;
import '../identify/cloud_usage_questions_screen.dart';
import '../identify/photo_capture_service.dart';
import '../discovery/device_data_refresh.dart';
import '../discovery/discovery_api.dart'
    show HubRequestException, PairingException;
import 'device_review_sheet.dart';
import 'efficiency_domain_repository.dart';
import 'efficiency_trailing_30_day_bindings.dart';
import 'dashboard_chart_projection.dart';
import 'dashboard_chart_renderer.dart';
import 'dashboard_domain_repository.dart';
import 'dashboard_top_savings_bindings.dart';
import 'design_context_coordinator.dart';
import 'design_numeric_bindings.dart';
import 'design_navigation_script.dart';
import 'design_category_picker_script.dart';
import 'design_page_read_dispatcher.dart';
import 'design_page_bridge.dart';
import 'design_page_state_script.dart';
import 'design_page_state_snapshot.dart';
import 'devices_domain_repository.dart';
import 'efficiency_away_domain_adapter.dart';
import 'efficiency_habits_domain_adapter.dart';
import 'efficiency_peak_rates_adapter.dart';
import 'live_devices_card_renderer.dart';
import 'live_devices_projection.dart';
import 'knowledge_page_script.dart';
import 'knowledge_domain_repository.dart';
import 'tips_domain_repository.dart';
import 'tips_page_renderer.dart';
import 'settings_saved_devices_renderer.dart';
import 'cloud_saved_plug_inventory.dart';
import 'settings_identity_renderer.dart';
import 'settings_domain_repository.dart';
import 'local_pilot_device_lifecycle.dart';
import 'local_pilot_device_review_sheet.dart';
import 'local_settings_devices_renderer.dart';
import 'local_pilot_settings.dart';
import 'home_details_screen.dart';
import 'appliance_identity_edit_screen.dart';
import 'account_profile_screen.dart';

/// The approved design files are complete mobile pages. Keep their markup and
/// wording in assets/design_pages; this shell only supplies native navigation.
class DesignShell extends StatefulWidget {
  const DesignShell({
    super.key,
    this.onSignOut,
    this.onChangeHome,
    this.onReportPreview,
    this.settingsApi,
    this.onDiscoverDevices,
    this.onboardingLifecycle,
    this.photoCapture = const PhotoCaptureService(),
    this.recoverLostPhotoOnStart,
    this.designContextCoordinator,
    this.designTour = false,
    this.localPilot = false,
    this.localDeviceLifecycle,
    this.deviceDataRefresh,
    this.homeName = 'The Miller Home',
  });

  final VoidCallback? onSignOut;
  final VoidCallback? onChangeHome;
  final VoidCallback? onReportPreview;
  final CloudApiClient? settingsApi;
  final Future<void> Function()? onDiscoverDevices;
  final CloudAuxiliaryDomainLifecycle? onboardingLifecycle;
  final PhotoCaptureService photoCapture;
  final bool? recoverLostPhotoOnStart;

  /// Native-only verified scope. It is never passed into the WebView.
  final DesignContextCoordinator? designContextCoordinator;
  final bool designTour;
  final bool localPilot;
  final LocalPilotDeviceLifecycle? localDeviceLifecycle;
  final DeviceDataRefresh? deviceDataRefresh;
  final String homeName;

  @override
  State<DesignShell> createState() => _DesignShellState();
}

class _DesignShellState extends State<DesignShell> with WidgetsBindingObserver {
  DateTime? _internalErrorShownAt;
  static const _pages = <String>{
    'dashboard',
    'devices',
    'efficiency',
    'efficiency_away',
    'efficiency_habits',
    'efficiency_peak_rates',
    'perks_tips',
    'settings',
    'settings_manage_devices',
    'settings_manual_device_entry',
    'settings_photo_scan_onboarding',
    'tips_care_upgrades',
    'tips_efficiency',
    'tips_knowledge',
  };
  static const _tourOrder = <String>[
    'dashboard',
    'devices',
    'efficiency',
    'efficiency_away',
    'efficiency_habits',
    'efficiency_peak_rates',
    'perks_tips',
    'settings',
    'settings_manage_devices',
    'settings_manual_device_entry',
    'settings_photo_scan_onboarding',
    'tips_care_upgrades',
    'tips_efficiency',
    'tips_knowledge',
  ];

  late final WebViewController _controller;
  late final DesignPageReadDispatcher _pageReads;
  static const _liveDevicesRenderer = LiveDevicesCardRenderer();
  static const _settingsSavedRenderer = SettingsSavedDevicesRenderer();
  static const _cloudSavedPlugInventory = CloudSavedPlugInventory();
  static const _localSettingsRenderer = LocalSettingsDevicesRenderer();
  static const _settingsIdentityRenderer = SettingsIdentityRenderer();
  static const _tipsRenderer = TipsPageRenderer();
  static const _settingsDevicePages = <String>{
    'settings_manage_devices',
    'settings_manual_device_entry',
    'settings_photo_scan_onboarding',
  };
  static const _efficiencyPages = <String>{
    'efficiency',
    'efficiency_away',
    'efficiency_habits',
    'efficiency_peak_rates',
  };
  final DesignPageRequestGate _bindingGate = DesignPageRequestGate();
  final DesignPageStateSnapshotStore _pageStates =
      DesignPageStateSnapshotStore();
  late final DesignTextBindingRenderer _bindingRenderer =
      DesignTextBindingRenderer(_bindingGate);
  late final DashboardChartRenderer _chartRenderer = DashboardChartRenderer(
    _bindingGate,
  );
  String _dashboardGranularity = 'day';
  int _pageLoadGeneration = 0;
  int _knowledgeRequestGeneration = 0;
  bool _pageReady = false;
  LiveDevicesProjection? _devicesProjection;
  List<CloudAppliance>? _savedAppliances;
  List<CloudSavedPlug> _savedPlugs = const [];
  String? _savedInventoryScope;
  LocalInventory? _localInventory;
  String? _renderedLocalIdentity;
  final Set<int> _deletingLocalIds = <int>{};
  DesignNumericBindings? _dashboardBindings;
  DesignNumericBindings? _sampleDevicesBindings;
  List<DesignTextBinding>? _efficiencyBindings;
  DashboardTopSavingsBindings? _topSavingsBindings;
  CloudEfficiencyTrailing30Days? _efficiencyChartSummary;
  int? _peerTabScrollY;
  DesignPageTicket? _pageTicket;
  Timer? _tourTimer;
  int _tourIndex = 0;
  final List<String> _history = [];
  String _page = 'dashboard';
  bool _reviewOpen = false;
  bool _identityEditOpen = false;
  bool _capturingPhoto = false;
  final Set<String> _archivingApplianceIds = <String>{};
  final Map<String, String> _archiveKeys = <String, String>{};
  bool _navigating = false;
  int _navigationEpoch = 0;
  late final DeviceDataRefresh _deviceDataRefresh =
      widget.deviceDataRefresh ?? DeviceDataRefresh();
  Future<void>? _deviceRefreshRun;
  String? _deviceRefreshScope;
  int _deviceRefreshGeneration = 0;
  bool _deviceRefreshReloadPending = false;
  bool _deviceRefreshReloadRunning = false;
  String? _observedLocalDeviceIdentity;
  String? _activePageStateScope;
  static const _localSettingsStore = LocalPilotSettingsStore();
  static EnergyCategories? _sessionCategories;
  late LocalPilotSettings _localSettings;

  String get _pageStateHomeId {
    final context = widget.designContextCoordinator?.context;
    return context == null
        ? '__local_design__'
        : '${context.accountId}/${context.homeId}';
  }

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _localSettings = LocalPilotSettings(
      homeName: widget.homeName,
      ownerName: 'Alex Miller',
      postalCode: '',
    );
    _pageReads = DesignPageReadDispatcher(widget.designContextCoordinator);
    _controller = WebViewController()
      ..setJavaScriptMode(JavaScriptMode.unrestricted)
      ..setBackgroundColor(const Color(0xFFF9F9FF))
      ..addJavaScriptChannel(
        'EnergyLensNavigation',
        onMessageReceived: (message) => unawaited(_open(message.message)),
      )
      ..addJavaScriptChannel(
        'EnergyLensDeviceReview',
        onMessageReceived: (message) =>
            unawaited(_reviewDevice(message.message)),
      )
      ..addJavaScriptChannel(
        'EnergyLensPhotoCapture',
        onMessageReceived: (message) =>
            unawaited(_capturePhoto(message.message)),
      )
      ..addJavaScriptChannel(
        'EnergyLensDeleteDevice',
        onMessageReceived: (message) =>
            unawaited(_archiveSavedAppliance(message.message)),
      )
      ..addJavaScriptChannel(
        'EnergyLensKnowledge',
        onMessageReceived: (message) =>
            unawaited(_answerKnowledgeEntry(message.message)),
      )
      ..setNavigationDelegate(
        NavigationDelegate(
          onPageFinished: (url) {
            unawaited(_finishAndRestorePage(url));
          },
          onNavigationRequest: (request) {
            final uri = Uri.tryParse(request.url);
            if (uri != null &&
                (uri.scheme == 'http' || uri.scheme == 'https')) {
              if (uri.host != 'example.com') {
                launchUrl(uri, mode: LaunchMode.externalApplication);
              }
              return NavigationDecision.prevent;
            }
            return NavigationDecision.navigate;
          },
        ),
      );
    WidgetsBinding.instance.addPostFrameCallback((_) async {
      if (!mounted) return;
      if (widget.localPilot) {
        try {
          _localSettings = await _localSettingsStore.load(widget.homeName);
        } catch (_) {
          // The pilot remains editable for this session if local storage fails.
        }
      }
      if (mounted) {
        await _loadPage();
        unawaited(_refreshDeviceData());
        if (widget.recoverLostPhotoOnStart ??
            (!kIsWeb && defaultTargetPlatform == TargetPlatform.android)) {
          unawaited(_recoverLostPhoto());
        }
      }
    });
  }

  @override
  void didUpdateWidget(covariant DesignShell oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (_deviceRefreshScope != _currentDeviceRefreshScope()) {
      _invalidateDeviceRefresh();
      unawaited(_refreshDeviceData());
    }
    if (!identical(
          oldWidget.designContextCoordinator,
          widget.designContextCoordinator,
        ) ||
        oldWidget.homeName != widget.homeName) {
      _pageReads.useCoordinator(widget.designContextCoordinator);
      unawaited(_loadPage());
    }
  }

  void _scheduleTourAdvance() {
    if (!widget.designTour) return;
    _tourTimer?.cancel();
    _tourTimer = Timer(
      const Duration(
        seconds: int.fromEnvironment(
          'ENERGYLENS_DESIGN_TOUR_DWELL_SECONDS',
          defaultValue: 8,
        ),
      ),
      () {
        if (!mounted || _tourIndex + 1 >= _tourOrder.length) return;
        _tourIndex++;
        setState(() => _page = _tourOrder[_tourIndex]);
        unawaited(_loadPage());
      },
    );
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _invalidateDeviceRefresh();
    _tourTimer?.cancel();
    _invalidatePageLoad();
    _pageReads.dispose();
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      unawaited(_refreshDeviceData());
    }
  }

  String? _currentDeviceRefreshScope() {
    if (!mounted || widget.designTour) return null;
    if (widget.localPilot) {
      return widget.localDeviceLifecycle == null
          ? null
          : 'local|${identityHashCode(widget.localDeviceLifecycle)}|${_observedLocalDeviceIdentity ?? ''}';
    }
    final context = widget.designContextCoordinator?.context;
    final cloud = widget.settingsApi;
    final lifecycle = widget.onboardingLifecycle;
    if (context == null ||
        context.mode != DesignContextMode.household ||
        cloud == null ||
        lifecycle == null ||
        !lifecycle.isVerifiedScope(context.accountId, context.homeId)) {
      return null;
    }
    final session = cloud.session;
    return '${identityHashCode(cloud)}|${identityHashCode(widget.designContextCoordinator)}|${identityHashCode(lifecycle)}|${session.config.apiUrl}|${session.credentialMethod}|${context.accountId}|${context.homeId}|${session.generation}';
  }

  void _invalidateDeviceRefresh() {
    _deviceRefreshGeneration++;
    _deviceRefreshScope = null;
    _deviceRefreshRun = null;
    _deviceRefreshReloadPending = false;
  }

  Future<void> _refreshDeviceData() async {
    if (widget.localPilot && widget.localDeviceLifecycle != null) {
      try {
        _observedLocalDeviceIdentity = await widget.localDeviceLifecycle!
            .currentIdentity();
      } catch (_) {
        _observedLocalDeviceIdentity = null;
      }
    }
    final scope = _currentDeviceRefreshScope();
    if (scope == null) {
      _invalidateDeviceRefresh();
      return;
    }
    if (scope == _deviceRefreshScope && _deviceRefreshRun != null) {
      return _deviceRefreshRun;
    }
    if (scope != _deviceRefreshScope) {
      _invalidateDeviceRefresh();
      _deviceRefreshScope = scope;
    }
    final generation = _deviceRefreshGeneration;
    bool current() =>
        mounted &&
        generation == _deviceRefreshGeneration &&
        _currentDeviceRefreshScope() == scope;
    final run = () async {
      var attempted = false;
      try {
        if (widget.localPilot) {
          final lifecycle = widget.localDeviceLifecycle;
          if (lifecycle == null) return;
          attempted = await _deviceDataRefresh.refreshLocal(
            lifecycle: lifecycle,
            isCurrent: current,
          );
        } else {
          final context = widget.designContextCoordinator?.context;
          final cloud = widget.settingsApi;
          if (context == null || cloud == null) return;
          attempted = await _deviceDataRefresh.refreshCloud(
            cloud: cloud,
            accountId: context.accountId,
            homeId: context.homeId,
            isCurrent: current,
          );
        }
      } catch (error) {
        // The visible page stays usable when Hub access is unavailable.
        if (current()) _showInternalErrorFor(error);
      } finally {
        if (current() && attempted) {
          _deviceRefreshReloadPending = true;
          unawaited(_reloadAfterDeviceRefresh());
        }
      }
    }();
    _deviceRefreshRun = run;
    await run;
    if (identical(_deviceRefreshRun, run)) _deviceRefreshRun = null;
  }

  Future<void> _reloadAfterDeviceRefresh() async {
    if (!_deviceRefreshReloadPending ||
        _deviceRefreshReloadRunning ||
        !mounted ||
        _reviewOpen ||
        _identityEditOpen ||
        _capturingPhoto ||
        _navigating ||
        !_pageReady) {
      return;
    }
    final scope = _currentDeviceRefreshScope();
    if (scope == null || scope != _deviceRefreshScope) return;
    final page = _page;
    final generation = _pageLoadGeneration;
    _deviceRefreshReloadRunning = true;
    try {
      await _capturePageState();
      if (!mounted ||
          scope != _currentDeviceRefreshScope() ||
          !_isCurrentPageLoad(page, generation) ||
          _reviewOpen ||
          _identityEditOpen ||
          _capturingPhoto ||
          _navigating) {
        return;
      }
      _deviceRefreshReloadPending = false;
      await _loadPage();
    } finally {
      _deviceRefreshReloadRunning = false;
    }
  }

  Future<void> _loadPage() async {
    if (!mounted) return;
    final scope = _pageStateHomeId;
    if (_activePageStateScope != scope) {
      _activePageStateScope = scope;
      _navigationEpoch++;
      _history.clear();
      _dashboardGranularity = 'day';
    }
    _pageStates.selectHome(scope);
    _invalidatePageLoad();
    final page = _page;
    final generation = _pageLoadGeneration;
    unawaited(_readPage(page, generation));
    // app.html is a self-contained copy of the approved HTML. The source
    // code.html and screen.png remain byte-for-byte references alongside it.
    await _controller.loadFlutterAsset('assets/design_pages/$page/app.html');
  }

  Future<void> _finishAndRestorePage(String url) async {
    final page = _page;
    final generation = _pageLoadGeneration;
    final path = Uri.tryParse(url)?.path;
    if (!_isCurrentPageLoad(page, generation) ||
        path == null ||
        !path.endsWith('assets/design_pages/$page/app.html')) {
      return;
    }
    try {
      await _installNavigation();
    } catch (_) {
      // The packaged page stays available if navigation setup fails.
    }
    if (!_isCurrentPageLoad(page, generation)) return;
    _scheduleTourAdvance();
    await _onPageFinished(url);
    if (!_isCurrentPageLoad(page, generation)) return;
    if (page == 'settings_manage_devices' ||
        page == 'settings_manual_device_entry') {
      try {
        final categories = widget.settingsApi != null
            ? await widget.settingsApi!.energyCategories(
                etag: _sessionCategories?.etag,
              )
            : await widget.localDeviceLifecycle?.energyCategories();
        if (categories != null) _sessionCategories = categories;
      } catch (error) {
        // Keep the last list for this session when a category refresh fails.
        _showInternalErrorFor(error);
      }
      if (!_isCurrentPageLoad(page, generation)) return;
      if (_sessionCategories case final categories?) {
        await _controller.runJavaScript(
          buildDesignCategoryPickerScript(categories),
        );
      }
    }
    if (widget.localPilot) {
      await _controller.runJavaScript(
        buildLocalPilotSettingsScript(page, _localSettings),
      );
    }
    if (page == 'settings' && widget.localPilot) {
      await _controller.runJavaScript('''
        document.querySelector('[data-el-bind="settings_text_025"]')?.replaceChildren('Preview sample energy costs for your devices.');
        document.querySelector('[data-el-bind="settings_text_026"]')?.replaceChildren('View demo report');
      ''');
    }
    final snapshot = _pageStates.forPage(_pageStateHomeId, page);
    if (snapshot != null) {
      try {
        await _controller.runJavaScript(
          buildDesignPageStateRestoreScript(snapshot),
        );
      } catch (_) {
        // A failed restoration leaves the page usable with its default state.
      }
    }
    final peerScrollY = _peerTabScrollY;
    _peerTabScrollY = null;
    if (peerScrollY != null && _isCurrentPageLoad(page, generation)) {
      await _controller.runJavaScript('window.scrollTo(0, $peerScrollY)');
    }
    if (_deviceRefreshReloadPending) unawaited(_reloadAfterDeviceRefresh());
  }

  Future<void> _capturePageState() async {
    if (!_pageReady) return;
    final page = _page;
    final generation = _pageLoadGeneration;
    final homeId = _pageStateHomeId;
    try {
      final result = await _controller.runJavaScriptReturningResult(
        buildDesignPageStateCaptureScript(page),
      );
      if (!_isCurrentPageLoad(page, generation) || homeId != _pageStateHomeId) {
        return;
      }
      var raw = result is String ? result : jsonEncode(result);
      final decoded = jsonDecode(raw);
      if (decoded is String) raw = decoded;
      _pageStates.save(
        DesignPageStateSnapshot.fromJson(raw, homeId: homeId, page: page),
      );
    } catch (_) {
      // State capture is best effort; navigation must remain available.
    }
  }

  Future<void> _editLocalPilotSettings({required bool editOwner}) async {
    final saved = await Navigator.of(context).push<LocalPilotSettings>(
      MaterialPageRoute<LocalPilotSettings>(
        builder: (_) => LocalPilotSettingsEditor(
          settings: _localSettings,
          editOwner: editOwner,
        ),
      ),
    );
    if (!mounted || saved == null || _page != 'settings') return;
    try {
      await _localSettingsStore.save(saved);
    } catch (_) {
      return;
    }
    _localSettings = saved;
    await _loadPage();
    if (mounted && _page == 'settings') {
      ScaffoldMessenger.of(context)
          .showSnackBar(const SnackBar(content: Text('Saved Successfully')));
    }
  }

  void _invalidatePageLoad() {
    _pageLoadGeneration++;
    _knowledgeRequestGeneration++;
    _pageReady = false;
    _devicesProjection = null;
    _savedAppliances = null;
    _localInventory = null;
    _renderedLocalIdentity = null;
    _dashboardBindings = null;
    _sampleDevicesBindings = null;
    _efficiencyBindings = null;
    _topSavingsBindings = null;
    _efficiencyChartSummary = null;
    _pageTicket = null;
    _bindingGate.clear();
  }

  bool _isCurrentPageLoad(String page, int generation) =>
      mounted && _page == page && _pageLoadGeneration == generation;

  Future<void> _readPage(String page, int generation) async {
    await _pageReads.load(page);
    if (!_isCurrentPageLoad(page, generation)) return;
    final readError = _pageReads.latestError;
    if (readError != null) _showInternalErrorFor(readError);
    if (page == 'settings') {
      await _applySettingsIdentity(generation);
      return;
    }
    if (_settingsDevicePages.contains(page)) {
      await _refreshSavedAppliances(page, generation);
      return;
    }
    final read = _pageReads.latestRead;
    if (_efficiencyPages.contains(page)) {
      final source = _efficiencySnapshot(read?.value);
      if (source == null) return;
      if (source.page != _efficiencyPageForRoute(page)) return;
      final bindings = prepareEfficiencyTrailing30DaysBindings(source);
      if (bindings == null ||
          !_isCurrentPageLoad(page, generation) ||
          !identical(_pageReads.latestRead, read)) {
        return;
      }
      _efficiencyBindings = bindings;
      _efficiencyChartSummary = source.trailing30Days?.efficiencyTrailing30Days;
      await _applyEfficiencyBindings(page, generation);
      return;
    }
    if (page == 'dashboard') {
      if (read == null || read.page != 'dashboard') return;
      try {
        final projection = prepareDesignNumericBindings(read);
        if (!_isCurrentPageLoad(page, generation) ||
            !identical(_pageReads.latestRead, read)) {
          return;
        }
        _dashboardBindings = projection;
        await _applyDashboardBindings(generation);
        await _applyDashboardChart(generation);
        final snapshot = read.value;
        _topSavingsBindings = snapshot is DashboardDomainSnapshot
            ? prepareDashboardTopSavingsBindings(snapshot.topSavingsMove)
            : null;
        await _applyDashboardTopSavings(generation);
      } catch (_) {
        // Packaged numeric values remain visible when live values are invalid.
      }
      return;
    }
    if (read?.value is TipsDomainSnapshot &&
        (page == 'perks_tips' ||
            page == 'tips_efficiency' ||
            page == 'tips_care_upgrades')) {
      await _applyTipsSnapshot(page, generation);
      return;
    }
    if (page != 'devices' || read == null) return;
    if (read.mode == DesignContextMode.sample) {
      try {
        final bindings = prepareDesignNumericBindings(read);
        if (!_isCurrentPageLoad(page, generation) ||
            !identical(_pageReads.latestRead, read)) {
          return;
        }
        _sampleDevicesBindings = bindings;
        await _applySampleDevicesBindings(generation);
      } catch (_) {
        // A rejected sample response cannot alter the approved packaged cards.
      }
      try {
        final projection = prepareLiveDevicesProjection(read);
        if (_isCurrentPageLoad(page, generation) &&
            identical(_pageReads.latestRead, read)) {
          _devicesProjection = projection;
          await _applyDevicesProjection(generation);
        }
      } catch (_) {
        // The packaged cards remain available if extra rows are invalid.
      }
      return;
    }
    if (read.mode != DesignContextMode.household) return;
    if (read.value is DevicesDomainSnapshot &&
        (read.value as DevicesDomainSnapshot).hasSeededRows) {
      try {
        final bindings = prepareDesignNumericBindings(read);
        if (!_isCurrentPageLoad(page, generation) ||
            !identical(_pageReads.latestRead, read)) {
          return;
        }
        _sampleDevicesBindings = bindings;
        await _applySampleDevicesBindings(generation);
      } catch (_) {
        // Invalid seeded cost data cannot alter the packaged cards.
      }
    }
    try {
      final projection = prepareLiveDevicesProjection(read);
      if (!_isCurrentPageLoad(page, generation) ||
          !identical(_pageReads.latestRead, read)) {
        return;
      }
      _devicesProjection = projection;
      await _applyDevicesProjection(generation);
    } catch (_) {
      // Keep the approved static cards when a native read cannot be projected.
    }
  }

  Future<void> _refreshSavedAppliances(String page, int generation) async {
    if (widget.localPilot && !widget.designTour) {
      await _refreshLocalInventory(page, generation);
      return;
    }
    final context = widget.designContextCoordinator?.context;
    final lifecycle = widget.onboardingLifecycle;
    if (!_settingsDevicePages.contains(page) ||
        context == null ||
        context.mode != DesignContextMode.household ||
        lifecycle == null ||
        !lifecycle.isVerifiedScope(context.accountId, context.homeId)) {
      return;
    }
    try {
      final rows = await lifecycle.refreshSavedAppliances(
        context.accountId,
        context.homeId,
      );
      if (rows == null ||
          !_isCurrentPageLoad(page, generation) ||
          !identical(widget.designContextCoordinator?.context, context) ||
          !lifecycle.isVerifiedScope(context.accountId, context.homeId)) {
        return;
      }
      _savedAppliances = rows;
      _savedPlugs = const [];
      _savedInventoryScope = _cloudSavedScope(
        context.accountId,
        context.homeId,
      );
      await _applySavedAppliances(page, generation);
      final cloud = widget.settingsApi;
      if (cloud == null) return;
      try {
        final plugs = await _cloudSavedPlugInventory.read(
          cloud: cloud,
          accountId: context.accountId,
          homeId: context.homeId,
          appliances: rows,
          isCurrent: () =>
              _isCurrentPageLoad(page, generation) &&
              identical(widget.designContextCoordinator?.context, context) &&
              lifecycle.isVerifiedScope(context.accountId, context.homeId),
        );
        if (_isCurrentPageLoad(page, generation) &&
            identical(widget.designContextCoordinator?.context, context) &&
            _savedInventoryScope ==
                _cloudSavedScope(context.accountId, context.homeId)) {
          _savedPlugs = plugs;
          await _applySavedAppliances(page, generation);
        }
      } catch (error) {
        // Cloud appliances remain visible if the owned Hub is unavailable.
        _showInternalErrorFor(error);
      }
    } catch (error) {
      // A failed inventory read never creates a saved row from a draft.
      _showInternalErrorFor(error);
    }
  }

  String? _cloudSavedScope(String accountId, String homeId) {
    final session = widget.settingsApi?.session;
    if (session == null) return null;
    return '${session.config.apiUrl}|${session.credentialMethod}|$accountId|$homeId|${session.generation}';
  }

  Future<void> _refreshLocalInventory(String page, int generation) async {
    if (!_settingsDevicePages.contains(page)) return;
    final lifecycle = widget.localDeviceLifecycle;
    final inventory = await lifecycle?.inventory();
    if (!_isCurrentPageLoad(page, generation)) return;
    _localInventory = inventory;
    if (inventory != null) {
      await _applyLocalInventory(page, generation);
    } else if (_pageReady) {
      try {
        await _controller.runJavaScriptReturningResult(
          _localSettingsRenderer.installationScript(
            identity: '__unavailable__',
            generation: generation,
          ),
        );
        _renderedLocalIdentity = '__unavailable__';
      } catch (_) {
        // The unavailable state never exposes a saved Hub row.
      }
    }
  }

  Future<void> _applyLocalInventory(String page, int generation) async {
    final inventory = _localInventory;
    if (!_pageReady ||
        !_isCurrentPageLoad(page, generation) ||
        !_settingsDevicePages.contains(page) ||
        inventory == null) {
      return;
    }
    // Recheck credentials before projecting any asynchronous Hub result.
    final currentIdentity = await widget.localDeviceLifecycle
        ?.currentIdentity();
    if (currentIdentity != inventory.identity ||
        !_isCurrentPageLoad(page, generation)) {
      return;
    }
    try {
      if (_renderedLocalIdentity != inventory.identity) {
        final installed = await _controller.runJavaScriptReturningResult(
          _localSettingsRenderer.installationScript(
            identity: inventory.identity,
            generation: generation,
          ),
        );
        if (installed != true || !_isCurrentPageLoad(page, generation)) return;
        _renderedLocalIdentity = inventory.identity;
      }
      await _controller.runJavaScriptReturningResult(
        _localSettingsRenderer.updateScript(
          identity: inventory.identity,
          generation: generation,
          appliances: inventory.rows,
          protocolDevices: inventory.protocolDevices,
          savedPlugs: inventory.savedPlugs,
        ),
      );
    } catch (_) {
      // No Hub inventory is inferred from a failed projection.
    }
  }

  Future<void> _onPageFinished(String url) async {
    final page = _page;
    final generation = _pageLoadGeneration;
    final path = Uri.tryParse(url)?.path;
    if (!_isCurrentPageLoad(page, generation) ||
        path == null ||
        !path.endsWith('assets/design_pages/$page/app.html')) {
      return;
    }
    _pageReady = true;
    final context = widget.designContextCoordinator?.context;
    if (context != null) {
      final ticket = _bindingGate.select(context.homeId, page);
      _pageTicket = ticket;
      try {
        final installed = await _controller.runJavaScriptReturningResult(
          _bindingRenderer.installationScript(ticket)!,
        );
        if (installed != true ||
            !_isCurrentPageLoad(page, generation) ||
            !identical(widget.designContextCoordinator?.context, context) ||
            !identical(_pageTicket, ticket)) {
          return;
        }
        await _applySelectedHomeName(page, generation, ticket);
        if (!_isCurrentPageLoad(page, generation) ||
            !identical(widget.designContextCoordinator?.context, context) ||
            !identical(_pageTicket, ticket)) {
          return;
        }
        if (page == 'settings') {
          await _applySettingsIdentity(generation);
          if (!_isCurrentPageLoad(page, generation) ||
              !identical(widget.designContextCoordinator?.context, context) ||
              !identical(_pageTicket, ticket)) {
            return;
          }
        }
      } catch (_) {
        // The packaged home name remains visible on script failure.
      }
    }
    if (page == 'dashboard' &&
        context == null &&
        (widget.localPilot || widget.designTour)) {
      final ticket = _bindingGate.select(_pageStateHomeId, page);
      _pageTicket = ticket;
      try {
        final installed = await _controller.runJavaScriptReturningResult(
          _bindingRenderer.installationScript(ticket)!,
        );
        if (installed != true || !_isCurrentPageLoad(page, generation)) {
          return;
        }
      } catch (_) {
        return;
      }
    }
    if (page == 'tips_knowledge') {
      try {
        await _controller.runJavaScriptReturningResult(
          buildKnowledgePageScript(),
        );
      } catch (_) {
        // The packaged local-pilot FAQ remains available on a script failure.
      }
      return;
    }
    if (page == 'perks_tips' ||
        page == 'tips_efficiency' ||
        page == 'tips_care_upgrades') {
      await _applyTipsSnapshot(page, generation);
      return;
    }
    if (page == 'dashboard') {
      await _applyDashboardBindings(generation);
      await _applyDashboardChart(generation);
      await _applyDashboardTopSavings(generation);
      return;
    }
    if (_efficiencyPages.contains(page)) {
      await _applyEfficiencyBindings(page, generation);
      return;
    }
    if (_settingsDevicePages.contains(page)) {
      if (widget.localPilot && !widget.designTour) {
        try {
          final identity = _localInventory?.identity ?? '__unavailable__';
          final installed = await _controller.runJavaScriptReturningResult(
            _localSettingsRenderer.installationScript(
              identity: identity,
              generation: generation,
            ),
          );
          if (installed != true || !_isCurrentPageLoad(page, generation)) {
            return;
          }
          _renderedLocalIdentity = identity;
          await _applyLocalInventory(page, generation);
        } catch (_) {
          // Functional local mode does not promote packaged examples.
        }
        return;
      }
      if (context == null ||
          context.mode != DesignContextMode.household ||
          widget.onboardingLifecycle?.isVerifiedScope(
                context.accountId,
                context.homeId,
              ) !=
              true) {
        return;
      }
      try {
        final installed = await _controller.runJavaScriptReturningResult(
          _settingsSavedRenderer.installationScript(
            homeId: context.homeId,
            generation: generation,
          ),
        );
        if (installed != true ||
            !_isCurrentPageLoad(page, generation) ||
            !identical(widget.designContextCoordinator?.context, context)) {
          return;
        }
        await _applySavedAppliances(page, generation);
      } catch (_) {
        // The packaged rows remain usable if the saved inventory cannot bind.
      }
      return;
    }
    if (page != 'devices') return;
    if (context == null) return;
    try {
      final installed = await _controller.runJavaScriptReturningResult(
        _liveDevicesRenderer.installationScript(
          homeId: context.homeId,
          generation: generation,
        ),
      );
      if (installed != true ||
          !_isCurrentPageLoad(page, generation) ||
          !identical(widget.designContextCoordinator?.context, context)) {
        return;
      }
      await _applySampleDevicesBindings(generation);
      await _applyDevicesProjection(generation);
    } catch (_) {
      // A WebView failure leaves the static asset intact.
    }
  }

  Future<void> _applySelectedHomeName(
    String page,
    int generation,
    DesignPageTicket ticket,
  ) async {
    final context = widget.designContextCoordinator?.context;
    if (!_isCurrentPageLoad(page, generation) ||
        !identical(_pageTicket, ticket) ||
        context?.homeId != ticket.homeId) {
      return;
    }
    final script = _bindingRenderer.updateScript(
      ticket,
      selectedHomeNameBindings(page, widget.homeName),
    );
    if (script == null) return;
    try {
      await _controller.runJavaScriptReturningResult(script);
    } catch (_) {
      // The packaged home name remains visible on script failure.
    }
  }

  Future<void> _applyTipsSnapshot(String page, int generation) async {
    final read = _pageReads.latestRead;
    final context = widget.designContextCoordinator?.context;
    final ticket = _pageTicket;
    if (!_pageReady ||
        !_isCurrentPageLoad(page, generation) ||
        read?.page != page ||
        read?.value is! TipsDomainSnapshot ||
        context == null ||
        context.mode != DesignContextMode.household ||
        read?.accountId != context.accountId ||
        read?.homeId != context.homeId ||
        ticket == null ||
        ticket.homeId != context.homeId ||
        !identical(widget.designContextCoordinator?.context, context)) {
      return;
    }
    final snapshot = read!.value as TipsDomainSnapshot;
    if (snapshot.homeId.toLowerCase() != context.homeId.toLowerCase() ||
        !identical(_pageReads.latestRead, read)) {
      return;
    }
    try {
      await _controller.runJavaScriptReturningResult(
        _tipsRenderer.script(ticket, snapshot),
      );
    } catch (_) {
      // The packaged cards remain visible if the source projection fails.
    }
  }

  Future<void> _answerKnowledgeEntry(String questionId) async {
    const page = 'tips_knowledge';
    final generation = _pageLoadGeneration;
    final requestGeneration = ++_knowledgeRequestGeneration;
    final coordinator = widget.designContextCoordinator;
    final context = coordinator?.context;
    final ticket = _pageTicket;
    if (!_pageReady ||
        !_isCurrentPageLoad(page, generation) ||
        context == null ||
        context.mode != DesignContextMode.household ||
        ticket == null ||
        ticket.homeId != context.homeId ||
        KnowledgeDomainRepository.bundledCatalog.find(
              questionId,
              localPilot: true,
            ) ==
            null) {
      return;
    }
    try {
      final read = await coordinator!.answerKnowledgeEntry(
        questionId,
        localPilot: true,
      );
      if (requestGeneration != _knowledgeRequestGeneration ||
          !_isCurrentPageLoad(page, generation) ||
          !identical(widget.designContextCoordinator, coordinator) ||
          !identical(coordinator.context, context) ||
          !identical(_pageTicket, ticket) ||
          read?.accountId != context.accountId ||
          read?.homeId != context.homeId) {
        return;
      }
      final value = read?.value;
      final String answer;
      if (value is KnowledgePreparedAnswerAvailable) {
        answer = value.text;
      } else if (value is KnowledgeAnswerAvailable) {
        final result = value.answer;
        answer = result.status == 'insufficient_information'
            ? "We can't answer this right now."
            : [
                result.text,
                ...result.findings.map((row) => row.text),
              ].join('\n');
      } else {
        answer = "We can't answer this right now.";
      }
      await _controller.runJavaScriptReturningResult(
        buildKnowledgeAnswerScript(
          questionId: questionId,
          answer: answer,
          homeId: context.homeId,
          generation: ticket.generation,
        ),
      );
    } catch (error) {
      // The bundled answer remains visible if the household read fails.
      _showInternalErrorFor(error);
    }
  }

  Future<void> _applySettingsIdentity(int generation) async {
    final read = _pageReads.latestRead;
    final context = widget.designContextCoordinator?.context;
    final ticket = _pageTicket;
    if (!_pageReady ||
        !_isCurrentPageLoad('settings', generation) ||
        read == null ||
        read.page != 'settings' ||
        read.mode != DesignContextMode.household ||
        read.value is! SettingsDomainSnapshot ||
        context == null ||
        context.mode != DesignContextMode.household ||
        ticket == null ||
        read.accountId != context.accountId ||
        read.homeId != context.homeId ||
        ticket.homeId != context.homeId ||
        !identical(widget.designContextCoordinator?.context, context)) {
      return;
    }
    final localAuthSession =
        await widget.settingsApi?.session.isLocalAuthSession ?? false;
    if (!_isCurrentPageLoad('settings', generation)) return;
    final script = _settingsIdentityRenderer.script(
      ticket: ticket,
      snapshot: read.value as SettingsDomainSnapshot,
      expectedAccountId: context.accountId,
      localAuthSession: localAuthSession,
    );
    if (script == null || !identical(_pageReads.latestRead, read)) return;
    try {
      await _controller.runJavaScriptReturningResult(script);
    } catch (_) {
      // Blank identity fields remain unavailable if the page rejects the read.
    }
  }

  Future<void> _applySampleDevicesBindings(int generation) async {
    final projection = _sampleDevicesBindings;
    final read = _pageReads.latestRead;
    final context = widget.designContextCoordinator?.context;
    final ticket = _pageTicket;
    if (!_pageReady ||
        !_isCurrentPageLoad('devices', generation) ||
        projection == null ||
        projection.bindings.isEmpty ||
        read == null ||
        read.page != 'devices' ||
        (read.mode != DesignContextMode.sample &&
            !(read.mode == DesignContextMode.household &&
                read.value is DevicesDomainSnapshot &&
                (read.value as DevicesDomainSnapshot).dataMode ==
                    CloudApplianceDataMode.mixed)) ||
        context?.allowsReadMode(read.mode) != true ||
        read.accountId != context?.accountId ||
        read.homeId != context?.homeId ||
        ticket == null) {
      return;
    }
    final script = _bindingRenderer.updateScript(ticket, projection.bindings);
    if (script == null) return;
    try {
      await _controller.runJavaScriptReturningResult(script);
    } catch (_) {
      // The packaged cards remain available when the WebView rejects a read.
    }
  }

  Future<void> _applyDashboardBindings(int generation) async {
    final projection = _dashboardBindings;
    final read = _pageReads.latestRead;
    final context = widget.designContextCoordinator?.context;
    final ticket = _pageTicket;
    if (!_pageReady ||
        !_isCurrentPageLoad('dashboard', generation) ||
        projection == null ||
        read == null ||
        read.page != 'dashboard' ||
        context == null ||
        ticket == null ||
        read.accountId != context.accountId ||
        read.homeId != context.homeId ||
        !context.allowsReadMode(read.mode)) {
      return;
    }
    final script = _bindingRenderer.updateScript(ticket, projection.bindings);
    if (script == null) return;
    try {
      await _controller.runJavaScriptReturningResult(script);
    } catch (_) {
      // The packaged values remain visible on script failure.
    }
  }

  Future<void> _applyDashboardTopSavings(int generation) async {
    final projection = _topSavingsBindings;
    final read = _pageReads.latestRead;
    final context = widget.designContextCoordinator?.context;
    final ticket = _pageTicket;
    if (!_pageReady ||
        !_isCurrentPageLoad('dashboard', generation) ||
        projection == null ||
        read == null ||
        read.page != 'dashboard' ||
        context == null ||
        ticket == null ||
        read.accountId != context.accountId ||
        read.homeId != context.homeId ||
        !context.allowsReadMode(read.mode)) {
      return;
    }
    final script = _bindingRenderer.updateScript(ticket, projection.bindings);
    if (script == null) return;
    try {
      await _controller.runJavaScriptReturningResult(script);
      if (!_bindingGate.acceptsTicket(ticket)) return;
      await _controller.runJavaScriptReturningResult(
        hideDashboardBindingsScript(ticket, projection.hiddenBindingIds),
      );
    } catch (_) {
      // The packaged card remains visible on script failure.
    }
  }

  Future<void> _applyDashboardChart(int generation) async {
    final context = widget.designContextCoordinator?.context;
    final ticket = _pageTicket;
    if (!_pageReady ||
        !_isCurrentPageLoad('dashboard', generation) ||
        ticket == null) {
      return;
    }
    DashboardChartProjection? chart;
    if (context == null && (widget.localPilot || widget.designTour)) {
      chart = DashboardChartProjection.fromDemo(_dashboardGranularity);
    } else {
      final read = _pageReads.latestRead;
      if (context == null || ticket.homeId != context.homeId) {
        return;
      }
      if (read != null &&
          read.page == 'dashboard' &&
          read.value is DashboardDomainSnapshot &&
          read.accountId == context.accountId &&
          read.homeId == context.homeId &&
          context.allowsReadMode(read.mode)) {
        chart = DashboardChartProjection.fromSnapshot(
          read.value as DashboardDomainSnapshot,
          _dashboardGranularity,
        );
      }
      // The approved illustration keeps all three tabs usable while a Cloud
      // period is pending or unavailable. It never derives a split from real
      // unclassified cost, and a compatible current read replaces it.
      chart ??= DashboardChartProjection.fromDemo(_dashboardGranularity);
    }
    final script = _chartRenderer.script(ticket, chart);
    if (script == null) return;
    try {
      await _controller.runJavaScriptReturningResult(script);
    } catch (_) {
      // Keep the packaged chart if WebView rendering fails.
    }
  }

  EfficiencyPage? _efficiencyPageForRoute(String page) => switch (page) {
    'efficiency' => EfficiencyPage.overview,
    'efficiency_away' => EfficiencyPage.away,
    'efficiency_peak_rates' => EfficiencyPage.peak,
    'efficiency_habits' => EfficiencyPage.habits,
    _ => null,
  };

  EfficiencyDomainSnapshot? _efficiencySnapshot(Object? value) =>
      switch (value) {
        EfficiencyDomainSnapshot snapshot => snapshot,
        EfficiencyAwayDomainSnapshot snapshot => snapshot.efficiency,
        EfficiencyHabitsSnapshot snapshot => snapshot.efficiencySnapshot,
        EfficiencyPeakRatesSnapshot snapshot => snapshot.efficiencySnapshot,
        _ => null,
      };

  Future<void> _applyEfficiencyBindings(String page, int generation) async {
    final bindings = _efficiencyBindings;
    final read = _pageReads.latestRead;
    final context = widget.designContextCoordinator?.context;
    final ticket = _pageTicket;
    if (!_pageReady ||
        !_isCurrentPageLoad(page, generation) ||
        !_efficiencyPages.contains(page) ||
        bindings == null ||
        read == null ||
        read.page != page ||
        _efficiencySnapshot(read.value)?.page !=
            _efficiencyPageForRoute(page) ||
        context == null ||
        ticket == null ||
        read.accountId != context.accountId ||
        read.homeId != context.homeId ||
        !context.allowsReadMode(read.mode)) {
      return;
    }
    final pageBindings = page == 'efficiency'
        ? bindings
        : [
            for (final binding in bindings)
              DesignTextBinding(
                binding.id.replaceFirst('efficiency_text_', '${page}_text_'),
                binding.text,
              ),
          ];
    final script = _bindingRenderer.updateScript(ticket, pageBindings);
    if (script == null) return;
    try {
      await _controller.runJavaScriptReturningResult(script);
      final chart = _efficiencyChartSummary;
      if (chart != null && _isCurrentPageLoad(page, generation)) {
        await _controller.runJavaScriptReturningResult(
          buildEfficiencyTrailing30DaysChartScript(ticket, chart),
        );
      }
    } catch (_) {
      // Keep the packaged spend value when coverage is unavailable.
    }
  }

  Future<void> _applyDevicesProjection(int generation) async {
    final projection = _devicesProjection;
    final read = _pageReads.latestRead;
    final context = widget.designContextCoordinator?.context;
    if (!_pageReady ||
        !_isCurrentPageLoad('devices', generation) ||
        projection == null ||
        read?.page != 'devices' ||
        context == null ||
        !context.allowsReadMode(projection.mode) ||
        read?.accountId != context.accountId ||
        read?.homeId != context.homeId ||
        projection.homeId != context.homeId ||
        projection.mode != read?.mode) {
      return;
    }
    try {
      await _controller.runJavaScriptReturningResult(
        _liveDevicesRenderer.appendScript(
          projection: projection,
          generation: generation,
        ),
      );
    } catch (_) {
      // The renderer is additive; static cards remain on script failure.
    }
  }

  Future<void> _applySavedAppliances(String page, int generation) async {
    final rows = _savedAppliances;
    final context = widget.designContextCoordinator?.context;
    final lifecycle = widget.onboardingLifecycle;
    if (!_pageReady ||
        !_isCurrentPageLoad(page, generation) ||
        !_settingsDevicePages.contains(page) ||
        rows == null ||
        context == null ||
        context.mode != DesignContextMode.household ||
        _savedInventoryScope !=
            _cloudSavedScope(context.accountId, context.homeId) ||
        lifecycle?.isVerifiedScope(context.accountId, context.homeId) != true) {
      return;
    }
    try {
      await _controller.runJavaScriptReturningResult(
        _settingsSavedRenderer.appendScript(
          homeId: context.homeId,
          generation: generation,
          appliances: rows,
          savedPlugs: _savedPlugs,
          allowIdentityEdit:
              page == 'settings_manage_devices' && widget.settingsApi != null,
        ),
      );
    } catch (_) {
      // A stale or invalid saved inventory must not replace packaged rows.
    }
  }

  Future<void> _reviewDevice(String raw, {bool fromPhoto = false}) async {
    if (_reviewOpen ||
        (!fromPhoto &&
            _page != 'settings_manage_devices' &&
            _page != 'settings_manual_device_entry') ||
        (fromPhoto && _page != 'settings_photo_scan_onboarding')) {
      return;
    }
    final context = widget.designContextCoordinator?.context;
    final lifecycle = widget.onboardingLifecycle;
    if (!widget.localPilot &&
        (context == null ||
            context.mode != DesignContextMode.household ||
            lifecycle == null ||
            !lifecycle.isVerifiedScope(context.accountId, context.homeId))) {
      return;
    }
    final Map<String, dynamic> fields;
    try {
      final decoded = jsonDecode(raw);
      if (decoded is! Map<String, dynamic> ||
          decoded['name'] is! String ||
          decoded['manufacturer'] is! String ||
          decoded['model'] is! String ||
          (decoded['group'] != null && decoded['group'] is! String) ||
          (decoded['room'] != null && decoded['room'] is! String) ||
          (decoded['category'] != null && decoded['category'] is! String) ||
          (decoded['serialNumber'] != null &&
              decoded['serialNumber'] is! String) ||
          (decoded['fccId'] != null && decoded['fccId'] is! String) ||
          (decoded['icId'] != null && decoded['icId'] is! String) ||
          (decoded['upc'] != null && decoded['upc'] is! String)) {
        return;
      }
      fields = decoded;
    } catch (_) {
      return;
    }
    final selectedCategory = fields['category'] as String?;
    if (!fromPhoto && (selectedCategory == null || selectedCategory.isEmpty)) {
      return;
    }
    final room = (fields['room'] as String?) ?? '';
    _reviewOpen = true;
    try {
      if (widget.localPilot) {
        final page = _page;
        final generation = _pageLoadGeneration;
        final inventory = _localInventory;
        final localLifecycle = widget.localDeviceLifecycle;
        if (inventory == null || localLifecycle == null) return;
        final session = await localLifecycle.beginSave(inventory);
        if (session == null || !_isCurrentPageLoad(page, generation)) return;
        if (!mounted) return;
        final result = await showDialog<LocalWriteResult>(
          context: this.context,
          builder: (_) => LocalPilotDeviceReviewSheet(
            lifecycle: localLifecycle,
            session: session,
            onboardingMethod: fromPhoto ? 'photo' : 'manual',
            name: fields['name'] as String,
            manufacturer: fields['manufacturer'] as String,
            model: fields['model'] as String,
            initialRoom: room,
            initialCategory: selectedCategory?.isEmpty == true
                ? null
                : selectedCategory,
            initialCategories: _sessionCategories,
          ),
        );
        if (result?.status == LocalWriteStatus.confirmed &&
            _settingsDevicePages.contains(_page)) {
          await _refreshLocalInventory(_page, _pageLoadGeneration);
        }
        return;
      }
      if (context == null || lifecycle == null || !mounted) return;
      final reviewPage = _page;
      final reviewGeneration = _pageLoadGeneration;
      final model = (fields['model'] as String).trim();
      final manufacturer = (fields['manufacturer'] as String).trim();
      var catalogResults = <CloudCatalogProduct>[];
      var catalogSearchFailed = false;
      if (fromPhoto && model.isNotEmpty && widget.settingsApi != null) {
        try {
          catalogResults = await widget.settingsApi!.searchCatalogModels(
            model: model,
            brand: manufacturer.isEmpty ? null : manufacturer,
          );
        } catch (_) {
          catalogSearchFailed = true;
        }
      }
      if (!mounted ||
          !_isCurrentPageLoad(reviewPage, reviewGeneration) ||
          !lifecycle.isVerifiedScope(context.accountId, context.homeId)) {
        return;
      }
      final saved = await showDialog<CloudAppliance>(
        context: this.context,
        builder: (_) => DeviceReviewSheet(
          lifecycle: lifecycle,
          api: widget.settingsApi,
          accountId: context.accountId,
          homeId: context.homeId,
          homeName: widget.homeName,
          name: fields['name'] as String,
          manufacturer: fields['manufacturer'] as String,
          model: fields['model'] as String,
          serialNumber: fromPhoto ? fields['serialNumber'] as String? : null,
          fccId: fromPhoto ? fields['fccId'] as String? : null,
          icId: fromPhoto ? fields['icId'] as String? : null,
          upc: fromPhoto ? fields['upc'] as String? : null,
          initialRoom: room,
          catalogResults: catalogResults,
          catalogSearchFailed: catalogSearchFailed,
          modelNotFoundOnLabel: fromPhoto && model.isEmpty,
          initialCategory: selectedCategory?.isEmpty == true
              ? null
              : selectedCategory,
        ),
      );
      if (saved != null &&
          saved.homeId == context.homeId &&
          lifecycle.isVerifiedScope(context.accountId, context.homeId)) {
        await _refreshSavedAppliances(_page, _pageLoadGeneration);
      }
    } finally {
      _reviewOpen = false;
      if (_deviceRefreshReloadPending) unawaited(_reloadAfterDeviceRefresh());
    }
  }

  Future<void> _capturePhoto(String source) async {
    if (_capturingPhoto ||
        _page != 'settings_photo_scan_onboarding' ||
        (source != 'camera' && source != 'gallery')) {
      return;
    }
    final context = widget.designContextCoordinator?.context;
    final lifecycle = widget.onboardingLifecycle;
    if (!widget.localPilot &&
        (context == null ||
            context.mode != DesignContextMode.household ||
            lifecycle == null ||
            !lifecycle.isVerifiedScope(context.accountId, context.homeId))) {
      return;
    }
    final pageGeneration = _pageLoadGeneration;
    _capturingPhoto = true;
    CapturedPhoto? photo;
    try {
      await _clearScanResults();
      photo = source == 'camera'
          ? await widget.photoCapture.capturePhoto()
          : await widget.photoCapture.pickFromGallery();
      if (photo != null) await _processCapturedPhoto(photo, pageGeneration);
    } on CameraPermissionDeniedException {
      _photoMessage(
        'Camera access was denied. Allow it in settings or choose a photo.',
      );
    } on PhotoLibraryPermissionDeniedException {
      _photoMessage(
        'Photo access was denied. Allow it in settings or use the camera.',
      );
    } on FormatException {
      _photoMessage(
        'This photo is over 5 MB. Take it again or choose a smaller one.',
      );
    } on PlatformException {
      _photoMessage('Camera is not available. Choose a photo instead.');
    } catch (_) {
      _photoMessage('Something went wrong with the photo. Try again.');
    } finally {
      if (photo != null) await widget.photoCapture.discard(photo);
      _capturingPhoto = false;
      if (_deviceRefreshReloadPending) unawaited(_reloadAfterDeviceRefresh());
    }
  }

  /// Backend failures are 5xx, network, timeout and unparseable responses.
  /// Session rejections (401/403) are handled centrally by signing out.
  static bool _isBackendFailure(Object error) {
    if (error is CloudApiException) {
      return !isSessionRejectionStatus(error.statusCode) &&
          !isInputRejectionStatus(error.statusCode);
    }
    if (error is HubRequestException) {
      return !isInputRejectionStatus(error.statusCode);
    }
    return error is PairingException ||
        error is SocketException ||
        error is TimeoutException ||
        error is ClientException ||
        error is HandshakeException ||
        error is TlsException ||
        error is FormatException ||
        error is TypeError;
  }

  void _showInternalErrorFor(Object error) {
    if (!mounted || !_isBackendFailure(error)) return;
    final now = DateTime.now();
    final last = _internalErrorShownAt;
    if (last != null && now.difference(last) < const Duration(seconds: 5)) {
      return;
    }
    _internalErrorShownAt = now;
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(const SnackBar(content: Text(internalErrorMessage)));
  }

  void _photoMessage(String message) {
    if (!mounted || _page != 'settings_photo_scan_onboarding') return;
    ScaffoldMessenger.of(context)
        .showSnackBar(SnackBar(content: Text(message)));
  }

  Future<void> _clearScanResults() async {
    if (!mounted || _page != 'settings_photo_scan_onboarding') return;
    try {
      await _controller.runJavaScript(
        'window.EnergyLensPhotoScanResults?.clear();',
      );
    } catch (_) {
      // The native review flow remains available if the page is still loading.
    }
  }

  Future<void> _showScanResults({
    required bool model,
    required bool brand,
    required bool serial,
    required bool fccId,
    required bool icId,
  }) async {
    if (!mounted || _page != 'settings_photo_scan_onboarding') return;
    final states = jsonEncode({
      'model': model,
      'brand': brand,
      'serial': serial,
      'fccId': fccId,
      'icId': icId,
    });
    try {
      await _controller.runJavaScript(
        'window.EnergyLensPhotoScanResults?.show($states);',
      );
    } catch (_) {
      // The native review flow remains available if the page is still loading.
    }
  }

  Future<void> _recoverLostPhoto() async {
    if (_capturingPhoto) return;
    _capturingPhoto = true;
    CapturedPhoto? photo;
    try {
      photo = await widget.photoCapture.recoverLostPhoto();
      if (photo == null || !mounted) return;
      if (_page != 'settings_photo_scan_onboarding') {
        await _navigate('settings_photo_scan_onboarding');
      }
      if (!mounted || _page != 'settings_photo_scan_onboarding') return;
      await _clearScanResults();
      _photoMessage('Your last photo was recovered. Reading it now.');
      await _processCapturedPhoto(photo, _pageLoadGeneration);
    } on PhotoRecoveryException {
      if (mounted && _page != 'settings_photo_scan_onboarding') {
        await _navigate('settings_photo_scan_onboarding');
      }
      _photoMessage(
        'The photo was lost while the camera was open. Take it again.',
      );
    } catch (_) {
      _photoMessage('Something went wrong with the photo. Try again.');
    } finally {
      if (photo != null) await widget.photoCapture.discard(photo);
      _capturingPhoto = false;
      if (_deviceRefreshReloadPending) unawaited(_reloadAfterDeviceRefresh());
    }
  }

  Future<void> _processCapturedPhoto(
    CapturedPhoto photo,
    int pageGeneration,
  ) async {
    final context = widget.designContextCoordinator?.context;
    final lifecycle = widget.onboardingLifecycle;
    bool isCurrent() =>
        _isCurrentPageLoad('settings_photo_scan_onboarding', pageGeneration) &&
        (widget.localPilot ||
            (context != null &&
                lifecycle != null &&
                lifecycle.isVerifiedScope(context.accountId, context.homeId)));
    if (!isCurrent()) return;
    String? text;
    String? upc;
    try {
      final results = await Future.wait<String?>([
        widget.photoCapture.extractTextHint(photo.path),
        widget.photoCapture.detectUpc(photo.path).catchError((_) => null),
      ]);
      text = results[0];
      upc = results[1];
    } catch (_) {
      if (isCurrent()) {
        _photoMessage(
          'Could not read this photo. Try again or enter the model yourself.',
        );
      }
      return;
    }
    if (!isCurrent()) return;
    if (text == null || text.trim().isEmpty) {
      await _showScanResults(
        model: false,
        brand: false,
        serial: false,
        fccId: false,
        icId: false,
      );
      _photoMessage(
        'No label text found. Try again or enter the model yourself.',
      );
      return;
    }
    final identity = identityFieldsFromOcr(text);
    final manufacturer = manufacturerHintFromOcr(text);
    await _showScanResults(
      model: identity.model != null,
      brand: manufacturer != null,
      serial: identity.serialNumber != null,
      fccId: identity.fccId != null,
      icId: identity.icId != null,
    );
    if (widget.localPilot &&
        (_localInventory == null || widget.localDeviceLifecycle == null)) {
      _photoMessage('Scan complete. A paired hub is needed to use it.');
      return;
    }
    await _reviewDevice(
      jsonEncode({
        'name': '',
        'manufacturer': manufacturer ?? '',
        'model': identity.model ?? '',
        'upc': upc,
        'serialNumber': identity.serialNumber,
        'fccId': identity.fccId,
        'icId': identity.icId,
      }),
      fromPhoto: true,
    );
  }

  Future<void> _archiveSavedAppliance(String applianceId) async {
    if (widget.localPilot) {
      await _deleteLocalAppliance(applianceId);
      return;
    }
    if (_archivingApplianceIds.contains(applianceId)) return;
    final context = widget.designContextCoordinator?.context;
    final lifecycle = widget.onboardingLifecycle;
    final row = _savedAppliances
        ?.where((item) => item.id == applianceId)
        .firstOrNull;
    if (context == null ||
        context.mode != DesignContextMode.household ||
        lifecycle == null ||
        row == null ||
        row.homeId != context.homeId ||
        row.archivedAt != null ||
        !lifecycle.isVerifiedScope(context.accountId, context.homeId)) {
      return;
    }
    final page = _page;
    final generation = _pageLoadGeneration;
    _archivingApplianceIds.add(applianceId);
    final key = _archiveKeys.putIfAbsent(applianceId, newCloudIdempotencyKey);
    try {
      await lifecycle.archiveAppliance(
        context.accountId,
        context.homeId,
        applianceId,
        key,
      );
      _archiveKeys.remove(applianceId);
      await _refreshSavedAppliances(page, generation);
    } catch (writeError) {
      // Reconcile an uncertain response against the authoritative inventory.
      var confirmed = false;
      try {
        final rows = await lifecycle.refreshSavedAppliances(
          context.accountId,
          context.homeId,
        );
        if (rows != null &&
            !rows.any((item) => item.id == applianceId) &&
            _isCurrentPageLoad(page, generation) &&
            identical(widget.designContextCoordinator?.context, context)) {
          confirmed = true;
          _archiveKeys.remove(applianceId);
          _savedAppliances = rows;
          await _applySavedAppliances(page, generation);
        }
      } catch (_) {
        // Retain the row and retry key when neither write nor read is confirmed.
      }
      if (!confirmed) _showInternalErrorFor(writeError);
    } finally {
      _archivingApplianceIds.remove(applianceId);
    }
  }

  Future<void> _editSavedAppliance(String applianceId) async {
    if (_identityEditOpen ||
        _page != 'settings_manage_devices' ||
        widget.localPilot ||
        widget.designTour ||
        widget.settingsApi == null) {
      return;
    }
    final context = widget.designContextCoordinator?.context;
    final lifecycle = widget.onboardingLifecycle;
    final row = _savedAppliances
        ?.where((item) => item.id == applianceId)
        .firstOrNull;
    if (context == null ||
        context.mode != DesignContextMode.household ||
        lifecycle == null ||
        !lifecycle.isVerifiedScope(context.accountId, context.homeId) ||
        row == null ||
        row.homeId != context.homeId ||
        row.archivedAt != null ||
        row.demoDeviceId != null) {
      return;
    }
    final generation = _pageLoadGeneration;
    bool current() =>
        mounted &&
        _isCurrentPageLoad('settings_manage_devices', generation) &&
        identical(widget.designContextCoordinator?.context, context) &&
        lifecycle.isVerifiedScope(context.accountId, context.homeId);
    if (!current()) return;
    _identityEditOpen = true;
    try {
      final saved = await Navigator.of(this.context).push<bool>(
        MaterialPageRoute<bool>(
          builder: (_) => ApplianceIdentityEditScreen(
            api: widget.settingsApi!,
            homeId: context.homeId,
            applianceId: applianceId,
            isCurrentScope: current,
          ),
        ),
      );
      if (saved == true && current()) {
        await _refreshSavedAppliances('settings_manage_devices', generation);
      }
    } finally {
      _identityEditOpen = false;
      if (_deviceRefreshReloadPending) unawaited(_reloadAfterDeviceRefresh());
    }
  }

  Future<void> _deleteLocalAppliance(String rawId) async {
    final id = int.tryParse(rawId);
    final inventory = _localInventory;
    final lifecycle = widget.localDeviceLifecycle;
    if (id == null ||
        id <= 0 ||
        _deletingLocalIds.contains(id) ||
        inventory == null ||
        lifecycle == null ||
        !inventory.rows.any(
          (row) =>
              row.id == id &&
              (row.onboardingMethod == 'manual' ||
                  row.onboardingMethod == 'photo'),
        )) {
      return;
    }
    final page = _page;
    final generation = _pageLoadGeneration;
    if (!_settingsDevicePages.contains(page)) return;
    final approved = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Delete device?'),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(context).pop(true),
            child: const Text('Delete'),
          ),
        ],
      ),
    );
    if (approved != true || !_isCurrentPageLoad(page, generation)) return;
    _deletingLocalIds.add(id);
    try {
      final result = await lifecycle.delete(inventory, id);
      if (_isCurrentPageLoad(page, generation) &&
          result.inventory?.identity == inventory.identity) {
        _localInventory = result.inventory;
        await _applyLocalInventory(page, generation);
      }
    } catch (error) {
      _showInternalErrorFor(error);
    } finally {
      _deletingLocalIds.remove(id);
    }
  }

  static const _deviceDetailRoute = 'device_detail:';
  static final _applianceIdPattern = RegExp(
    r'^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$',
  );
  bool _deviceDetailOpen = false;

  /// [target] is `<appliance id>:<name>` from a tapped Devices card.
  Future<void> _openDeviceDetail(String target) async {
    final split = target.indexOf(':');
    final id = split < 0 ? '' : target.substring(0, split);
    final name = split < 0 ? '' : target.substring(split + 1).trim();
    final api = widget.settingsApi;
    final current = widget.designContextCoordinator?.context;
    final lifecycle = widget.onboardingLifecycle;
    if (_deviceDetailOpen ||
        _page != 'devices' ||
        api == null ||
        current == null ||
        name.isEmpty ||
        !_applianceIdPattern.hasMatch(id) ||
        (lifecycle != null &&
            !lifecycle.isVerifiedScope(current.accountId, current.homeId))) {
      return;
    }
    _deviceDetailOpen = true;
    try {
      await Navigator.of(context).push<void>(
        MaterialPageRoute<void>(
          builder: (_) => CloudUsageQuestionsScreen(
            api: api,
            homeId: current.homeId,
            applianceId: id,
            applianceName: name,
          ),
        ),
      );
    } finally {
      _deviceDetailOpen = false;
    }
  }

  Future<void> _open(String route) async {
    if (route.startsWith('edit_appliance:')) {
      await _editSavedAppliance(route.substring('edit_appliance:'.length));
      return;
    }
    if (route == 'discover_devices') {
      if (widget.localPilot && !widget.designTour) {
        if (_page != 'settings_manage_devices' ||
            widget.onDiscoverDevices == null) {
          return;
        }
        final generation = _pageLoadGeneration;
        await widget.onDiscoverDevices!();
        if (_isCurrentPageLoad('settings_manage_devices', generation)) {
          _localInventory = null;
          await _refreshLocalInventory('settings_manage_devices', generation);
        }
        return;
      }
      final context = widget.designContextCoordinator?.context;
      final lifecycle = widget.onboardingLifecycle;
      final discover = widget.onDiscoverDevices;
      if (_page != 'settings_manage_devices' ||
          context == null ||
          context.mode != DesignContextMode.household ||
          lifecycle == null ||
          discover == null ||
          !lifecycle.isVerifiedScope(context.accountId, context.homeId)) {
        return;
      }
      final generation = _pageLoadGeneration;
      await discover();
      if (_isCurrentPageLoad('settings_manage_devices', generation) &&
          identical(widget.designContextCoordinator?.context, context) &&
          lifecycle.isVerifiedScope(context.accountId, context.homeId)) {
        await _refreshSavedAppliances('settings_manage_devices', generation);
      }
      return;
    }
    if (route.startsWith(_deviceDetailRoute)) {
      await _openDeviceDetail(route.substring(_deviceDetailRoute.length));
      return;
    }
    if (_page == 'dashboard' && route.startsWith('dashboard_period:')) {
      final granularity = route.substring('dashboard_period:'.length);
      if (const {'day', 'week', 'month'}.contains(granularity)) {
        // Keep the requested period while typed reads are still pending.
        // _readPage applies it once the matching current-home data arrives.
        _dashboardGranularity = granularity;
        await _applyDashboardChart(_pageLoadGeneration);
      }
      return;
    }
    if (route == 'sign_out') {
      _invalidateDeviceRefresh();
      _navigationEpoch++;
      _pageStates.clear();
      _history.clear();
      _invalidatePageLoad();
      _pageReads.clear();
      _dashboardGranularity = 'day';
      widget.onSignOut?.call();
      return;
    }
    if (route == 'change_home') {
      _invalidateDeviceRefresh();
      _navigationEpoch++;
      _pageStates.clear();
      _history.clear();
      _invalidatePageLoad();
      _pageReads.clear();
      _dashboardGranularity = 'day';
      widget.onChangeHome?.call();
      return;
    }
    if (route == 'report_preview') {
      widget.onReportPreview?.call();
      return;
    }
    if (route == 'edit_home_details') {
      if (widget.localPilot && _page == 'settings') {
        await _editLocalPilotSettings(editOwner: false);
        return;
      }
      final coordinator = widget.designContextCoordinator;
      final current = coordinator?.context;
      final api = widget.settingsApi;
      if (current == null || api == null || _page != 'settings') return;
      bool stillCurrent() =>
          mounted &&
          _page == 'settings' &&
          identical(coordinator?.context, current);
      final saved = await Navigator.of(context).push<bool>(
        MaterialPageRoute<bool>(
          builder: (_) => HomeDetailsScreen(
            api: api,
            homeId: current.homeId,
            isCurrentHome: stillCurrent,
          ),
        ),
      );
      if (saved == true && stillCurrent()) {
        await _loadPage();
        if (mounted && stillCurrent()) {
          ScaffoldMessenger.of(
            context,
          ).showSnackBar(const SnackBar(content: Text('Saved Successfully')));
        }
      }
      return;
    }
    if (route == 'edit_account_owner' ||
        route == 'edit_account_email' ||
        route == 'change_account_password') {
      if (widget.localPilot &&
          route == 'edit_account_owner' &&
          _page == 'settings') {
        await _editLocalPilotSettings(editOwner: true);
        return;
      }
      if (widget.localPilot &&
          route == 'change_account_password' &&
          _page == 'settings') {
        bool stillCurrent() =>
            mounted && widget.localPilot && _page == 'settings';
        final saved = await Navigator.of(context).push<bool>(
          MaterialPageRoute<bool>(
            builder: (_) => AccountProfileScreen.localPilotPassword(
              isCurrentAccount: stillCurrent,
            ),
          ),
        );
        if (saved == true && mounted && stillCurrent()) {
          ScaffoldMessenger.of(
            context,
          ).showSnackBar(const SnackBar(content: Text('Saved Successfully')));
        }
        return;
      }
      final coordinator = widget.designContextCoordinator;
      final current = coordinator?.context;
      final api = widget.settingsApi;
      if (current == null || api == null || _page != 'settings') return;
      final field = switch (route) {
        'edit_account_owner' => AccountProfileField.owner,
        'edit_account_email' => AccountProfileField.email,
        _ => AccountProfileField.password,
      };
      if (field != AccountProfileField.owner &&
          !await api.session.isLocalAuthSession) {
        return;
      }
      bool stillCurrent() =>
          mounted &&
          _page == 'settings' &&
          identical(coordinator?.context, current);
      if (!stillCurrent() || !mounted) return;
      final saved = await Navigator.of(context).push<bool>(
        MaterialPageRoute<bool>(
          builder: (_) => AccountProfileScreen(
            api: api,
            field: field,
            isCurrentAccount: stillCurrent,
          ),
        ),
      );
      if (saved == true && stillCurrent()) {
        if (field == AccountProfileField.password) {
          if (mounted) {
            ScaffoldMessenger.of(
              context,
            ).showSnackBar(const SnackBar(content: Text('Saved Successfully')));
            await Future<void>.delayed(const Duration(milliseconds: 1500));
          }
          await api.session.signOut();
          if (mounted) {
            widget.onSignOut?.call();
          }
        } else {
          await _loadPage();
          if (mounted && stillCurrent()) {
            ScaffoldMessenger.of(
              context,
            ).showSnackBar(const SnackBar(content: Text('Saved Successfully')));
          }
        }
      }
      return;
    }
    if (!_pages.contains(route) || route == _page) return;
    await _navigate(route);
  }

  void _back() => unawaited(_backOrDismissPicker());

  Future<void> _backOrDismissPicker() async {
    if (_page == 'settings_manage_devices' ||
        _page == 'settings_manual_device_entry') {
      try {
        final dismissed = await _controller.runJavaScriptReturningResult(
          'window.EnergyLensDevicePicker?.dismiss() === true',
        );
        if (dismissed == true || dismissed.toString() == 'true') return;
      } catch (_) {
        // The page can still navigate if its picker is not installed.
      }
    }
    if (_history.isNotEmpty) await _navigate(null);
  }

  Future<void> _navigate(String? route) async {
    if (_navigating) return;
    _navigating = true;
    final epoch = _navigationEpoch;
    try {
      await _capturePageState();
      if (!mounted || epoch != _navigationEpoch) return;
      final destination = route ?? _history.last;
      final sourceSection = _peerTabSection(_page);
      _peerTabScrollY =
          sourceSection != null && sourceSection == _peerTabSection(destination)
          ? _pageStates.forPage(_pageStateHomeId, _page)?.scrollY
          : null;
      if (route == null) {
        if (_history.isEmpty) return;
        setState(() => _page = _history.removeLast());
      } else {
        setState(() {
          _history.add(_page);
          _page = route;
        });
      }
      await _loadPage();
    } finally {
      _navigating = false;
      if (_deviceRefreshReloadPending) unawaited(_reloadAfterDeviceRefresh());
    }
  }

  String? _peerTabSection(String page) {
    if (_efficiencyPages.contains(page)) return 'efficiency';
    if (page == 'perks_tips' || page.startsWith('tips_')) return 'tips';
    if (page == 'settings' || page == 'settings_manage_devices') {
      return 'settings';
    }
    return null;
  }

  Future<void> _installNavigation() async {
    await _controller.runJavaScript(buildDesignNavigationScript(_page));
  }

  @override
  Widget build(BuildContext context) {
    return PopScope(
      canPop: _history.isEmpty,
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop) _back();
      },
      child: Scaffold(
        backgroundColor: Colors.white,
        body: SafeArea(child: WebViewWidget(controller: _controller)),
      ),
    );
  }
}
