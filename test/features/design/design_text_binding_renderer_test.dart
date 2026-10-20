import 'dart:convert';
import 'dart:io';

import 'package:energylens_mobile/features/design/design_page_bridge.dart';
import 'package:energylens_mobile/features/design/design_page_api.dart';
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

  test('dashboard home name is bound to the current selected home', () {
    final gate = DesignPageRequestGate();
    final renderer = DesignTextBindingRenderer(gate);
    final firstHome = gate.select('home_1', 'dashboard');
    const firstName = 'The Miller Home';
    final firstScript = renderer.updateScript(firstHome, const [
      DesignTextBinding('dashboard_text_001', firstName),
    ])!;
    final encoded = RegExp("atob\\('([^']+)'\\)")
        .firstMatch(firstScript)!
        .group(1)!;
    final payload = jsonDecode(utf8.decode(base64Decode(encoded))) as Map;
    expect(payload['context']['homeId'], 'home_1');
    expect((payload['bindings'] as List).single, {
      'id': 'dashboard_text_001',
      'text': firstName,
    });

    final secondHome = gate.select('home_2', 'dashboard');
    expect(
      renderer.updateScript(firstHome, const [
        DesignTextBinding('dashboard_text_001', firstName),
      ]),
      isNull,
    );
    final secondScript = renderer.updateScript(secondHome, const [
      DesignTextBinding('dashboard_text_001', 'Lake House'),
    ])!;
    final secondEncoded = RegExp("atob\\('([^']+)'\\)")
        .firstMatch(secondScript)!
        .group(1)!;
    final secondPayload =
        jsonDecode(utf8.decode(base64Decode(secondEncoded))) as Map;
    expect(secondPayload['context']['homeId'], 'home_2');
    expect((secondPayload['bindings'] as List).single['text'], 'Lake House');
  });

  test('selected home name binds every page header and Settings home row', () {
    final gate = DesignPageRequestGate();
    final renderer = DesignTextBindingRenderer(gate);
    for (final page in designPageIds) {
      final ticket = gate.select('home_1', page);
      final script = renderer.updateScript(
        ticket,
        selectedHomeNameBindings(page, 'Lake House'),
      )!;
      final encoded = RegExp("atob\\('([^']+)'\\)")
          .firstMatch(script)!
          .group(1)!;
      final payload = jsonDecode(utf8.decode(base64Decode(encoded))) as Map;
      final bindings = (payload['bindings'] as List).cast<Map>();
      expect(bindings.first, {'id': '${page}_text_001', 'text': 'Lake House'});
      expect(bindings.length, page == 'settings' ? 2 : 1, reason: page);
      if (page == 'settings') {
        expect(bindings.last, {
          'id': 'settings_text_010',
          'text': 'Lake House',
        });
      }
    }
    expect(
      () => selectedHomeNameBindings('unknown', 'Lake House'),
      throwsArgumentError,
    );
  });

  test('selected home also binds the initially empty Settings home row', () {
    final nodeCheck = Process.runSync('node', ['--version']);
    if (nodeCheck.exitCode != 0) return;
    final gate = DesignPageRequestGate();
    final renderer = DesignTextBindingRenderer(gate);
    final ticket = gate.select('home_1', 'settings');
    final install = renderer.installationScript(ticket)!;
    final update = renderer.updateScript(
      ticket,
      selectedHomeNameBindings('settings', 'Lake House'),
    )!;
    final testScript =
        '''
const label = {nodeType: 3, textContent: 'The Miller Home'};
const header = {
  childNodes: [label],
  getAttribute: name => name === 'data-el-bind' ? 'settings_text_001' : null,
};
const home = {
  childNodes: [],
  textContent: '',
  getAttribute: name => name === 'data-el-bind' ? 'settings_text_010' : null,
};
const document = {
  querySelector: () => header,
  querySelectorAll: () => [header, home],
};
const window = {};
const Node = {TEXT_NODE: 3};
const installed = eval(${jsonEncode(install)});
const applied = eval(${jsonEncode(update)});
console.log(JSON.stringify({installed, applied, header: label.textContent, home: home.textContent}));
''';
    final result = Process.runSync('node', ['-e', testScript]);
    expect(result.exitCode, 0, reason: result.stderr.toString());
    expect(jsonDecode(result.stdout as String), {
      'installed': true,
      'applied': true,
      'header': 'Lake House',
      'home': 'Lake House',
    });
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
const fallbackValue = {nodeType: 3, textContent: '\$2.88'};
const fallbackSuffix = {nodeType: 1, textContent: '/day'};
const fallbackElement = {
  childNodes: [fallbackValue, fallbackSuffix],
  getAttribute: name => name === 'data-el-bind' ? 'dashboard_text_009' : null,
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
allElements = [element, fallbackElement];
const applied = eval(${jsonEncode(update)});
const newerInstalled = eval(${jsonEncode(newerInstall)});
const oldInstallRejected = eval(${jsonEncode(install)});
const stale = eval(${jsonEncode(update)});
console.log(JSON.stringify({installed, missingRejected, applied, newerInstalled, oldInstallRejected, stale, value: value.textContent, suffix: suffix.textContent, fallbackValue: fallbackValue.textContent, fallbackSuffix: fallbackSuffix.textContent}));
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
      'fallbackValue': r'$2.88',
      'fallbackSuffix': '/day',
    });
  });
}
