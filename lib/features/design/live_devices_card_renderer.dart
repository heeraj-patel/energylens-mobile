import 'dart:convert';

import 'live_devices_projection.dart';

/// Generates narrowly scoped DOM operations for the approved Devices asset.
/// Saved identity and Cloud costs are assigned with textContent.
class LiveDevicesCardRenderer {
  const LiveDevicesCardRenderer();

  static const _contextKey = '__energyLensLiveDevicesContext';

  String installationScript({required String homeId, required int generation}) {
    final context = _encode({'homeId': homeId, 'generation': generation});
    return '''
(() => {
  const expected = JSON.parse(new TextDecoder().decode(Uint8Array.from(atob('$context'), c => c.charCodeAt(0))));
  const feed = document.getElementById('devices-feed');
  const marker = feed?.querySelector('[data-el-bind="devices_text_022"]');
  const template = marker && Array.from(feed.children).find(card => card.contains(marker));
  if (!feed || !template) return false;
  const current = window.$_contextKey;
  if (current && current.generation >= expected.generation) return false;
  window.$_contextKey = expected;
  return true;
})()
''';
  }

  String appendScript({
    required LiveDevicesProjection projection,
    required int generation,
  }) {
    final payload = _encode({
      'homeId': projection.homeId,
      'generation': generation,
      'rows': [
        for (final row in projection.rows)
          {
            'id': row.applianceId,
            'name': row.name,
            'identity': '${row.manufacturer} ${row.model}'.trim(),
            'usageCost': row.usageCost,
            'usefulCost': row.usefulCost,
            'wasteCost': row.wasteCost,
            'state': row.state,
            'stateExpiresAt': row.stateExpiresAt?.millisecondsSinceEpoch,
          },
      ],
      'seededRows': [
        for (final row in projection.seededRows)
          {
            'id': row.deviceId,
            'name': row.name,
            'totalCost': row.totalCost,
            'usefulCost': row.usefulCost,
            'wasteCost': row.wasteCost,
          },
      ],
    });
    return '''
(() => {
  const payload = JSON.parse(new TextDecoder().decode(Uint8Array.from(atob('$payload'), c => c.charCodeAt(0))));
  const current = window.$_contextKey;
  if (!current || current.homeId !== payload.homeId || current.generation !== payload.generation) return false;
  const feed = document.getElementById('devices-feed');
  const marker = feed?.querySelector('[data-el-bind="devices_text_022"]');
  const template = marker && Array.from(feed.children).find(card => card.contains(marker));
  if (!feed || !template) return false;
  const existing = Array.from(feed.children).filter(node =>
    node.hasAttribute('data-el-live-device-id') || node.hasAttribute('data-el-seeded-device-id'));
  const cards = [];
  for (const row of payload.seededRows) {
    if (typeof row.id !== 'string' || typeof row.name !== 'string' ||
        typeof row.totalCost !== 'string' || typeof row.usefulCost !== 'string' ||
        typeof row.wasteCost !== 'string') return false;
    const clone = template.cloneNode(true);
    const name = clone.querySelector('[data-el-bind="devices_text_022"]');
    const identity = clone.querySelector('[data-el-bind="devices_text_023"]');
    const useful = clone.querySelector('[data-el-bind="devices_text_026"]');
    const waste = clone.querySelector('[data-el-bind="devices_text_028"]');
    if (!name || !identity || !useful || !waste) return false;
    for (const node of [clone, ...clone.querySelectorAll('[data-el-bind], [data-el-action], [id]')]) {
      node.removeAttribute('data-el-bind');
      node.removeAttribute('data-el-action');
      node.removeAttribute('id');
    }
    name.textContent = row.name;
    identity.textContent = '';
    clone.querySelector('.flex.flex-col.items-end')?.remove();
    const icon = clone.querySelector('.material-symbols-outlined');
    if (icon) icon.textContent = 'devices_other';
    useful.textContent = row.usefulCost;
    waste.textContent = row.wasteCost;
    clone.setAttribute('data-el-seeded-device-id', row.id);
    clone.setAttribute('data-el-device-name', row.name);
    clone.setAttribute('data-el-usage-cost', row.totalCost);
    clone.setAttribute('data-el-waste-cost', row.wasteCost);
    cards.push(clone);
  }
  for (const row of payload.rows) {
    if (typeof row.id !== 'string' || typeof row.name !== 'string' ||
        typeof row.identity !== 'string' ||
        (row.usageCost !== null && typeof row.usageCost !== 'string') ||
        (row.usefulCost !== null && typeof row.usefulCost !== 'string') ||
        (row.wasteCost !== null && typeof row.wasteCost !== 'string') ||
        (row.stateExpiresAt !== null && !Number.isSafeInteger(row.stateExpiresAt)) ||
        !['active', 'idle', 'offline', 'standalone'].includes(row.state)) return false;
    const clone = template.cloneNode(true);
    const name = clone.querySelector('[data-el-bind="devices_text_022"]');
    const identity = clone.querySelector('[data-el-bind="devices_text_023"]');
    const status = clone.querySelector('[data-el-bind="devices_text_024"]');
    const useful = clone.querySelector('[data-el-bind="devices_text_026"]');
    const waste = clone.querySelector('[data-el-bind="devices_text_028"]');
    const icon = clone.querySelector('.material-symbols-outlined');
    if (!name || !identity || !status || !useful || !waste || !icon) return false;
    for (const node of [clone, ...clone.querySelectorAll('[data-el-bind], [data-el-action], [id]')]) {
      node.removeAttribute('data-el-bind');
      node.removeAttribute('data-el-action');
      node.removeAttribute('id');
    }
    name.textContent = row.name;
    identity.textContent = row.identity;
    const expiresAt = row.stateExpiresAt;
    const initialState = (row.state === 'active' || row.state === 'idle') &&
      expiresAt !== null && expiresAt <= Date.now()
      ? 'offline' : row.state;
    const setState = state => {
    const stateText = state[0].toUpperCase() + state.slice(1);
    status.className = state === 'active'
      ? 'inline-flex items-center gap-1 px-2 py-0.5 rounded-full text-[10px] font-semibold bg-[#059669]/10 el-useful-ink border border-[#059669]/25'
      : state === 'idle'
      ? 'inline-flex items-center gap-1 px-2 py-0.5 rounded-full text-[10px] font-semibold bg-[#fffbeb] el-waste-ink border border-[#fde68a]'
      : 'inline-flex items-center gap-1 px-2 py-0.5 rounded-full text-[10px] font-semibold bg-surface-container-high text-on-surface-variant border border-outline-variant/50';
    const dot = document.createElement('span');
    dot.className = state === 'active' ? 'w-1 h-1 rounded-full bg-[#059669]'
      : state === 'idle' ? 'w-1 h-1 rounded-full bg-[#d97706]' : 'w-1 h-1 rounded-full bg-on-surface-variant';
    status.replaceChildren(dot, document.createTextNode(stateText));
    clone.setAttribute('data-el-device-state', state);
    };
    setState(initialState);
    useful.textContent = row.usefulCost ?? 'N/A';
    useful.classList.remove('text-[#059669]');
    useful.classList.remove('el-useful-ink');
    useful.classList.remove('text-on-surface-variant');
    const usefulAmount = row.usefulCost && Number(row.usefulCost.replace(/[^0-9.]/g, ''));
    useful.classList.add(usefulAmount > 0 ? 'el-useful-ink' : 'text-on-surface-variant');
    const wasteText = row.wasteCost;
    waste.textContent = wasteText ?? 'N/A';
    waste.classList.remove('text-[#d97706]');
    waste.classList.remove('el-waste-ink');
    waste.classList.remove('text-on-surface-variant');
    const wasteAmount = wasteText && (wasteText === '<\$0.01' ? 0.005 : Number(wasteText.replace(/[^0-9.]/g, '')));
    waste.classList.add(wasteAmount > 0 ? 'el-waste-ink' : 'text-on-surface-variant');
    icon.textContent = 'devices_other';
    clone.setAttribute('data-el-live-device-id', row.id);
    clone.setAttribute('data-el-device-name', row.name);
    if (row.usageCost !== null) clone.setAttribute('data-el-usage-cost', row.usageCost);
    if (wasteText !== null) clone.setAttribute('data-el-waste-cost', wasteText);
    cards.push(clone);
    if ((initialState === 'active' || initialState === 'idle') && expiresAt !== null) {
      const expire = () => {
        if (window.$_contextKey !== current || !clone.isConnected) return;
        const remaining = expiresAt - Date.now();
        if (remaining > 0) {
          setTimeout(expire, Math.min(remaining, 2147483647));
          return;
        }
        setState('offline');
        feed.dispatchEvent(new Event('energylens:devices-changed'));
      };
      setTimeout(expire, Math.max(0, expiresAt - Date.now()));
    }
  }
  for (const node of existing) node.remove();
  for (const card of cards) feed.appendChild(card);
  feed.dispatchEvent(new Event('energylens:devices-changed'));
  return true;
})()
''';
  }

  String _encode(Object payload) =>
      base64Encode(utf8.encode(jsonEncode(payload)));
}
