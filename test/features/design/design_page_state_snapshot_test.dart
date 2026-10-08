import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:energylens_mobile/features/design/design_page_api.dart';
import 'package:energylens_mobile/features/design/design_page_state_script.dart';
import 'package:energylens_mobile/features/design/design_page_state_snapshot.dart';

void main() {
  test('snapshot validates bounds and clears across home changes', () {
    const home = 'home-a';
    final snapshot = DesignPageStateSnapshot.fromJson(
      jsonEncode({
        'scroll_x': 0,
        'scroll_y': 420,
        'fields': {'tips_knowledge_field_001': 'washer'},
        'checks': {},
      }),
      homeId: home,
      page: 'tips_knowledge',
    );
    final store = DesignPageStateSnapshotStore()..selectHome(home);
    store.save(snapshot);
    expect(store.forPage(home, 'tips_knowledge'), same(snapshot));
    store.selectHome('home-b');
    expect(store.forPage('home-b', 'tips_knowledge'), isNull);
    expect(() => store.save(snapshot), throwsStateError);
    store.clear();
    expect(store.forPage(home, 'tips_knowledge'), isNull);
  });

  test('snapshot rejects sensitive or malformed values', () {
    expect(
      () => DesignPageStateSnapshot.fromJson(
        jsonEncode({
          'scroll_x': 0,
          'scroll_y': 0,
          'fields': {'other_page_field_001': 'secret'},
          'checks': {},
        }),
        homeId: 'home',
        page: 'settings',
      ),
      throwsFormatException,
    );
    expect(
      () => DesignPageStateSnapshot.fromJson(
        jsonEncode({
          'scroll_x': 0,
          'scroll_y': 0,
          'fields': {},
          'checks': {'settings_action_001': true},
        }),
        homeId: 'home',
        page: 'settings',
      ),
      throwsFormatException,
    );
    expect(
      () => DesignPageStateSnapshot.fromJson(
        jsonEncode({
          'scroll_x': 0,
          'scroll_y': 0,
          'fields': {},
          'checks': {},
          'selected_type': 'settings_manage_devices_action_020',
        }),
        homeId: 'home',
        page: 'settings_manage_devices',
      ),
      throwsFormatException,
    );
    expect(
      () => DesignPageStateSnapshot.fromJson(
        jsonEncode({'scroll_x': 0, 'scroll_y': 0, 'fields': {}, 'checks': {}}),
        homeId: 'home',
        page: 'unknown',
      ),
      throwsFormatException,
    );
  });

  test('manual entry type selection stays in its own page', () {
    final snapshot = DesignPageStateSnapshot.fromJson(
      jsonEncode({
        'scroll_x': 0,
        'scroll_y': 0,
        'fields': {'settings_manual_device_entry_field_001': 'Lamp'},
        'checks': {},
        'selected_type': 'settings_manual_device_entry_action_017',
      }),
      homeId: 'home',
      page: 'settings_manual_device_entry',
    );
    expect(
      snapshot.selectedTypeAction,
      'settings_manual_device_entry_action_017',
    );
    expect(
      () => DesignPageStateSnapshot.fromJson(
        jsonEncode({
          ...snapshot.toJson(),
          'selected_type': 'settings_manage_devices_action_017',
        }),
        homeId: 'home',
        page: 'settings_manual_device_entry',
      ),
      throwsFormatException,
    );
  });

  test('scripts capture only allowed state and restore values, events, and scroll', () async {
    final scripts = {
      'capture': buildDesignPageStateCaptureScript('perks_tips'),
      'restore': buildDesignPageStateRestoreScript(
        DesignPageStateSnapshot.fromJson(
          jsonEncode({
            'scroll_x': 0,
            'scroll_y': 260,
            'fields': {'perks_tips_field_001': 'query'},
            'checks': {'perks_tips_action_013': false},
          }),
          homeId: 'home',
          page: 'perks_tips',
        ),
      ),
      'type': buildDesignPageStateRestoreScript(
        DesignPageStateSnapshot.fromJson(
          jsonEncode({
            'scroll_x': 0,
            'scroll_y': 0,
            'fields': {},
            'checks': {},
            'selected_type': 'settings_manage_devices_action_015',
          }),
          homeId: 'home',
          page: 'settings_manage_devices',
        ),
      ),
      'manualType': buildDesignPageStateRestoreScript(
        DesignPageStateSnapshot.fromJson(
          jsonEncode({
            'scroll_x': 0,
            'scroll_y': 0,
            'fields': {},
            'checks': {},
            'selected_type': 'settings_manual_device_entry_action_017',
          }),
          homeId: 'home',
          page: 'settings_manual_device_entry',
        ),
      ),
      for (final page in designPageIds)
        page: buildDesignPageStateCaptureScript(page),
    };
    final file = await File(
      '${Directory.systemTemp.path}/energylens-page-state-${DateTime.now().microsecondsSinceEpoch}.json',
    ).writeAsString(jsonEncode(scripts));
    try {
      final result = await Process.run('node', [
        '-e',
        r'''
const assert = require('node:assert/strict');
const fs = require('node:fs');
const scripts = JSON.parse(fs.readFileSync(process.argv[1], 'utf8'));
function element({tag='INPUT', type='text', field=null, action=null, value='', checked=false, selected=false}={}) {
  const events = [];
  return {
    tagName: tag, type, value, checked, dataset: {elField: field, elAction: action},
    classList: {contains(name) { return selected && name === 'bg-primary-container'; }},
    getAttribute(name) { return name === 'aria-pressed' && selected ? 'true' : null; },
    dispatchEvent(event) { events.push(event.type); return true; },
    click() { this.clicked = true; }, events,
  };
}
const text = element({field: 'perks_tips_field_001', value: 'search term'});
const search = element({type: 'search', field: 'perks_tips_field_002', value: 'abc'});
const password = element({type: 'password', field: 'perks_tips_field_003', value: 'secret'});
const email = element({type: 'email', field: 'perks_tips_field_004', value: 'person@example.com'});
const checkbox = element({type: 'checkbox', action: 'perks_tips_action_013', checked: true});
const selectedType = element({tag: 'BUTTON', action: 'settings_manage_devices_action_015', selected: true});
const manualType = element({tag: 'BUTTON', action: 'settings_manual_device_entry_action_017', selected: true});
globalThis.Event = class { constructor(type) { this.type = type; this.bubbles = true; } };
globalThis.window = {scrollX: 0, scrollY: 88, scrollTo(x, y) { this.restored = [x, y]; }};
globalThis.document = {
  querySelectorAll(selector) {
    if (selector.includes('input[data-el-field]')) return [text, search, password, email];
    if (selector.includes('type="checkbox"')) return [checkbox];
    if (selector.includes('.type-pill')) return [selectedType, manualType];
    return [];
  },
};
const captured = JSON.parse(eval(scripts.capture));
assert.deepEqual(captured.fields, {perks_tips_field_001: 'search term', perks_tips_field_002: 'abc'});
assert.deepEqual(captured.checks, {perks_tips_action_013: true});
assert.equal(captured.scroll_y, 88);
assert.equal(eval(scripts.restore), true);
assert.equal(text.value, 'query');
assert.deepEqual(text.events, ['input', 'change']);
assert.equal(checkbox.checked, false);
assert.deepEqual(checkbox.events, ['input', 'change']);
assert.deepEqual(window.restored, [0, 260]);
assert.equal(eval(scripts.type), true);
assert.equal(selectedType.clicked, true);
assert.equal(eval(scripts.manualType), true);
assert.equal(manualType.clicked, true);
assert.equal(JSON.parse(eval(scripts.settings_manual_device_entry)).selected_type,
  'settings_manual_device_entry_action_017');
for (const page of Object.keys(scripts)) {
  if (page === 'capture' || page === 'restore' || page === 'type' || page === 'manualType') continue;
  assert.ok(scripts[page].includes(JSON.stringify(page)));
}
''',
        file.path,
      ]);
      expect(result.exitCode, 0, reason: '${result.stdout}\n${result.stderr}');
    } finally {
      await file.delete();
    }
  });
}
