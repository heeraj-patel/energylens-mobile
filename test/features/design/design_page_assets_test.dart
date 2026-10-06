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

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('approved design page assets', () {
    test('source and packaged pages retain the same visible content', () async {
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
          _visibleText(sourceHtml),
          reason: '$pageId packaged visible text must match its source',
        );
      }
    });

    test(
      'all approved pages are packaged and top-level nav targets resolve',
      () async {
        final assetPaths = <String>{};
        final navTargets = <String>{};
        for (final pageId in _pageIds) {
          final assetPath = 'assets/design_pages/$pageId/app.html';
          assetPaths.add(assetPath);
          final html = await rootBundle.loadString(assetPath);
          for (final match in RegExp(r'data-path="([^"]+)"').allMatches(html)) {
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
