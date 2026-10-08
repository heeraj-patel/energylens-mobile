import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

Set<String> _approvedRemovedIds(String page, String category) {
  if (!const {
    'settings_manage_devices',
    'settings_manual_device_entry',
    'settings_photo_scan_onboarding',
  }.contains(page)) {
    return const {};
  }
  if (category == 'bindings') {
    return {
      for (var n = 17; n <= 26; n++)
        '${page}_text_${n.toString().padLeft(3, '0')}',
      if (page == 'settings_photo_scan_onboarding')
        '${page}_text_056'
      else
        '${page}_text_054',
      if (page == 'settings_photo_scan_onboarding')
        for (var n = 27; n <= 53; n++)
          '${page}_text_${n.toString().padLeft(3, '0')}',
    };
  }
  if (category == 'actions') {
    return {
      for (var n = 8; n <= 10; n++)
        '${page}_action_${n.toString().padLeft(3, '0')}',
      if (page == 'settings_photo_scan_onboarding')
        for (var n = 11; n <= 22; n++)
          if (n != 14 && n != 15)
            '${page}_action_${n.toString().padLeft(3, '0')}',
    };
  }
  return page == 'settings_photo_scan_onboarding'
      ? {
          for (var n = 1; n <= 3; n++)
            '${page}_field_${n.toString().padLeft(3, '0')}',
        }
      : const {};
}

void main() {
  test('all 14 packaged pages carry their frozen unique binding IDs', () {
    final manifest = jsonDecode(
      File('docs/design_page_binding_map.json').readAsStringSync(),
    ) as Map<String, dynamic>;
    final pages = manifest['pages'] as Map<String, dynamic>;
    expect(pages, hasLength(14));
    expect(manifest['revision'], 'mobile_design_2026_10_06_v1');

    for (final entry in pages.entries) {
      final page = entry.key;
      final mapping = entry.value as Map<String, dynamic>;
      final html = File('assets/design_pages/$page/app.html')
          .readAsStringSync();
      final chromeMatch = RegExp(
        r'EnergyLensChrome\.mount\((\{.*?\})\);',
        dotAll: true,
      ).firstMatch(html);
      expect(chromeMatch, isNotNull, reason: '$page shared chrome');
      final chrome = jsonDecode(chromeMatch!.group(1)!) as Map<String, dynamic>;
      final allIds = <String>{};
      for (final category in <String, String>{
        'bindings': 'data-el-bind',
        'actions': 'data-el-action',
        'fields': 'data-el-field',
      }.entries) {
        final items = mapping[category.key] as List<dynamic>;
        final declared = items
            .map((item) => (item as Map<String, dynamic>)['id'] as String)
            .toSet();
        expect(declared, hasLength(items.length), reason: '$page IDs');
        final raw = RegExp('${category.value}="([^"]+)"')
            .allMatches(html)
            .map((match) => match.group(1)!)
            .toList();
        expect(
          raw.toSet(),
          hasLength(raw.length),
          reason: '$page raw duplicates',
        );
        final shared =
            (category.key == 'bindings'
                    ? [
                        ...chrome['headerBindings'] as List<dynamic>,
                        ...chrome['footerBindings'] as List<dynamic>,
                      ]
                    : category.key == 'actions'
                    ? [
                        ...chrome['headerActions'] as List<dynamic>,
                        ...chrome['footerActions'] as List<dynamic>,
                      ]
                    : const <dynamic>[])
                .cast<String>();
        final removed = _approvedRemovedIds(page, category.key);
        expect(
          declared.containsAll(removed),
          isTrue,
          reason: '$page removed IDs',
        );
        expect(
          {...raw, ...shared},
          declared.difference(removed),
          reason: '$page ${category.key}',
        );
        for (final id in declared) {
          expect(allIds.add(id), isTrue, reason: '$page duplicate ID');
          expect(id, startsWith('${page}_'));
        }
      }
    }
  });

  test('binding map covers every frozen non-icon text and actionable control', () {
    final pages =
        (jsonDecode(
              File('docs/design_page_binding_map.json').readAsStringSync(),
            ) as Map<String, dynamic>)['pages']
            as Map<String, dynamic>;
    for (final entry in pages.entries) {
      final page = entry.key;
      final fixture = jsonDecode(
        File(
          '../energylens-common/docs/plans/support/golden_fixtures/$page.json',
        ).readAsStringSync(),
      ) as Map<String, dynamic>;
      final mapping = entry.value as Map<String, dynamic>;
      final textPaths = (fixture['ordered_text_segments'] as List<dynamic>)
          .cast<Map<String, dynamic>>()
          .where((segment) => segment['icon_glyph'] == false)
          .map((segment) => segment['path'] as String)
          .toSet();
      final bindingPaths = (mapping['bindings'] as List<dynamic>)
          .cast<Map<String, dynamic>>()
          .map((item) => item['path'] as String)
          .toSet();
      expect(bindingPaths, textPaths, reason: '$page text coverage');

      final controlPaths = (fixture['controls'] as List<dynamic>)
          .cast<Map<String, dynamic>>()
          .where(
            (control) => {
              'a',
              'button',
              'input',
              'select',
              'textarea',
            }.contains(control['tag']),
          )
          .map((control) => control['path'] as String)
          .toSet();
      final markedPaths =
          [
                ...mapping['actions'] as List<dynamic>,
                ...mapping['fields'] as List<dynamic>,
              ]
              .cast<Map<String, dynamic>>()
              .map((item) => item['path'] as String)
              .toSet();
      expect(markedPaths, controlPaths, reason: '$page control coverage');
    }
  });

  test('key numeric and unresolved control surfaces remain identifiable', () {
    final pages =
        (jsonDecode(
              File('docs/design_page_binding_map.json').readAsStringSync(),
            ) as Map<String, dynamic>)['pages']
            as Map<String, dynamic>;
    for (final entry in <String, List<String>>{
      'dashboard': [r'$6.96', r'$2.88', r'$23.30'],
      'devices': [r'$1.14', r'$6.67'],
      'efficiency': [r'$18.60', r'$142.30', r'$123.70'],
      'efficiency_away': [r'$4.20', r'$2.15'],
      'efficiency_peak_rates': [r'$4.70', r'$3.90'],
      'efficiency_habits': [r'$6.40', r'$135.90'],
      'perks_tips': [r'$1,200 Tax Credit'],
      'tips_efficiency': [r'~$12', r'~$18'],
      'tips_care_upgrades': [r'~$14/mo', r'~$16/mo'],
    }.entries) {
      final bindings =
          ((pages[entry.key] as Map<String, dynamic>)['bindings']
                  as List<dynamic>)
              .cast<Map<String, dynamic>>()
              .expand((item) => (item['text'] as List<dynamic>).cast<String>())
              .join(' ');
      for (final text in entry.value) {
        expect(bindings, contains(text), reason: entry.key);
      }
    }
    final dashboardActions =
        ((pages['dashboard'] as Map<String, dynamic>)['actions']
                as List<dynamic>)
            .cast<Map<String, dynamic>>()
            .map((item) => item['text'] as String)
            .join(' ');
    expect(dashboardActions, contains('Quick Nap'));
    expect(dashboardActions, contains('Daily'));
    expect(dashboardActions, contains('Monthly'));
  });
}
