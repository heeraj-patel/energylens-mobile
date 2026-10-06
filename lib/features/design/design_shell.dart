import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:webview_flutter/webview_flutter.dart';

/// The approved design files are complete mobile pages. Keep their markup and
/// wording in assets/design_pages; this shell only supplies native navigation.
class DesignShell extends StatefulWidget {
  const DesignShell({
    super.key,
    this.onSignOut,
    this.onChangeHome,
    this.onReportPreview,
    this.designTour = false,
  });

  final VoidCallback? onSignOut;
  final VoidCallback? onChangeHome;
  final VoidCallback? onReportPreview;
  final bool designTour;

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
  Timer? _tourTimer;
  int _tourIndex = 0;
  final List<String> _history = [];
  String _page = 'dashboard';

  @override
  void initState() {
    super.initState();
    _controller = WebViewController()
      ..setJavaScriptMode(JavaScriptMode.unrestricted)
      ..setBackgroundColor(const Color(0xFFF9F9FF))
      ..addJavaScriptChannel(
        'EnergyLensNavigation',
        onMessageReceived: (message) => _open(message.message),
      )
      ..setNavigationDelegate(
        NavigationDelegate(
          onPageFinished: (_) => _installNavigation(),
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
    _loadPage();
    if (widget.designTour) {
      _tourTimer = Timer.periodic(const Duration(seconds: 8), (timer) {
        if (_tourIndex + 1 >= _tourOrder.length) {
          timer.cancel();
          return;
        }
        _tourIndex++;
        setState(() => _page = _tourOrder[_tourIndex]);
        _loadPage();
      });
    }
  }

  @override
  void dispose() {
    _tourTimer?.cancel();
    super.dispose();
  }

  Future<void> _loadPage() async {
    // app.html is a self-contained copy of the approved HTML. The source
    // code.html and screen.png remain byte-for-byte references alongside it.
    await _controller.loadFlutterAsset('assets/design_pages/$_page/app.html');
  }

  void _open(String route) {
    if (route == 'sign_out') {
      widget.onSignOut?.call();
      return;
    }
    if (route == 'change_home') {
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
          let route;
          if (button.id === 'email-btn') route = 'report_preview';
          if (label.startsWith('The Miller Home')) route = 'change_home';
          else if (page.startsWith('efficiency')) {
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
