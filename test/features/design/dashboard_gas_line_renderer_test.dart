import 'dart:convert';
import 'dart:io';

import 'package:energylens_mobile/features/design/dashboard_gas_line_renderer.dart';
import 'package:energylens_mobile/features/design/design_page_bridge.dart';
import 'package:flutter_test/flutter_test.dart';

const home = '11111111-1111-4111-8111-111111111111';

void main() {
  test('gas line is added once, replaced, and removed inside the cost card', () async {
    final gate = DesignPageRequestGate();
    final ticket = gate.select(home, 'dashboard');
    final renderer = DashboardGasLineRenderer(gate);
    final scripts = [
      renderer.script(ticket, 'Gas appliances: \$1.23/day')!,
      renderer.script(ticket, 'Gas appliances: \$2.00/day')!,
      renderer.script(ticket, null)!,
    ];
    expect(renderer.script(gate.select(home, 'devices'), 'x'), isNull);
    final file = await File(
      '${Directory.systemTemp.path}/energylens-gas-line-${DateTime.now().microsecondsSinceEpoch}.json',
    ).writeAsString(jsonEncode({'scripts': scripts, 'homeId': home}));
    try {
      final result = await Process.run('node', [
        '-e',
        r'''
const assert = require('node:assert/strict');
const fs = require('node:fs');
const {scripts, homeId} = JSON.parse(fs.readFileSync(process.argv[1], 'utf8'));
globalThis.atob = input => Buffer.from(input, 'base64').toString('binary');
globalThis.window = {__energyLensTextBindingContext: {homeId, page: 'dashboard', generation: 1}};
const card = {children: [], appendChild(node) { node.parent = this; this.children.push(node); },
  querySelectorAll() { return this.children.filter(n => n.attrs['data-el-gas-line'] !== undefined); }};
const anchor = {closest(sel) { assert.equal(sel, '.rounded-xl'); return card; }};
globalThis.document = {
  querySelector(sel) { return sel.includes('dashboard_text_004') ? anchor : null; },
  createElement(name) {
    return {name, attrs: {}, className: '', textContent: '',
      setAttribute(k, v) { this.attrs[k] = v; },
      remove() { this.parent.children.splice(this.parent.children.indexOf(this), 1); }};
  }
};
assert.equal(eval(scripts[0]), true);
assert.deepEqual(card.children.map(n => n.textContent), ['Gas appliances: $1.23/day']);
assert.equal(eval(scripts[1]), true);
assert.deepEqual(card.children.map(n => n.textContent), ['Gas appliances: $2.00/day']);
assert.equal(eval(scripts[2]), true);
assert.equal(card.children.length, 0);
window.__energyLensTextBindingContext.generation = 2;
assert.equal(eval(scripts[0]), false);
assert.equal(card.children.length, 0);
''',
        file.path,
      ]);
      expect(result.exitCode, 0, reason: '${result.stdout}\n${result.stderr}');
    } finally {
      await file.delete();
    }
  });
}
