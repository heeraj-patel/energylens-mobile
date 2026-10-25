import 'dart:async';

import 'package:energylens_mobile/features/design/design_shell.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:webview_flutter_platform_interface/webview_flutter_platform_interface.dart';

class _WebPlatform extends WebViewPlatform {
  final controllers = <_WebController>[];

  @override
  PlatformWebViewController createPlatformWebViewController(
    PlatformWebViewControllerCreationParams params,
  ) {
    final controller = _WebController(params, controllers.length);
    controllers.add(controller);
    return controller;
  }

  @override
  PlatformNavigationDelegate createPlatformNavigationDelegate(
    PlatformNavigationDelegateCreationParams params,
  ) => _WebNavigation(params);

  @override
  PlatformWebViewWidget createPlatformWebViewWidget(
    PlatformWebViewWidgetCreationParams params,
  ) => _WebWidget(params);
}

class _WebNavigation extends PlatformNavigationDelegate {
  _WebNavigation(super.params) : super.implementation();

  void Function(String)? onFinished;

  @override
  Future<void> setOnPageFinished(void Function(String) callback) async {
    onFinished = callback;
  }

  @override
  Future<void> setOnNavigationRequest(
    FutureOr<NavigationDecision> Function(NavigationRequest) callback,
  ) async {}
}

class _WebController extends PlatformWebViewController {
  _WebController(super.params, this.id) : super.implementation();

  final int id;
  final channels = <String, JavaScriptChannelParams>{};
  _WebNavigation? navigation;
  String? asset;

  void route(String value) => channels['EnergyLensNavigation']!
      .onMessageReceived(JavaScriptMessage(message: value));

  void finish() => navigation?.onFinished?.call('file:///$asset');

  @override
  Future<void> setJavaScriptMode(JavaScriptMode mode) async {}

  @override
  Future<void> setBackgroundColor(Color color) async {}

  @override
  Future<void> addJavaScriptChannel(JavaScriptChannelParams params) async {
    channels[params.name] = params;
  }

  @override
  Future<void> setPlatformNavigationDelegate(
    PlatformNavigationDelegate handler,
  ) async => navigation = handler as _WebNavigation;

  @override
  Future<void> loadFlutterAsset(String key) async => asset = key;

  @override
  Future<void> runJavaScript(String script) async {}

  @override
  Future<Object> runJavaScriptReturningResult(String script) async => '{}';
}

class _WebWidget extends PlatformWebViewWidget {
  _WebWidget(super.params) : super.implementation();

  @override
  Widget build(BuildContext context) => const SizedBox.expand();
}

double _trackOffset(WidgetTester tester) => tester
    .widget<Transform>(find.byKey(const ValueKey('design-page-track')))
    .transform
    .getTranslation()
    .x;

void main() {
  testWidgets('keeps the current page visible until the next page is ready', (
    tester,
  ) async {
    final platform = _WebPlatform();
    WebViewPlatform.instance = platform;

    await tester.pumpWidget(
      const MaterialApp(home: DesignShell(recoverLostPhotoOnStart: false)),
    );
    await tester.pumpAndSettle();
    expect(platform.controllers, hasLength(2));
    expect(platform.controllers[0].asset, endsWith('/dashboard/app.html'));

    platform.controllers[0].finish();
    await tester.pumpAndSettle();
    expect(_trackOffset(tester), 0);

    platform.controllers[0].route('devices');
    await tester.pumpAndSettle();
    expect(platform.controllers[1].asset, endsWith('/devices/app.html'));
    expect(_trackOffset(tester), 0);

    platform.controllers[1].finish();
    await tester.pump(const Duration(milliseconds: 200));
    await tester.pumpAndSettle();
    expect(_trackOffset(tester), lessThan(0));
  });
}
