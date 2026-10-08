const assert = require('node:assert/strict');
const fs = require('node:fs');
const path = require('node:path');
const vm = require('node:vm');
const {test} = require('node:test');

class Element {
  constructor(action) {
    this.dataset = {elAction: action};
    this.children = [];
    this.attributes = {};
    this.listeners = {};
    this.classList = {toggle() {}};
    this.disabled = false;
    this.hidden = false;
    this.style = {display: ''};
    this.textContent = '';
  }
  addEventListener(type, listener) { this.listeners[type] = listener; }
  dispatch(type, event = {}) { this.listeners[type]?.(event); }
  click() {
    this.dispatch('click', {target: {closest: () => this}});
  }
  appendChild(child) { this.children.push(child); }
  querySelector(selector) {
    const match = selector.match(/devices_action_(\d{3})/);
    if (match) return this.buttons?.[Number(match[1])] || null;
    return this.badge || null;
  }
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

function makePage() {
  const feed = new Element();
  feed.appendChild = item => {
    feed.children = feed.children.filter(current => current !== item);
    feed.children.push(item);
  };
  const filters = new Element();
  const sorts = new Element();
  filters.buttons = {};
  sorts.buttons = {};
  const buttons = {};
  for (let number = 4; number <= 14; number++) {
    const button = new Element('devices_action_' + String(number).padStart(3, '0'));
    buttons[number] = button;
    if (number <= 7) {
      button.badge = new Element();
      filters.buttons[number] = button;
      button.addEventListener('click', () => {});
    } else if (number <= 10) sorts.buttons[number] = button;
  }
  const summary = new Element();
  const document = {
    getElementById(id) {
      return id === 'devices-feed' ? feed :
        id === 'status-filter-group' ? filters : id === 'sort-pill-group' ? sorts : null;
    },
    querySelector(selector) {
      if (selector.includes('devices_text_092')) return summary;
      const match = selector.match(/devices_action_(\d{3})/);
      return match ? buttons[Number(match[1])] : null;
    },
    createElement: () => new Element()
  };
  const rows = [
    card('A', 'Active', '$1.00', '$0.05'),
    card('B', 'Idle', '$0.10', '$0.30'),
    card('C', 'Standby', '$0.05', '$0.15'),
    card('D', 'Active', '$0.20', '$0.02'),
    card('E', 'Idle', '$0.08', '$0.10'),
    card('F', 'Standby', '$0.05', '$0.08'),
    card('G', 'Active', '$0.50', '$0.06'),
    card('H', 'Idle', '$0.10', '$0.03'),
    card('I', 'Standby', '$0.01', '$0.09'),
    card('J', 'Active', '$0.70', '$0.01')
  ];
  for (const row of rows) feed.appendChild(row);
  const script = fs.readFileSync(
    path.join(__dirname, '../../../assets/design_pages/devices/controls.js'), 'utf8');
  vm.runInNewContext(script, {document});
  const visible = () => feed.children.filter(item => !item.hidden)
    .map(item => item.fields?.[0].textContent || item.getAttribute('data-el-device-name'));
  const click = number => {
    const group = number <= 7 ? filters : number <= 10 ? sorts : buttons[number];
    if (number <= 10) group.dispatch('click',
      {target: {closest: () => buttons[number]}});
    else buttons[number].click();
  };
  return {feed, buttons, filters, summary, visible, click};
}

test('filters, sorts, and paginates the cards actually present', () => {
  const page = makePage();
  assert.equal(page.summary.textContent, 'Showing 1–5 of 10 devices');
  assert.deepEqual(page.visible(), ['B', 'C', 'E', 'I', 'F']);
  assert.equal(page.filters.buttons[4].badge.textContent, '10');
  assert.equal(page.filters.buttons[5].badge.textContent, '(4)');
  assert.equal(page.filters.buttons[6].badge.textContent, '(3)');
  assert.equal(page.filters.buttons[7].badge.textContent, '(3)');
  page.click(14);
  assert.equal(page.summary.textContent, 'Showing 6–10 of 10 devices');
  assert.deepEqual(page.visible(), ['G', 'A', 'H', 'D', 'J']);
  page.click(6);
  assert.equal(page.summary.textContent, 'Showing 1–3 of 3 devices');
  assert.deepEqual(page.visible(), ['B', 'E', 'H']);
  page.click(8);
  assert.deepEqual(page.visible(), ['B', 'E', 'H']);
});

test('live cards with unknown values stay in All and sort after known cost', () => {
  const page = makePage();
  const live = new Element();
  live.setAttribute('data-el-live-device-id', 'live-1');
  live.setAttribute('data-el-device-name', 'Live Device');
  page.feed.appendChild(live);
  page.feed.dispatch('energylens:devices-changed');
  assert.equal(page.filters.buttons[4].badge.textContent, '11');
  assert.equal(page.filters.buttons[5].badge.textContent, '(4)');
  page.click(8);
  page.click(14);
  page.click(14);
  assert.deepEqual(page.visible(), ['Live Device']);
});
