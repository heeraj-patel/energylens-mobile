import 'dart:convert';

import 'design_page_api.dart';

/// A response ticket is valid only for the home and page that requested it.
/// Navigation, sign-out, and home changes invalidate every outstanding ticket.
class DesignPageRequestGate {
  String? _homeId;
  String? _page;
  int _generation = 0;

  DesignPageTicket select(String homeId, String page) {
    if (homeId.isEmpty || !designPageIds.contains(page)) {
      throw ArgumentError('Invalid design page selection');
    }
    _homeId = homeId;
    _page = page;
    return DesignPageTicket(homeId, page, ++_generation);
  }

  void clear() {
    _homeId = null;
    _page = null;
    _generation++;
  }

  bool acceptsTicket(DesignPageTicket ticket) =>
      ticket.generation == _generation &&
      ticket.homeId == _homeId &&
      ticket.page == _page;

  bool accepts(DesignPageTicket ticket, DesignPageSnapshot response) =>
      acceptsTicket(ticket) &&
      response.homeId == _homeId &&
      response.page == _page;
}

class DesignPageTicket {
  const DesignPageTicket(this.homeId, this.page, this.generation);
  final String homeId;
  final String page;
  final int generation;
}

/// Only the approved home labels are populated from the selected Cloud home.
List<DesignTextBinding> selectedHomeNameBindings(String page, String homeName) {
  if (!designPageIds.contains(page)) {
    throw ArgumentError.value(page, 'page', 'Unknown design page');
  }
  return [
    DesignTextBinding('${page}_text_001', homeName),
    if (page == 'settings') DesignTextBinding('settings_text_010', homeName),
  ];
}

/// Narrow native message format. Action semantics remain disabled until each
/// control has an approved behavior; only navigation/report callbacks are known.
class DesignBridgeMessage {
  const DesignBridgeMessage({
    required this.homeId,
    required this.page,
    required this.action,
    this.entityId,
    this.targetPage,
  });

  final String homeId;
  final String page;
  final String action;
  final String? entityId;
  final String? targetPage;

  static const version = 1;
  static const maxMessageBytes = 4096;
  static const allowedActions = <String>{
    'navigate',
    'report_preview',
    'change_home',
    'sign_out',
  };

  static DesignBridgeMessage? parse(
    String raw, {
    required String expectedHomeId,
    required String expectedPage,
    required Set<String> ownedEntityIds,
  }) {
    if (expectedHomeId.isEmpty ||
        !designPageIds.contains(expectedPage) ||
        utf8.encode(raw).length > maxMessageBytes) {
      return null;
    }
    Object? decoded;
    try {
      decoded = jsonDecode(raw);
    } on FormatException {
      return null;
    }
    if (decoded is! Map<String, dynamic> ||
        decoded['version'] != version ||
        decoded['home_id'] != expectedHomeId ||
        decoded['page'] != expectedPage ||
        decoded['action'] is! String ||
        !allowedActions.contains(decoded['action']) ||
        decoded.keys.any(
          (key) => !{
            'version',
            'home_id',
            'page',
            'action',
            'entity_id',
            'target_page',
          }.contains(key),
        )) {
      return null;
    }
    final action = decoded['action'] as String;
    final entity = decoded['entity_id'];
    final target = decoded['target_page'];
    if (entity != null &&
        (entity is! String || !ownedEntityIds.contains(entity))) {
      return null;
    }
    if (action == 'navigate') {
      if (target is! String ||
          !designPageIds.contains(target) ||
          entity != null) {
        return null;
      }
    } else if (target != null || entity != null) {
      return null;
    }
    return DesignBridgeMessage(
      homeId: expectedHomeId,
      page: expectedPage,
      action: action,
      entityId: entity as String?,
      targetPage: target as String?,
    );
  }
}

/// A future renderer may map approved binding IDs to these text values. It
/// must assign textContent, never innerHTML, and may not fall back to assets.
class DesignTextBinding {
  const DesignTextBinding(this.id, this.text);
  final String id;
  final String text;

  Map<String, String> toJson() => {'id': id, 'text': text};
}

String encodeDesignTextBindings(Iterable<DesignTextBinding> bindings) {
  final ids = <String>{};
  final rows = <Map<String, String>>[];
  for (final binding in bindings) {
    if (!RegExp(r'^[a-z][a-z0-9_]{0,63}$').hasMatch(binding.id) ||
        !ids.add(binding.id) ||
        utf8.encode(binding.text).length > 8192) {
      throw ArgumentError('Invalid design text binding');
    }
    rows.add(binding.toJson());
  }
  return jsonEncode({'version': 1, 'bindings': rows});
}

/// Dormant protocol for a future WebView caller. The page's approved binding
/// counts are frozen in docs/design_page_binding_map.json. No credentials or
/// arbitrary JavaScript supplied by a response enter either script.
class DesignTextBindingRenderer {
  const DesignTextBindingRenderer(this.gate);

  final DesignPageRequestGate gate;

  static const _bindingCounts = <String, int>{
    'dashboard': 43,
    'devices': 102,
    'efficiency': 77,
    'efficiency_away': 73,
    'efficiency_habits': 55,
    'efficiency_peak_rates': 55,
    'perks_tips': 84,
    'settings': 62,
    'settings_manage_devices': 81,
    'settings_manual_device_entry': 81,
    'settings_photo_scan_onboarding': 90,
    'tips_care_upgrades': 34,
    'tips_efficiency': 29,
    'tips_knowledge': 21,
  };

  static const _contextKey = '__energyLensTextBindingContext';

  String? installationScript(DesignPageTicket ticket) {
    if (!gate.acceptsTicket(ticket)) return null;
    final context = _encodedContext(ticket);
    return '''
(() => {
  const context = JSON.parse(new TextDecoder().decode(Uint8Array.from(atob('$context'), c => c.charCodeAt(0))));
  const first = document.querySelector('[data-el-bind]');
  if (!first || !first.getAttribute('data-el-bind').startsWith(context.page + '_text_')) return false;
  const installed = window.$_contextKey;
  if (installed && installed.generation >= context.generation) return false;
  window.$_contextKey = context;
  return true;
})()
''';
  }

  /// Returns null if navigation, a home change, or sign-out superseded [ticket].
  /// The JavaScript repeats the context check because WebView calls may queue.
  String? updateScript(
    DesignPageTicket ticket,
    Iterable<DesignTextBinding> bindings,
  ) {
    if (!gate.acceptsTicket(ticket)) return null;
    final rows = bindings.toList(growable: false);
    final count = _bindingCounts[ticket.page];
    if (count == null || rows.length > count) {
      throw ArgumentError('Invalid design text binding count');
    }
    final ids = <String>{};
    for (final row in rows) {
      final match = RegExp('^${RegExp.escape(ticket.page)}_text_([0-9]{3})\$')
          .firstMatch(row.id);
      final ordinal = match == null ? null : int.tryParse(match.group(1)!);
      if (ordinal == null ||
          ordinal < 1 ||
          ordinal > count ||
          !ids.add(row.id)) {
        throw ArgumentError('Invalid design text binding ID');
      }
    }
    final payload = jsonEncode({
      'context': _context(ticket),
      'bindings': jsonDecode(encodeDesignTextBindings(rows))['bindings'],
    });
    if (utf8.encode(payload).length > 65536) {
      throw ArgumentError('Design text binding payload too large');
    }
    final encoded = base64Encode(utf8.encode(payload));
    return '''
(() => {
  const payload = JSON.parse(new TextDecoder().decode(Uint8Array.from(atob('$encoded'), c => c.charCodeAt(0))));
  const current = window.$_contextKey;
  const expected = payload.context;
  if (!current || current.homeId !== expected.homeId || current.page !== expected.page || current.generation !== expected.generation) return false;
  const first = document.querySelector('[data-el-bind]');
  if (!first || !first.getAttribute('data-el-bind').startsWith(expected.page + '_text_')) return false;
  const elements = Array.from(document.querySelectorAll('[data-el-bind]'));
  const targets = [];
  for (const row of payload.bindings) {
    const matches = elements.filter(node => node.getAttribute('data-el-bind') === row.id);
    if (matches.length !== 1) return false;
    const textNodes = Array.from(matches[0].childNodes).filter(node => node.nodeType === Node.TEXT_NODE);
    if (textNodes.length !== 1) return false;
    targets.push([textNodes[0], row.text]);
  }
  for (const [node, value] of targets) node.textContent = value;
  return true;
})()
''';
  }

  Map<String, Object> _context(DesignPageTicket ticket) => {
    'homeId': ticket.homeId,
    'page': ticket.page,
    'generation': ticket.generation,
  };

  String _encodedContext(DesignPageTicket ticket) =>
      base64Encode(utf8.encode(jsonEncode(_context(ticket))));
}
