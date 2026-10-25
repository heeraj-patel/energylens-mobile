import 'dart:async';
import 'dart:io';

import 'package:energylens_mobile/core/backend_error.dart';
import 'package:energylens_mobile/core/cloud_api/cloud_api_client.dart';
import 'package:energylens_mobile/features/design/dashboard_domain_repository.dart';
import 'package:energylens_mobile/features/design/design_context_coordinator.dart';
import 'package:energylens_mobile/features/design/design_shell.dart';
import 'package:energylens_mobile/features/design/efficiency_domain_repository.dart';
import 'package:energylens_mobile/features/discovery/discovery_api.dart';
import 'package:flutter/foundation.dart' as foundation;
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:webview_flutter_platform_interface/webview_flutter_platform_interface.dart';

const _home = '11111111-1111-4111-8111-111111111111';

class _FailingAdapters implements DesignContextAdapters {
  _FailingAdapters(this.error);
  final Object error;
  @override
  void clear() {}
  @override
  Future<DashboardDomainSnapshot?> dashboard(String homeId) async => null;
  @override
  Future<EfficiencyDomainSnapshot?> efficiency(
    String homeId,
    EfficiencyPage page,
  ) async => throw error;
  @override
  dynamic noSuchMethod(Invocation invocation) => null;
}

class _WebPlatform extends WebViewPlatform {
  late _WebController controller;
  @override
  PlatformWebViewController createPlatformWebViewController(
    PlatformWebViewControllerCreationParams params,
  ) {
    final created = _WebController(params);
    created.onLoad = () => controller = created;
    return controller = created;
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
  Future<void> setOnPageFinished(void Function(String) callback) async =>
      onFinished = callback;
  @override
  Future<void> setOnNavigationRequest(
    FutureOr<NavigationDecision> Function(NavigationRequest) callback,
  ) async {}
}

class _WebController extends PlatformWebViewController {
  _WebController(super.params) : super.implementation();
  VoidCallback? onLoad;
  final channels = <String, JavaScriptChannelParams>{};
  _WebNavigation? navigation;
  @override
  Future<void> setJavaScriptMode(JavaScriptMode mode) async {}
  @override
  Future<void> setBackgroundColor(Color color) async {}
  @override
  Future<void> addJavaScriptChannel(JavaScriptChannelParams params) async =>
      channels[params.name] = params;
  @override
  Future<void> setPlatformNavigationDelegate(
    PlatformNavigationDelegate handler,
  ) async => navigation = handler as _WebNavigation;
  @override
  Future<void> loadFlutterAsset(String key) async {
    onLoad?.call();
    navigation?.onFinished?.call('file:///$key');
  }

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

Future<void> _open(WidgetTester tester, Object error) async {
  WebViewPlatform.instance = _WebPlatform();
  final coordinator = DesignContextCoordinator(_FailingAdapters(error));
  coordinator.useVerifiedContext(
    VerifiedDesignContext(
      accountId: 'probe',
      homeId: _home,
      mode: DesignContextMode.sample,
    ),
  );
  await tester.pumpWidget(
    MaterialApp(home: DesignShell(designContextCoordinator: coordinator)),
  );
  await tester.pumpAndSettle();
  (WebViewPlatform.instance! as _WebPlatform)
      .controller
      .channels['EnergyLensNavigation']!
      .onMessageReceived(const JavaScriptMessage(message: 'efficiency'));
  await tester.pumpAndSettle();
}

void main() {
  for (final error in <Object>[
    const CloudApiException(500, 'http_500'),
    const CloudApiException(503, 'http_503'),
    const SocketException('offline'),
    TimeoutException('slow'),
    const FormatException('bad json'),
  ]) {
    testWidgets('page read ${error.runtimeType} shows the internal error', (
      tester,
    ) async {
      await _open(tester, error);
      expect(find.text(internalErrorMessage), findsOneWidget);
    });
  }

  testWidgets('debug diagnostic contains only type, status and path', (
    tester,
  ) async {
    final lines = <String>[];
    final previous = foundation.debugPrint;
    foundation.debugPrint = (message, {wrapWidth}) {
      if (message != null) lines.add(message);
    };
    try {
      await _open(
        tester,
        const CloudApiException(
          503,
          'secret-error-code',
          path: '/v1/homes/owner/dashboard?token=private-token',
        ),
      );
      expect(find.text(internalErrorMessage), findsOneWidget);
      expect(lines.where((line) => line.startsWith('ELR-064 ')), [
        'ELR-064 type=CloudApiException status=503 path=/v1/homes/owner/dashboard',
      ]);
      expect(lines.join(), isNot(contains('secret-error-code')));
      expect(lines.join(), isNot(contains('private-token')));
    } finally {
      foundation.debugPrint = previous;
    }
  });

  for (final (error, expected) in [
    (
      const CloudApiException(503, 'private-code'),
      'ELR-064 type=CloudApiException status=503 path=unavailable',
    ),
    (
      HubRequestException(502, 'private-code', 'private-message'),
      'ELR-064 type=HubRequestException status=502 path=unavailable',
    ),
  ]) {
    testWidgets('debug diagnostic retains ${error.runtimeType} status', (
      tester,
    ) async {
      final lines = <String>[];
      final previous = foundation.debugPrint;
      foundation.debugPrint = (message, {wrapWidth}) {
        if (message != null) lines.add(message);
      };
      try {
        await _open(tester, error);
        expect(find.text(internalErrorMessage), findsOneWidget);
        expect(lines.where((line) => line.startsWith('ELR-064 ')), [expected]);
        expect(lines.join(), isNot(contains('private-code')));
        expect(lines.join(), isNot(contains('private-message')));
      } finally {
        foundation.debugPrint = previous;
      }
    });
  }

  for (final error in <Object>[
    const CloudApiException(401, 'not_authenticated'),
    const CloudApiException(403, 'forbidden'),
  ]) {
    testWidgets(
      'page read rejected with ${(error as CloudApiException).statusCode} '
      'leaves sign-out to the gate',
      (tester) async {
        await _open(tester, error);
        expect(find.text(internalErrorMessage), findsNothing);
      },
    );
  }
}
