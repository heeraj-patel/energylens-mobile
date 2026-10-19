const test = require('node:test');
const assert = require('node:assert/strict');
const fs = require('node:fs');
const vm = require('node:vm');

const html = fs.readFileSync(
  'assets/design_pages/settings_photo_scan_onboarding/app.html',
  'utf8',
);
const names = ['Model', 'Brand', 'Serial', 'FCC ID', 'IC'];
const keys = ['model', 'brand', 'serial', 'fccId', 'icId'];

function classes(initial = []) {
  const values = new Set(initial);
  return {
    contains(value) { return values.has(value); },
    add(value) { values.add(value); },
    remove(value) { values.delete(value); },
    toggle(value, force) {
      if (force) values.add(value);
      else values.delete(value);
    },
  };
}

function pageApi() {
  const chips = names.map((name, index) => {
    const icon = {textContent: '', style: {}};
    const label = {classList: classes()};
    return {
      dataset: {
        scanField: keys[index],
        foundLabel: `${name} found`,
        missingLabel: `${name} not found`,
      },
      classList: classes(),
      icon,
      label,
      attrs: {},
      setAttribute(key, value) { this.attrs[key] = value; },
      querySelector(selector) {
        return selector === '.material-symbols-outlined' ? icon : label;
      },
    };
  });
  const results = {
    classList: classes(['hidden']),
    querySelectorAll() { return chips; },
  };
  const window = {};
  const script = html.match(/window\.EnergyLensPhotoScanResults = \{[\s\S]*?\n  \};/)?.[0];
  assert.ok(script, 'scan result page API');
  vm.runInNewContext(script, {
    window,
    document: {getElementById: (id) => id === 'scan-results' ? results : null},
  });
  return {api: window.EnergyLensPhotoScanResults, results, chips};
}

test('Photo Scan guide uses approved sample, hint, and responsive button sizes', () => {
  assert.match(html, /id="sample-label"/);
  assert.match(html, /viewBox="0 0 320 196"[^>]*role="img"/);
  assert.match(html, /max-w-\[420px\] mx-auto h-auto/);
  assert.match(html, /aria-label="Sample appliance label\. Model, Serial, FCC ID and IC are highlighted\."/);
  for (const value of ['MODEL', 'AB-1234X', 'SERIAL', '0000000000',
    'FCC ID', 'XXX-0000', 'IC', '0000A-0000']) {
    assert.match(html, new RegExp(`>${value}</text>`));
  }
  assert.match(html, /Labels are usually on the back, side, or inside the door\. Shoot flat, with no glare\./);
  for (const id of ['014', '015']) {
    assert.match(html, new RegExp(`<button class="[^"]*min-h-12[^"]*"[^>]*data-el-action="settings_photo_scan_onboarding_action_${id}"`));
  }
  assert.match(html, /id="scan-results"/);
  assert.match(html, /aria-label="Scan results"/);
  assert.equal((html.match(/data-scan-field="/g) || []).length, 5);
});

test('all five scan-result chips expose found and not-found states', () => {
  const {api, results, chips} = pageApi();
  api.show({model: true, brand: false, serial: true, fccId: false, icId: true});
  assert.equal(results.classList.contains('hidden'), false);
  for (const [index, chip] of chips.entries()) {
    const found = index % 2 === 0;
    assert.equal(chip.dataset.found, String(found));
    assert.equal(chip.attrs['aria-label'], `${names[index]} ${found ? 'found' : 'not found'}`);
    assert.equal(chip.icon.textContent, found ? 'check_circle' : 'do_not_disturb_on');
    assert.equal(chip.classList.contains('bg-emerald-100'), found);
    assert.equal(chip.classList.contains('bg-surface-container-low'), !found);
  }
  api.show({});
  for (const [index, chip] of chips.entries()) {
    assert.equal(chip.attrs['aria-label'], `${names[index]} not found`);
  }
  api.clear();
  assert.equal(results.classList.contains('hidden'), true);
});
