import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:webview_flutter/webview_flutter.dart';

import '../../core/cloud_api/cloud_appliance.dart';
import '../../core/cloud_api/cloud_appliance_list.dart';
import '../../core/cloud_api/cloud_home.dart' show newCloudIdempotencyKey;
import '../../core/cloud_auth/cloud_auxiliary_domain_lifecycle.dart';
import '../identify/appliance_onboarding_screen.dart'
    show manufacturerHintFromOcr, modelHintFromOcr;
import '../identify/photo_capture_service.dart';
import 'device_review_sheet.dart';
import 'efficiency_domain_repository.dart';
import 'efficiency_rolling_bindings.dart';
import 'dashboard_chart_projection.dart';
import 'dashboard_chart_renderer.dart';
import 'dashboard_domain_repository.dart';
import 'design_context_coordinator.dart';
import 'design_numeric_bindings.dart';
import 'design_navigation_script.dart';
import 'design_page_read_dispatcher.dart';
import 'design_page_bridge.dart';
import 'design_page_state_script.dart';
import 'design_page_state_snapshot.dart';
import 'devices_domain_repository.dart';
import 'live_devices_card_renderer.dart';
import 'live_devices_projection.dart';
import 'knowledge_page_script.dart';
import 'settings_saved_devices_renderer.dart';
import 'settings_identity_renderer.dart';
import 'settings_domain_repository.dart';
import 'local_pilot_device_lifecycle.dart';
import 'local_pilot_device_review_sheet.dart';
import 'local_settings_devices_renderer.dart';

/// The approved design files are complete mobile pages. Keep their markup and
/// wording in assets/design_pages; this shell only supplies native navigation.
class DesignShell extends StatefulWidget {
  const DesignShell({
    super.key,
    this.onSignOut,
    this.onChangeHome,
    this.onReportPreview,
    this.onDiscoverDevices,
    this.onboardingLifecycle,
    this.photoCapture = const PhotoCaptureService(),
    this.designContextCoordinator,
    this.designTour = false,
    this.localPilot = false,
    this.localDeviceLifecycle,
    this.homeName = 'The Miller Home',
  });

  final VoidCallback? onSignOut;
  final VoidCallback? onChangeHome;
  final VoidCallback? onReportPreview;
  final Future<void> Function()? onDiscoverDevices;
  final CloudAuxiliaryDomainLifecycle? onboardingLifecycle;
  final PhotoCaptureService photoCapture;

  /// Native-only verified scope. It is never passed into the WebView.
  final DesignContextCoordinator? designContextCoordinator;
  final bool designTour;
  final bool localPilot;
  final LocalPilotDeviceLifecycle? localDeviceLifecycle;
  final String homeName;

  @override
  State<DesignShell> createState() => _DesignShellState();
}

class _DesignShellState extends State<DesignShell> {
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
  static const _localSettingsRenderer = LocalSettingsDevicesRenderer();
  static const _settingsIdentityRenderer = SettingsIdentityRenderer();
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
  bool _pageReady = false;
  LiveDevicesProjection? _devicesProjection;
  List<CloudAppliance>? _savedAppliances;
  LocalInventory? _localInventory;
  String? _renderedLocalIdentity;
  final Set<int> _deletingLocalIds = <int>{};
  DesignNumericBindings? _dashboardBindings;
  DesignNumericBindings? _sampleDevicesBindings;
  List<DesignTextBinding>? _efficiencyBindings;
  List<DesignTextBinding>? _sharedEfficiencyBindings;
  Object? _sharedEfficiencyContext;
  bool _efficiencyDetailsExpanded = false;
  DesignPageTicket? _pageTicket;
  Timer? _tourTimer;
  int _tourIndex = 0;
  final List<String> _history = [];
  String _page = 'dashboard';
  bool _reviewOpen = false;
  bool _capturingPhoto = false;
  final Set<String> _archivingApplianceIds = <String>{};
  final Map<String, String> _archiveKeys = <String, String>{};
  bool _navigating = false;
  int _navigationEpoch = 0;
  String? _activePageStateScope;

  String get _pageStateHomeId {
    final context = widget.designContextCoordinator?.context;
    return context == null
        ? '__local_design__'
        : '${context.accountId}/${context.homeId}';
  }

  @override
  void initState() {
    super.initState();
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
    WidgetsBinding.instance.addPostFrameCallback((_) => _loadPage());
  }

  @override
  void didUpdateWidget(covariant DesignShell oldWidget) {
    super.didUpdateWidget(oldWidget);
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
    _tourTimer = Timer(const Duration(seconds: 8), () {
      if (!mounted || _tourIndex + 1 >= _tourOrder.length) return;
      _tourIndex++;
      setState(() => _page = _tourOrder[_tourIndex]);
      _loadPage();
    });
  }

  @override
  void dispose() {
    _tourTimer?.cancel();
    _invalidatePageLoad();
    _pageReads.dispose();
    super.dispose();
  }

  Future<void> _loadPage() async {
    if (!mounted) return;
    final scope = _pageStateHomeId;
    if (_activePageStateScope != scope) {
      _activePageStateScope = scope;
      _navigationEpoch++;
      _history.clear();
      _dashboardGranularity = 'day';
      _sharedEfficiencyBindings = null;
      _sharedEfficiencyContext = null;
      _efficiencyDetailsExpanded = false;
    }
    if (!_efficiencyPages.contains(_page)) {
      _sharedEfficiencyBindings = null;
      _sharedEfficiencyContext = null;
      _efficiencyDetailsExpanded = false;
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
    final snapshot = _pageStates.forPage(_pageStateHomeId, page);
    if (snapshot == null) return;
    try {
      await _controller.runJavaScript(
        buildDesignPageStateRestoreScript(snapshot),
      );
    } catch (_) {
      // A failed restoration leaves the page usable with its default state.
    }
  }

  Future<void> _capturePageState() async {
    if (!_pageReady) return;
    final page = _page;
    final generation = _pageLoadGeneration;
    final homeId = _pageStateHomeId;
    try {
      if (_efficiencyPages.contains(page)) {
        final expanded = await _controller.runJavaScriptReturningResult(
          "document.getElementById('efficiency-details-toggle')?.getAttribute('aria-expanded') === 'true'",
        );
        if (!_isCurrentPageLoad(page, generation)) return;
        _efficiencyDetailsExpanded = expanded == true;
      }
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

  void _invalidatePageLoad() {
    _pageLoadGeneration++;
    _pageReady = false;
    _devicesProjection = null;
    _savedAppliances = null;
    _localInventory = null;
    _renderedLocalIdentity = null;
    _dashboardBindings = null;
    _sampleDevicesBindings = null;
    _efficiencyBindings = null;
    _pageTicket = null;
    _bindingGate.clear();
  }

  bool _isCurrentPageLoad(String page, int generation) =>
      mounted && _page == page && _pageLoadGeneration == generation;

  Future<void> _readPage(String page, int generation) async {
    await _pageReads.load(page);
    if (!_isCurrentPageLoad(page, generation)) return;
    if (page == 'settings') {
      await _applySettingsIdentity(generation);
      return;
    }
    if (_settingsDevicePages.contains(page)) {
      await _refreshSavedAppliances(page, generation);
      return;
    }
    final read = _pageReads.latestRead;
    if (page == 'efficiency') {
      if (read?.value is! EfficiencyDomainSnapshot) return;
      final source = read!.value as EfficiencyDomainSnapshot;
      final bindings = prepareEfficiencyRollingBindings(source);
      if (bindings == null ||
          !_isCurrentPageLoad(page, generation) ||
          !identical(_pageReads.latestRead, read)) {
        return;
      }
      _efficiencyBindings = bindings;
      _sharedEfficiencyBindings = bindings;
      _sharedEfficiencyContext = widget.designContextCoordinator?.context;
      await _applyEfficiencyBindings(generation);
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
      } catch (_) {
        // Packaged numeric values remain visible when live values are invalid.
      }
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
      await _applySavedAppliances(page, generation);
    } catch (_) {
      // A failed inventory read never creates a saved row from a draft.
    }
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
    if (_efficiencyPages.contains(page) && _efficiencyDetailsExpanded) {
      try {
        await _controller.runJavaScriptReturningResult(
          "(() => { const toggle = document.getElementById('efficiency-details-toggle'); if (!toggle) return false; toggle.click(); return true; })()",
        );
      } catch (_) {
        // The shared summary remains available with its default collapsed detail.
      }
    }
    if (page == 'tips_knowledge') {
      try {
        await _controller.runJavaScriptReturningResult(
          buildKnowledgePageScript(
            localPilot: const bool.fromEnvironment('ENERGYLENS_LOCAL_PILOT'),
          ),
        );
      } catch (_) {
        // The packaged local-pilot FAQ remains available on a script failure.
      }
      return;
    }
    if (page == 'dashboard') {
      if (context == null) return;
      await _applyDashboardBindings(generation);
      await _applyDashboardChart(generation);
      return;
    }
    if (page == 'efficiency') {
      await _applyEfficiencyBindings(generation);
      return;
    }
    if (_efficiencyPages.contains(page)) {
      await _applySharedEfficiencyBindings(page, generation);
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
    if (context?.mode == DesignContextMode.sample) {
      await _applySampleDevicesBindings(generation);
      return;
    }
    if (context == null || context.mode != DesignContextMode.household) return;
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
    if (page == 'settings') return;
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
    final script = _settingsIdentityRenderer.script(
      ticket: ticket,
      snapshot: read.value as SettingsDomainSnapshot,
      expectedAccountId: context.accountId,
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

  Future<void> _applyDashboardChart(int generation) async {
    final read = _pageReads.latestRead;
    final context = widget.designContextCoordinator?.context;
    final ticket = _pageTicket;
    if (!_pageReady ||
        !_isCurrentPageLoad('dashboard', generation) ||
        read == null ||
        read.page != 'dashboard' ||
        read.value is! DashboardDomainSnapshot ||
        context == null ||
        ticket == null ||
        read.accountId != context.accountId ||
        read.homeId != context.homeId ||
        !context.allowsReadMode(read.mode)) {
      return;
    }
    final snapshot = read.value as DashboardDomainSnapshot;
    final chart = DashboardChartProjection.fromSnapshot(
      snapshot,
      _dashboardGranularity,
    );
    if (chart == null) return;
    final script = _chartRenderer.script(ticket, chart);
    if (script == null) return;
    try {
      await _controller.runJavaScriptReturningResult(script);
    } catch (_) {
      // Keep the packaged chart if WebView rendering fails.
    }
  }

  Future<void> _applyEfficiencyBindings(int generation) async {
    final bindings = _efficiencyBindings;
    final read = _pageReads.latestRead;
    final context = widget.designContextCoordinator?.context;
    final ticket = _pageTicket;
    if (!_pageReady ||
        !_isCurrentPageLoad('efficiency', generation) ||
        bindings == null ||
        read == null ||
        read.page != 'efficiency' ||
        read.value is! EfficiencyDomainSnapshot ||
        context == null ||
        ticket == null ||
        read.accountId != context.accountId ||
        read.homeId != context.homeId ||
        !context.allowsReadMode(read.mode)) {
      return;
    }
    final script = _bindingRenderer.updateScript(ticket, bindings);
    if (script == null) return;
    try {
      await _controller.runJavaScriptReturningResult(script);
    } catch (_) {
      // Keep the packaged month-to-date fixture when coverage is unavailable.
    }
  }

  Future<void> _applySharedEfficiencyBindings(
    String page,
    int generation,
  ) async {
    final context = widget.designContextCoordinator?.context;
    final ticket = _pageTicket;
    final bindings = _sharedEfficiencyBindings;
    if (!_pageReady ||
        !_isCurrentPageLoad(page, generation) ||
        !_efficiencyPages.contains(page) ||
        page == 'efficiency' ||
        context == null ||
        !identical(context, _sharedEfficiencyContext) ||
        ticket == null ||
        bindings == null) {
      return;
    }
    final script = _bindingRenderer.updateScript(ticket, [
      for (final binding in bindings)
        DesignTextBinding(
          binding.id.replaceFirst('efficiency_text_', '${page}_text_'),
          binding.text,
        ),
    ]);
    if (script == null) return;
    try {
      await _controller.runJavaScriptReturningResult(script);
    } catch (_) {
      // Keep the same packaged summary when a prior overview read is unavailable.
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
        context.mode != DesignContextMode.household ||
        read?.accountId != context.accountId ||
        read?.homeId != context.homeId ||
        projection.homeId != context.homeId ||
        projection.mode != DesignContextMode.household) {
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
        lifecycle?.isVerifiedScope(context.accountId, context.homeId) != true) {
      return;
    }
    try {
      await _controller.runJavaScriptReturningResult(
        _settingsSavedRenderer.appendScript(
          homeId: context.homeId,
          generation: generation,
          appliances: rows,
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
          (decoded['category'] != null && decoded['category'] is! String)) {
        return;
      }
      fields = decoded;
    } catch (_) {
      return;
    }
    const reviewCategories = {
      'computer',
      'lighting',
      'refrigerator',
      'television',
      'washer',
      'dryer',
      'dishwasher',
      'space_heater',
      'air_conditioner',
      'water_heater',
      'other',
    };
    final selectedCategory = fields['category'] as String?;
    if (!fromPhoto &&
        (selectedCategory == null ||
            !reviewCategories.contains(selectedCategory))) {
      return;
    }
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
            initialCategory: reviewCategories.contains(selectedCategory)
                ? selectedCategory
                : null,
          ),
        );
        if (result?.status == LocalWriteStatus.confirmed &&
            _settingsDevicePages.contains(_page)) {
          await _refreshLocalInventory(_page, _pageLoadGeneration);
        }
        return;
      }
      if (context == null || lifecycle == null || !mounted) return;
      final saved = await showDialog<CloudAppliance>(
        context: this.context,
        builder: (_) => DeviceReviewSheet(
          lifecycle: lifecycle,
          accountId: context.accountId,
          homeId: context.homeId,
          homeName: widget.homeName,
          name: fields['name'] as String,
          manufacturer: fields['manufacturer'] as String,
          model: fields['model'] as String,
          initialCategory: reviewCategories.contains(selectedCategory)
              ? selectedCategory
              : null,
        ),
      );
      if (saved != null &&
          saved.homeId == context.homeId &&
          lifecycle.isVerifiedScope(context.accountId, context.homeId)) {
        await _refreshSavedAppliances(_page, _pageLoadGeneration);
      }
    } finally {
      _reviewOpen = false;
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
      photo = source == 'camera'
          ? await widget.photoCapture.capturePhoto()
          : await widget.photoCapture.pickFromGallery();
      if (photo == null ||
          !_isCurrentPageLoad(
            'settings_photo_scan_onboarding',
            pageGeneration,
          ) ||
          (!widget.localPilot &&
              !lifecycle!.isVerifiedScope(
                context!.accountId,
                context.homeId,
              ))) {
        return;
      }
      final text = await widget.photoCapture.extractTextHint(photo.path);
      if (text == null) return;
      if (!_isCurrentPageLoad(
            'settings_photo_scan_onboarding',
            pageGeneration,
          ) ||
          (!widget.localPilot &&
              !lifecycle!.isVerifiedScope(
                context!.accountId,
                context.homeId,
              ))) {
        return;
      }
      await _reviewDevice(
        jsonEncode({
          'name': '',
          'manufacturer': manufacturerHintFromOcr(text) ?? '',
          'model': modelHintFromOcr(text) ?? '',
        }),
        fromPhoto: true,
      );
    } catch (_) {
      // Picker cancellation or unavailable native capture leaves the page as is.
    } finally {
      if (photo != null) await widget.photoCapture.discard(photo);
      _capturingPhoto = false;
    }
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
    } catch (_) {
      // Reconcile an uncertain response against the authoritative inventory.
      try {
        final rows = await lifecycle.refreshSavedAppliances(
          context.accountId,
          context.homeId,
        );
        if (rows != null &&
            !rows.any((item) => item.id == applianceId) &&
            _isCurrentPageLoad(page, generation) &&
            identical(widget.designContextCoordinator?.context, context)) {
          _archiveKeys.remove(applianceId);
          _savedAppliances = rows;
          await _applySavedAppliances(page, generation);
        }
      } catch (_) {
        // Retain the row and retry key when neither write nor read is confirmed.
      }
    } finally {
      _archivingApplianceIds.remove(applianceId);
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
    } finally {
      _deletingLocalIds.remove(id);
    }
  }

  Future<void> _open(String route) async {
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
    if (_page == 'dashboard' && route.startsWith('dashboard_period:')) {
      final granularity = route.substring('dashboard_period:'.length);
      if (const {'day', 'week', 'month'}.contains(granularity)) {
        final read = _pageReads.latestRead;
        if (read?.value is DashboardDomainSnapshot &&
            DashboardChartProjection.fromSnapshot(
                  read!.value as DashboardDomainSnapshot,
                  granularity,
                ) !=
                null) {
          _dashboardGranularity = granularity;
          await _applyDashboardChart(_pageLoadGeneration);
        }
      }
      return;
    }
    if (route == 'sign_out') {
      _navigationEpoch++;
      _pageStates.clear();
      _history.clear();
      _invalidatePageLoad();
      _pageReads.clear();
      _dashboardGranularity = 'day';
      _sharedEfficiencyBindings = null;
      _sharedEfficiencyContext = null;
      _efficiencyDetailsExpanded = false;
      widget.onSignOut?.call();
      return;
    }
    if (route == 'change_home') {
      _navigationEpoch++;
      _pageStates.clear();
      _history.clear();
      _invalidatePageLoad();
      _pageReads.clear();
      _dashboardGranularity = 'day';
      _sharedEfficiencyBindings = null;
      _sharedEfficiencyContext = null;
      _efficiencyDetailsExpanded = false;
      widget.onChangeHome?.call();
      return;
    }
    if (route == 'report_preview') {
      widget.onReportPreview?.call();
      return;
    }
    if (!_pages.contains(route) || route == _page) return;
    await _navigate(route);
  }

  void _back() {
    if (_history.isEmpty) return;
    unawaited(_navigate(null));
  }

  Future<void> _navigate(String? route) async {
    if (_navigating) return;
    _navigating = true;
    final epoch = _navigationEpoch;
    try {
      await _capturePageState();
      if (!mounted || epoch != _navigationEpoch) return;
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
    }
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
