import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  test(
    'FAQ question toggles between plus/open-minus and collapses on close',
    () async {
      final node = Process.runSync('node', ['--version']);
      if (node.exitCode != 0) return;
      final source = File('assets/design_pages/shared/faq_answer_expander.js')
          .readAsStringSync();
      final result = await Process.run('node', [
        '-e',
        r'''
const assert = require('node:assert/strict');
const vm = require('node:vm');
const source = process.argv[1];
const classes = () => ({values:new Set(), add(value) { this.values.add(value); }, remove(value) { this.values.delete(value); }, toggle(value, force) { const on = force ?? !this.values.has(value); on ? this.values.add(value) : this.values.delete(value); return on; }, contains(value) { return this.values.has(value); }});
const icon = {textContent:'add', classList:classes()};
const answer = {classList:classes(), scrollHeight:30, clientHeight:100, nextElementSibling:null, after(row) { this.nextElementSibling = row; }, closest() { return panel; }, matches(selector) { return selector === '[data-faq-answer]'; }};
const panel = {id:'faq-answer', classList:classes(), querySelector(selector) { return selector === '[data-faq-answer]' ? answer : null; }};
panel.classList.add('hidden');
const trigger = {attrs:{'aria-controls':'faq-answer','aria-expanded':'false'}, setAttribute(key, value) { this.attrs[key] = value; }, getAttribute(key) { return this.attrs[key]; }, querySelector(selector) { return selector === '[data-faq-trigger-icon]' ? icon : null; }};
const listeners = {};
const document = {addEventListener(name, fn) { listeners[name] = fn; }, querySelectorAll(selector) { return selector === '[data-faq-answer]' ? [answer] : []; }, getElementById() { return panel; }, createElement(tag) { return {tag, className:'', hidden:false, attrs:{}, child:null, parentElement:null, setAttribute(key, value) { this.attrs[key] = value; }, getAttribute(key) { return this.attrs[key]; }, append(child) { this.child = child; child.parentElement = this; }, querySelector(selector) { return selector === '.faq-answer-expand' && this.child ? this.child : {textContent:'expand_more'}; }}; }};
const window = {addEventListener() {}};
const event = () => ({target:{closest(selector) { return selector === '[data-faq-trigger][aria-controls]' ? trigger : null; }}});
vm.runInNewContext(source, {document, window, requestAnimationFrame:fn => fn()});
listeners.click(event());
assert.equal(panel.classList.contains('hidden'), false);
assert.equal(trigger.getAttribute('aria-expanded'), 'true');
assert.equal(icon.textContent, 'remove');
listeners.click(event());
assert.equal(panel.classList.contains('hidden'), true);
assert.equal(trigger.getAttribute('aria-expanded'), 'false');
assert.equal(icon.textContent, 'add');
assert.equal(answer.classList.contains('faq-answer-collapsed'), true);
''',
        source,
      ]);
      expect(result.exitCode, 0, reason: '${result.stdout}\n${result.stderr}');
    },
  );

  for (final page in [
    'settings_manage_devices',
    'settings_manual_device_entry',
  ]) {
    test(
      '$page starts neutral and selects Auto Scan with its section on tap',
      () async {
        final node = Process.runSync('node', ['--version']);
        if (node.exitCode != 0) return;
        final source = File('assets/design_pages/$page/app.html')
            .readAsStringSync();
        final methodButtons = RegExp(
          r'<button\b[^>]*id="method-btn-(?:scan|camera|manual)"[^>]*>',
        ).allMatches(source).map((match) => match.group(0)!);
        expect(methodButtons, hasLength(3));
        for (final button in methodButtons) {
          final classes = RegExp(r'class="([^"]*)"')
              .firstMatch(button)!
              .group(1)!;
          expect(classes, isNot(contains('bg-white')));
          expect(classes, isNot(contains('border-primary')));
          expect(classes, isNot(contains('ring-2')));
        }
        final methodSections = RegExp(
          r'<div\b[^>]*id="section-(?:scan|camera|manual)"[^>]*>',
        ).allMatches(source).map((match) => match.group(0)!);
        expect(methodSections, hasLength(3));
        for (final section in methodSections) {
          expect(section, contains('hidden'));
        }
        final result = await Process.run('node', [
          '-e',
          r'''
const assert = require('node:assert/strict');
const vm = require('node:vm');
const source = process.argv[1];
const match = source.match(/function selectOnboardingMethod\(method\) \{[\s\S]*?\n  \}/);
assert.ok(match, 'page defines the method selection behavior');
const states = {};
function target(prefix, name) {
  const values = new Set();
  states[prefix + name] = values;
  return {classList:{toggle(value, on) { on ? values.add(value) : values.delete(value); }, contains(value) { return values.has(value); }}};
}
const nodes = {};
for (const name of ['scan','camera','manual']) {
  nodes['method-btn-' + name] = target('button:', name);
  nodes['section-' + name] = target('section:', name);
}
const document = {getElementById(id) { return nodes[id]; }};
vm.runInNewContext(match[0] + '; selectOnboardingMethod("scan");', {document});
assert.equal(states['button:scan'].has('bg-white'), true);
assert.equal(states['button:scan'].has('ring-2'), true);
assert.equal(states['section:scan'].has('hidden'), false);
for (const name of ['camera','manual']) {
  assert.equal(states['button:' + name].has('bg-white'), false);
  assert.equal(states['section:' + name].has('hidden'), true);
}
''',
          source,
        ]);
        expect(
          result.exitCode,
          0,
          reason: '${result.stdout}\n${result.stderr}',
        );
      },
    );
  }
}
