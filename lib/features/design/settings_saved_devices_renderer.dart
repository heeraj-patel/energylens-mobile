import 'dart:convert';

import '../../core/cloud_api/cloud_appliance.dart';

/// Adds verified-home inventory to the three Settings device-entry assets.
/// The packaged rows stay intact; appended rows make no telemetry claim.
class SettingsSavedDevicesRenderer {
  const SettingsSavedDevicesRenderer();

  static const _contextKey = '__energyLensSettingsSavedDevicesContext';

  String installationScript({required String homeId, required int generation}) {
    final context = _encode({'homeId': homeId, 'generation': generation});
    return '''
(() => {
  const expected = JSON.parse(new TextDecoder().decode(Uint8Array.from(atob('$context'), c => c.charCodeAt(0))));
  if (!document.getElementById('monitored-device-list')) return false;
  const current = window.$_contextKey;
  if (current && current.generation >= expected.generation) return false;
  window.$_contextKey = expected;
  return true;
})()
''';
  }

  String appendScript({
    required String homeId,
    required int generation,
    required List<CloudAppliance> appliances,
  }) {
    final ids = <String>{};
    final rows = <Map<String, String>>[];
    for (final appliance in appliances) {
      if (appliance.homeId.toLowerCase() != homeId.toLowerCase()) {
        throw const FormatException(
          'Settings appliance belongs to another home',
        );
      }
      if (appliance.archivedAt != null) continue;
      if (appliance.id.isEmpty || appliance.name.trim().isEmpty) {
        throw const FormatException('Invalid Settings appliance identity');
      }
      if (!ids.add(appliance.id)) continue;
      rows.add({
        'id': appliance.id,
        'name': appliance.name,
        'brand': appliance.brand,
        'model': appliance.fullModel,
        'fuel': appliance.fuel,
        'variant': appliance.variant ?? '',
      });
    }
    final payload = _encode({
      'homeId': homeId,
      'generation': generation,
      'rows': rows,
    });
    return '''
(() => {
  const payload = JSON.parse(new TextDecoder().decode(Uint8Array.from(atob('$payload'), c => c.charCodeAt(0))));
  const current = window.$_contextKey;
  if (!current || current.homeId !== payload.homeId || current.generation !== payload.generation) return false;
  const list = document.getElementById('monitored-device-list');
  if (!list) return false;
  const cards = [];
  for (const row of payload.rows) {
    if (typeof row.id !== 'string' || typeof row.name !== 'string' ||
        typeof row.brand !== 'string' || typeof row.model !== 'string' ||
        typeof row.fuel !== 'string' || typeof row.variant !== 'string') return false;
    const card = document.createElement('div');
    card.className = 'p-3 rounded-lg bg-surface-container-low/50 border border-outline-variant/20 flex items-center gap-3';
    card.setAttribute('data-el-saved-appliance-id', row.id);
    const iconBox = document.createElement('div');
    iconBox.className = 'w-9 h-9 rounded-lg bg-secondary-container/40 flex items-center justify-center text-secondary shrink-0';
    const icon = document.createElement('span');
    icon.className = 'material-symbols-outlined text-[20px]';
    icon.textContent = 'devices_other';
    iconBox.appendChild(icon);
    const labels = document.createElement('div');
    labels.className = 'min-w-0';
    const name = document.createElement('p');
    name.className = 'font-label-md text-label-md font-medium text-on-surface truncate';
    name.textContent = row.name;
    const identity = document.createElement('p');
    identity.className = 'text-[11px] font-body-md text-on-surface-variant truncate';
    identity.textContent = [row.brand, row.model].filter(Boolean).join(' ');
    labels.append(name, identity);
    card.append(iconBox, labels);
    cards.push(card);
  }
  for (const card of list.querySelectorAll('[data-el-saved-appliance-id]')) card.remove();
  for (const card of cards) list.appendChild(card);
  const count = document.getElementById('configured-count');
  if (count) count.textContent = String(list.children.length);
  // A discovered candidate is removed only when all identity fields are
  // explicitly present and exactly equal to the saved inventory identity.
  for (const candidate of document.querySelectorAll('[data-el-discovered-candidate]')) {
    if (!['data-el-brand', 'data-el-model', 'data-el-fuel', 'data-el-variant']
        .every(field => candidate.hasAttribute(field))) continue;
    if (payload.rows.some(row =>
        candidate.getAttribute('data-el-brand') === row.brand &&
        candidate.getAttribute('data-el-model') === row.model &&
        candidate.getAttribute('data-el-fuel') === row.fuel &&
        candidate.getAttribute('data-el-variant') === row.variant)) candidate.remove();
  }
  return true;
})()
''';
  }

  String _encode(Object payload) =>
      base64Encode(utf8.encode(jsonEncode(payload)));
}
