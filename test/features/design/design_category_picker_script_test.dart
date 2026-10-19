import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

import 'package:energylens_mobile/core/cloud_api/cloud_energy_categories.dart';
import 'package:energylens_mobile/features/design/design_category_picker_script.dart';

void main() {
  test('exposed picker uses every API type and supports keyboard and dismissal', () async {
    const categories = EnergyCategories(
      version: 9,
      etag: '"9"',
      groups: [
        EnergyCategoryGroup(
          key: 'first',
          label: 'First group',
          types: [EnergyCategoryType(key: 'first_type', label: 'First type')],
        ),
        EnergyCategoryGroup(
          key: 'new_server_group',
          label: 'New server group',
          types: [
            EnergyCategoryType(
              key: 'new_server_type',
              label: 'New server type',
            ),
            EnergyCategoryType(
              key: 'another_new_type',
              label: 'Another new type',
            ),
          ],
        ),
      ],
    );
    final file =
        await File(
          '${Directory.systemTemp.path}/energylens-picker-${DateTime.now().microsecondsSinceEpoch}.json',
        ).writeAsString(
          jsonEncode({'picker': buildDesignCategoryPickerScript(categories)}),
        );
    try {
      final result = await Process.run('node', [
        '-e',
        r'''
const assert = require('node:assert/strict');
const fs = require('node:fs');
const {picker} = JSON.parse(fs.readFileSync(process.argv[1], 'utf8'));

class Element {
  constructor(tag = 'div') {
    this.tag = tag; this.children = []; this.attrs = {}; this.dataset = {};
    this.listeners = {}; this.style = {}; this.value = ''; this.textContent = '';
    this.classes = new Set(); this.options = [];
    this.classList = {
      add: (name) => this.classes.add(name),
      remove: (name) => this.classes.delete(name),
      contains: (name) => this.classes.has(name),
      toggle: (name, force) => {
        const add = force === undefined ? !this.classes.has(name) : force;
        add ? this.classes.add(name) : this.classes.delete(name);
      },
    };
  }
  setAttribute(name, value) { this.attrs[name] = value; }
  getAttribute(name) { return this.attrs[name] ?? null; }
  removeAttribute(name) { delete this.attrs[name]; }
  addEventListener(name, fn) { (this.listeners[name] ||= []).push(fn); }
  fire(name, event = {}) { for (const fn of this.listeners[name] || []) fn(event); }
  replaceChildren(...children) {
    this.children = [...children]; this.options = [...children];
    if (this.tag === 'select') this.value = children[0]?.value || '';
  }
  add(child) { this.children.push(child); this.options.push(child); }
  append(child) { this.children.push(child); }
  querySelectorAll(selector) {
    if (selector === '[role="option"]') return this.children.filter((c) => c.attrs.role === 'option');
    return [];
  }
  closest(selector) {
    return selector === '[role="option"]' && this.attrs.role === 'option' ? this : null;
  }
  focus() { focused = this; }
  scrollIntoView() {}
  getBoundingClientRect() { return {top: 200, bottom: 248}; }
  get scrollHeight() { return this.children.length * 48; }
}
let focused;
const nodes = {
  'energy-category': new Element('select'), 'energy-type': new Element('select'),
  'dd-category': new Element('button'), 'dd-type': new Element('button'),
  'menu-category': new Element('ul'), 'menu-type': new Element('ul'),
  'dd-category-value': new Element('span'), 'dd-type-value': new Element('span'),
  'dd-category-icon': new Element('span'),
};
nodes['dd-category'].setAttribute('aria-disabled', 'true');
nodes['dd-category'].setAttribute('aria-expanded', 'false');
nodes['dd-type'].setAttribute('aria-disabled', 'true');
nodes['dd-type'].setAttribute('aria-expanded', 'false');
globalThis.Option = class { constructor(label, value) { this.label = label; this.value = value; } };
globalThis.window = {innerHeight: 844};
globalThis.getComputedStyle = () => ({maxHeight: '368px'});
globalThis.document = {
  getElementById(id) { return nodes[id] || null; },
  createElement(tag) { return new Element(tag); },
  querySelector() { return null; },
  listeners: {},
  addEventListener(name, fn) { (this.listeners[name] ||= []).push(fn); },
};
const key = (name) => ({key: name, preventDefault() {}});
assert.equal(eval(picker), true);
assert.equal(nodes['dd-category'].getAttribute('aria-disabled'), 'false');
assert.equal(nodes['dd-type'].getAttribute('aria-disabled'), 'true');
nodes['dd-category'].fire('keydown', key('ArrowDown'));
assert.equal(nodes['dd-category'].getAttribute('aria-expanded'), 'true');
nodes['dd-category'].fire('keydown', key('End'));
nodes['dd-category'].fire('keydown', key('Enter'));
assert.equal(nodes['energy-category'].value, 'new_server_group');
assert.equal(nodes['dd-category-value'].textContent, 'New server group');
assert.equal(nodes['dd-type'].getAttribute('aria-disabled'), 'false');
assert.equal(focused, nodes['dd-type']);
nodes['dd-type'].fire('click');
assert.deepEqual(nodes['menu-type'].children.map((row) => row.children[0].textContent),
  ['New server type', 'Another new type']);
nodes['dd-type'].fire('keydown', key('End'));
nodes['dd-type'].fire('keydown', key('Enter'));
assert.equal(nodes['energy-type'].value, 'another_new_type');
assert.equal(nodes['dd-type-value'].textContent, 'Another new type');
assert.equal(window.EnergyLensDevicePicker.dismiss(), false);
nodes['dd-type'].fire('click');
assert.equal(window.EnergyLensDevicePicker.dismiss(), true);
assert.equal(nodes['energy-type'].value, 'another_new_type');
nodes['dd-category'].fire('click');
nodes['dd-category'].fire('keydown', key('Escape'));
assert.equal(nodes['dd-category'].getAttribute('aria-expanded'), 'false');
nodes['dd-category'].fire('click');
for (const listener of document.listeners.click || []) {
  listener({target: {closest() { return null; }}});
}
assert.equal(nodes['dd-category'].getAttribute('aria-expanded'), 'false');
nodes['dd-category'].fire('click');
nodes['dd-category'].fire('keydown', key('Home'));
nodes['dd-category'].fire('keydown', key('Enter'));
assert.equal(nodes['energy-category'].value, 'first');
assert.equal(nodes['energy-type'].value, '');
assert.equal(nodes['dd-type-value'].textContent, 'Choose type');
''',
        file.path,
      ]);
      expect(result.exitCode, 0, reason: '${result.stdout}\n${result.stderr}');
    } finally {
      await file.delete();
    }
  });
}
