import 'dart:convert';
import 'dart:io';

import 'package:energylens_mobile/features/design/design_navigation_script.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('Dashboard period buttons route exact backend granularities', () async {
    final script = buildDesignNavigationScript('dashboard');
    final file = await File(
      '${Directory.systemTemp.path}/energylens-dashboard-period-${DateTime.now().microsecondsSinceEpoch}.json',
    ).writeAsString(jsonEncode({'script': script}));
    try {
      final result = await Process.run('node', [
        '-e',
        r'''
const assert = require('node:assert/strict');
const fs = require('node:fs');
const {script} = JSON.parse(fs.readFileSync(process.argv[1], 'utf8'));
const routes = [];
let clickHandler;
globalThis.document = {addEventListener(type, handler) { clickHandler = handler; }};
globalThis.EnergyLensNavigation = {postMessage(route) { routes.push(route); }};
eval(script);
for (const action of ['dashboard_action_004', 'dashboard_action_005', 'dashboard_action_006']) {
  let prevented = false, stopped = false;
  const button = {dataset: {elAction: action}};
  clickHandler({
    target: {closest(selector) { return selector === 'button' ? button : null; }},
    preventDefault() { prevented = true; },
    stopImmediatePropagation() { stopped = true; }
  });
  assert.equal(prevented, true);
  assert.equal(stopped, true);
}
assert.deepEqual(routes, [
  'dashboard_period:day', 'dashboard_period:week', 'dashboard_period:month'
]);
''',
        file.path,
      ]);
      expect(result.exitCode, 0, reason: '${result.stdout}\n${result.stderr}');
    } finally {
      await file.delete();
    }
  });

  test('manual and photo controls bypass packaged fake save handlers', () async {
    for (final page in [
      'settings_manage_devices',
      'settings_manual_device_entry',
    ]) {
      final html = await File('assets/design_pages/$page/app.html')
          .readAsString();
      expect(html, isNot(contains('onclick="saveManualDevice()"')));
      expect(html, contains('data-el-action="${page}_action_020"'));
    }
    final photo = await File(
      'assets/design_pages/settings_photo_scan_onboarding/app.html',
    ).readAsString();
    expect(photo, contains('Take a photo or choose one to review a device.'));
    expect(photo, isNot(contains('BOSCH SMS4ECW14E')));
    expect(photo, contains('Kitchen Refrigerator'));
    final payload = {
      'scripts': {
        for (final page in [
          'settings_manage_devices',
          'settings_manual_device_entry',
          'settings_photo_scan_onboarding',
        ])
          page: buildDesignNavigationScript(page),
      },
    };
    final file = await File(
      '${Directory.systemTemp.path}/energylens-onboarding-navigation-${DateTime.now().microsecondsSinceEpoch}.json',
    ).writeAsString(jsonEncode(payload));
    try {
      final result = await Process.run('node', [
        '-e',
        r'''
const assert = require('node:assert/strict');
const fs = require('node:fs');
const scripts = JSON.parse(fs.readFileSync(process.argv[1], 'utf8')).scripts;
for (const [page, script] of Object.entries(scripts)) {
  let clickHandler;
  const reviews = [], photos = [], routes = [];
  globalThis.document = {
    addEventListener(_, handler) { clickHandler = handler; },
    querySelectorAll() { return [{
      dataset: {elAction: page + '_action_015'},
      classList: {contains(name) { return name === 'bg-primary-container'; }},
      getAttribute() { return null; },
    }]; },
    getElementById(id) {
      return {value: ({'input-device-name': 'Fridge',
                       'input-manufacturer': 'Acme',
                       'input-model': 'A123'})[id]};
    },
  };
  globalThis.EnergyLensNavigation = {postMessage(value) { routes.push(value); }};
  globalThis.EnergyLensDeviceReview = {postMessage(value) { reviews.push(JSON.parse(value)); }};
  globalThis.EnergyLensPhotoCapture = {postMessage(value) { photos.push(value); }};
  eval(script);
  function click(action) {
    let prevented = false, stopped = false;
    const button = {
      id: '', dataset: {elAction: action},
      cloneNode() { return {textContent: 'Save Device', querySelectorAll() { return []; }}; },
    };
    clickHandler({
      target: {closest(selector) { return selector === 'button' ? button : null; }},
      preventDefault() { prevented = true; },
      stopImmediatePropagation() { stopped = true; },
    });
    assert.equal(prevented, true);
    assert.equal(stopped, true);
  }
  if (page === 'settings_photo_scan_onboarding') {
    click(page + '_action_014');
    click(page + '_action_015');
    assert.deepEqual(photos, ['camera', 'gallery']);
    assert.deepEqual(reviews, []);
  } else {
    click(page + '_action_020');
    assert.deepEqual(reviews, [{
      name: 'Fridge', manufacturer: 'Acme', model: 'A123',
      category: page === 'settings_manual_device_entry' ? 'refrigerator' : 'dishwasher'
    }]);
    assert.deepEqual(photos, []);
  }
  assert.deepEqual(routes, []);
}
''',
        file.path,
      ]);
      expect(result.exitCode, 0, reason: '${result.stdout}\n${result.stderr}');
    } finally {
      await file.delete();
    }
  });

  test('Devices Daily Overview opens Dashboard within the selected home', () async {
    final html = await File('assets/design_pages/devices/app.html')
        .readAsString();
    expect(
      html,
      matches(
        RegExp(
          r'<a[^>]*data-path="settings"[^>]*data-el-action="devices_action_003"',
        ),
      ),
    );
    final payload = {'script': buildDesignNavigationScript('devices')};
    final file = await File(
      '${Directory.systemTemp.path}/energylens-devices-navigation-${DateTime.now().microsecondsSinceEpoch}.json',
    ).writeAsString(jsonEncode(payload));
    try {
      final result = await Process.run('node', [
        '-e',
        r'''
const assert = require('node:assert/strict');
const fs = require('node:fs');
const p = JSON.parse(fs.readFileSync(process.argv[1], 'utf8'));
const routes = [];
let clickHandler;
globalThis.document = {addEventListener(type, handler) {
  assert.equal(type, 'click');
  clickHandler = handler;
}};
globalThis.EnergyLensNavigation = {postMessage(route) { routes.push(route); }};
eval(p.script);
function click(action, label) {
  let prevented = false;
  const link = {
    dataset: {elAction: action, path: 'settings'},
    cloneNode() { return {textContent: label, querySelectorAll() { return []; }}; }
  };
  clickHandler({
    target: {closest(selector) { return selector === 'a[data-path]' ? link : null; }},
    preventDefault() { prevented = true; },
    stopImmediatePropagation() {},
  });
  assert.equal(prevented, true);
}
click('devices_action_003', 'Daily Overview');
click('devices_action_015', 'Manage Devices in Settings');
assert.deepEqual(routes, ['dashboard', 'settings_manage_devices']);
''',
        file.path,
      ]);
      expect(result.exitCode, 0, reason: '${result.stdout}\n${result.stderr}');
    } finally {
      await file.delete();
    }
  });

  test('section routes work and unbound controls are not intercepted', () async {
    final payload = {
      'scripts': {
        for (final page in [
          'efficiency',
          'tips_knowledge',
          'settings',
          'dashboard',
        ])
          page: buildDesignNavigationScript(page),
      },
    };
    final file = await File(
      '${Directory.systemTemp.path}/energylens-section-navigation-${DateTime.now().microsecondsSinceEpoch}.json',
    ).writeAsString(jsonEncode(payload));
    try {
      final result = await Process.run('node', [
        '-e',
        r'''
const assert = require('node:assert/strict');
const fs = require('node:fs');
const scripts = JSON.parse(fs.readFileSync(process.argv[1], 'utf8')).scripts;
for (const [page, script] of Object.entries(scripts)) {
  const routes = [];
  let clickHandler;
  globalThis.document = {addEventListener(type, handler) {
    assert.equal(type, 'click');
    clickHandler = handler;
  }};
  globalThis.EnergyLensNavigation = {postMessage(route) { routes.push(route); }};
  eval(script);
  function click(label, {tab = false, id = '', route} = {}) {
    let prevented = false;
    const button = {
      id,
      dataset: {elRoute: route},
      closest(selector) { return selector === '[role="tablist"]' && tab ? {} : null; },
      cloneNode() { return {textContent: label, querySelectorAll() { return []; }}; },
    };
    clickHandler({
      target: {closest(selector) { return selector === 'button' ? button : null; }},
      preventDefault() { prevented = true; },
      stopImmediatePropagation() {},
    });
    return prevented;
  }
  if (page === 'efficiency') {
    assert.equal(click('Away'), true);
    assert.equal(click('Peak Rates'), true);
    assert.equal(click('Habits'), true);
    assert.deepEqual(routes, ['efficiency_away', 'efficiency_peak_rates', 'efficiency_habits']);
  } else if (page === 'tips_knowledge') {
    assert.equal(click('Programs', {tab: true}), true);
    assert.equal(click('Care & Upgrades', {tab: true}), true);
    assert.deepEqual(routes, ['perks_tips', 'tips_care_upgrades']);
    assert.equal(click('Why did my AC power jump this afternoon?'), false);
  } else if (page === 'settings') {
    assert.equal(click('Manage Devices'), true);
    assert.equal(click('Email Report Now', {id: 'email-btn'}), true);
    assert.deepEqual(routes, ['settings_manage_devices', 'report_preview']);
    assert.equal(click('Edit'), false);
  } else {
    assert.equal(click('Quick Nap'), false);
    assert.equal(click('Monthly'), false);
    assert.deepEqual(routes, []);
  }
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
