import 'dart:convert';

import 'settings_domain_repository.dart';
import 'design_page_bridge.dart';

/// Applies authenticated identity fields to the approved Settings bindings.
/// The script accepts only the ticket installed for this Settings page load.
class SettingsIdentityRenderer {
  const SettingsIdentityRenderer();

  String? script({
    required DesignPageTicket ticket,
    required SettingsDomainSnapshot snapshot,
    required String expectedAccountId,
  }) {
    if (ticket.page != 'settings' ||
        snapshot.account.id != expectedAccountId ||
        snapshot.home.id != ticket.homeId ||
        !snapshot.homes.any((home) => home.id == ticket.homeId) ||
        snapshot.home.name.trim().isEmpty) {
      return null;
    }

    final email = _visibleValue(snapshot.email);
    final postalCode = _visibleValue(snapshot.postalCode);
    final payload = base64Encode(
      utf8.encode(
        jsonEncode({
          'homeId': ticket.homeId,
          'page': ticket.page,
          'generation': ticket.generation,
          'homeName': snapshot.home.name,
          'email': email,
          'postalCode': postalCode,
        }),
      ),
    );
    return '''
(() => {
  const payload = JSON.parse(new TextDecoder().decode(Uint8Array.from(atob('$payload'), c => c.charCodeAt(0))));
  const current = window.__energyLensTextBindingContext;
  if (!current || current.homeId !== payload.homeId || current.page !== payload.page || current.generation !== payload.generation) return false;
  const home = document.querySelectorAll('[data-el-bind="settings_text_010"]');
  const email = document.querySelectorAll('[data-el-bind="settings_text_016"]');
  const postal = document.querySelectorAll('[data-el-bind="settings_text_019"]');
  const emailRow = document.querySelectorAll('[data-el-settings-email-row]');
  const postalRow = document.querySelectorAll('[data-el-settings-postal-row]');
  if (home.length !== 1 || email.length !== 1 || postal.length !== 1 || emailRow.length !== 1 || postalRow.length !== 1) return false;
  home[0].textContent = payload.homeName;
  email[0].textContent = payload.email || '';
  postal[0].textContent = payload.postalCode || '';
  emailRow[0].hidden = !payload.email;
  postalRow[0].hidden = !payload.postalCode;
  return true;
})()
''';
  }
}

String? _visibleValue(String? value) {
  final trimmed = value?.trim();
  return trimmed == null || trimmed.isEmpty ? null : trimmed;
}
