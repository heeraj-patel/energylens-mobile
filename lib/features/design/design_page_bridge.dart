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

  bool accepts(DesignPageTicket ticket, DesignPageSnapshot response) =>
      ticket.generation == _generation &&
      ticket.homeId == _homeId &&
      ticket.page == _page &&
      response.homeId == _homeId &&
      response.page == _page;
}

class DesignPageTicket {
  const DesignPageTicket(this.homeId, this.page, this.generation);
  final String homeId;
  final String page;
  final int generation;
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
    if (utf8.encode(raw).length > maxMessageBytes) return null;
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
        !designPageIds.contains(expectedPage) ||
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
    } else if (target != null) {
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
