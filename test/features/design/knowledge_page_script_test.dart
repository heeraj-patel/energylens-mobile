import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:energylens_mobile/features/design/knowledge_page_script.dart';

void main() {
  test(
    'production renders all approved labels with fallback for missing evidence',
    () {
      final script = buildKnowledgePageScript();
      expect(RegExp('"id":').allMatches(script), hasLength(34));
      expect(script, contains('Power is how quickly electricity is used'));
      expect(script, contains('What is a kilowatt-hour?'));
      expect(script, contains('a program shown for my device?'));
      expect(script, contains("We can't answer this right now."));
      expect(script, contains('Outdoor heat peaked at 91°F'));
      expect(script, contains('Tier 1 off-peak pricing'));
      expect(script, contains('When are my peak-rate hours?'));
      expect(script, contains("existing.classList.remove('hidden')"));
    },
  );

  test(
    'answer updates only its accordion in the current home and page',
    () async {
      final script = buildKnowledgeAnswerScript(
        questionId: 'reduce_cost',
        answer: 'These options have supporting information.\n<source answer>',
        homeId: 'home-a',
        generation: 7,
      );
      final result = await Process.run('node', [
        '-e',
        r'''
const assert = require('node:assert/strict');
const vm = require('node:vm');
const script = JSON.parse(process.argv[1]);
const answers = {reduce_cost: {textContent:'fallback', style:{}}, high_use: {textContent:'other answer', style:{}}};
const triggers = Object.keys(answers).map(id => ({getAttribute: name => name === 'data-el-knowledge-id' ? id : id + '-panel'}));
const document = {
  querySelectorAll: () => triggers,
  getElementById: id => ({querySelector: () => answers[id.replace('-panel', '')]}),
};
const window = {__energyLensTextBindingContext: {homeId:'home-a', page:'tips_knowledge', generation:7}};
assert.equal(vm.runInNewContext(script, {document, window}), true);
assert.equal(answers.reduce_cost.textContent, 'These options have supporting information.\n<source answer>');
assert.equal(answers.reduce_cost.style.whiteSpace, 'pre-line');
assert.equal(answers.high_use.textContent, 'other answer');
window.__energyLensTextBindingContext.homeId = 'home-b';
assert.equal(vm.runInNewContext(script, {document, window}), false);
window.__energyLensTextBindingContext.homeId = 'home-a';
window.__energyLensTextBindingContext.generation = 8;
assert.equal(vm.runInNewContext(script, {document, window}), false);
''',
        jsonEncode(script),
      ]);
      expect(result.exitCode, 0, reason: '${result.stdout}\n${result.stderr}');
    },
  );

  test(
    'device cost question opens Devices while other questions request answers',
    () async {
      final result = await Process.run('node', [
        '-e',
        r'''
const assert = require('node:assert/strict');
const vm = require('node:vm');
const script = JSON.parse(process.argv[1]);
const nodes = {};
const list = {cards: [], listeners: {}, classList: {remove() {}}, append(card) { this.cards.push(card); }, addEventListener(name, fn) { this.listeners[name] = fn; }};
function cardFor(id) {
  const label = {classList:{remove() {}}, removeAttribute() {}, textContent:''};
  const answer = {removeAttribute() {}, textContent:''};
  const trigger = {attrs:{}, setAttribute(key, value) { this.attrs[key] = value; }, removeAttribute(key) { delete this.attrs[key]; }, getAttribute(key) { return this.attrs[key]; }, querySelector(selector) { return selector === '[data-el-bind]' ? label : null; }};
  const panel = {id, parentElement:null};
  const card = {parentElement:list, hidden:false, style:{}, cloneNode() { return cardFor('clone'); }, querySelector(selector) { return selector === '[id]' ? panel : selector === '[data-faq-trigger]' ? trigger : selector === '[data-faq-answer]' ? answer : null; }, querySelectorAll() { return []; }};
  panel.parentElement = card;
  nodes[id] = panel;
  card.trigger = trigger;
  return card;
}
for (let n = 1; n <= 3; n++) list.append(cardFor(`faq-${n}-content`));
const input = {value:'', addEventListener() {}};
const document = {querySelector: () => input, getElementById: id => nodes[id]};
const routes = [], answers = [];
const window = {EnergyLensNavigation:{postMessage: value => routes.push(value)}, EnergyLensKnowledge:{postMessage: value => answers.push(value)}};
assert.equal(vm.runInNewContext(script, {document, window, EnergyLensKnowledge:window.EnergyLensKnowledge}), true);
assert.equal(list.cards.length, 34);
function click(id) {
  const trigger = list.cards.map(card => card.trigger).find(node => node.getAttribute('data-el-knowledge-id') === id);
  assert.ok(trigger, id);
  const event = {target:{closest: () => trigger}, prevented:false, stopped:false, preventDefault() { this.prevented = true; }, stopPropagation() { this.stopped = true; }};
  list.listeners.click(event);
  return event;
}
const device = click('device_cost');
assert.deepEqual(routes, ['devices']);
assert.deepEqual(answers, []);
assert.equal(device.prevented, true);
assert.equal(device.stopped, true);
const general = click('reduce_cost');
assert.deepEqual(answers, ['reduce_cost']);
assert.equal(general.stopped, false);
''',
        jsonEncode(buildKnowledgePageScript()),
      ]);
      expect(result.exitCode, 0, reason: '${result.stdout}\n${result.stderr}');
    },
  );
}
