import 'dart:convert';

import 'package:energylens_mobile/features/design/local_settings_devices_renderer.dart';
import 'package:energylens_mobile/features/discovery/discovery_api.dart';
import 'package:flutter_test/flutter_test.dart';

SavedAppliance row(int id, {String method = 'manual', String name = 'Lamp'}) =>
    SavedAppliance(
      id: id,
      name: name,
      room: '',
      category: 'lighting',
      manufacturer: '',
      model: '',
      loadKind: 'appliance',
      onboardingMethod: method,
    );

Map<String, dynamic> payload(String script) {
  final encoded = RegExp("atob\\('([^']+)'\\)").firstMatch(script)!.group(1)!;
  return jsonDecode(utf8.decode(base64Decode(encoded))) as Map<String, dynamic>;
}

void main() {
  const renderer = LocalSettingsDevicesRenderer();

  test('install hides packaged rows, count, and circuit claim', () {
    final script = renderer.installationScript(
      identity: 'hub-a|1',
      generation: 3,
    );
    expect(payload(script), {'identity': 'hub-a|1', 'generation': 3});
    expect(script, contains('list.replaceChildren()'));
    expect(script, contains("count.textContent = ''"));
    expect(script, contains('circuit.hidden = true'));
    expect(script, contains("removeAttribute('onclick')"));
  });

  test('real rows are deduplicated and only manual/photo are removable', () {
    const attack = '<img src=x onerror=alert(1)>';
    final script = renderer.updateScript(
      identity: 'hub-a|1',
      generation: 3,
      appliances: [
        row(7, name: attack),
        row(7),
        row(8, method: 'photo'),
        row(9, method: 'discovered'),
      ],
    );
    final rows = payload(script)['rows'] as List<dynamic>;
    expect(rows.length, 3);
    expect(rows.map((row) => row['removable']), [true, true, false]);
    expect(script, isNot(contains(attack)));
    expect(script, contains('name.textContent = row.name'));
    final labelClasses = RegExp(r"labels.className = '([^']+)'")
        .firstMatch(script)!
        .group(1)!
        .split(' ');
    final deleteClasses = RegExp(r"remove.className = '([^']+)'")
        .firstMatch(script)!
        .group(1)!
        .split(' ');
    expect(labelClasses, containsAll(['min-w-0', 'flex-1']));
    expect(deleteClasses, containsAll(['ml-auto', 'shrink-0', 'w-11', 'h-11']));

    expect(script, contains('scope.identity !== data.identity'));
    expect(script, contains('scope.generation !== data.generation'));
    expect(script, contains('String(cards.length)'));
    expect(script, isNot(contains('innerHTML')));
  });

  test('invalid Hub ID cannot be projected', () {
    expect(
      () => renderer.updateScript(
        identity: 'hub-a|1',
        generation: 3,
        appliances: [row(0)],
      ),
      throwsFormatException,
    );
  });
}
