import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:webview_flutter_platform_interface/webview_flutter_platform_interface.dart';
import 'package:energylens_mobile/core/cloud_api/cloud_household_energy.dart';
import 'package:energylens_mobile/features/design/dashboard_domain_repository.dart';
import 'package:energylens_mobile/features/design/design_context_coordinator.dart';
import 'package:energylens_mobile/features/design/design_shell.dart';
import 'package:energylens_mobile/features/design/efficiency_domain_repository.dart';
import 'package:energylens_mobile/features/design/efficiency_away_domain_adapter.dart';
import 'package:energylens_mobile/features/design/efficiency_habits_domain_adapter.dart';
import 'package:energylens_mobile/features/design/efficiency_peak_rates_adapter.dart';
import 'package:energylens_mobile/features/design/design_page_bridge.dart';
import 'package:energylens_mobile/features/design/efficiency_month_to_date_bindings.dart';

const home = '11111111-1111-4111-8111-111111111111';

Map<String, dynamic> allocation(String cost) => {
  'energy': {'value': '1', 'unit': 'kWh'},
  'cost': {'amount': cost, 'currency': 'USD'},
  'useful_energy': {'value': '0.5', 'unit': 'kWh'},
  'useful_cost': {'amount': '0.10', 'currency': 'USD'},
  'waste_energy': {'value': '0.25', 'unit': 'kWh'},
  'waste_cost': {'amount': '0.05', 'currency': 'USD'},
  'unclassified_energy': {'value': '0.25', 'unit': 'kWh'},
  'unclassified_cost': {'amount': '0.05', 'currency': 'USD'},
  'availability': 'partial',
  'evidence_basis': 'synthetic',
};

Map<String, dynamic> base(String start, String end) => {
  'schema_revision': 'household_energy_v1',
  'content_revision': 'synthetic_household_energy_v2',
  'home_id': home,
  'data_mode': 'sample',
  'fixture_revision': 'synthetic_household_v1',
  'snapshot_id': 'snapshot',
  'generated_at': '2026-10-06T18:00:00Z',
  'as_of': null,
  'timezone': 'America/Chicago',
  'period': {'start_local': start, 'end_exclusive_local': end},
  'scope': 'attributed_devices',
  'availability': 'partial',
  'evidence_basis': 'synthetic',
};

EfficiencyDomainSnapshot snapshot(EfficiencyPage page) {
  const dayStart = '2026-10-06T00:00:00-05:00';
  const dayEnd = '2026-10-07T00:00:00-05:00';
  final dashboard = CloudHouseholdDashboard.fromJson({
    ...base(dayStart, dayEnd),
    'view': 'dashboard',
    'totals': allocation('0.20'),
    'trend_period': 'day',
    'top_recommendation_id': null,
    'assistant_intent_id': null,
  }, expectedHomeId: home);
  final hourly = CloudHouseholdEnergyTrends.fromJson({
    ...base(dayStart, dayEnd),
    'view': 'energy_trends',
    'granularity': 'hour',
    'totals': allocation('0.20'),
    'buckets': [],
  }, expectedHomeId: home);
  final monthToDate = CloudHouseholdEnergyTrends.fromJson({
    ...base('2026-10-01T00:00:00-05:00', dayEnd),
    'view': 'energy_trends',
    'granularity': 'day',
    'totals': allocation('6.00'),
    'efficiency_month_to_date': {
      'month_to_date_cost': {'amount': '6.000000', 'currency': 'USD'},
      'identified_opportunity': {'amount': '16.300000', 'currency': 'USD'},
      'optimal_base': {'amount': '5.000000', 'currency': 'USD'},
      'waste_opportunity': {'amount': '1.000000', 'currency': 'USD'},
      'away_opportunity': {'amount': '4.200000', 'currency': 'USD'},
      'peak_rates_opportunity': {'amount': '4.700000', 'currency': 'USD'},
      'habits_opportunity': {'amount': '6.400000', 'currency': 'USD'},
      'night_total_opportunity': {'amount': '0.750000', 'currency': 'USD'},
      'away_total_opportunity': {'amount': '4.450000', 'currency': 'USD'},
      'chart_segment_width_percent': {
        'night': '4.60',
        'away': '27.30',
        'peak_rates': '28.84',
        'habits': '39.26',
      },
      'waste_timing_basis': 'unknown_75_25_demo_fallback',
      'evidence_basis': 'synthetic',
    },
    'buckets': [],
  }, expectedHomeId: home);
  return EfficiencyDomainSnapshot(
    page: page,
    energy: DashboardDomainSnapshot(dashboard, hourly, isCurrent: () => true),
    operatingEstimates: const [],
    recommendations: const [],
    monthToDate: monthToDate,
  );
}

class ProbeAdapters implements DesignContextAdapters {
  @override
  void clear() {}
  @override
  Future<EfficiencyDomainSnapshot?> efficiency(
    String homeId,
    EfficiencyPage page,
  ) async => snapshot(page);
  @override
  Future<EfficiencyAwayDomainSnapshot?> efficiencyAway(String homeId) async =>
      EfficiencyAwayDomainSnapshot(snapshot(EfficiencyPage.away));
  @override
  Future<EfficiencyHabitsSnapshot?> efficiencyHabits(String homeId) async {
    final data = snapshot(EfficiencyPage.habits);
    return EfficiencyHabitsSnapshot(
      energy: data.energy,
      recommendations: const [],
      efficiencySnapshot: data,
    );
  }

  @override
  Future<EfficiencyPeakRatesSnapshot?> efficiencyPeakRates(
    String homeId,
  ) async => EfficiencyPeakRatesSnapshot(
    homeId: home,
    status: EfficiencyTariffStatus.unavailable,
    marginalRateUsdPerKwh: null,
    sourceAsOf: null,
    effectiveFrom: null,
    efficiencySnapshot: snapshot(EfficiencyPage.peak),
  );
  @override
  dynamic noSuchMethod(Invocation invocation) => null;
}

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
  Future<void> setOnPageFinished(void Function(String) callback) async =>
      onFinished = callback;
  @override
  Future<void> setOnNavigationRequest(
    FutureOr<NavigationDecision> Function(NavigationRequest) callback,
  ) async {}
}

class _WebController extends PlatformWebViewController {
  _WebController(super.params) : super.implementation();
  final channels = <String, JavaScriptChannelParams>{};
  final scripts = <String>[];
  String? asset;
  _WebNavigation? navigation;
  void route(String value) => channels['EnergyLensNavigation']!
      .onMessageReceived(JavaScriptMessage(message: value));
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
    asset = key;
    scripts.clear();
    navigation?.onFinished?.call('file:///$key');
  }

  @override
  Future<void> runJavaScript(String script) async => scripts.add(script);
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

const routes = [
  'efficiency',
  'efficiency_away',
  'efficiency_peak_rates',
  'efficiency_habits',
];
const expectedValues = [
  '\$16.30',
  '\$6.00',
  '\$5.00',
  '\$0.75',
  '\$4.45',
  '\$4.70',
  '\$6.40',
];
const expectedWidths = [4.60, 27.30, 28.84, 39.26];
const expectedTitles = [
  'Night: \$0.75',
  'Away: \$4.45',
  'Peak: \$4.70',
  'Habits: \$6.40',
];
const expectedDemo = [
  'Night Hours',
  "While You're Away",
  'Peak Rates',
  'Everyday Habits',
];
const expectedExamples = [
  ['Living Room Soundbar & TV', 'Central AC Overnight Setpoint'],
  ['Water Heater Standby Re-heat', 'Media Console & Living Room'],
  ['Central AC High-Heat Strain', 'Dishwasher & EV Charger'],
  ['Washer & Dryer Half-Loads', 'Kitchen Refrigerator Dial Setpoint'],
];
final chromePath = [
  ?Platform.environment['CHROME_BIN'],
  '/Applications/Google Chrome.app/Contents/MacOS/Google Chrome',
  '/usr/bin/google-chrome',
  '/usr/bin/chromium',
].where((path) => File(path).existsSync()).firstOrNull;

void main() {
  testWidgets(
    'selected-home DesignShell injects API MTD values on all Efficiency routes',
    (tester) async {
      final platform = _WebPlatform();
      WebViewPlatform.instance = platform;
      final coordinator = DesignContextCoordinator(ProbeAdapters());
      coordinator.useVerifiedContext(
        VerifiedDesignContext(
          accountId: 'probe',
          homeId: home,
          mode: DesignContextMode.sample,
        ),
      );
      await tester.pumpWidget(
        MaterialApp(home: DesignShell(designContextCoordinator: coordinator)),
      );
      await tester.pumpAndSettle();
      for (final route in routes) {
        platform.controller.route(route);
        await tester.pumpAndSettle();
        expect(
          platform.controller.asset,
          'assets/design_pages/$route/app.html',
        );
        final scripts = platform.controller.scripts;
        expect(
          scripts.any(
            (script) =>
                script.contains('"widths":["4.60","27.30","28.84","39.26"]'),
          ),
          isTrue,
          reason: route,
        );
        expect(
          scripts.any(
            (script) => script.contains(
              '"amounts":["\$0.75","\$4.45","\$4.70","\$6.40"]',
            ),
          ),
          isTrue,
          reason: route,
        );
        final bindingScripts = scripts
            .where(
              (script) => script.contains(
                'const payload = JSON.parse(new TextDecoder()',
              ),
            )
            .toList();
        expect(bindingScripts, isNotEmpty, reason: route);
        final encoded = RegExp("atob\\('([^']+)'\\)")
            .firstMatch(bindingScripts.last)!
            .group(1)!;
        final payload = jsonDecode(
          utf8.decode(base64Decode(encoded)),
        ) as Map<String, dynamic>;
        expect((payload['context'] as Map)['page'], route);
        expect(
          (payload['bindings'] as List).map((row) => (row as Map)['text']),
          expectedValues,
          reason: route,
        );
      }
    },
  );

  test('packaged Efficiency DOM executes approved binding and chart scripts', () async {
    final temp = await Directory.systemTemp.createTemp(
      'energylens-efficiency-dom-',
    );
    try {
      for (var i = 0; i < routes.length; i++) {
        final route = routes[i];
        final gate = DesignPageRequestGate();
        final renderer = DesignTextBindingRenderer(gate);
        final ticket = gate.select(home, route);
        final source = snapshot(
          EfficiencyPage.values[i == 2
              ? 3
              : i == 3
              ? 2
              : i],
        );
        final bindings = prepareEfficiencyMonthToDateBindings(source)!;
        final pageBindings = [
          for (final binding in bindings)
            DesignTextBinding(
              binding.id.replaceFirst('efficiency_text_', '${route}_text_'),
              binding.text,
            ),
        ];
        final install = renderer.installationScript(ticket)!;
        final update = renderer.updateScript(ticket, pageBindings)!;
        final chart = buildEfficiencyMonthToDateChartScript(
          ticket,
          source.monthToDate!.efficiencyMonthToDate!,
        );
        final original = File('assets/design_pages/$route/app.html')
            .readAsStringSync();
        final page = File('${temp.path}/$route.html');
        final probe =
            '''<script>
const results = [$install, $update, $chart];
const ids = [6,9,11,15,17,19,21].map(n => routeName + '_text_' + String(n).padStart(3,'0'));
const values = ids.map(id => document.querySelector('[data-el-bind="' + id + '"]')?.textContent.trim());
const bar = document.getElementById('efficiency-details')?.querySelector('div.w-full.h-3');
const segments = Array.from(bar?.children || []).map(x => ({width:parseFloat(x.style.width),title:x.title}));
const labels = [5,8,10,12,14,16,18,20].map(n => document.querySelector('[data-el-bind="' + routeName + '_text_' + String(n).padStart(3,'0') + '"]')?.textContent.trim());
const demo = document.body.innerText.includes(demoText) && exampleTexts.every(text => document.body.innerText.includes(text));
const badge = document.querySelector('[data-el-bind="' + routeName + '_text_013"]')?.textContent.trim();
const pre = document.createElement('pre'); pre.id = 'probe'; pre.textContent = JSON.stringify({results,values,segments,labels,demo,badge}); document.body.appendChild(pre);
</script>''';
        final body = original.replaceFirst(
          '</body>',
          '<script>const routeName = ${jsonEncode(route)}; const demoText = ${jsonEncode(expectedDemo[i])}; const exampleTexts = ${jsonEncode(expectedExamples[i])};</script>$probe</body>',
        );
        await page.writeAsString(body);
        final result = await Process.run(chromePath!, [
          '--headless=new',
          '--disable-gpu',
          '--no-sandbox',
          '--disable-extensions',
          '--dump-dom',
          '--virtual-time-budget=1500',
          page.uri.toString(),
        ]);
        expect(result.exitCode, 0, reason: '$route: ${result.stderr}');
        final match = RegExp(
          r'<pre id="probe">(.*?)</pre>',
          dotAll: true,
        ).firstMatch(result.stdout as String);
        expect(match, isNotNull, reason: route);
        final data = jsonDecode(match!.group(1)!) as Map<String, dynamic>;
        expect(data['results'], [true, true, true], reason: route);
        expect(data['values'], expectedValues, reason: route);
        expect(
          (data['segments'] as List).map((row) => (row as Map)['width']),
          expectedWidths,
          reason: route,
        );
        expect(
          (data['segments'] as List).map((row) => (row as Map)['title']),
          expectedTitles,
          reason: route,
        );
        expect(data['labels'], [
          'Identified Opportunity',
          'Month to date',
          'Optimal Base',
          'Avoidable Leak Breakdown',
          'Night',
          'Away',
          'Peak',
          'Habits',
        ], reason: route);
        expect(data['demo'], isTrue, reason: route);
        expect(data['badge'], isNull, reason: route);
      }
    } finally {
      await temp.delete(recursive: true);
    }
  }, skip: chromePath == null ? 'Chrome is unavailable' : false);
}
