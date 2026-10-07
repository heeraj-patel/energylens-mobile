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
            measuredBucket: null,
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
for (const card of appended) {
  assert.equal(card.querySelector('[data-el-bind], [data-el-action], [id]'), null);
}
assert.equal(w.eval(p.refresh), true);
assert.equal(feed.children.length, originals.length + 1);
appended = Array.from(feed.children).slice(originals.length);
assert.equal(appended[0].querySelector('.font-semibold.text-on-surface.truncate').textContent, 'Renamed Fridge');
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
