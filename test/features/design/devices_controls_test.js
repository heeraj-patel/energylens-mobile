const assert = require('node:assert/strict');
const fs = require('node:fs');
const path = require('node:path');
const vm = require('node:vm');
const {test} = require('node:test');

class Element {
  constructor() {
    this.children = [];
    this.attributes = {};
    this.listeners = {};
    this.disabled = false;
    this.hidden = false;
    this.style = {display: ''};
    this.textContent = '';
    this.value = '';
  }
  addEventListener(type, listener) {
    (this.listeners[type] ||= []).push(listener);
  }
  dispatch(type, event = {}) {
    for (const listener of this.listeners[type] || []) listener(event);
  }
  click() { this.dispatch('click'); }
  appendChild(child) {
    this.children = this.children.filter(current => current !== child);
    this.children.push(child);
    return child;
  }
  replaceChildren(...children) { this.children = [...children]; }
  setAttribute(name, value) { this.attributes[name] = value; }
  hasAttribute(name) { return Object.hasOwn(this.attributes, name); }
  getAttribute(name) { return this.attributes[name] || null; }
}

function card(name, state, useful, waste) {
  const item = new Element();
  item.fields = [name, '', state, 'Useful:', useful, 'Waste:', waste]
    .map(textContent => ({textContent}));
  item.querySelectorAll = () => item.fields;
  return item;
}

function makePage(rows = defaultRows()) {
  const feed = new Element();
  const filter = new Element();
  filter.value = 'all';
  const sort = new Element();
  sort.value = 'waste';
  const summary = new Element();
  const pagination = new Element();
  const pageNumbers = new Element();
  const previous = new Element();
  const next = new Element();
  const elements = {
    'devices-feed': feed,
    'status-filter-select': filter,
    'sort-select': sort,
    'devices-pagination': pagination,
    'devices-page-numbers': pageNumbers,
    'devices-previous-page': previous,
    'devices-next-page': next
  };
  const document = {
    getElementById: id => elements[id] || null,
    querySelector: selector => selector.includes('devices_text_092') ? summary : null,
    createElement: () => new Element()
  };
  for (const item of rows) feed.appendChild(item);
  const script = fs.readFileSync(
    path.join(__dirname, '../../../assets/design_pages/devices/controls.js'), 'utf8');
  vm.runInNewContext(script, {document});
  const visible = () => feed.children.filter(item => !item.hidden)
    .map(item => item.fields?.[0].textContent || item.getAttribute('data-el-device-name'));
  return {feed, filter, sort, summary, pagination, pageNumbers, previous, next, visible};
}

function defaultRows() {
  return [
    card('A', 'Active', '$1.00', '$0.05'),
    card('B', 'Idle', '$0.10', '$0.30'),
    card('C', 'Offline', '$0.05', '$0.15'),
    card('D', 'Active', '$0.20', '$0.02'),
    card('E', 'Idle', '$0.08', '$0.10'),
    card('F', 'Offline', '$0.05', '$0.08'),
    card('G', 'Active', '$0.50', '$0.06'),
    card('H', 'Idle', '$0.10', '$0.03'),
    card('I', 'Offline', '$0.01', '$0.09'),
    card('J', 'Active', '$0.70', '$0.01')
  ];
}

function namedRows(count) {
  return Array.from({length: count}, (_, index) =>
    card('Device ' + String(index + 1).padStart(2, '0'), 'Active',
      '$0.10', '$' + String((index + 1) / 100).padStart(4, '0')));
}


test('uses the compact Devices range and pagination row', () => {
  const html = fs.readFileSync(
    path.join(__dirname, '../../../assets/design_pages/devices/app.html'), 'utf8');
  assert.match(html,
    /class="flex items-center justify-between w-full px-1">\s*<span class="font-label-md text-\[13px\][^>]*data-el-bind="devices_text_092"/);
  assert.match(html,
    /id="devices-pagination" class="flex items-center gap-1\.5">\s*<button id="devices-previous-page"[^>]*class="w-8 h-8/);
  assert.match(html,
    /id="devices-page-numbers" class="flex items-center gap-1"><\/div>/);
});

test('paginates more than two pages and exposes accessible page controls', () => {
  const page = makePage(namedRows(25));
  assert.equal(page.summary.textContent, 'Showing 1–10 of 25 devices');
  assert.deepEqual(page.visible(),
    Array.from({length: 10}, (_, index) => 'Device ' + String(25 - index).padStart(2, '0')));
  assert.equal(page.pagination.hidden, false);
  assert.equal(page.previous.disabled, true);
  assert.equal(page.next.disabled, false);
  assert.equal(page.previous.attributes['aria-label'], 'Previous page');
  assert.equal(page.next.attributes['aria-label'], 'Next page');
  assert.deepEqual(page.pageNumbers.children.map(button => button.textContent), ['1', '2', '3']);
  assert.equal(page.pageNumbers.children[0].attributes['aria-label'], 'Page 1');
  assert.equal(page.pageNumbers.children[0].attributes['aria-current'], 'page');

  page.next.click();
  assert.equal(page.summary.textContent, 'Showing 11–20 of 25 devices');
  assert.equal(page.pageNumbers.children[1].attributes['aria-current'], 'page');
  page.pageNumbers.children[2].click();
  assert.equal(page.summary.textContent, 'Showing 21–25 of 25 devices');
  assert.equal(page.next.disabled, true);
  page.previous.click();
  assert.equal(page.summary.textContent, 'Showing 11–20 of 25 devices');
});

test('keeps numbered pagination within the phone-width control row', () => {
  const page = makePage(namedRows(100));
  assert.deepEqual(page.pageNumbers.children.map(button => button.textContent),
    ['1', '2', '3', '4']);
  assert.ok(page.pageNumbers.children.every(button =>
    button.className.includes('w-8 h-8') &&
    button.className.includes('text-[12px]') &&
    button.attributes['aria-controls'] === 'devices-feed'));
  for (let index = 0; index < 5; index++) page.next.click();
  assert.equal(page.summary.textContent, 'Showing 51–60 of 100 devices');
  assert.deepEqual(page.pageNumbers.children.map(button => button.textContent),
    ['4', '5', '6', '7']);
});

test('sort and filter update count and reset to the first page', () => {
  const page = makePage([...namedRows(15), card('ZZ Offline', 'Offline', '$0.10', '$0.99')]);
  page.next.click();
  assert.equal(page.summary.textContent, 'Showing 11–16 of 16 devices');
  page.sort.value = 'name';
  page.sort.dispatch('change');
  assert.equal(page.summary.textContent, 'Showing 1–10 of 16 devices');
  page.filter.value = 'offline';
  page.filter.dispatch('change');
  assert.equal(page.summary.textContent, 'Showing 1–1 of 1 devices');
  assert.deepEqual(page.visible(), ['ZZ Offline']);
  assert.equal(page.pagination.hidden, false);
  assert.equal(page.previous.disabled, true);
  assert.equal(page.next.disabled, true);
});

test('Standalone filter separates unmonitored devices from Offline', () => {
  const html = fs.readFileSync(
    path.join(__dirname, '../../../assets/design_pages/devices/app.html'), 'utf8');
  assert.match(html, /<option value="standalone">Standalone<\/option>/);
  const page = makePage([
    ...namedRows(11),
    card('Standalone A', 'Standalone', '$0.20', '$0.80'),
    card('Standalone B', 'Standalone', '$0.10', '$0.10'),
    card('Disconnected', 'Offline', '$0.05', '$0.50')
  ]);
  page.next.click();
  page.filter.value = 'standalone';
  page.filter.dispatch('change');
  assert.equal(page.summary.textContent, 'Showing 1–2 of 2 devices');
  assert.deepEqual(page.visible(), ['Standalone A', 'Standalone B']);
  page.sort.value = 'name';
  page.sort.dispatch('change');
  assert.deepEqual(page.visible(), ['Standalone A', 'Standalone B']);
  page.filter.value = 'offline';
  page.filter.dispatch('change');
  assert.deepEqual(page.visible(), ['Disconnected']);
  page.filter.value = 'all';
  page.filter.dispatch('change');
  assert.equal(page.summary.textContent, 'Showing 1–10 of 14 devices');
  assert.equal(page.next.disabled, false);
});

test('shows zero range and hides pagination when filter has no matches', () => {
  const page = makePage([card('Idle', 'Idle', '$0.10', '$0.01')]);
  page.filter.value = 'active';
  page.filter.dispatch('change');
  assert.equal(page.summary.textContent, 'Showing 0–0 of 0 devices');
  assert.equal(page.pagination.hidden, true);
  assert.deepEqual(page.visible(), []);
});

test('unknown live devices remain in All, sort after known values, and reset on change', () => {
  const page = makePage(namedRows(10));
  const live = new Element();
  live.setAttribute('data-el-live-device-id', 'live-1');
  live.setAttribute('data-el-device-name', 'Live Device');
  page.feed.appendChild(live);
  page.feed.dispatch('energylens:devices-changed');
  assert.equal(page.summary.textContent, 'Showing 1–10 of 11 devices');
  assert.equal(page.next.disabled, false);
  page.next.click();
  assert.equal(page.summary.textContent, 'Showing 11–11 of 11 devices');
  assert.deepEqual(page.visible(), ['Live Device']);
  page.filter.value = 'active';
  page.filter.dispatch('change');
  assert.equal(page.summary.textContent, 'Showing 1–10 of 10 devices');
});

test('sorts positive sub-cent waste above zero', () => {
  const page = makePage([
    card('Zero', 'Active', '$0.10', '$0.00'),
    card('Tiny', 'Active', '$0.10', '<$0.01'),
    card('Big', 'Active', '$0.10', '$0.30')
  ]);
  assert.deepEqual(page.visible(), ['Big', 'Tiny', 'Zero']);
});
