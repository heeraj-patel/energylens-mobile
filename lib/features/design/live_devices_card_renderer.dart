import 'dart:convert';

import 'live_devices_projection.dart';

/// Generates narrowly scoped DOM operations for the approved Devices asset.
/// Only the saved name is supplied by Cloud; it is assigned with textContent.
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
          {'id': row.applianceId, 'name': row.name},
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
  const existing = Array.from(feed.children).filter(node => node.hasAttribute('data-el-live-device-id'));
  const cards = [];
  for (const row of payload.rows) {
    if (typeof row.id !== 'string' || typeof row.name !== 'string') return false;
    const clone = template.cloneNode(true);
    const name = clone.querySelector('[data-el-bind="devices_text_022"]');
    if (!name) return false;
    for (const node of [clone, ...clone.querySelectorAll('[data-el-bind], [data-el-action], [id]')]) {
      node.removeAttribute('data-el-bind');
      node.removeAttribute('data-el-action');
      node.removeAttribute('id');
    }
    name.textContent = row.name;
    clone.setAttribute('data-el-live-device-id', row.id);
    clone.setAttribute('data-el-device-name', row.name);
    cards.push(clone);
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
