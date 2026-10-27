import 'dart:async';
import 'dart:convert';

import 'package:energylens_mobile/core/cloud_api/cloud_api_client.dart';
import 'package:energylens_mobile/core/cloud_api/cloud_appliance.dart';
import 'package:energylens_mobile/core/cloud_api/cloud_home.dart';
import 'package:energylens_mobile/core/cloud_api/cloud_preferences.dart';
import 'package:energylens_mobile/core/cloud_auth/cloud_auth.dart';
import 'package:energylens_mobile/core/cloud_auth/cloud_auxiliary_domain_lifecycle.dart';
import 'package:energylens_mobile/features/design/demo_report_preview_screen.dart';
import 'package:energylens_mobile/features/design/design_context_coordinator.dart';
import 'package:energylens_mobile/features/design/design_shell.dart';
import 'package:energylens_mobile/features/design/settings_domain_repository.dart';
import 'package:energylens_mobile/features/energy/cloud_report_preview_screen.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:webview_flutter_platform_interface/webview_flutter_platform_interface.dart';

const _homeId = '11111111-1111-4111-8111-111111111111';
const _accountId = '22222222-2222-4222-8222-222222222222';

class _VerifiedInventory implements CloudAuxiliaryDomainLifecycle {
  int refreshes = 0;

  @override
  bool isVerifiedScope(String accountId, String homeId) =>
      accountId == _accountId && homeId == _homeId;

  @override
  Future<List<CloudAppliance>?> refreshSavedAppliances(
    String accountId,
    String homeId,
  ) async {
    if (!isVerifiedScope(accountId, homeId)) return null;
    refreshes++;
    return const [];
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _Store implements CloudTokenStore {
  @override
  Future<void> clear() async {}
  @override
  Future<CloudTokens?> read() async =>
      const CloudTokens(accessToken: 'owner-token');
  @override
  Future<void> save(CloudTokens value) async {}
}

class _Auth implements CloudAuthenticator {
  @override
  Future<CloudTokens> signIn(CloudAuthConfig config) async =>
      const CloudTokens(accessToken: 'owner-token');
  @override
  Future<CloudTokens> refresh(
    CloudAuthConfig config,
    String refreshToken,
  ) async => const CloudTokens(accessToken: 'owner-token');
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

  VoidCallback? onLoad;
  final Map<String, JavaScriptChannelParams> channels = {};
  final List<String> scripts = [];
  String? asset;
  int cacheClears = 0;
  _WebNavigation? navigation;

  void route(String value) => channels['EnergyLensNavigation']!
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
  ) async {
    navigation = handler as _WebNavigation;
  }

  @override
  Future<void> clearCache() async {
    cacheClears++;
  }

  @override
  Future<void> loadFlutterAsset(String key) async {
    onLoad?.call();
    expectSync(
      cacheClears,
      0,
      reason: 'Packaged pages load without clearing the WebView cache',
    );
    asset = key;
    navigation?.onFinished?.call('file:///$key');
  }

  @override
  Future<void> runJavaScript(String script) async {
    scripts.add(script);
  }

  @override
  Future<Object> runJavaScriptReturningResult(String script) async {
    scripts.add(script);
    if (script.contains(
      "const first = document.querySelector('[data-el-bind]')",
    )) {
      return true;
    }
    return '{}';
  }
}

class _WebWidget extends PlatformWebViewWidget {
  _WebWidget(super.params) : super.implementation();

  @override
  Widget build(BuildContext context) => const SizedBox.expand();
}

class _Adapters implements DesignContextAdapters {
  _Adapters(this.home);
  CloudHome home;

  @override
  void clear() {}

  @override
  Future<SettingsDomainSnapshot?> settings(String homeId) async {
    if (homeId != home.id) return null;
    return SettingsDomainSnapshot(
      account: const CloudAccount(
        id: 'owner',
        email: 'owner@example.com',
        emailVerified: true,
      ),
      homes: [home],
      accountPreferences: const CloudAccountPreferences(
        version: 1,
        emailReportsEnabled: false,
      ),
      accountPreferencesEtag: '"1"',
      home: home,
      homeEtag: '"1"',
      homePreferences: const CloudHomePreferences(
        version: 1,
        goal: 'unspecified',
        comfortPriority: 'unknown',
      ),
      homePreferencesEtag: '"1"',
      appliances: const [],
    );
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

void main() {
  testWidgets('a tapped Devices card opens its appliance detail screen', (
    tester,
  ) async {
    final platform = _WebPlatform();
    WebViewPlatform.instance = platform;
    const home = CloudHome(
      id: _homeId,
      name: 'Selected Home',
      timezone: 'America/Chicago',
      countryCode: 'US',
      postalCode: '60601',
      version: 1,
      etag: '"1"',
    );
    final coordinator = DesignContextCoordinator(_Adapters(home));
    coordinator.useVerifiedContext(
      VerifiedDesignContext(
        accountId: 'owner',
        homeId: _homeId,
        mode: DesignContextMode.household,
      ),
    );
    final paths = <String>[];
    final api = CloudApiClient(
      session: CloudSession(
        config: const CloudAuthConfig(
          issuer: 'https://issuer.example',
          audience: 'energylens-cloud',
          clientId: 'client',
          redirectUrl: 'io.energylens.app://login-callback',
          apiUrl: 'https://api.example',
        ),
        store: _Store(),
        authenticator: _Auth(),
      ),
      client: MockClient((request) async {
        paths.add(request.url.path);
        if (request.url.path.endsWith('/questions')) {
          return http.Response(jsonEncode({'questions': []}), 200);
        }
        if (request.url.path.endsWith('/questions/answers')) {
          return http.Response(jsonEncode({'answers': []}), 200);
        }
        return http.Response('{}', 500);
      }),
    );
    await tester.pumpWidget(
      MaterialApp(
        home: DesignShell(
          settingsApi: api,
          designContextCoordinator: coordinator,
        ),
      ),
    );
    await tester.pump();
    platform.controller.route('devices');
    await tester.pumpAndSettle();
    platform.controller.route('device_detail:not-an-id:Washer');
    await tester.pumpAndSettle();
    expect(find.text('Refresh estimate'), findsNothing);
    platform.controller.route(
      'device_detail:22222222-2222-4222-8222-222222222222:Washer: big',
    );
    await tester.pumpAndSettle();
    expect(find.text('Washer: big'), findsOneWidget);
    expect(find.text('Refresh estimate'), findsOneWidget);
    expect(paths, contains('/v1/homes/$_homeId/questions'));
  });

  testWidgets('all Settings equipment methods open discovery', (
    tester,
  ) async {
    final platform = _WebPlatform();
    WebViewPlatform.instance = platform;
    var discoveryOpens = 0;
    await tester.pumpWidget(
      MaterialApp(
        home: DesignShell(
          localPilot: true,
          onDiscoverDevices: () async => discoveryOpens++,
        ),
      ),
    );
    await tester.pump();
    platform.controller.route('settings');
    await tester.pumpAndSettle();
    for (final page in [
      'settings_manage_devices',
      'settings_manual_device_entry',
      'settings_photo_scan_onboarding',
    ]) {
      platform.controller.route(page);
      await tester.pumpAndSettle();
      expect(platform.controller.asset, 'assets/design_pages/$page/app.html');
      platform.controller.route('discover_devices');
      await tester.pumpAndSettle();
    }
    expect(discoveryOpens, 3);
  });

  testWidgets('Dashboard Add device opens discovery directly', (tester) async {
    final platform = _WebPlatform();
    WebViewPlatform.instance = platform;
    var addOpens = 0;
    var settingsOpens = 0;
    await tester.pumpWidget(
      MaterialApp(
        home: DesignShell(
          localPilot: true,
          onAddDevice: () async => addOpens++,
          onDiscoverDevices: () async => settingsOpens++,
        ),
      ),
    );
    await tester.pumpAndSettle();
    platform.controller.route('discover_devices');
    await tester.pumpAndSettle();
    expect(addOpens, 1);
    expect(settingsOpens, 0);
  });

  testWidgets(
    'Cloud discovery return refreshes inventory and first-device status',
    (tester) async {
      final platform = _WebPlatform();
      WebViewPlatform.instance = platform;
      const home = CloudHome(
        id: _homeId,
        name: 'Selected Home',
        timezone: 'America/Chicago',
        countryCode: 'US',
        postalCode: '60601',
      );
      final coordinator = DesignContextCoordinator(_Adapters(home));
      coordinator.useVerifiedContext(
        VerifiedDesignContext(
          accountId: _accountId,
          homeId: _homeId,
          mode: DesignContextMode.household,
        ),
      );
      final inventory = _VerifiedInventory();
      var homeReads = 0;
      var saved = false;
      final api = CloudApiClient(
        session: CloudSession(
          config: const CloudAuthConfig(
            issuer: 'https://issuer.example',
            audience: 'energylens-cloud',
            clientId: 'client',
            redirectUrl: 'io.energylens.app://login-callback',
            apiUrl: 'https://api.example',
          ),
          store: _Store(),
          authenticator: _Auth(),
        ),
        client: MockClient((request) async {
          if (request.url.path == '/v1/homes/$_homeId') {
            homeReads++;
            return http.Response(
              jsonEncode({
                'id': _homeId,
                'name': 'Selected Home',
                'timezone': 'America/Chicago',
                'location': {'country_code': 'US', 'postal_code': '60601'},
                'first_device_added_at': saved ? '2026-10-22T15:00:00Z' : null,
              }),
              200,
              headers: {'etag': '"1"'},
            );
          }
          if (request.url.path == '/v1/homes/$_homeId/hubs') {
            return http.Response('{"hubs":[]}', 200);
          }
          if (request.url.path == '/v1/energy-categories') {
            return http.Response(
              '{"version":1,"groups":[]}',
              200,
              headers: {'etag': '"1"'},
            );
          }
          return http.Response('{}', 500);
        }),
      );
      await tester.pumpWidget(
        MaterialApp(
          home: DesignShell(
            settingsApi: api,
            designContextCoordinator: coordinator,
            onboardingLifecycle: inventory,
            onDiscoverDevices: () async => saved = true,
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(homeReads, greaterThanOrEqualTo(1));
      platform.controller.route('settings_manage_devices');
      await tester.pumpAndSettle();
      final inventoryBefore = inventory.refreshes;
      final homeBefore = homeReads;
      platform.controller.route('discover_devices');
      await tester.pumpAndSettle();
      expect(inventory.refreshes, greaterThan(inventoryBefore));
      expect(homeReads, greaterThan(homeBefore));
      platform.controller.route('dashboard');
      await tester.pumpAndSettle();
      expect(
        platform.controller.scripts.any(
          (script) => script.contains('guide.hidden = true'),
        ),
        isTrue,
      );
      api.close();
    },
  );

  testWidgets('Settings routes to local preview without delivery controls', (
    tester,
  ) async {
    final platform = _WebPlatform();
    WebViewPlatform.instance = platform;
    final navigator = GlobalKey<NavigatorState>();
    await tester.pumpWidget(
      MaterialApp(
        navigatorKey: navigator,
        home: DesignShell(
          localPilot: true,
          onReportPreview: () => navigator.currentState!.push(
            MaterialPageRoute<void>(
              builder: (_) => const DemoReportPreviewScreen(),
            ),
          ),
        ),
      ),
    );
    await tester.pump();
    platform.controller.route('settings');
    await tester.pumpAndSettle();
    expect(platform.controller.asset, 'assets/design_pages/settings/app.html');
    expect(
      platform.controller.scripts.any(
        (script) => script.contains('View demo report'),
      ),
      isTrue,
    );
    platform.controller.route('report_preview');
    await tester.pumpAndSettle();
    expect(find.text('Demo report preview'), findsOneWidget);
    expect(
      find.text('This is a sample preview. Nothing will be emailed.'),
      findsOneWidget,
    );
    expect(find.byType(FilledButton), findsNothing);
  });

  testWidgets('verified Settings route opens selected-home Edit form', (
    tester,
  ) async {
    final platform = _WebPlatform();
    WebViewPlatform.instance = platform;
    const home = CloudHome(
      id: _homeId,
      name: 'Original Home',
      timezone: 'America/Chicago',
      countryCode: 'US',
      postalCode: '60601',
      version: 1,
      etag: '"1"',
    );
    final coordinator = DesignContextCoordinator(_Adapters(home));
    coordinator.useVerifiedContext(
      VerifiedDesignContext(
        accountId: 'owner',
        homeId: _homeId,
        mode: DesignContextMode.household,
      ),
    );
    final api = CloudApiClient(
      session: CloudSession(
        config: const CloudAuthConfig(
          issuer: 'https://issuer.example',
          audience: 'energylens-cloud',
          clientId: 'client',
          redirectUrl: 'io.energylens.app://login-callback',
          apiUrl: 'https://api.example',
        ),
        store: _Store(),
        authenticator: _Auth(),
      ),
      client: MockClient((request) async {
        expect(request.headers['authorization'], 'Bearer owner-token');
        final path = request.url.path;
        if (path == '/v1/me') {
          return http.Response(
            jsonEncode({
              'id': 'owner',
              'email': 'owner@example.com',
              'email_verified': true,
            }),
            200,
          );
        }
        final homeJson = {
          'id': _homeId,
          'name': 'Original Home',
          'timezone': 'America/Chicago',
          'location': {'country_code': 'US', 'postal_code': '60601'},
          'version': 1,
        };
        if (path == '/v1/homes') {
          return http.Response(
            jsonEncode({
              'homes': [homeJson],
            }),
            200,
          );
        }
        if (path == '/v1/homes/$_homeId') {
          return http.Response(
            jsonEncode(homeJson),
            200,
            headers: {'etag': '"1"'},
          );
        }
        if (path == '/v1/me/preferences') {
          return http.Response(
            jsonEncode({
              'schema_version': 1,
              'version': 1,
              'email_reports_enabled': false,
            }),
            200,
            headers: {'etag': '"1"'},
          );
        }
        if (path == '/v1/homes/$_homeId/preferences') {
          return http.Response(
            jsonEncode({
              'schema_version': 1,
              'version': 1,
              'goal': 'unspecified',
              'comfort_priority': 'unknown',
            }),
            200,
            headers: {'etag': '"1"'},
          );
        }
        if (path == '/v1/homes/$_homeId/appliances') {
          return http.Response(jsonEncode({'appliances': []}), 200);
        }
        fail('Unexpected ${request.method} $path');
      }),
    );
    await tester.pumpWidget(
      MaterialApp(
        home: DesignShell(
          settingsApi: api,
          designContextCoordinator: coordinator,
        ),
      ),
    );
    await tester.pump();
    platform.controller.route('settings');
    await tester.pumpAndSettle();
    expect(platform.controller.asset, 'assets/design_pages/settings/app.html');
    expect(
      platform.controller.scripts.any(
        (script) =>
            script.contains('data-el-settings-edit') &&
            script.contains('setVisible(button, true)'),
      ),
      isTrue,
    );
    platform.controller.route('settings_manage_devices');
    await tester.pumpAndSettle();
    expect(
      platform.controller.asset,
      'assets/design_pages/settings_manage_devices/app.html',
    );
    platform.controller.route('settings');
    await tester.pumpAndSettle();
    expect(platform.controller.asset, 'assets/design_pages/settings/app.html');
    expect(
      platform.controller.scripts
          .where((script) => script.contains('setVisible(button, true)'))
          .length,
      greaterThanOrEqualTo(1),
    );
    platform.controller.route('edit_home_details');
    await tester.pumpAndSettle();
    expect(find.text('Home details'), findsOneWidget);
    expect(find.text('Original Home'), findsOneWidget);
    expect(find.text('Save changes'), findsOneWidget);
  });

  testWidgets(
    'verified Settings route opens selected-home Cloud report preview',
    (tester) async {
      final platform = _WebPlatform();
      WebViewPlatform.instance = platform;
      const home = CloudHome(
        id: _homeId,
        name: 'Selected Home',
        timezone: 'America/Chicago',
        countryCode: 'US',
        postalCode: '60601',
        version: 1,
        etag: '"1"',
      );
      final coordinator = DesignContextCoordinator(_Adapters(home));
      coordinator.useVerifiedContext(
        VerifiedDesignContext(
          accountId: 'owner',
          homeId: home.id,
          mode: DesignContextMode.household,
        ),
      );
      final requests = <String>[];
      final api = CloudApiClient(
        session: CloudSession(
          config: const CloudAuthConfig(
            issuer: 'https://issuer.example',
            audience: 'energylens-cloud',
            clientId: 'client',
            redirectUrl: 'io.energylens.app://login-callback',
            apiUrl: 'https://api.example',
          ),
          store: _Store(),
          authenticator: _Auth(),
        ),
        client: MockClient((request) async {
          expect(request.headers['authorization'], 'Bearer owner-token');
          requests.add('${request.method} ${request.url.path}');
          expect(request.method, 'GET');
          expect(request.url.path, '/v1/homes/${home.id}/appliances');
          return http.Response(jsonEncode({'appliances': []}), 200);
        }),
      );
      final navigator = GlobalKey<NavigatorState>();
      await tester.pumpWidget(
        MaterialApp(
          navigatorKey: navigator,
          home: DesignShell(
            designContextCoordinator: coordinator,
            onReportPreview: () {
              if (coordinator.context?.homeId != home.id) return;
              navigator.currentState!.push(
                MaterialPageRoute<void>(
                  builder: (_) =>
                      CloudReportPreviewScreen(api: api, home: home),
                ),
              );
            },
          ),
        ),
      );
      await tester.pump();
      platform.controller.route('settings');
      await tester.pumpAndSettle();
      expect(
        platform.controller.asset,
        'assets/design_pages/settings/app.html',
      );
      platform.controller.route('report_preview');
      await tester.pumpAndSettle();
      expect(find.text('Private report preview'), findsOneWidget);
      expect(find.text(home.name), findsOneWidget);
      expect(
        find.text('Add a cloud appliance to this home first.'),
        findsOneWidget,
      );
      expect(requests, ['GET /v1/homes/${home.id}/appliances']);
      expect(find.byKey(const Key('requestReportDelivery')), findsNothing);
    },
  );
}
