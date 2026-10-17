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
    bool localAuthSession = false,
  }) {
    if (ticket.page != 'settings' ||
        snapshot.account.id != expectedAccountId ||
        snapshot.home.id != ticket.homeId ||
        !snapshot.homes.any((home) => home.id == ticket.homeId) ||
        snapshot.home.name.trim().isEmpty) {
      return null;
    }

    final identity = _visibleValue(snapshot.identity);
    final postalCode = _visibleValue(snapshot.postalCode);
    final payload = base64Encode(
      utf8.encode(
        jsonEncode({
          'homeId': ticket.homeId,
          'page': ticket.page,
          'generation': ticket.generation,
          'homeName': snapshot.home.name,
          'ownerName': _visibleValue(snapshot.account.displayName),
          'identity': identity,
          'email': _visibleValue(snapshot.email),
          'identityLabel': snapshot.usernameIdentity ? 'Username' : 'Email ID',
          'usernameIdentity': snapshot.usernameIdentity,
          'postalCode': postalCode,
          'localAuthSession': localAuthSession,
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
  const identityLabel = document.querySelectorAll('[data-el-bind="settings_text_015"]');
  const postal = document.querySelectorAll('[data-el-bind="settings_text_019"]');
  const emailRow = document.querySelectorAll('[data-el-settings-email-row]');
  const postalRow = document.querySelectorAll('[data-el-settings-postal-row]');
  const editButtons = document.querySelectorAll('[data-el-settings-edit]');
  const owner = document.querySelectorAll('[data-el-settings-owner]')[0];
  const ownerRow = document.querySelectorAll('[data-el-settings-owner-row]')[0];
  const ownerEdit = document.querySelectorAll('[data-el-settings-owner-edit]')[0];
  const emailEdit = document.querySelectorAll('[data-el-settings-email-edit]')[0];
  const passwordChange = document.querySelectorAll('[data-el-settings-password-change]')[0];
  const setVisible = (element, visible) => {
    if (!element) return;
    element.hidden = !visible;
    if (visible) element.removeAttribute('hidden');
    else element.setAttribute('hidden', '');
  };
  if (home.length !== 1 || email.length !== 1 || postal.length !== 1 || emailRow.length !== 1 || postalRow.length !== 1 || editButtons.length !== 2) return false;
  home[0].textContent = payload.homeName;
  document.querySelectorAll('[data-el-bind="settings_text_001"]').forEach(node => node.textContent = payload.homeName);
  email[0].textContent = payload.identity || '';
  if (identityLabel.length === 1) identityLabel[0].textContent = payload.identityLabel;
  postal[0].textContent = payload.postalCode || '';
  emailRow[0].hidden = false;
  postalRow[0].hidden = false;
  editButtons.forEach(button => setVisible(button, true));
  if (owner && ownerRow && ownerEdit && emailEdit && passwordChange) {
    owner.textContent = payload.ownerName || '';
    setVisible(ownerRow, true);
    setVisible(ownerEdit, true);
    setVisible(emailEdit, Boolean(payload.identity && payload.localAuthSession && !payload.usernameIdentity));
    setVisible(passwordChange, Boolean(payload.localAuthSession));
  }
  return true;
})()
''';
  }
}

String? _visibleValue(String? value) {
  final trimmed = value?.trim();
  return trimmed == null || trimmed.isEmpty ? null : trimmed;
}
