import 'dart:convert';
import 'dart:io';

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

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
  return withoutNonVisibleContent.replaceAll(RegExp(r'\s+'), ' ').trim();
}

String _withoutOuterChrome(String html) => html
    .replaceFirst(RegExp(r'<header\b[^>]*>.*?</header>', dotAll: true), '')
    .replaceFirst(RegExp(r'<nav\b[^>]*>.*?</nav>', dotAll: true), '');

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
    test('source and packaged page content stays unchanged outside chrome', () async {
      for (final pageId in _pageIds) {
        final source = File('assets/design_pages/$pageId/code.html');
        expect(source.existsSync(), isTrue, reason: '$pageId source HTML');
        final sourceHtml = await source.readAsString();
        final packagedHtml = await rootBundle.loadString(
          'assets/design_pages/$pageId/app.html',
        );

        expect(_visibleText(sourceHtml), isNotEmpty, reason: pageId);
        expect(
          _visibleText(packagedHtml),
          _visibleText(_withoutOuterChrome(sourceHtml)),
          reason: '$pageId content must match its approved source',
        );
      }
    });

    test('shared chrome preserves each page binding, action, and active tab', () async {
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
        expect(config['footerActions'], hasLength(5));
        expect(config['footerBindings'], hasLength(5));
        expect(config['headerActions'], hasLength(pageId == 'dashboard' ? 1 : 2));
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
          'Dashboard', 'Devices', 'Efficiency', 'Tips', 'Settings',
        ]);
        expect(html, contains('src="../shared/chrome.js"'));
        expect(html, contains('<div id="el-header"></div>'));
        expect(html, contains('<div id="el-footer"></div>'));
      }
    });

    test('dashboard home switcher keeps its native route', () async {
      final html = await rootBundle.loadString(
        'assets/design_pages/dashboard/app.html',
      );
      final config = _chromeConfig(html);
      expect(config['homeRoute'], 'change_home');
      expect(config['headerBindings'], contains('dashboard_text_001'));
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
          for (final match in RegExp(r'data-path="([^"]+)"').allMatches(source)) {
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
