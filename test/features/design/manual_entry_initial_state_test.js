const test = require('node:test');
const assert = require('node:assert/strict');
const fs = require('node:fs');
const vm = require('node:vm');

test('manual entry opens its form and hides the other onboarding panels', () => {
  const html = fs.readFileSync('assets/design_pages/settings_manual_device_entry/app.html', 'utf8');
  const script = html.slice(html.indexOf('  function selectOnboardingMethod('), html.indexOf('  function switchSettingsTab('));
  const nodes = {};
  for (const method of ['scan', 'camera', 'manual']) {
    for (const prefix of ['method-btn-', 'section-']) {
      const classes = new Set(['hidden']);
      nodes[prefix + method] = {classList: {
        toggle(name, active) { active ? classes.add(name) : classes.delete(name); },
        contains(name) { return classes.has(name); }
      }};
    }
  }
  vm.runInNewContext(script, {document: {getElementById(id) { return nodes[id]; }}});
  assert.equal(nodes['section-manual'].classList.contains('hidden'), false);
  assert.equal(nodes['section-camera'].classList.contains('hidden'), true);
  assert.equal(nodes['section-scan'].classList.contains('hidden'), true);
  assert.equal(nodes['method-btn-manual'].classList.contains('border-primary'), true);
});
