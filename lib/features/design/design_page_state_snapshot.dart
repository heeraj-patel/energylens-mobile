import 'dart:convert';

import 'design_page_api.dart';

/// A bounded, home-scoped snapshot of transient state for one design page.
/// Passwords, numeric fields, and other non-text controls are never captured.
class DesignPageStateSnapshot {
  const DesignPageStateSnapshot({
    required this.homeId,
    required this.page,
    required this.scrollX,
    required this.scrollY,
    required this.fieldValues,
    required this.checkedActions,
    this.selectedTypeAction,
  });

  static const maxPayloadBytes = 8192;
  static const maxFieldCount = 24;
  static const maxValueLength = 512;

  final String homeId;
  final String page;
  final int scrollX;
  final int scrollY;
  final Map<String, String> fieldValues;
  final Map<String, bool> checkedActions;
  final String? selectedTypeAction;

  Map<String, Object?> toJson() => {
    'scroll_x': scrollX,
    'scroll_y': scrollY,
    'fields': fieldValues,
    'checks': checkedActions,
    if (selectedTypeAction != null) 'selected_type': selectedTypeAction,
  };

  factory DesignPageStateSnapshot.fromJson(
    String raw, {
    required String homeId,
    required String page,
  }) {
    if (homeId.isEmpty ||
        !designPageIds.contains(page) ||
        utf8.encode(raw).length > maxPayloadBytes) {
      throw const FormatException('Invalid design page state envelope');
    }
    final decoded = jsonDecode(raw);
    if (decoded is! Map<String, dynamic> ||
        decoded.keys.any(
          (key) => !{
            'scroll_x',
            'scroll_y',
            'fields',
            'checks',
            'selected_type',
          }.contains(key),
        )) {
      throw const FormatException('Invalid design page state');
    }
    final x = decoded['scroll_x'];
    final y = decoded['scroll_y'];
    final fields = decoded['fields'];
    final checks = decoded['checks'];
    final selectedType = decoded['selected_type'];
    if (x is! int ||
        y is! int ||
        x < 0 ||
        y < 0 ||
        x > 10000000 ||
        y > 10000000 ||
        fields is! Map<String, dynamic> ||
        checks is! Map<String, dynamic> ||
        fields.length > maxFieldCount ||
        checks.length > maxFieldCount ||
        (selectedType != null && selectedType is! String)) {
      throw const FormatException('Invalid design page state values');
    }
    final fieldPrefix = '${page}_field_';
    final parsedFields = <String, String>{};
    for (final entry in fields.entries) {
      if (!entry.key.startsWith(fieldPrefix) ||
          entry.value is! String ||
          (entry.value as String).length > maxValueLength) {
        throw const FormatException('Invalid design page text field');
      }
      parsedFields[entry.key] = entry.value as String;
    }
    final parsedChecks = <String, bool>{};
    for (final entry in checks.entries) {
      if ((!page.startsWith('tips_') && page != 'perks_tips') ||
          !entry.key.startsWith('${page}_action_') ||
          entry.value is! bool) {
        throw const FormatException('Invalid design page checkbox');
      }
      parsedChecks[entry.key] = entry.value as bool;
    }
    final validTypeAction =
        (page == 'settings_manage_devices' ||
            page == 'settings_manual_device_entry') &&
        selectedType is String &&
        RegExp('^${RegExp.escape(page)}_action_01[4-9]\$')
            .hasMatch(selectedType);
    if (selectedType != null && !validTypeAction) {
      throw const FormatException('Invalid selected device type');
    }
    final snapshot = DesignPageStateSnapshot(
      homeId: homeId,
      page: page,
      scrollX: x,
      scrollY: y,
      fieldValues: Map.unmodifiable(parsedFields),
      checkedActions: Map.unmodifiable(parsedChecks),
      selectedTypeAction: selectedType as String?,
    );
    if (utf8.encode(jsonEncode(snapshot.toJson())).length > maxPayloadBytes) {
      throw const FormatException('Design page state exceeds size limit');
    }
    return snapshot;
  }
}

/// Keeps snapshots only while the selected home stays the same.
class DesignPageStateSnapshotStore {
  String? _homeId;
  final Map<String, DesignPageStateSnapshot> _pages = {};

  void selectHome(String homeId) {
    if (homeId.isEmpty) throw ArgumentError.value(homeId, 'homeId');
    if (_homeId != homeId) _pages.clear();
    _homeId = homeId;
  }

  void save(DesignPageStateSnapshot snapshot) {
    if (_homeId != snapshot.homeId || !designPageIds.contains(snapshot.page)) {
      throw StateError('Snapshot home is not selected');
    }
    _pages[snapshot.page] = snapshot;
  }

  DesignPageStateSnapshot? forPage(String homeId, String page) =>
      _homeId == homeId ? _pages[page] : null;

  void clear() {
    _homeId = null;
    _pages.clear();
  }
}
