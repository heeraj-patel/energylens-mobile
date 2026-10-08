import 'dart:convert';
import 'dart:io';

import 'package:energylens_mobile/features/design/design_navigation_script.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
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
}
