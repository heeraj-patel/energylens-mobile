import 'dart:io';

import 'package:energylens_mobile/features/design/local_pilot_settings.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test(
    'pilot profile preserves email and password rows on load and return',
    () async {
      final script = buildLocalPilotSettingsScript(
        'settings',
        const LocalPilotSettings(
          homeName: 'My Home',
          ownerName: 'Owner',
          postalCode: '60601',
        ),
      );
      const harness = r'''
const assert = require('node:assert/strict');
const vm = require('node:vm');
const nodes = new Map();
const document = {
  querySelector(selector) {
    if (!nodes.has(selector)) nodes.set(selector, {
      hidden: true, removed: false,
      remove() { this.removed = true; },
      removeAttribute(name) { if (name === 'hidden') this.hidden = false; },
      replaceChildren(value) { this.textContent = value; }
    });
    return nodes.get(selector);
  },
  querySelectorAll(selector) { return [this.querySelector(selector)]; }
};
for (let load = 0; load < 2; load++) {
  for (const node of nodes.values()) node.hidden = true;
  vm.runInNewContext(process.argv[1], {document});
  for (const selector of ['[data-el-settings-email-row]', '[data-el-settings-password-row]']) {
    assert.equal(document.querySelector(selector).removed, false);
    assert.equal(document.querySelector(selector).hidden, false);
  }
  assert.equal(document.querySelector('[data-el-settings-email-edit]').hidden, true);
  assert.equal(document.querySelector('[data-el-settings-password-change]').hidden, false);
  assert.equal(document.querySelector('[data-el-settings-owner]').textContent, 'Owner');
}
''';
      final result = await Process.run('node', ['-e', harness, script]);
      expect(result.exitCode, 0, reason: '${result.stdout}\n${result.stderr}');
    },
  );
}
