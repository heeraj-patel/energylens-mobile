import 'dart:convert';
import 'dart:io';

import 'package:energylens_mobile/core/cloud_api/cloud_appliance.dart';
import 'package:energylens_mobile/features/design/settings_saved_devices_renderer.dart';
import 'package:energylens_mobile/features/design/cloud_saved_plug_inventory.dart';
import 'package:flutter_test/flutter_test.dart';

const homeA = '11111111-1111-4111-8111-111111111111';
const homeB = '22222222-2222-4222-8222-222222222222';

CloudAppliance appliance(
  String id, {
  String home = homeA,
  String name = 'Kitchen Refrigerator',
  String brand = 'Acme',
  String model = 'F100',
  DateTime? archivedAt,
  String? demoDeviceId,
}) => CloudAppliance(
  id: id,
  homeId: home,
  name: name,
  category: 'refrigerator',
  room: null,
  brand: brand,
  fullModel: model,
  fuel: 'electric',
  matchQuality: 'confirmed_exact',
  archivedAt: archivedAt,
  demoDeviceId: demoDeviceId,
);

Map<String, dynamic> payloadOf(String script) {
  final encoded = RegExp("atob\\('([^']+)'\\)").firstMatch(script)!.group(1)!;
  return jsonDecode(utf8.decode(base64Decode(encoded))) as Map<String, dynamic>;
}

void main() {
  const renderer = SettingsSavedDevicesRenderer();

  test('all three device-entry assets expose the existing list', () async {
    for (final page in [
      'settings_manage_devices',
      'settings_manual_device_entry',
      'settings_photo_scan_onboarding',
    ]) {
      final html = await File('assets/design_pages/$page/app.html')
          .readAsString();
      expect(html, contains('id="monitored-device-list"'));
    }
  });

  test('encodes owner-scoped rows once and leaves source text as data', () {
    const attack = '<img src=x onerror=alert(1)> ${r'$'}{evil}';
    final script = renderer.appendScript(
      homeId: homeA,
      generation: 4,
      appliances: [
        appliance('one', name: attack, brand: 'A&B', model: 'M<1>'),
        appliance('one', name: 'Duplicate'),
        appliance('archived', archivedAt: DateTime.utc(2026)),
      ],
    );
    expect(payloadOf(script), {
      'homeId': homeA,
      'generation': 4,
      'rows': [
        {
          'id': 'one',
          'name': attack,
          'brand': 'A&B',
          'model': 'M<1>',
          'fuel': 'electric',
          'variant': '',
          'persisted': true,
          'editable': false,
        },
      ],
    });
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

    expect(
      script,
      contains(
        "identity.textContent = [row.brand, row.model].filter(Boolean).join(' ')",
      ),
    );
    expect(script, isNot(contains('innerHTML')));
    expect(script, contains("data-el-delete-appliance-id"));
    expect(
      script,
      contains("remove.setAttribute('aria-label', 'Remove ' + row.name)"),
    );
    expect(script, contains("removeIcon.textContent = 'delete_outline'"));
  });

  test('synthetic inventory rows never receive the archive action', () {
    final script = renderer.appendScript(
      homeId: homeA,
      generation: 5,
      appliances: [
        appliance(
          'demo-device-01',
          name: 'Demo refrigerator',
          demoDeviceId: 'demo-device-01',
        ),
      ],
    );
    expect(payloadOf(script)['rows'], [
      {
        'id': 'demo-device-01',
        'name': 'Demo refrigerator',
        'brand': 'Acme',
        'model': 'F100',
        'fuel': 'electric',
        'variant': '',
        'persisted': false,
        'editable': false,
      },
    ]);
    expect(script, contains('if (row.persisted)'));
    expect(script, contains("typeof row.persisted !== 'boolean'"));
  });

  test('saved Hub plugs reuse monitored cards without an archive action', () {
    final script = renderer.appendScript(
      homeId: homeA,
      generation: 6,
      appliances: const [],
      savedPlugs: const [
        CloudSavedPlug(
          id: 'hub-a|plug-8',
          name: 'Kitchehn Mixer Plug KS8',
          model: 'KS8',
        ),
        CloudSavedPlug(id: 'hub-a|plug-8', name: 'Duplicate', model: 'KS8'),
      ],
    );
    expect(payloadOf(script)['rows'], [
      {
        'id': 'hub-a|plug-8',
        'name': 'Kitchehn Mixer Plug KS8',
        'brand': '',
        'model': 'KS8',
        'fuel': '',
        'variant': '',
        'persisted': false,
        'editable': false,
        'plug': true,
      },
    ]);
    expect(script, contains("'data-el-saved-plug-id'"));
    expect(script, contains('list.replaceChildren(...cards)'));
    expect(script, contains('!row.plug &&'));
  });

  test('rejects cross-home rows and guards stale script generations', () {
    expect(
      () => renderer.appendScript(
        homeId: homeA,
        generation: 1,
        appliances: [appliance('other', home: homeB)],
      ),
      throwsFormatException,
    );
    final install = renderer.installationScript(homeId: homeA, generation: 2);
    final append = renderer.appendScript(
      homeId: homeA,
      generation: 2,
      appliances: const [],
    );
    expect(install, contains('current.generation >= expected.generation'));
    expect(append, contains('current.homeId !== payload.homeId'));
    expect(append, contains('current.generation !== payload.generation'));
    expect(append, contains('list.replaceChildren(...cards)'));
    expect(append, contains('count.textContent = String(cards.length)'));
    expect(append, contains('candidate.hasAttribute(field)'));
    expect(
      append,
      contains("candidate.getAttribute('data-el-model') === row.model"),
    );
  });

  test('edit action applies only to persisted appliance rows when enabled', () {
    final script = renderer.appendScript(
      homeId: homeA,
      generation: 7,
      allowIdentityEdit: true,
      appliances: [
        appliance('real'),
        appliance('demo', demoDeviceId: 'demo-device-01'),
      ],
      savedPlugs: const [CloudSavedPlug(id: 'plug', name: 'Plug', model: 'P1')],
    );
    final rows = payloadOf(script)['rows'] as List<dynamic>;
    expect(rows.map((row) => row['editable']), [true, false, false]);
    expect(script, contains("edit.textContent = 'Edit'"));
    expect(
      script,
      contains("edit.setAttribute('aria-label', 'Edit ' + row.name)"),
    );
    expect(
      script,
      contains("edit.setAttribute('data-el-edit-appliance-id', row.id)"),
    );
  });
}
