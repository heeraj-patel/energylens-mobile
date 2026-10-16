import 'dart:convert';

import '../discovery/discovery_api.dart';

/// A separate Hub projection for functional local pilot Settings pages.
class LocalSettingsDevicesRenderer {
  const LocalSettingsDevicesRenderer();

  static const _key = '__energyLensLocalSettingsDevices';

  String installationScript({
    required String identity,
    required int generation,
  }) {
    final payload = _encode({'identity': identity, 'generation': generation});
    return '''
(() => {
  const scope = JSON.parse(new TextDecoder().decode(Uint8Array.from(atob('$payload'), c => c.charCodeAt(0))));
  const list = document.getElementById('monitored-device-list');
  if (!list) return false;
  scope.fallbackRows = window.$_key?.fallbackRows ?? Array.from(list.children, row => row.cloneNode(true));
  for (const row of scope.fallbackRows) {
    for (const button of row.querySelectorAll('button')) button.remove();
  }
  window.$_key = scope;
  list.replaceChildren(...scope.fallbackRows.map(row => row.cloneNode(true)));
  const count = document.getElementById('configured-count');
  if (count) count.textContent = '';
  const circuit = count?.closest('h2')?.parentElement?.nextElementSibling;
  if (circuit) circuit.hidden = true;
  for (const save of document.querySelectorAll('button[data-el-action\$="_action_020"]')) save.disabled = true;
  for (const node of document.querySelectorAll('[onclick^="removeDevice("]')) node.removeAttribute('onclick');
  return true;
})()
''';
  }

  String updateScript({
    required String identity,
    required int generation,
    required List<SavedAppliance> appliances,
    List<NearbySavedDevice> protocolDevices = const [],
    List<SavedPlug> savedPlugs = const [],
  }) {
    final ids = <int>{};
    final protocolIds = <String>{};
    final rows = <Map<String, Object?>>[];
    for (final row in appliances) {
      if (row.id <= 0) throw const FormatException('Invalid Hub appliance ID');
      if (!ids.add(row.id)) continue;
      rows.add({
        'id': row.id,
        'protocolId': null,
        'name': row.name,
        'manufacturer': row.manufacturer,
        'model': row.model,
        'removable':
            row.onboardingMethod == 'manual' || row.onboardingMethod == 'photo',
      });
    }
    for (final plug in savedPlugs) {
      if (plug.id.isEmpty) {
        throw const FormatException('Invalid Hub plug ID');
      }
      if (!protocolIds.add(plug.id)) continue;
      rows.add({
        'id': null,
        'protocolId': plug.id,
        'name': plug.name.trim().isEmpty ? 'Unnamed device' : plug.name,
        'manufacturer': '',
        'model': plug.model,
        'removable': false,
      });
    }
    for (final device in protocolDevices) {
      if (device.id.isEmpty) {
        throw const FormatException('Invalid Hub device ID');
      }
      if (!protocolIds.add(device.id)) continue;
      rows.add({
        'id': null,
        'protocolId': device.id,
        'name': device.name.trim().isEmpty ? 'Unnamed device' : device.name,
        'manufacturer': device.manufacturer ?? '',
        'model': device.model ?? '',
        'removable': false,
      });
    }
    final payload = _encode({
      'identity': identity,
      'generation': generation,
      'rows': rows,
    });
    return '''
(() => {
  const data = JSON.parse(new TextDecoder().decode(Uint8Array.from(atob('$payload'), c => c.charCodeAt(0))));
  const scope = window.$_key;
  if (!scope || scope.identity !== data.identity || scope.generation !== data.generation) return false;
  const list = document.getElementById('monitored-device-list');
  if (!list) return false;
  const cards = [];
  for (const row of data.rows) {
    if (!((Number.isSafeInteger(row.id) && row.id > 0 && row.protocolId === null) ||
          (row.id === null && typeof row.protocolId === 'string' && row.protocolId.length > 0)) ||
        typeof row.name !== 'string' || typeof row.manufacturer !== 'string' ||
        typeof row.model !== 'string' || typeof row.removable !== 'boolean') return false;
    const card = document.createElement('div');
    card.className = 'p-3 rounded-lg bg-surface-container-low/50 border border-outline-variant/20 flex items-center gap-3';
    card.setAttribute(row.protocolId === null ? 'data-el-local-appliance-id' : 'data-el-local-protocol-device-id',
      row.protocolId === null ? String(row.id) : row.protocolId);
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
    const detail = document.createElement('p');
    detail.className = 'text-[11px] font-body-md text-on-surface-variant truncate';
    detail.textContent = [row.manufacturer, row.model].filter(Boolean).join(' ');
    labels.append(name, detail);
    card.append(iconBox, labels);
    if (row.removable) {
      const remove = document.createElement('button');
      remove.type = 'button';
      remove.className = 'ml-auto shrink-0 w-11 h-11 rounded-lg flex items-center justify-center text-outline hover:text-error hover:bg-error-container/20 transition-colors';
      remove.setAttribute('aria-label', 'Remove ' + row.name);
      remove.setAttribute('data-el-delete-appliance-id', String(row.id));
      const removeIcon = document.createElement('span');
      removeIcon.className = 'material-symbols-outlined text-[18px]';
      removeIcon.textContent = 'delete_outline';
      remove.appendChild(removeIcon);
      card.appendChild(remove);
    }
    cards.push(card);
  }
  list.replaceChildren(...(cards.length ? cards : scope.fallbackRows.map(row => row.cloneNode(true))));
  const count = document.getElementById('configured-count');
  if (count) count.textContent = String(cards.length);
  for (const save of document.querySelectorAll('button[data-el-action\$="_action_020"]')) save.disabled = false;
  return true;
})()
''';
  }

  String _encode(Object value) => base64Encode(utf8.encode(jsonEncode(value)));
}
