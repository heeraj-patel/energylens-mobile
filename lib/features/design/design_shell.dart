import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:webview_flutter/webview_flutter.dart';

import 'design_context_coordinator.dart';
import 'design_numeric_bindings.dart';
import 'design_page_read_dispatcher.dart';
import 'design_page_bridge.dart';
import 'live_devices_card_renderer.dart';
import 'live_devices_projection.dart';

/// The approved design files are complete mobile pages. Keep their markup and
/// wording in assets/design_pages; this shell only supplies native navigation.
class DesignShell extends StatefulWidget {
  const DesignShell({
    super.key,
    this.onSignOut,
    this.onChangeHome,
    this.onReportPreview,
    this.designContextCoordinator,
    this.designTour = false,
    this.homeName = 'The Miller Home',
  });

  final VoidCallback? onSignOut;
  final VoidCallback? onChangeHome;
  final VoidCallback? onReportPreview;

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
  final DesignPageRequestGate _bindingGate = DesignPageRequestGate();
  late final DesignTextBindingRenderer _bindingRenderer =
      DesignTextBindingRenderer(_bindingGate);
  int _pageLoadGeneration = 0;
  bool _pageReady = false;
  LiveDevicesProjection? _devicesProjection;
  DesignNumericBindings? _dashboardBindings;
  DesignPageTicket? _dashboardTicket;
  Timer? _tourTimer;
  int _tourIndex = 0;
  final List<String> _history = [];
  String _page = 'dashboard';

  @override
  void initState() {
    super.initState();
    _pageReads = DesignPageReadDispatcher(widget.designContextCoordinator);
    _controller = WebViewController()
      ..setJavaScriptMode(JavaScriptMode.unrestricted)
      ..setBackgroundColor(const Color(0xFFF9F9FF))
      ..addJavaScriptChannel(
        'EnergyLensNavigation',
        onMessageReceived: (message) => _open(message.message),
      )
      ..setNavigationDelegate(
        NavigationDelegate(
          onPageFinished: (url) {
            _installNavigation();
            _scheduleTourAdvance();
            unawaited(_onPageFinished(url));
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
    )) {
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
    _invalidatePageLoad();
    final page = _page;
    final generation = _pageLoadGeneration;
    unawaited(_readPage(page, generation));
    // app.html is a self-contained copy of the approved HTML. The source
    // code.html and screen.png remain byte-for-byte references alongside it.
    await _controller.loadFlutterAsset('assets/design_pages/$page/app.html');
  }

  void _invalidatePageLoad() {
    _pageLoadGeneration++;
    _pageReady = false;
    _devicesProjection = null;
    _dashboardBindings = null;
    _dashboardTicket = null;
    _bindingGate.clear();
  }

  bool _isCurrentPageLoad(String page, int generation) =>
      mounted && _page == page && _pageLoadGeneration == generation;

  Future<void> _readPage(String page, int generation) async {
    await _pageReads.load(page);
    if (!_isCurrentPageLoad(page, generation)) return;
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
    if (page == 'dashboard') {
      final context = widget.designContextCoordinator?.context;
      if (context == null) return;
      final ticket = _bindingGate.select(context.homeId, page);
      _dashboardTicket = ticket;
      try {
        final installed = await _controller.runJavaScriptReturningResult(
          _bindingRenderer.installationScript(ticket)!,
        );
        if (installed != true ||
            !_isCurrentPageLoad(page, generation) ||
            !identical(widget.designContextCoordinator?.context, context) ||
            !identical(_dashboardTicket, ticket)) {
          return;
        }
        await _applyDashboardHomeName(generation, ticket);
        await _applyDashboardBindings(generation);
      } catch (_) {
        // A WebView failure leaves the packaged values intact.
      }
      return;
    }
    if (page != 'devices') return;
    final context = widget.designContextCoordinator?.context;
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

  Future<void> _applyDashboardHomeName(
    int generation,
    DesignPageTicket ticket,
  ) async {
    final context = widget.designContextCoordinator?.context;
    if (!_isCurrentPageLoad('dashboard', generation) ||
        !identical(_dashboardTicket, ticket) ||
        context?.homeId != ticket.homeId) {
      return;
    }
    final script = _bindingRenderer.updateScript(ticket, [
      DesignTextBinding('dashboard_text_001', widget.homeName),
    ]);
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
    final ticket = _dashboardTicket;
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

  void _open(String route) {
    if (route == 'sign_out') {
      _invalidatePageLoad();
      _pageReads.clear();
      widget.onSignOut?.call();
      return;
    }
    if (route == 'change_home') {
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
    setState(() {
      _history.add(_page);
      _page = route;
    });
    _loadPage();
  }

  void _back() {
    if (_history.isEmpty) return;
    setState(() => _page = _history.removeLast());
    _loadPage();
  }

  Future<void> _installNavigation() async {
    final currentPage = jsonEncode(_page);
    await _controller.runJavaScript('''
      (() => {
        const page = $currentPage;
        const send = (route) => EnergyLensNavigation.postMessage(route);
        const textOf = (element) => {
          const clone = element.cloneNode(true);
          clone.querySelectorAll('.material-symbols-outlined').forEach((node) => node.remove());
          return clone.textContent.replace(/\\s+/g, ' ').trim();
        };
        document.addEventListener('click', (event) => {
          const link = event.target.closest('a[data-path]');
          if (link) {
            const label = textOf(link);
            const route = label.includes('Manage Devices')
              ? 'settings_manage_devices'
              : ({'perks-and-tips': 'perks_tips'}[link.dataset.path] || link.dataset.path);
            event.preventDefault();
            event.stopImmediatePropagation();
            send(route);
            return;
          }
          const button = event.target.closest('button');
          if (!button) return;
          const label = textOf(button);
          let route = button.dataset.elRoute;
          if (button.id === 'email-btn') route = 'report_preview';
          else if (route !== 'change_home' && page.startsWith('efficiency')) {
            if (label === 'Night') route = 'efficiency';
            else if (label === 'Away') route = 'efficiency_away';
            else if (label === 'Peak Rates') route = 'efficiency_peak_rates';
            else if (label === 'Habits') route = 'efficiency_habits';
          } else if (page === 'perks_tips' || page.startsWith('tips_')) {
            if (label === 'Programs') route = 'perks_tips';
            else if (label === 'Efficiency') route = 'tips_efficiency';
            else if (label === 'Care & Upgrades') route = 'tips_care_upgrades';
            else if (label === 'Knowledge') route = 'tips_knowledge';
          } else if (page.startsWith('settings')) {
            if (label === 'Profile & Reports') route = 'settings';
            else if (label === 'Manage Devices') route = 'settings_manage_devices';
            else if (label.startsWith('Auto Scan')) route = 'settings_manage_devices';
            else if (label.startsWith('Photo Scan') || label.startsWith('Snap Photo')) route = 'settings_photo_scan_onboarding';
            else if (label.startsWith('Manual Form') || label.startsWith('Type In Manual')) route = 'settings_manual_device_entry';
            else if (label === 'Sign Out') route = 'sign_out';
          }
          if (route) {
            event.preventDefault();
            event.stopImmediatePropagation();
            send(route);
          }
        }, true);
      })();
    ''');
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
