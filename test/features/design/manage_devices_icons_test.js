const test = require('node:test');
const assert = require('node:assert/strict');
const fs = require('node:fs');
const vm = require('node:vm');

const page = fs.readFileSync('assets/design_pages/settings_manage_devices/app.html', 'utf8');
const pathsSource = fs.readFileSync('assets/design_pages/shared/manage_devices_icon_paths.js', 'utf8');
const adapterSource = fs.readFileSync('assets/design_pages/shared/manage_devices_icon_fallback.js', 'utf8');

function fixture() {
  let observer;
  const icons = [];
  class Element {
    constructor(name, text = '') {
      this.name = name;
      this.value = text;
      this.children = [];
      this.attributes = {};
      this.parent = null;
      this.className = '';
      this.style = {};
      this.classList = {
        contains: (name) => this.className.split(' ').includes(name),
        add: (name) => { this.className = `${this.className} ${name}`.trim(); },
      };
    }
    get textContent() { return this.value + this.children.map((child) => child.textContent).join(''); }
    set textContent(value) { this.value = value; this.children = []; observer?.(); }
    setAttribute(name, value) { this.attributes[name] = value; }
    getAttribute(name) { return this.attributes[name] ?? null; }
    appendChild(child) { child.parent = this; this.children.push(child); observer?.(); }
    replaceChildren(...children) {
      this.value = '';
      this.children = children;
      children.forEach((child) => { child.parent = this; });
      observer?.();
    }
    replaceWith(replacement) {
      const siblings = this.parent.children;
      siblings[siblings.indexOf(this)] = replacement;
      replacement.parent = this.parent;
      observer?.();
    }
  }
  const document = {
    readyState: 'complete', body: new Element('body'),
    querySelectorAll: () => icons,
    createElement: (name) => new Element(name),
    createElementNS: (_, name) => new Element(name),
  };
  const window = {};
  const context = {document, window, MutationObserver: class {
    constructor(callback) { this.callback = callback; }
    observe() { observer = this.callback; }
  }, getComputedStyle: (node) => ({
    fontVariationSettings: node.fill || 'normal', fontWeight: node.weight || '400',
  }), queueMicrotask};
  vm.runInNewContext(pathsSource, context);
  const add = (token, attrs = {}) => {
    const host = new Element('span', token);
    host.className = 'material-symbols-outlined text-[20px]';
    host.attributes = {...attrs};
    icons.push(host);
    observer?.();
    return host;
  };
  const svg = (host) => host.children.find((child) => child.name === 'svg');
  return {add, svg, changed: () => observer?.(),
    start: () => vm.runInNewContext(adapterSource, context),
    paths: window.EnergyLensManageDevicesIconPaths};
}

test('Manage Devices alone loads local outlines after chrome mounts', () => {
  assert.match(page, /EnergyLensChrome\.mount\([\s\S]*?<script src="\.\.\/shared\/manage_devices_icon_paths\.js"><\/script><script src="\.\.\/shared\/manage_devices_icon_fallback\.js"><\/script>/);
  const manual = fs.readFileSync('assets/design_pages/settings_manual_device_entry/app.html', 'utf8');
  assert.doesNotMatch(manual, /manage_devices_icon_(paths|fallback)\.js/);
});

test('bundled outlines cover reported, Cloud, chrome, and category icons in both fill variants', () => {
  const {paths} = fixture();
  for (const token of ['tune', 'badge', 'radar', 'photo_camera', 'delete',
    'devices_other', 'delete_outline', 'bolt', 'person', 'space_dashboard',
    'devices', 'energy_savings_leaf', 'savings', 'settings', 'thermostat',
    'skillet', 'local_laundry_service', 'router', 'more_horiz', 'check']) {
    for (const weight of ['400', '700']) {
      assert.ok(paths.paths[weight]['0'][token], `${token} at ${weight}`);
      assert.ok(paths.paths[weight]['1'][token], `${token} filled at ${weight}`);
    }
  }
  assert.notEqual(paths.paths['400']['0'].badge, paths.paths['400']['1'].badge);
  assert.notEqual(paths.paths['400']['0'].settings, paths.paths['700']['0'].settings);
});

test('adapter keeps the original span, text, action attributes and accessibility while updating icons', async () => {
  const {add, svg, start} = fixture();
  const host = add('tune', {'data-el-action': 'settings_manage_devices_action_001', 'aria-hidden': 'true', id: 'tune-icon'});
  host.fill = "'FILL' 1";
  start();
  assert.equal(host.textContent, 'tune');
  assert.equal(host.getAttribute('id'), 'tune-icon');
  assert.equal(host.getAttribute('data-el-action'), 'settings_manage_devices_action_001');
  assert.equal(host.getAttribute('aria-hidden'), 'true');
  assert.equal(svg(host).getAttribute('aria-hidden'), 'true');
  assert.equal(svg(host).getAttribute('focusable'), 'false');
  assert.equal(svg(host).getAttribute('data-fill'), '1');
  assert.equal(svg(host).getAttribute('data-weight'), '400');
  const first = svg(host);
  await Promise.resolve();
  assert.equal(svg(host), first, 'mutation pass is idempotent');
  host.textContent = 'badge';
  await Promise.resolve();
  assert.equal(host.textContent, 'badge');
  assert.equal(svg(host).getAttribute('data-token'), 'badge');
  const cloudIcon = add('devices_other');
  await Promise.resolve();
  assert.equal(svg(cloudIcon).getAttribute('data-token'), 'devices_other');
  const categoryIcon = add('category');
  await Promise.resolve();
  categoryIcon.textContent = 'skillet';
  await Promise.resolve();
  assert.equal(svg(categoryIcon).getAttribute('data-token'), 'skillet');
  categoryIcon.textContent = 'unknown_token';
  await Promise.resolve();
  assert.equal(categoryIcon.textContent, 'unknown_token');
  assert.equal(svg(categoryIcon), undefined);
});

test('selected Settings icon uses the bundled 700 weight and follows weight changes', async () => {
  const {add, svg, changed, start, paths} = fixture();
  const settings = add('settings');
  settings.weight = '700';
  start();
  assert.equal(svg(settings).getAttribute('data-weight'), '700');
  assert.equal(svg(settings).children[0].getAttribute('d'), paths.paths['700']['0'].settings);
  settings.weight = '400';
  changed();
  await Promise.resolve();
  assert.equal(svg(settings).getAttribute('data-weight'), '400');
  assert.equal(svg(settings).children[0].getAttribute('d'), paths.paths['400']['0'].settings);
  settings.fill = "'wght' 700, 'FILL' 1";
  changed();
  await Promise.resolve();
  assert.equal(svg(settings).getAttribute('data-weight'), '700');
  assert.equal(svg(settings).getAttribute('data-fill'), '1');
});
