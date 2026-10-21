const assert = require('node:assert/strict');
const fs = require('node:fs');
const path = require('node:path');
const vm = require('node:vm');
const {test} = require('node:test');

class Element {
  constructor(id = '') {
    this.id = id;
    this.children = [];
    this.attributes = {};
    this.listeners = {};
    this.style = {display: ''};
    this.hidden = false;
    this.textContent = '';
  }
  appendChild(child) { child.parent = this; this.children.push(child); return child; }
  replaceChildren(...children) { this.children = children; }
  addEventListener(type, listener) { (this.listeners[type] ||= []).push(listener); }
  dispatch(type) {
    for (const listener of this.listeners[type] || []) listener();
    if (this.parent) this.parent.dispatch(type);
  }
  click() { this.dispatch('click'); }
  setAttribute(name, value) { this.attributes[name] = value; }
  querySelectorAll(selector) {
    const result = [];
    for (const child of this.children) {
      if (child.attributes[selector.slice(1, -1)] !== undefined) result.push(child);
      result.push(...child.querySelectorAll(selector));
    }
    return result;
  }
}

function page(packaged, live, care = false) {
  const feed = new Element(care ? 'tab-panel-upgrades' : 'tab-panel-efficiency');
  const groupA = feed.appendChild(new Element());
  const groupB = feed.appendChild(new Element());
  const liveGroup = feed.appendChild(new Element());
  for (const group of [groupA, groupB, liveGroup]) group.setAttribute('data-el-tip-group', '');
  const add = (group, count, prefix) => {
    for (let index = 0; index < count; index++) {
      const item = group.appendChild(new Element());
      item.textContent = prefix + index;
      item.setAttribute('data-el-tip-item', '');
    }
  };
  add(groupA, Math.ceil(packaged / 2), 'a');
  add(groupB, Math.floor(packaged / 2), 'b');
  add(liveGroup, live, 'live');
  const ids = {
    [feed.id]: feed,
    'tips-pagination-footer': new Element(),
    'tips-pagination-summary': new Element(),
    'tips-pagination': new Element(),
    'tips-page-numbers': new Element(),
    'tips-previous-page': new Element(),
    'tips-next-page': new Element(),
  };
  const document = {getElementById: id => ids[id] || null, createElement: () => new Element()};
  const context = {document, window: {}};
  for (const file of ['list_pagination.js', 'tips_pagination.js']) {
    const script = fs.readFileSync(path.join(__dirname, '../../../assets/design_pages/shared', file), 'utf8');
    vm.runInNewContext(script, context);
  }
  const visible = () => feed.querySelectorAll('[data-el-tip-item]')
    .filter(item => !item.hidden).map(item => item.textContent);
  return {feed, groupA, groupB, liveGroup, ids, visible, add};
}

test('keeps the full list visible through ten items', () => {
  for (const count of [0, 1, 10]) {
    const p = page(count, 0);
    assert.equal(p.visible().length, count);
    assert.equal(p.ids['tips-pagination-footer'].hidden, true);
  }
});

test('paginates packaged and live tips in original order with Devices controls', () => {
  const p = page(4, 21);
  const summary = p.ids['tips-pagination-summary'];
  const numbers = p.ids['tips-page-numbers'];
  const next = p.ids['tips-next-page'];
  const previous = p.ids['tips-previous-page'];
  assert.equal(summary.textContent, 'Showing 1–10 of 25');
  assert.deepEqual(p.visible(), ['a0', 'a1', 'b0', 'b1', ...Array.from({length: 6}, (_, i) => 'live' + i)]);
  assert.equal(previous.disabled, true);
  assert.equal(next.attributes['aria-controls'], 'tab-panel-efficiency');
  assert.equal(numbers.children[0].attributes['aria-current'], 'page');
  next.click();
  assert.equal(summary.textContent, 'Showing 11–20 of 25');
  assert.equal(p.visible().length, 10);
  assert.equal(p.groupA.hidden, true);
  numbers.children[2].click();
  assert.equal(summary.textContent, 'Showing 21–25 of 25');
  assert.deepEqual(p.visible(), ['live16', 'live17', 'live18', 'live19', 'live20']);
  assert.equal(next.disabled, true);
  previous.click();
  numbers.children[0].click();
  assert.equal(p.groupA.hidden, false);
});

test('recounts care tips on refresh and resets page', () => {
  const p = page(5, 15, true);
  const summary = p.ids['tips-pagination-summary'];
  p.ids['tips-next-page'].click();
  assert.equal(summary.textContent, 'Showing 11–20 of 20');
  p.liveGroup.replaceChildren();
  p.add(p.liveGroup, 6, 'new');
  p.liveGroup.dispatch('energylens:tips-changed');
  assert.equal(summary.textContent, 'Showing 1–10 of 11');
  assert.equal(p.visible().length, 10);
  p.liveGroup.replaceChildren();
  p.liveGroup.dispatch('energylens:tips-changed');
  assert.equal(p.visible().length, 5);
  assert.equal(p.ids['tips-pagination-footer'].hidden, true);
  assert.equal(p.groupA.hidden, false);
});

test('limits numbered controls to four across a long list', () => {
  const p = page(4, 96);
  for (let i = 0; i < 5; i++) p.ids['tips-next-page'].click();
  assert.equal(p.ids['tips-pagination-summary'].textContent, 'Showing 51–60 of 100');
  assert.deepEqual(p.ids['tips-page-numbers'].children.map(item => item.textContent), ['4', '5', '6', '7']);
  assert.ok(p.ids['tips-page-numbers'].children.every(item => item.attributes['aria-label'].startsWith('Page ')));
});
