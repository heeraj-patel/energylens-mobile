import 'dart:convert';

import '../../core/cloud_api/cloud_appliance.dart';
import 'cloud_saved_plug_inventory.dart';

/// Shows verified-home inventory on the Settings device-entry pages.
/// Packaged fallback rows remain only until a verified inventory is available.
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
    List<CloudSavedPlug> savedPlugs = const [],
    bool allowIdentityEdit = false,
  }) {
    final ids = <String>{};
    final rows = <Map<String, Object?>>[];
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
        'persisted': appliance.demoDeviceId == null,
        'editable': allowIdentityEdit && appliance.demoDeviceId == null,
      });
    }
    final plugIds = <String>{};
    for (final plug in savedPlugs) {
      if (plug.id.isEmpty || plug.name.trim().isEmpty) {
        throw const FormatException('Invalid Settings plug identity');
      }
      if (!plugIds.add(plug.id)) continue;
      rows.add({
        'id': plug.id,
        'name': plug.name,
        'brand': '',
        'model': plug.model,
        'fuel': '',
        'variant': '',
        'persisted': false,
        'editable': false,
        'plug': true,
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
        typeof row.fuel !== 'string' || typeof row.variant !== 'string' ||
        typeof row.persisted !== 'boolean' ||
        typeof row.editable !== 'boolean' ||
        (row.plug !== undefined && typeof row.plug !== 'boolean')) return false;
    const card = document.createElement('div');
    card.className = 'p-3 rounded-lg bg-surface-container-low/50 border border-outline-variant/20 flex items-center gap-3';
    card.setAttribute(row.plug ? 'data-el-saved-plug-id' : 'data-el-saved-appliance-id', row.id);
    const iconBox = document.createElement('div');
    iconBox.className = 'w-9 h-9 rounded-lg bg-secondary-container/40 flex items-center justify-center text-secondary shrink-0';
    const icon = document.createElement('span');
    icon.className = 'material-symbols-outlined text-[20px]';
    icon.textContent = 'devices_other';
    iconBox.appendChild(icon);
    const labels = document.createElement('div');
    labels.className = 'min-w-0 flex-1';
    const name = document.createElement('p');
    name.className = 'font-label-md text-label-md font-medium text-on-surface truncate';
    name.textContent = row.name;
    const identity = document.createElement('p');
    identity.className = 'text-[11px] font-body-md text-on-surface-variant truncate';
    identity.textContent = [row.brand, row.model].filter(Boolean).join(' ');
    labels.append(name, identity);
    card.append(iconBox, labels);
    if (row.editable) {
      const edit = document.createElement('button');
      edit.type = 'button';
      edit.className = 'shrink-0 min-w-11 min-h-11 px-2 rounded-lg font-label-md text-xs font-semibold text-primary';
      edit.textContent = 'Edit';
      edit.setAttribute('aria-label', 'Edit ' + row.name);
      edit.setAttribute('data-el-edit-appliance-id', row.id);
      card.appendChild(edit);
    }
    if (row.persisted) {
      const remove = document.createElement('button');
      remove.type = 'button';
      remove.className = 'ml-auto shrink-0 w-11 h-11 rounded-lg flex items-center justify-center text-outline hover:text-error hover:bg-error-container/20 transition-colors';
      remove.setAttribute('aria-label', 'Remove ' + row.name);
      remove.setAttribute('data-el-delete-appliance-id', row.id);
      const removeIcon = document.createElement('span');
      removeIcon.className = 'material-symbols-outlined text-[18px]';
      removeIcon.textContent = 'delete_outline';
      remove.appendChild(removeIcon);
      card.appendChild(remove);
    }
    cards.push(card);
  }
  list.replaceChildren(...cards);
  const count = document.getElementById('configured-count');
  if (count) count.textContent = String(cards.length);
  // A discovered candidate is removed only when all identity fields are
  // explicitly present and exactly equal to the saved inventory identity.
  for (const candidate of document.querySelectorAll('[data-el-discovered-candidate]')) {
    if (!['data-el-brand', 'data-el-model', 'data-el-fuel', 'data-el-variant']
        .every(field => candidate.hasAttribute(field))) continue;
    if (payload.rows.some(row => !row.plug &&
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
