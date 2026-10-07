import 'dart:convert';
import 'dart:io';

import 'package:energylens_mobile/features/design/design_page_bridge.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('approved ID bounds match the frozen binding map', () {
    final pages =
        (jsonDecode(
              File('docs/design_page_binding_map.json').readAsStringSync(),
            ) as Map<String, dynamic>)['pages']
            as Map<String, dynamic>;
    final gate = DesignPageRequestGate();
    final renderer = DesignTextBindingRenderer(gate);
    for (final entry in pages.entries) {
      final page = entry.key;
      final ids = ((entry.value as Map<String, dynamic>)['bindings'] as List)
          .cast<Map<String, dynamic>>()
          .map((item) => item['id'] as String)
          .toList();
      final ticket = gate.select('home_1', page);
      expect(
        renderer.updateScript(
          ticket,
          ids.map((id) => DesignTextBinding(id, 'safe')),
        ),
        isNotNull,
        reason: page,
      );
      expect(
        () => renderer.updateScript(ticket, [
          DesignTextBinding(
            '${page}_text_${(ids.length + 1).toString().padLeft(3, '0')}',
            'bad',
          ),
        ]),
        throwsArgumentError,
        reason: page,
      );
    }
  });

  test('rejects cross-page, malformed, and duplicate IDs', () {
    final gate = DesignPageRequestGate();
    final renderer = DesignTextBindingRenderer(gate);
    final ticket = gate.select('home_1', 'dashboard');
    for (final id in [
      'devices_text_001',
      'dashboard_action_001',
      'dashboard_text_000',
      'dashboard_text_44',
      'dashboard_text_044',
      'dashboard_text_001] [data-el-bind',
    ]) {
      expect(
        () => renderer.updateScript(ticket, [DesignTextBinding(id, 'x')]),
        throwsArgumentError,
        reason: id,
      );
    }
    expect(
      () => renderer.updateScript(ticket, const [
        DesignTextBinding('dashboard_text_006', 'one'),
        DesignTextBinding('dashboard_text_006', 'two'),
      ]),
      throwsArgumentError,
    );
  });

  test('navigation, home change, and clear invalidate queued scripts', () {
    final gate = DesignPageRequestGate();
    final renderer = DesignTextBindingRenderer(gate);
    final first = gate.select('home_1', 'dashboard');
    expect(renderer.installationScript(first), isNotNull);
    gate.select('home_1', 'devices');
    expect(renderer.installationScript(first), isNull);
    expect(renderer.updateScript(first, const []), isNull);
    final second = gate.select('home_2', 'dashboard');
    expect(renderer.updateScript(second, const []), isNotNull);
    gate.clear();
    expect(renderer.updateScript(second, const []), isNull);
  });

  test('encoded payload cannot become executable JavaScript', () {
    final gate = DesignPageRequestGate();
    final renderer = DesignTextBindingRenderer(gate);
    final ticket = gate.select('home_1', 'dashboard');
    const attack = '</script>\u2028\${evil()} <img onerror="evil()">';
    final script = renderer.updateScript(ticket, const [
      DesignTextBinding('dashboard_text_006', attack),
    ])!;
    expect(script, isNot(contains(attack)));
    expect(script, isNot(contains('innerHTML')));
    expect(script, contains('node.textContent = value'));
    final encoded = RegExp("atob\\('([^']+)'\\)").firstMatch(script)!.group(1)!;
    final payload = jsonDecode(utf8.decode(base64Decode(encoded))) as Map;
    expect((payload['bindings'] as List).single['text'], attack);
    expect(payload.keys, {'context', 'bindings'});
  });

  test('JavaScript preserves nested suffix and rejects stale page context', () {
    final nodeCheck = Process.runSync('node', ['--version']);
    if (nodeCheck.exitCode != 0) return;
    final gate = DesignPageRequestGate();
    final renderer = DesignTextBindingRenderer(gate);
    final ticket = gate.select('home_1', 'dashboard');
    final install = renderer.installationScript(ticket)!;
    final update = renderer.updateScript(ticket, const [
      DesignTextBinding('dashboard_text_006', r'$7.25'),
    ])!;
    final newerTicket = gate.select('home_2', 'dashboard');
    final newerInstall = renderer.installationScript(newerTicket)!;
    final testScript =
        '''
const value = {nodeType: 3, textContent: '\$6.96'};
const suffix = {nodeType: 1, textContent: '/day'};
const element = {
  childNodes: [value, suffix],
  getAttribute: name => name === 'data-el-bind' ? 'dashboard_text_006' : null,
};
let allElements = [];
const document = {
  querySelector: () => element,
  querySelectorAll: () => allElements,
};
const window = {};
const Node = {TEXT_NODE: 3};
const installed = eval(${jsonEncode(install)});
const missingRejected = eval(${jsonEncode(update)});
allElements = [element];
const applied = eval(${jsonEncode(update)});
const newerInstalled = eval(${jsonEncode(newerInstall)});
const oldInstallRejected = eval(${jsonEncode(install)});
const stale = eval(${jsonEncode(update)});
console.log(JSON.stringify({installed, missingRejected, applied, newerInstalled, oldInstallRejected, stale, value: value.textContent, suffix: suffix.textContent}));
''';
    final result = Process.runSync('node', ['-e', testScript]);
    expect(result.exitCode, 0, reason: result.stderr.toString());
    expect(jsonDecode(result.stdout as String), {
      'installed': true,
      'missingRejected': false,
      'applied': true,
      'newerInstalled': true,
      'oldInstallRejected': false,
      'stale': false,
      'value': r'$7.25',
      'suffix': '/day',
    });
  });
}
