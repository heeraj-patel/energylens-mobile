import 'dart:convert';

import 'design_page_api.dart';
import 'design_page_state_snapshot.dart';

/// Builds a read-only script returning bounded transient state as JSON.
String buildDesignPageStateCaptureScript(String page) {
  if (!designPageIds.contains(page)) throw ArgumentError.value(page, 'page');
  final pageJson = jsonEncode(page);
  return '''
    (() => {
      const page = $pageJson;
      const fields = {};
      const checks = {};
      document.querySelectorAll('input[data-el-field]')
        .forEach((element) => {
          const type = (element.type || '').toLowerCase();
          if (element.tagName === 'INPUT' && type !== 'text' && type !== 'search') return;
          const key = element.dataset.elField;
          if (key && key.startsWith(page + '_field_') && Object.keys(fields).length < 24) {
            fields[key] = String(element.value || '').slice(0, 512);
          }
        });
      if (page === 'perks_tips' || page.startsWith('tips_')) {
        document.querySelectorAll('input[type="checkbox"][data-el-action]')
          .forEach((element) => {
            const key = element.dataset.elAction;
            if (key && key.startsWith(page + '_action_') && Object.keys(checks).length < 24) {
              checks[key] = Boolean(element.checked);
            }
          });
      }
      let selectedType = null;
      if (page === 'settings_manage_devices' || page === 'settings_manual_device_entry') {
        selectedType = document.getElementById('energy-type')?.value || null;
      }
      return JSON.stringify({
        scroll_x: Math.max(0, Math.min(10000000, Math.round(window.scrollX || 0))),
        scroll_y: Math.max(0, Math.min(10000000, Math.round(window.scrollY || 0))),
        fields, checks,
        ...(selectedType ? {selected_type: selectedType} : {})
      });
    })()
  ''';
}

/// Builds a restore script for a validated snapshot. Restore dispatches input
/// and change events so each page's existing controls observe the restored state.
String buildDesignPageStateRestoreScript(DesignPageStateSnapshot snapshot) {
  if (!designPageIds.contains(snapshot.page) || snapshot.homeId.isEmpty) {
    throw ArgumentError('Invalid design page snapshot');
  }
  final stateJson = jsonEncode(snapshot.toJson());
  final pageJson = jsonEncode(snapshot.page);
  return '''
    (() => {
      const page = $pageJson;
      const state = $stateJson;
      const emit = (element) => {
        element.dispatchEvent(new Event('input', {bubbles: true}));
        element.dispatchEvent(new Event('change', {bubbles: true}));
      };
      const fields = state.fields || {};
      document.querySelectorAll('input[data-el-field]')
        .forEach((element) => {
          const type = (element.type || '').toLowerCase();
          if (element.tagName === 'INPUT' && type !== 'text' && type !== 'search') return;
          const key = element.dataset.elField;
          if (key && key.startsWith(page + '_field_') && Object.hasOwn(fields, key)) {
            element.value = fields[key];
            emit(element);
          }
        });
      if (page === 'perks_tips' || page.startsWith('tips_')) {
        const checks = state.checks || {};
        document.querySelectorAll('input[type="checkbox"][data-el-action]')
          .forEach((element) => {
            const key = element.dataset.elAction;
            if (key && key.startsWith(page + '_action_') && Object.hasOwn(checks, key)) {
              element.checked = checks[key] === true;
              emit(element);
            }
          });
      }
      if ((page === 'settings_manage_devices' || page === 'settings_manual_device_entry') && state.selected_type) {
        window.energyLensSelectType?.(state.selected_type);
      }
      window.scrollTo(state.scroll_x || 0, state.scroll_y || 0);
      return true;
    })()
  ''';
}
