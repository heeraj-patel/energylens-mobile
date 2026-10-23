import 'dart:io';

import 'package:energylens_mobile/core/cloud_api/cloud_home.dart';
import 'package:energylens_mobile/features/design/design_navigation_script.dart';
import 'package:energylens_mobile/features/design/first_device_guide_script.dart';
import 'package:energylens_mobile/features/design/first_device_guide_state.dart';
import 'package:flutter_test/flutter_test.dart';

const _base = CloudHome(
  id: 'home-a',
  name: 'Home',
  timezone: 'America/Chicago',
  countryCode: 'US',
  postalCode: '60601',
);

void main() {
  test('unknown stays hidden; completion never regresses within a scope', () {
    final state = FirstDeviceGuideState();
    const a = 'account-a/home-a/generation-1';
    const b = 'account-a/home-b/generation-1';
    const nextSession = 'account-a/home-a/generation-2';
    expect(state.shouldShow(a), isFalse);
    state.accept(a, _base);
    expect(state.shouldShow(a), isFalse);
    state.accept(
      a,
      const CloudHome(
        id: 'home-a',
        name: 'Home',
        timezone: 'America/Chicago',
        countryCode: 'US',
        postalCode: '60601',
        hasFirstDeviceStatus: true,
      ),
    );
    expect(state.shouldShow(a), isTrue);
    expect(state.shouldShow(b), isFalse);
    expect(state.shouldShow(nextSession), isFalse);
    state.accept(
      a,
      CloudHome(
        id: 'home-a',
        name: 'Home',
        timezone: 'America/Chicago',
        countryCode: 'US',
        postalCode: '60601',
        hasFirstDeviceStatus: true,
        firstDeviceAddedAt: DateTime.utc(2026),
      ),
    );
    state.accept(
      a,
      const CloudHome(
        id: 'home-a',
        name: 'Home',
        timezone: 'America/Chicago',
        countryCode: 'US',
        postalCode: '60601',
        hasFirstDeviceStatus: true,
      ),
    );
    expect(state.shouldShow(a), isFalse);
    state.accept(
      b,
      const CloudHome(
        id: 'home-b',
        name: 'Other',
        timezone: 'America/Chicago',
        countryCode: 'US',
        postalCode: '60601',
        hasFirstDeviceStatus: true,
      ),
    );
    expect(state.shouldShow(b), isTrue);
    state.clear();
    expect(state.shouldShow(b), isFalse);
  });

  test(
    'packaged guide is hidden by default and routes without discovery',
    () async {
      final html = await File('assets/design_pages/dashboard/app.html')
          .readAsString();
      final cost = html.indexOf('<!-- Cost Card -->');
      final guide = html.indexOf('id="el-first-device-guide"');
      final trends = html.indexOf('<!-- Energy Trends Section -->', guide);
      expect(cost, lessThan(guide));
      expect(guide, lessThan(trends));
      expect(
        html,
        contains('id="el-first-device-guide" hidden style="display:none"'),
      );
      expect(html, contains('Add your first device'));
      expect(html, contains('Add a device to see its energy use and cost.'));
      expect(html, contains('data-el-route="settings_manage_devices"'));
      expect(html, contains('>Add device</button>'));
      final navigation = buildDesignNavigationScript('dashboard');
      expect(navigation, contains('let route = button.dataset.elRoute'));
      expect(
        buildFirstDeviceGuideScript(true),
        contains('guide.hidden = false'),
      );
      expect(
        buildFirstDeviceGuideScript(false),
        contains('guide.hidden = true'),
      );
      expect(navigation, contains("if (page === 'settings_manage_devices' &&"));
      final result = await Process.run('node', [
        '-e',
        r'''
const assert = require('node:assert/strict');
const routes = [];
let click;
globalThis.document = {addEventListener: (_, handler) => click = handler};
globalThis.EnergyLensNavigation = {postMessage: route => routes.push(route)};
eval(process.argv[1]);
const button = {
  dataset: {elRoute: 'settings_manage_devices'},
  getAttribute: () => null,
  closest: () => null,
  cloneNode: () => ({textContent: 'Add device', querySelectorAll: () => []}),
};
let prevented = false;
click({
  target: {closest: selector => selector === 'button' ? button : null},
  preventDefault: () => prevented = true,
  stopImmediatePropagation: () => {},
});
assert.equal(prevented, true);
assert.deepEqual(routes, ['settings_manage_devices']);
''',
        navigation,
      ]);
      expect(result.exitCode, 0, reason: '${result.stdout}\n${result.stderr}');
    },
  );
}
