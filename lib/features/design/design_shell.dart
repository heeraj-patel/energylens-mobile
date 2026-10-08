import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:webview_flutter/webview_flutter.dart';

import '../../core/cloud_api/cloud_appliance.dart';
import '../../core/cloud_auth/cloud_auxiliary_domain_lifecycle.dart';
import '../identify/appliance_onboarding_screen.dart'
    show manufacturerHintFromOcr, modelHintFromOcr;
import '../identify/photo_capture_service.dart';
import 'device_review_sheet.dart';
import 'design_context_coordinator.dart';
import 'design_numeric_bindings.dart';
import 'design_navigation_script.dart';
import 'design_page_read_dispatcher.dart';
import 'design_page_bridge.dart';
import 'design_page_state_script.dart';
import 'design_page_state_snapshot.dart';
import 'live_devices_card_renderer.dart';
import 'live_devices_projection.dart';
import 'knowledge_page_script.dart';
import 'settings_saved_devices_renderer.dart';

/// The approved design files are complete mobile pages. Keep their markup and
/// wording in assets/design_pages; this shell only supplies native navigation.
class DesignShell extends StatefulWidget {
  const DesignShell({
    super.key,
    this.onSignOut,
    this.onChangeHome,
    this.onReportPreview,
    this.onboardingLifecycle,
    this.photoCapture = const PhotoCaptureService(),
    this.designContextCoordinator,
    this.designTour = false,
    this.homeName = 'The Miller Home',
  });

  final VoidCallback? onSignOut;
  final VoidCallback? onChangeHome;
  final VoidCallback? onReportPreview;
  final CloudAuxiliaryDomainLifecycle? onboardingLifecycle;
  final PhotoCaptureService photoCapture;

  /// Native-only verified scope. It is never passed into the WebView.
  final DesignContextCoordinator? designContextCoordinator;
  final bool designTour;
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
  static const _settingsDevicePages = <String>{
    'settings_manage_devices',
    'settings_manual_device_entry',
    'settings_photo_scan_onboarding',
  };
  final DesignPageRequestGate _bindingGate = DesignPageRequestGate();
  final DesignPageStateSnapshotStore _pageStates =
      DesignPageStateSnapshotStore();
  late final DesignTextBindingRenderer _bindingRenderer =
      DesignTextBindingRenderer(_bindingGate);
  int _pageLoadGeneration = 0;
  bool _pageReady = false;
  LiveDevicesProjection? _devicesProjection;
  List<CloudAppliance>? _savedAppliances;
  DesignNumericBindings? _dashboardBindings;
  DesignPageTicket? _pageTicket;
  Timer? _tourTimer;
  int _tourIndex = 0;
  final List<String> _history = [];
  String _page = 'dashboard';
  bool _reviewOpen = false;
  bool _capturingPhoto = false;
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
      ..setNavigationDelegate(
        NavigationDelegate(
          onPageFinished: (url) {
            _installNavigation();
            _scheduleTourAdvance();
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
    _dashboardBindings = null;
    _pageTicket = null;
    _bindingGate.clear();
  }

  bool _isCurrentPageLoad(String page, int generation) =>
      mounted && _page == page && _pageLoadGeneration == generation;

  Future<void> _readPage(String page, int generation) async {
    await _pageReads.load(page);
    if (!_isCurrentPageLoad(page, generation)) return;
    if (_settingsDevicePages.contains(page)) {
      await _refreshSavedAppliances(page, generation);
      return;
    }
    final read = _pageReads.latestRead;
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
      } catch (_) {
        // Packaged numeric values remain visible when live values are invalid.
      }
      return;
    }
    if (page != 'devices') return;
    if (read == null || read.mode != DesignContextMode.household) return;
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
      } catch (_) {
        // The packaged home name remains visible on script failure.
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
      return;
    }
    if (_settingsDevicePages.contains(page)) {
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

  Future<void> _applyDashboardBindings(int generation) async {
    final projection = _dashboardBindings;
    final read = _pageReads.latestRead;
    final context = widget.designContextCoordinator?.context;
    final ticket = _pageTicket;
    if (!_pageReady ||
        !_isCurrentPageLoad('dashboard', generation) ||
        projection == null ||
        read?.page != 'dashboard' ||
        context == null ||
        ticket == null ||
        read?.accountId != context.accountId ||
        read?.homeId != context.homeId ||
        read?.mode != context.mode) {
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
    if (context == null ||
        context.mode != DesignContextMode.household ||
        lifecycle == null ||
        !lifecycle.isVerifiedScope(context.accountId, context.homeId)) {
      return;
    }
    final Map<String, dynamic> fields;
    try {
      final decoded = jsonDecode(raw);
      if (decoded is! Map<String, dynamic> ||
          decoded['name'] is! String ||
          decoded['manufacturer'] is! String ||
          decoded['model'] is! String) {
        return;
      }
      fields = decoded;
    } catch (_) {
      return;
    }
    _reviewOpen = true;
    try {
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
    if (context == null ||
        context.mode != DesignContextMode.household ||
        lifecycle == null ||
        !lifecycle.isVerifiedScope(context.accountId, context.homeId)) {
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
          !lifecycle.isVerifiedScope(context.accountId, context.homeId)) {
        return;
      }
      final text = await widget.photoCapture.extractTextHint(photo.path);
      if (!_isCurrentPageLoad(
            'settings_photo_scan_onboarding',
            pageGeneration,
          ) ||
          !lifecycle.isVerifiedScope(context.accountId, context.homeId)) {
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

  Future<void> _open(String route) async {
    if (route == 'sign_out') {
      _navigationEpoch++;
      _pageStates.clear();
      _history.clear();
      _invalidatePageLoad();
      _pageReads.clear();
      widget.onSignOut?.call();
      return;
    }
    if (route == 'change_home') {
      _navigationEpoch++;
      _pageStates.clear();
      _history.clear();
      _invalidatePageLoad();
      _pageReads.clear();
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
