import 'dart:async';

import 'package:energylens_mobile/features/design/design_shell.dart';
import 'package:energylens_mobile/features/identify/photo_capture_service.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:webview_flutter_platform_interface/webview_flutter_platform_interface.dart';

class _WebPlatform extends WebViewPlatform {
  late _WebController controller;

  @override
  PlatformWebViewController createPlatformWebViewController(
    PlatformWebViewControllerCreationParams params,
  ) => controller = _WebController(params);

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
  _WebController(super.params) : super.implementation();
  final Map<String, JavaScriptChannelParams> channels = {};
  _WebNavigation? navigation;
  String? asset;
  final List<String> scripts = [];

  void route(String value) => channels['EnergyLensNavigation']!
      .onMessageReceived(JavaScriptMessage(message: value));
  void capture(String value) => channels['EnergyLensPhotoCapture']!
      .onMessageReceived(JavaScriptMessage(message: value));

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
  Future<void> clearCache() async {}
  @override
  Future<void> loadFlutterAsset(String key) async {
    asset = key;
    navigation?.onFinished?.call('file:///$key');
  }

  @override
  Future<void> runJavaScript(String script) async => scripts.add(script);
  @override
  Future<Object> runJavaScriptReturningResult(String script) async => '{}';
}

class _WebWidget extends PlatformWebViewWidget {
  _WebWidget(super.params) : super.implementation();
  @override
  Widget build(BuildContext context) => const SizedBox.expand();
}

class _Capture extends PhotoCaptureService {
  _Capture();
  CapturedPhoto? photo = CapturedPhoto(path: 'test.jpg', bytes: Uint8List(0));
  Object? captureError;
  Object? ocrError;
  String? text = 'MODEL: ABC123';
  int detectCalls = 0;
  int discardCalls = 0;
  int recoverCalls = 0;
  CapturedPhoto? recovered;
  Object? recoveryError;

  @override
  Future<CapturedPhoto?> capturePhoto() async {
    if (captureError != null) throw captureError!;
    return photo;
  }

  @override
  Future<CapturedPhoto?> pickFromGallery() => capturePhoto();
  @override
  Future<CapturedPhoto?> recoverLostPhoto() async {
    recoverCalls++;
    if (recoveryError != null) throw recoveryError!;
    return recovered;
  }

  @override
  Future<String?> extractTextHint(String path) async {
    if (ocrError != null) throw ocrError!;
    return text;
  }

  @override
  Future<String?> detectUpc(String path) async {
    detectCalls++;
    return '012345678905';
  }

  @override
  Future<void> discard(CapturedPhoto photo) async => discardCalls++;
}

Future<_WebPlatform> _scanPage(WidgetTester tester, _Capture capture) async {
  final platform = _WebPlatform();
  WebViewPlatform.instance = platform;
  await tester.pumpWidget(
    MaterialApp(home: DesignShell(localPilot: true, photoCapture: capture)),
  );
  await tester.pump();
  platform.controller.route('settings_photo_scan_onboarding');
  await tester.pumpAndSettle();
  return platform;
}

void main() {
  testWidgets('capture distinguishes empty OCR from OCR failure', (
    tester,
  ) async {
    final capture = _Capture()..text = null;
    final platform = await _scanPage(tester, capture);
    platform.controller.capture('camera');
    await tester.pumpAndSettle();
    expect(
      find.text('No label text found. Try again or enter the model yourself.'),
      findsOneWidget,
    );
    expect(capture.detectCalls, 1);
    expect(capture.discardCalls, 1);
    ScaffoldMessenger.of(tester.element(find.byType(DesignShell)))
        .removeCurrentSnackBar();
    await tester.pumpAndSettle();

    capture.ocrError = StateError('ocr failed');
    platform.controller.capture('camera');
    await tester.pumpAndSettle();
    expect(
      find.text(
        'Could not read this photo. Try again or enter the model yourself.',
      ),
      findsOneWidget,
    );
    expect(capture.detectCalls, 2);
    expect(capture.discardCalls, 2);
  });

  testWidgets('scan publishes the five extracted field states', (tester) async {
    final capture = _Capture()
      ..text = 'SAMSUNG\nMODEL: RF28R7351SR/AA\nSERIAL: K12345678\n'
          'FCC ID: A3LWRF555\nIC: 649E-WRF555';
    final platform = await _scanPage(tester, capture);
    platform.controller.capture('camera');
    await tester.pumpAndSettle();
    final scripts = platform.controller.scripts
        .where((script) => script.contains('EnergyLensPhotoScanResults'))
        .toList();
    expect(scripts.first, contains('?.clear()'));
    expect(
      scripts.last,
      contains('"model":true,"brand":true,"serial":true,'
          '"fccId":true,"icId":true'),
    );
    expect(capture.discardCalls, 1);
  });

  testWidgets(
    'capture outcomes have approved messages and cancellation is silent',
    (tester) async {
      final capture = _Capture();
      final platform = await _scanPage(tester, capture);
      final cases = <(Object, String)>[
        (
          const FormatException(),
          'This photo is over 5 MB. Take it again or choose a smaller one.',
        ),
        (
          const PhotoLibraryPermissionDeniedException(),
          'Photo access was denied. Allow it in settings or use the camera.',
        ),
        (
          const CameraPermissionDeniedException(),
          'Camera access was denied. Allow it in settings or choose a photo.',
        ),
        (
          PlatformException(code: 'unavailable'),
          'Camera is not available. Choose a photo instead.',
        ),
        (
          StateError('unexpected'),
          'Something went wrong with the photo. Try again.',
        ),
      ];
      for (final (error, message) in cases) {
        capture.captureError = error;
        platform.controller.capture('camera');
        await tester.pumpAndSettle();
        expect(find.text(message), findsOneWidget);
        ScaffoldMessenger.of(tester.element(find.byType(DesignShell)))
            .removeCurrentSnackBar();
        await tester.pumpAndSettle();
      }
      capture.captureError = null;
      capture.photo = null;
      platform.controller.capture('camera');
      await tester.pumpAndSettle();
      expect(find.byType(SnackBar), findsNothing);
    },
  );

  testWidgets('Android recovery navigates and scans through the same path', (
    tester,
  ) async {
    final capture = _Capture()
      ..recovered = CapturedPhoto(path: 'recovered.jpg', bytes: Uint8List(0))
      ..text = null;
    final platform = _WebPlatform();
    WebViewPlatform.instance = platform;
    await tester.pumpWidget(
      MaterialApp(
        home: DesignShell(
          localPilot: true,
          photoCapture: capture,
          recoverLostPhotoOnStart: true,
        ),
      ),
    );
    await tester.runAsync(
      () => Future<void>.delayed(const Duration(milliseconds: 30)),
    );
    await tester.pump();
    expect(
      find.text('Your last photo was recovered. Reading it now.'),
      findsOneWidget,
    );
    expect(
      platform.controller.asset,
      'assets/design_pages/settings_photo_scan_onboarding/app.html',
    );
    expect(capture.recoverCalls, 1);
    expect(capture.detectCalls, 1);
    expect(capture.discardCalls, 1);
  });

  testWidgets('lost Android photo reports the approved recovery error', (
    tester,
  ) async {
    final capture = _Capture()..recoveryError = const PhotoRecoveryException();
    final platform = _WebPlatform();
    WebViewPlatform.instance = platform;
    await tester.pumpWidget(
      MaterialApp(
        home: DesignShell(
          localPilot: true,
          photoCapture: capture,
          recoverLostPhotoOnStart: true,
        ),
      ),
    );
    await tester.runAsync(
      () => Future<void>.delayed(const Duration(milliseconds: 30)),
    );
    await tester.pump();
    expect(
      platform.controller.asset,
      'assets/design_pages/settings_photo_scan_onboarding/app.html',
    );
    expect(
      find.text('The photo was lost while the camera was open. Take it again.'),
      findsOneWidget,
    );
    expect(capture.discardCalls, 0);
  });
}
