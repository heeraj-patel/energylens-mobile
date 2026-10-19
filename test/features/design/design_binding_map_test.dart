import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

Set<String> _approvedRemovedIds(String page, String category) {
  if (page == 'dashboard' && category == 'bindings') {
    return {'dashboard_text_017', 'dashboard_text_024', 'dashboard_text_025'};
  }
  if (page == 'dashboard' && category == 'actions') {
    return {'dashboard_action_002'};
  }
  if (page == 'devices' && category == 'bindings') {
    return {
      for (final n in [12, 14, 16, 93, 94, 96])
        'devices_text_${n.toString().padLeft(3, '0')}',
    };
  }
  if (page == 'devices' && category == 'actions') {
    return {
      for (var n = 11; n <= 14; n++)
        'devices_action_${n.toString().padLeft(3, '0')}',
    };
  }
  if (page == 'efficiency' && category == 'bindings') {
    return {
      for (final n in [13, 23, 29, 30, 32, 36])
        'efficiency_text_${n.toString().padLeft(3, '0')}',
    };
  }
  if (category == 'bindings' && page.startsWith('efficiency_')) {
    final removed = switch (page) {
      'efficiency_away' => [13, 23, 29, 30, 31, 33, 34, 36, 40, 44],
      'efficiency_habits' => [
        13,
        23,
        29,
        30,
        31,
        32,
        33,
        34,
        35,
        36,
        37,
        38,
        40,
        44,
        48,
      ],
      'efficiency_peak_rates' => [
        13,
        23,
        29,
        30,
        31,
        32,
        33,
        34,
        35,
        36,
        37,
        38,
        40,
        44,
      ],
      _ => const <int>[],
    };
    return {
      for (final n in removed) '${page}_text_${n.toString().padLeft(3, '0')}',
    };
  }
  if (page == 'tips_knowledge' && category == 'bindings')
    return {'tips_knowledge_text_010'};
  if (page == 'tips_care_upgrades' && category == 'bindings') {
    return {'tips_care_upgrades_text_009', 'tips_care_upgrades_text_010'};
  }
  if (page == 'settings' && category == 'bindings') {
    return {
      for (var n in [7, 8, 11, 12, 13, 14, 17, 20, 23])
        '${page}_text_${n.toString().padLeft(3, '0')}',
    };
  }
  if (page == 'settings' && category == 'actions') {
    return {
      for (var n = 5; n <= 10; n++)
        '${page}_action_${n.toString().padLeft(3, '0')}',
    };
  }
  if (!const {
    'settings_manage_devices',
    'settings_manual_device_entry',
    'settings_photo_scan_onboarding',
  }.contains(page)) {
    return const {};
  }
  if (category == 'bindings') {
    return {
      if (page != 'settings_photo_scan_onboarding')
        for (var n = 45; n <= 50; n++)
          '${page}_text_${n.toString().padLeft(3, '0')}',
      for (final n in [8, 9, 11, 13, 15, 53, 55])
        '${page}_text_${n.toString().padLeft(3, '0')}',
      if (page == 'settings_photo_scan_onboarding') '${page}_text_057',
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
      if (page != 'settings_photo_scan_onboarding')
        for (var n = 14; n <= 19; n++)
          '${page}_action_${n.toString().padLeft(3, '0')}',
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

Set<String> _approvedDeviceSetupAddedIds(String page, String category) {
  if (category == 'bindings') {
    final first = page == 'settings_photo_scan_onboarding' ? 73 : 71;
    final last = page == 'settings_photo_scan_onboarding' ? 90 : 81;
    if (const {
      'settings_manage_devices',
      'settings_manual_device_entry',
      'settings_photo_scan_onboarding',
    }.contains(page)) {
      return {
        for (var n = first; n <= last; n++)
          '${page}_text_${n.toString().padLeft(3, '0')}',
      };
    }
  }
  if (category == 'fields' &&
      const {
        'settings_manage_devices',
        'settings_manual_device_entry',
      }.contains(page)) {
    return {
      for (var n = 4; n <= 6; n++)
        '${page}_field_${n.toString().padLeft(3, '0')}',
    };
  }
  return const {};
}

Set<String> _approvedAddedIds(String page, String category) =>
    page == 'settings' && category == 'actions'
    ? {
        'settings_action_edit_home',
        'settings_action_edit_zip',
        'settings_action_edit_owner',
        'settings_action_edit_email',
        'settings_action_change_password',
      }
    : const {};

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
          declared
              .difference(removed)
              .union(_approvedAddedIds(page, category.key)),
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
          .where(
            (item) => !_approvedDeviceSetupAddedIds(
              page,
              'bindings',
            ).contains(item['id']),
          )
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
              .where(
                (item) => !_approvedDeviceSetupAddedIds(
                  page,
                  'fields',
                ).contains(item['id']),
              )
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
