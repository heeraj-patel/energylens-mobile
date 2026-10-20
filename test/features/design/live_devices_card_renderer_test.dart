import 'dart:convert';
import 'dart:io';

import 'package:energylens_mobile/features/design/design_context_coordinator.dart';
import 'package:energylens_mobile/features/design/live_devices_card_renderer.dart';
import 'package:energylens_mobile/features/design/live_devices_projection.dart';
import 'package:flutter_test/flutter_test.dart';

const homeA = '11111111-1111-1111-1111-111111111111';
const homeB = '22222222-2222-2222-2222-222222222222';

LiveDevicesProjection _projection(String home, List<LiveDeviceRow> rows) =>
    LiveDevicesProjection(
      homeId: home,
      mode: DesignContextMode.household,
      fixtureRevision: null,
      hasMoreMeteredPages: false,
      rows: rows,
      seededRows: const [],
    );

void main() {
  test('encodes names as data and removes cloned binding hooks', () {
    const renderer = LiveDevicesCardRenderer();
    const attack = '<img src=x onerror=alert(1)> ${r'$'}{evil}';
    final script = renderer.appendScript(
      projection: _projection(homeA, [
        const LiveDeviceRow(
          applianceId: 'appliance-1',
          name: attack,
          measuredBucket: null,
        ),
      ]),
      generation: 3,
    );
    expect(script, isNot(contains(attack)));
    expect(script, contains('name.textContent = row.name'));
    expect(script, contains("node.removeAttribute('data-el-bind')"));
    expect(script, contains("node.removeAttribute('data-el-action')"));
    expect(script, isNot(contains('innerHTML')));
    expect(
      renderer.installationScript(homeId: homeA, generation: 3),
      contains('current.generation >= expected.generation'),
    );
  });

  test('measured energy does not invent card cost or Active state', () {
    const renderer = LiveDevicesCardRenderer();
    final script = renderer.appendScript(
      projection: _projection(homeA, [
        LiveDeviceRow(
          applianceId: 'metered-device',
          name: 'Saved Device',
          measuredBucket: LiveDeviceMeasuredBucket(
            energyWh: 1250,
            bucketStart: DateTime.utc(2026, 10, 6),
            computedAt: DateTime.utc(2026, 10, 6, 4),
            coveredSeconds: 3600,
          ),
        ),
      ]),
      generation: 1,
    );
    final encodedPayload = RegExp("atob\\('([^']+)'\\)")
        .firstMatch(script)!
        .group(1)!;
    final payload = jsonDecode(
      utf8.decode(base64Decode(encodedPayload)),
    ) as Map<String, dynamic>;
    expect(payload['rows'], [
      {
        'id': 'metered-device',
        'name': 'Saved Device',
        'identity': '',
        'usageCost': null,
        'usefulCost': null,
        'wasteCost': null,
        'state': 'offline',
        'stateExpiresAt': null,
      },
    ]);
    expect(script, isNot(contains('energyWh')));
    expect(script, isNot(contains('coveredSeconds')));
  });

  test('renders supported real Useful and Waste costs', () {
    const renderer = LiveDevicesCardRenderer();
    final script = renderer.appendScript(
      projection: _projection(homeA, [
        const LiveDeviceRow(
          applianceId: 'appliance-1',
          name: 'Washer',
          measuredBucket: null,
          usefulCost: '\$0.75',
          wasteCost: '\$0.25',
        ),
      ]),
      generation: 1,
    );
    final encodedPayload = RegExp("atob\\('([^']+)'\\)")
        .firstMatch(script)!
        .group(1)!;
    final payload = jsonDecode(
      utf8.decode(base64Decode(encodedPayload)),
    ) as Map<String, dynamic>;
    expect(payload['rows'][0]['usefulCost'], '\$0.75');
    expect(payload['rows'][0]['wasteCost'], '\$0.25');
    expect(script, contains("useful.textContent = row.usefulCost ?? 'N/A'"));
    expect(script, contains("waste.textContent = wasteText ?? 'N/A'"));
  });

  test('accepts Standalone with neutral status and no expiry timer', () {
    const renderer = LiveDevicesCardRenderer();
    final script = renderer.appendScript(
      projection: _projection(homeA, [
        const LiveDeviceRow(
          applianceId: 'standalone-device',
          name: 'Fridge',
          measuredBucket: null,
          usefulCost: '\$0.75',
          wasteCost: '\$0.25',
          state: 'standalone',
        ),
      ]),
      generation: 1,
    );
    final encoded = RegExp("atob\\('([^']+)'\\)").firstMatch(script)!.group(1)!;
    final payload =
        jsonDecode(utf8.decode(base64Decode(encoded))) as Map<String, dynamic>;
    expect(payload['rows'][0]['state'], 'standalone');
    expect(payload['rows'][0]['stateExpiresAt'], isNull);
    expect(payload['rows'][0]['usefulCost'], '\$0.75');
    expect(script, contains("['active', 'idle', 'offline', 'standalone']"));
    expect(
      script,
      contains("clone.setAttribute('data-el-device-state', state)"),
    );
    expect(
      script,
      contains(
        "status.replaceChildren(dot, document.createTextNode(stateText))",
      ),
    );
    expect(
      script,
      contains(
        "if ((initialState === 'active' || initialState === 'idle') && expiresAt !== null)",
      ),
    );
  });

  test('uses only Cloud-supplied waste cost for live rows', () {
    const renderer = LiveDevicesCardRenderer();
    final script = renderer.appendScript(
      projection: _projection(homeA, [
        const LiveDeviceRow(
          applianceId: 'light',
          name: 'Lamp',
          manufacturer: 'Acme',
          model: 'L1',
          measuredBucket: null,
        ),
        const LiveDeviceRow(
          applianceId: 'tv',
          name: 'Television',
          measuredBucket: null,
        ),
        const LiveDeviceRow(
          applianceId: 'capped',
          name: 'Capped device',
          measuredBucket: null,
        ),
      ]),
      generation: 1,
    );
    final encodedPayload = RegExp("atob\\('([^']+)'\\)")
        .firstMatch(script)!
        .group(1)!;
    final payload = jsonDecode(
      utf8.decode(base64Decode(encodedPayload)),
    ) as Map<String, dynamic>;
    expect(payload['rows'], [
      {
        'id': 'light',
        'name': 'Lamp',
        'identity': 'Acme L1',
        'usageCost': null,
        'usefulCost': null,
        'wasteCost': null,
        'state': 'offline',
        'stateExpiresAt': null,
      },
      {
        'id': 'tv',
        'name': 'Television',
        'identity': '',
        'usageCost': null,
        'usefulCost': null,
        'wasteCost': null,
        'state': 'offline',
        'stateExpiresAt': null,
      },
      {
        'id': 'capped',
        'name': 'Capped device',
        'identity': '',
        'usageCost': null,
        'usefulCost': null,
        'wasteCost': null,
        'state': 'offline',
        'stateExpiresAt': null,
      },
    ]);
    expect(script, isNot(contains('demoWaste')));
    expect(
      script,
      contains("clone.setAttribute('data-el-device-state', state)"),
    );
    expect(script, contains("useful.textContent = row.usefulCost ?? 'N/A'"));
    expect(script, contains("waste.textContent = wasteText ?? 'N/A'"));
  });

  test('DOM append preserves mock cards, refreshes, and rejects stale scope', () async {
    final available = Process.runSync('node', [
      '-e',
      'require.resolve("jsdom")',
    ]);
    if (available.exitCode != 0) return;

    const renderer = LiveDevicesCardRenderer();
    const attack = '<img src=x onerror=alert(1)> ${r'$'}{evil}';
    final payload = <String, String>{
      'html': await File('assets/design_pages/devices/app.html').readAsString(),
      'install1': renderer.installationScript(homeId: homeA, generation: 1),
      'append1': renderer.appendScript(
        projection: _projection(homeA, [
          const LiveDeviceRow(
            applianceId: 'a1',
            name: attack,
            measuredBucket: null,
          ),
          const LiveDeviceRow(
            applianceId: 'a2',
            name: 'Saved Fridge',
            manufacturer: 'Acme',
            model: 'F100',
            measuredBucket: null,
            wasteCost: '\$0.25',
            state: 'standalone',
          ),
        ]),
        generation: 1,
      ),
      'refresh': renderer.appendScript(
        projection: _projection(homeA, [
          const LiveDeviceRow(
            applianceId: 'a2',
            name: 'Renamed Fridge',
            measuredBucket: null,
            state: 'standalone',
          ),
        ]),
        generation: 1,
      ),
      'install2': renderer.installationScript(homeId: homeB, generation: 2),
      'stale': renderer.appendScript(
        projection: _projection(homeA, [
          const LiveDeviceRow(
            applianceId: 'a3',
            name: 'Old home',
            measuredBucket: null,
          ),
        ]),
        generation: 1,
      ),
    };
    final file = await File(
      '${Directory.systemTemp.path}/energylens-devices-renderer-${DateTime.now().microsecondsSinceEpoch}.json',
    ).writeAsString(jsonEncode(payload));
    try {
      final result = await Process.run('node', [
        '-e',
        r'''
const assert = require('node:assert/strict');
const fs = require('node:fs');
const {JSDOM} = require('jsdom');
const p = JSON.parse(fs.readFileSync(process.argv[1], 'utf8'));
const dom = new JSDOM(p.html, {runScripts: 'outside-only', url: 'https://app.test/assets/design_pages/devices/app.html'});
const w = dom.window;
w.TextDecoder = TextDecoder;
const feed = w.document.getElementById('devices-feed');
const originals = Array.from(feed.children);
const originalHtml = originals.map(node => node.outerHTML);
assert.equal(w.eval(p.install1), true);
assert.equal(w.eval(p.append1), true);
assert.equal(feed.children.length, originals.length + 2);
assert.deepEqual(originals.map(node => node.outerHTML), originalHtml);
let appended = Array.from(feed.children).slice(originals.length);
assert.equal(appended[0].querySelector('.font-semibold.text-on-surface.truncate').textContent, '<img src=x onerror=alert(1)> ${evil}');
assert.equal(appended[0].querySelector('img'), null);
assert.equal(appended[0].querySelector('.flex.flex-col.items-end'), null);
assert.equal(appended[0].textContent.includes('Useful:N/A'), true);
assert.equal(appended[0].textContent.includes('Waste:N/A'), true);
assert.equal(appended[1].textContent.includes('Acme F100'), true);
assert.equal(appended[1].textContent.includes('Waste:$0.25'), true);
assert.equal(appended[1].getAttribute('data-el-device-state'), 'standalone');
assert.equal(appended[1].textContent.includes('Standalone'), true);
const supportedWaste = Array.from(appended[1].querySelectorAll('span')).find(node => node.textContent === '$0.25');
assert.equal(supportedWaste.classList.contains('el-waste-ink'), true);
assert.equal(appended[0].textContent.includes('Idle (3h)'), false);
assert.equal(appended[0].textContent.includes('$0.68'), false);
assert.equal(appended[0].textContent.includes('$0.35'), false);
for (const card of appended) {
  assert.equal(card.querySelector('[data-el-bind], [data-el-action], [id]'), null);
}
assert.equal(w.eval(p.refresh), true);
assert.equal(feed.children.length, originals.length + 1);
appended = Array.from(feed.children).slice(originals.length);
assert.equal(appended[0].querySelector('.font-semibold.text-on-surface.truncate').textContent, 'Renamed Fridge');
assert.equal(appended[0].getAttribute('data-el-device-state'), 'standalone');
assert.equal(w.eval(p.install2), true);
assert.equal(w.eval(p.stale), false);
assert.equal(feed.children.length, originals.length + 1);
assert.deepEqual(originals.map(node => node.outerHTML), originalHtml);
''',
        file.path,
      ]);
      expect(result.exitCode, 0, reason: '${result.stdout}\n${result.stderr}');
    } finally {
      await file.delete();
    }
  });
}
