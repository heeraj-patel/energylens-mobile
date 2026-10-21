import 'dart:convert';
import 'dart:io';

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:energylens_mobile/features/design/design_navigation_script.dart';

const _pageIds = <String>{
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

String _visibleText(String html) {
  final withoutNonVisibleContent = html
      .replaceAll(
        RegExp(
          r'<(script|style)\b[^>]*>.*?</\1>',
          dotAll: true,
          caseSensitive: false,
        ),
        ' ',
      )
      .replaceAll(
        RegExp(r'<head\b[^>]*>.*?</head>', dotAll: true, caseSensitive: false),
        ' ',
      )
      .replaceAll(RegExp(r'<[^>]+>'), ' ')
      .replaceAll('&amp;', '&')
      .replaceAll('&lt;', '<')
      .replaceAll('&gt;', '>')
      .replaceAll('&quot;', '"')
      .replaceAll('&#39;', "'");
  return withoutNonVisibleContent
      .replaceAll('tips_and_updates', '')
      .replaceAll(RegExp(r'\s+'), ' ')
      .trim();
}

String _withApprovedPolish(String text, String pageId) {
  if (pageId == 'dashboard') {
    return text.replaceFirst(
      'savings PIGGYBANK HAPPY Happy afternoon, Alex! Piggybank is looking safe & happy today 🌻',
      'energy_savings_leaf Energylens provides customized energy savings for your house. Helping you & the Globe!!',
    );
  }
  if (pageId == 'tips_knowledge')
    return text
        .replaceFirst('Find information to most common questions.', '')
        .replaceAll(RegExp(r'\s+'), ' ')
        .trim();
  if (pageId == 'settings') {
    return text
        .replaceFirst(' intelligence tune', ' intelligence')
        .replaceFirst('Manage Settings', 'tune Manage Settings')
        .replaceFirstMapped(RegExp(r'•+'), (match) => '${match[0]} Edit');
  }
  if (pageId == 'efficiency' || pageId.startsWith('efficiency_')) {
    text = text
        .replaceFirst('touch_app Select category ', '')
        .replaceFirst('insights Efficiency Insights', 'Efficiency Insights');
    if (pageId == 'efficiency_away')
      text = text.replaceFirst(
        'Detected Away Events 3 events (38 hrs)',
        '38 hrs',
      );
    return text;
  }
  return text;
}

String _withoutOuterChrome(String html) => html
    .replaceFirst(RegExp(r'<header\b[^>]*>.*?</header>', dotAll: true), '')
    .replaceFirst(RegExp(r'<nav\b[^>]*>.*?</nav>', dotAll: true), '');

String _withoutApprovedRevealControls(String html) => html.replaceAll(
  RegExp(
    r'<button\b(?=[^>]*(?:id="devices-reveal"|id="efficiency-details-toggle"|aria-controls="program-detail-[^"]+"))[^>]*>.*?</button>',
    dotAll: true,
  ),
  '',
);

String _withoutApprovedDeviceSections(String html, String pageId) {
  if (pageId != 'devices') return html;
  for (final (start, end) in [
    ('<!-- Quick Glancer Stats Mini-Bar -->', '<!-- Devices Feed -->'),
    (
      '<!-- Pagination Component -->',
      '<!-- Pairing / Settings Action Callout Card -->',
    ),
  ]) {
    final from = html.indexOf(start);
    final to = html.indexOf(end, from);
    expect(from, greaterThanOrEqualTo(0), reason: start);
    expect(to, greaterThan(from), reason: end);
    html = html.replaceRange(from, to, '');
  }
  return html;
}

String _withApprovedLabelChanges(String html, String pageId) {
  if (pageId == 'dashboard') {
    return html
        .replaceFirst('>Energy Lens</span>', '>Cost</span>')
        .replaceFirst('>Energy Trends</span>', '>Trends</span>')
        .replaceFirst(
          RegExp(
            r'<button\b[^>]*>\s*<span class="">Quick Nap</span>\s*<span class="material-symbols-outlined text-\[16px\]">power_settings_new</span>\s*</button>',
            dotAll: true,
          ),
          '',
        )
        .replaceFirst('Useful Power', 'Useful cost')
        .replaceFirst('Wasted Power', 'Waste cost')
        .replaceFirst('71% Productive load', '71% Useful')
        .replaceFirst('29% Wasted Energy', '29% Waste')
        .replaceFirst('Useful energy', 'Useful')
        .replaceFirst('Wasted Energy', 'Waste');
  }
  if (pageId == 'devices') {
    return html
        .replaceAll('Standby', 'Offline')
        .replaceFirst('add_circle', '')
        .replaceFirst(
          'Smart Plugs can be auto-calibrated or assigned to custom automation routines.',
          '',
        );
  }
  if (pageId == 'settings') {
    return html
        .replaceFirst('Home Name', 'Home Name Edit')
        .replaceFirst('Zipcode (Tariff Zone)', 'Zipcode (Tariff Zone) Edit')
        .replaceFirst(
          'Email report with useful cost, wastage, trends and breakdowns.',
          'Email a report for selected devices.',
        )
        .replaceFirst('✉ Email Report Now', 'Email Report Now');
  }
  if (const {
    'efficiency_away',
    'efficiency_habits',
    'efficiency_peak_rates',
  }.contains(pageId)) {
    return html.replaceFirst('Monthly Spend', 'Last 30 days');
  }
  return html;
}

String _withoutApprovedTabSummary(String text, String pageId) {
  final adjusted = switch (pageId) {
    'efficiency_habits' => text.replaceFirst(
      'Aggregated Monthly Impact 3 Routines Diagnosed Optimal Base \$135.90',
      '',
    ),
    'efficiency_peak_rates' => text.replaceFirst(
      'savings Off-Peak Shift \$3.90 recoverable',
      '',
    ),
    _ => text,
  };
  return adjusted.replaceAll(RegExp(r'\s+'), ' ').trim();
}

String _withoutRestoredProfileActions(String text, String pageId) {
  if (pageId != 'settings') return text;
  return text
      .replaceFirst('person Account Owner Edit ', '')
      .replaceFirst('Email ID Edit ', 'Email ID ')
      .replaceFirst('Password •••••••••••• Change ', 'Password •••••••••••• ');
}

String _withApprovedDashboardOrder(String html) {
  const start = '<!-- Top Saving Move Card -->';
  const next = '<!-- Energy Trends Section -->';
  final before = html.indexOf(start);
  final after = html.indexOf(next, before);
  expect(before, greaterThanOrEqualTo(0));
  expect(after, greaterThan(before));
  final card = html.substring(before, after);
  final withoutCard = html.replaceRange(before, after, '');
  const end = '</main>';
  final insertion = withoutCard.indexOf(end);
  expect(insertion, greaterThan(after - card.length));
  return withoutCard.replaceRange(insertion, insertion, card);
}

String _withoutApprovedDashboardSummary(String html) => html
    .replaceAll(
      RegExp(
        r'<span\b(?=[^>]*data-el-bind="dashboard_text_(?:024|025)")[^>]*>.*?</span>',
        dotAll: true,
      ),
      '',
    )
    .replaceAll(
      RegExp(
        r'<div class="flex flex-col">\s*<span[^>]*>This Week Total</span>\s*<span[^>]*>\$23\.30</span>\s*</div>',
        dotAll: true,
      ),
      '',
    );

String _withSourceFallbackValues(String html, String pageId) {
  final approved = <String, Map<String, (String, String)>>{
    'dashboard': {},
    'devices': {
      'devices_text_006': ('\$1.96', '\$1.14'),
      'devices_text_009': ('\$6.83', '\$6.67'),
    },
    for (final page in <String>['efficiency'])
      page: {'${page}_text_009': ('\$37.42', '\$142.30')},
    for (final page in <String>[
      'efficiency_away',
      'efficiency_habits',
      'efficiency_peak_rates',
    ])
      page: {'${page}_text_009': ('\$37.42', '\$142.30')},
  };
  for (final entry in (approved[pageId] ?? {}).entries) {
    final (packaged, source) = entry.value;
    final pattern = RegExp(
      '(<[^>]*data-el-bind="${entry.key}"[^>]*>)${RegExp.escape(packaged)}',
    );
    expect(pattern.allMatches(html), hasLength(1), reason: entry.key);
    html = html.replaceFirstMapped(pattern, (match) => '${match[1]}$source');
  }
  return html;
}

Map<String, dynamic> _chromeConfig(String html) {
  final match = RegExp(
    r'EnergyLensChrome\.mount\((\{.*?\})\);',
    dotAll: true,
  ).firstMatch(html);
  expect(match, isNotNull);
  return jsonDecode(match!.group(1)!) as Map<String, dynamic>;
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('approved design page assets', () {
    test('Efficiency summary stays above every category tab', () async {
      const pages = [
        'efficiency',
        'efficiency_away',
        'efficiency_habits',
        'efficiency_peak_rates',
      ];
      const start = '<!-- Top Insight Badge & Sub-header -->';
      const end = '<!-- Segmented Tabs Navigation -->';
      String? sharedSummary;
      for (final pageId in pages) {
        final html = await rootBundle.loadString(
          'assets/design_pages/$pageId/app.html',
        );
        final topStart = html.indexOf(start);
        final tabsStart = html.indexOf(end, topStart);
        expect(topStart, greaterThanOrEqualTo(0), reason: pageId);
        expect(tabsStart, greaterThan(topStart), reason: pageId);
        final summary = html
            .substring(topStart, tabsStart)
            .replaceAll('${pageId}_text_', 'efficiency_text_');
        sharedSummary ??= summary;
        expect(summary, sharedSummary, reason: pageId);
        expect(summary, contains('>Identified Opportunity</span>'));
        expect(summary, isNot(contains('>insights</span>')));
        expect(summary, contains('el-compact-page-title'));
        expect(summary, contains('el-monthly-overview'));
        expect(summary, contains('>Optimal Base</span>'));
        expect(html, isNot(contains('id="efficiency-details-toggle"')));
        expect(
          html,
          contains('<div id="efficiency-details" class="space-y-space-md">'),
        );
        expect(html, isNot(contains('efficiency/controls.js')));
        final belowTabs = html.substring(tabsStart);
        expect(belowTabs, isNot(contains('>Identified Opportunity<')));
        expect(belowTabs, isNot(contains('>Optimal Base<')));
        expect(belowTabs, isNot(contains('>Off-Peak Shift<')));
      }
    });

    test('Efficiency opportunity ink is green while waste costs stay amber', () async {
      const pages = [
        'efficiency',
        'efficiency_away',
        'efficiency_habits',
        'efficiency_peak_rates',
      ];
      for (final pageId in pages) {
        final html = await rootBundle.loadString(
          'assets/design_pages/$pageId/app.html',
        );
        expect(
          html,
          contains(
            'class="el-useful-ink" data-el-bind="${pageId}_text_006">\$18.60',
          ),
          reason: pageId,
        );
        expect(
          RegExp(
            r'<span class="[^"]*bg-amber-100 el-waste-ink[^"]*" data-el-bind="[^"]+">\+?\$[^<]+</span>',
          ).allMatches(html),
          isNotEmpty,
          reason: pageId,
        );
        expect(html, isNot(contains('tips_and_updates')), reason: pageId);
      }
    });

    test('source and packaged page content stays unchanged outside chrome', () async {
      for (final pageId in _pageIds) {
        final source = File('assets/design_pages/$pageId/code.html');
        expect(source.existsSync(), isTrue, reason: '$pageId source HTML');
        // The owner retired this source-only Efficiency badge from the app.
        final sourceHtml = (await source.readAsString()).replaceAll(
          RegExp(r'<span\b[^>]*>13% of Bill</span>'),
          '',
        );
        final packagedHtml = await rootBundle.loadString(
          'assets/design_pages/$pageId/app.html',
        );

        if (pageId == 'efficiency') {
          expect(_visibleText(packagedHtml), contains('Last 30 days'));
          expect(_visibleText(packagedHtml), isNot(contains('Monthly Spend')));
        }
        if (pageId == 'dashboard') {
          expect(
            _visibleText(packagedHtml),
            isNot(contains('Device cost · week to date')),
          );
          expect(packagedHtml, isNot(contains('dashboard_text_024')));
          expect(packagedHtml, isNot(contains('dashboard_text_025')));
          final summary = packagedHtml.substring(
            packagedHtml.indexOf('<!-- Active Summary -->'),
            packagedHtml.indexOf('<!-- Inline SVG Split Bar Chart -->'),
          );
          expect(
            summary,
            contains('class="flex w-full items-center justify-between'),
          );
          expect(summary, contains('data-el-bind="dashboard_text_026"'));
          expect(summary, contains('data-el-bind="dashboard_text_027"'));
          expect(
            summary.indexOf('data-el-bind="dashboard_text_026"'),
            lessThan(summary.indexOf('data-el-bind="dashboard_text_027"')),
          );
          expect(
            packagedHtml,
            contains('data-el-bind="dashboard_text_004">Cost</span>'),
          );
          expect(
            packagedHtml,
            contains('data-el-bind="dashboard_text_020">Trends</span>'),
          );
          expect(packagedHtml, isNot(contains('Quick Nap')));
          expect(packagedHtml, isNot(contains('dashboard_action_002')));
          expect(packagedHtml, contains('data-el-chart="dashboard-trends"'));
          final sourceButton = RegExp(
            r'<button\b[^>]*>.*?Browse energy answers.*?</button>',
            dotAll: true,
          );
          final packagedButton = RegExp(
            r'<button\b[^>]*data-el-action="dashboard_action_007"[^>]*>.*?data-el-bind="dashboard_text_038">Browse energy answers</span>.*?</button>',
            dotAll: true,
          );
          expect(sourceButton.hasMatch(sourceHtml), isTrue);
          expect(packagedButton.hasMatch(packagedHtml), isTrue);
        }
        if (pageId == 'devices') {
          final useful = packagedHtml.indexOf(
            'data-el-bind="devices_text_008"',
          );
          final waste = packagedHtml.indexOf('data-el-bind="devices_text_005"');
          expect(useful, greaterThanOrEqualTo(0));
          expect(waste, greaterThan(useful));
          expect(
            packagedHtml,
            contains('for="status-filter-select">Filter by'),
          );
          expect(packagedHtml, contains('for="sort-select"'));
          expect(packagedHtml, contains('id="devices-pagination"'));
          expect(packagedHtml, contains('aria-label="Previous page"'));
          expect(packagedHtml, contains('aria-label="Next page"'));
          expect(packagedHtml, isNot(contains('id="devices-reveal"')));
          expect(
            packagedHtml,
            isNot(
              contains(
                'Smart Plugs can be auto-calibrated or assigned to custom automation routines.',
              ),
            ),
          );
        }

        expect(_visibleText(sourceHtml), isNotEmpty, reason: pageId);
        if (const {
          'settings_manage_devices',
          'settings_manual_device_entry',
          'settings_photo_scan_onboarding',
        }.contains(pageId)) {
          final discoveredBinding = '${pageId}_text_016';
          final monitoredSubtitleBinding = switch (pageId) {
            'settings_photo_scan_onboarding' =>
              'settings_photo_scan_onboarding_text_056',
            _ => '${pageId}_text_054',
          };
          expect(
            packagedHtml,
            contains(
              'data-el-bind="$discoveredBinding">Discovered Devices</h3>',
            ),
            reason: '$pageId uses the approved discovered-device label',
          );
          expect(
            sourceHtml,
            contains('Discovered on Circuit'),
            reason: '$pageId immutable source keeps its reference wording',
          );
          expect(
            packagedHtml,
            isNot(contains('Discovered on Circuit')),
            reason: '$pageId packaged page uses only the approved label',
          );
          expect(
            packagedHtml,
            isNot(contains('data-el-bind="$monitoredSubtitleBinding"')),
            reason: '$pageId removes the approved telemetry subtitle',
          );
          expect(
            packagedHtml,
            contains('Monitored Devices'),
            reason: '$pageId preserves the monitored-device section label',
          );
          for (final duplicate in [
            'LG Smart Refrigerator',
            'Ecobee Smart Thermostat',
            'Sony Bravia TV 4K',
            '3 Ready',
          ]) {
            expect(packagedHtml, isNot(contains(duplicate)), reason: pageId);
          }
          if (pageId == 'settings_photo_scan_onboarding') {
            expect(
              packagedHtml,
              contains('Take a photo or choose one to review a device.'),
            );
            expect(packagedHtml, isNot(contains('BOSCH SMS4ECW14E')));
          }
          const mockListMarker = '<!-- Existing Monitored Devices List -->';
          expect(
            _visibleText(packagedHtml.split(mockListMarker).last),
            _visibleText(
              _withoutOuterChrome(sourceHtml)
                  .split(mockListMarker)
                  .last
                  .replaceAll('Active continuous energy telemetry', ''),
            ).replaceFirst(
              RegExp(r'Monitored Devices\s*\(\s*5\s*\)\s*5 of 16 circuits'),
              'Monitored Devices',
            ),
            reason: 'Photo Scan keeps the approved mock device list',
          );
          continue;
        }
        expect(
          _withoutRestoredProfileActions(
            _visibleText(
              _withoutApprovedDeviceSections(
                _withoutApprovedRevealControls(
                  _withSourceFallbackValues(packagedHtml, pageId),
                ),
                pageId,
              ),
            ),
            pageId,
          ),
          _withApprovedPolish(
            _withoutApprovedTabSummary(
              _visibleText(
                _withoutApprovedDeviceSections(
                  _withoutOuterChrome(
                    _withApprovedLabelChanges(
                      pageId == 'efficiency'
                          ? sourceHtml.replaceFirst(
                              'Monthly Spend',
                              'Last 30 days',
                            )
                          : pageId == 'dashboard'
                          ? _withoutApprovedDashboardSummary(
                              _withApprovedDashboardOrder(sourceHtml),
                            )
                          : sourceHtml,
                      pageId,
                    ),
                  ),
                  pageId,
                ),
              ),
              pageId,
            ),
            pageId,
          ),
          reason:
              '$pageId content must match its approved source except approved fallback values',
        );
      }
    });

    test(
      'shared chrome preserves each page binding, action, and active tab',
      () async {
        final chrome = await rootBundle.loadString(
          'assets/design_pages/shared/chrome.js',
        );
        expect(chrome, contains('window.EnergyLensChrome'));
        for (final pageId in _pageIds) {
          final html = await rootBundle.loadString(
            'assets/design_pages/$pageId/app.html',
          );
          final config = _chromeConfig(html);
          expect(config['headerBindings'], hasLength(2));
          expect(
            (config['headerBindings'] as List).first,
            '${pageId}_text_001',
            reason: '$pageId selected-home header slot',
          );
          expect(config['footerActions'], hasLength(5));
          expect(config['footerBindings'], hasLength(5));
          expect(
            config['headerActions'],
            hasLength(pageId == 'dashboard' ? 1 : 2),
          );
          for (final id in <String>[
            ...(config['headerBindings'] as List).cast<String>(),
            ...(config['footerBindings'] as List).cast<String>(),
            ...(config['headerActions'] as List).cast<String>(),
            ...(config['footerActions'] as List).cast<String>(),
          ]) {
            expect(id, startsWith('${pageId}_'), reason: pageId);
          }
          expect(config['homeName'], 'The Miller Home');
          expect(config['tabLabels'], <String>[
            'Dashboard',
            'Devices',
            'Efficiency',
            'Tips',
            'Settings',
          ]);
          expect(html, contains('src="../shared/chrome.js"'));
          expect(html, contains('<div id="el-header"></div>'));
          expect(html, contains('<div id="el-footer"></div>'));
        }
      },
    );

    test(
      'Settings profile exposes approved owner and credential actions',
      () async {
        final html = await rootBundle.loadString(
          'assets/design_pages/settings/app.html',
        );
        expect(html, contains('data-el-bind="settings_text_010"></p>'));
        expect(html, contains('data-el-bind="settings_text_016"></p>'));
        expect(html, contains('data-el-bind="settings_text_019"></p>'));
        expect(html, contains('data-el-settings-email-row hidden'));
        expect(html, contains('data-el-settings-postal-row hidden'));
        expect(html, isNot(contains('Alex Miller')));
        expect(html, contains('Account Owner'));
        expect(html, contains('data-el-action="settings_action_edit_owner"'));
        expect(html, contains('data-el-action="settings_action_edit_email"'));
        expect(
          html,
          contains('data-el-action="settings_action_change_password"'),
        );
        for (var action = 5; action <= 10; action++) {
          final actionId =
              'settings_action_${action.toString().padLeft(3, '0')}';
          expect(html, isNot(contains('data-el-action="$actionId"')));
        }
      },
    );

    test('dashboard home switcher keeps its native route', () async {
      final html = await rootBundle.loadString(
        'assets/design_pages/dashboard/app.html',
      );
      final config = _chromeConfig(html);
      expect(config['homeRoute'], 'change_home');
      expect(config['headerBindings'], contains('dashboard_text_001'));
    });

    test('Tips local tabs navigate without consuming other buttons', () async {
      final node = Process.runSync('node', ['--version']);
      if (node.exitCode != 0) return;
      final script = buildDesignNavigationScript('tips_efficiency');
      final result = await Process.run('node', [
        '-e',
        '''
const assert = require('node:assert/strict');
const vm = require('node:vm');
let click;
const routes = [];
const document = {addEventListener: (_, callback) => click = callback};
const EnergyLensNavigation = {postMessage: route => routes.push(route)};
vm.runInNewContext(process.argv[1], {document, EnergyLensNavigation});
function element(label, tab) {
  return {
    dataset: {},
    cloneNode: () => ({textContent: label, querySelectorAll: () => []}),
    closest: selector => selector === '[role="tablist"]' && tab ? {} : null,
  };
}
function tap(button) {
  click({
    target: {closest: selector => selector === 'button' ? button : null},
    preventDefault: () => {}, stopImmediatePropagation: () => {},
  });
}
tap(element('Efficiency', true));
assert.deepEqual(routes, ['tips_efficiency']);
tap(element('Efficiency', false));
assert.deepEqual(routes, ['tips_efficiency']);
''',
        script,
      ]);
      expect(result.exitCode, 0, reason: '${result.stderr}');
    });

    test(
      'all approved pages are packaged and top-level nav targets resolve',
      () async {
        final assetPaths = <String>{};
        final navTargets = <String>{};
        for (final pageId in _pageIds) {
          final assetPath = 'assets/design_pages/$pageId/app.html';
          assetPaths.add(assetPath);
          final source = await rootBundle.loadString(
            'assets/design_pages/$pageId/code.html',
          );
          for (final match in RegExp(
            r'data-path="([^"]+)"',
          ).allMatches(source)) {
            navTargets.add(match.group(1)!);
          }
        }

        expect(assetPaths, hasLength(14));
        expect(
          navTargets,
          containsAll(<String>{
            'dashboard',
            'devices',
            'efficiency',
            'perks-and-tips',
            'settings',
          }),
        );
        expect(
          navTargets.difference(<String>{
            'dashboard',
            'devices',
            'efficiency',
            'perks-and-tips',
            'settings',
          }),
          isEmpty,
        );
      },
    );
  });
}
