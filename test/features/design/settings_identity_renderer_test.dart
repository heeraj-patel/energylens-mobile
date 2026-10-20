import 'dart:convert';
import 'dart:io';

import 'package:energylens_mobile/core/cloud_api/cloud_api_client.dart';
import 'package:energylens_mobile/core/cloud_api/cloud_home.dart';
import 'package:energylens_mobile/core/cloud_api/cloud_preferences.dart';
import 'package:energylens_mobile/features/design/design_page_bridge.dart';
import 'package:energylens_mobile/features/design/settings_domain_repository.dart';
import 'package:energylens_mobile/features/design/settings_identity_renderer.dart';
import 'package:flutter_test/flutter_test.dart';

const _homeId = '11111111-1111-4111-8111-111111111111';
const _accountId = 'owner-account';

SettingsDomainSnapshot _snapshot({
  String? email,
  String? ownerName,
  String postalCode = '60601',
}) {
  final home = CloudHome(
    id: _homeId,
    name: 'Selected Home',
    timezone: 'America/Chicago',
    countryCode: 'US',
    postalCode: postalCode,
  );
  return SettingsDomainSnapshot(
    account: CloudAccount(
      id: _accountId,
      email: email,
      emailVerified: email != null,
      displayName: ownerName,
    ),
    homes: [home],
    accountPreferences: const CloudAccountPreferences(
      version: 1,
      emailReportsEnabled: false,
    ),
    accountPreferencesEtag: '"1"',
    home: home,
    homeEtag: '"1"',
    homePreferences: const CloudHomePreferences(
      version: 1,
      goal: 'unspecified',
      comfortPriority: 'unknown',
    ),
    homePreferencesEtag: '"1"',
    appliances: const [],
  );
}

void main() {
  const renderer = SettingsIdentityRenderer();

  test('rejects stale account, home, and page identity', () {
    final snapshot = _snapshot(email: 'owner@example.com');
    expect(
      renderer.script(
        ticket: const DesignPageTicket(_homeId, 'settings', 1),
        snapshot: snapshot,
        expectedAccountId: 'another-account',
      ),
      isNull,
    );
    expect(
      renderer.script(
        ticket: const DesignPageTicket(
          '22222222-2222-4222-8222-222222222222',
          'settings',
          1,
        ),
        snapshot: snapshot,
        expectedAccountId: _accountId,
      ),
      isNull,
    );
    expect(
      renderer.script(
        ticket: const DesignPageTicket(_homeId, 'dashboard', 1),
        snapshot: snapshot,
        expectedAccountId: _accountId,
      ),
      isNull,
    );
  });

  test(
    'writes authenticated values and hides absent optional rows in DOM',
    () async {
      final node = Process.runSync('node', ['--version']);
      if (node.exitCode != 0) return;
      final script = renderer.script(
        ticket: const DesignPageTicket(_homeId, 'settings', 7),
        snapshot: _snapshot(email: null, postalCode: '  '),
        expectedAccountId: _accountId,
      )!;
      final harness = r'''
const assert = require('node:assert/strict');
const vm = require('node:vm');
const html = process.argv[1];
const expected = JSON.parse(Buffer.from(process.argv[2], 'base64').toString());
const nodes = Object.fromEntries(['settings_text_010', 'settings_text_016', 'settings_text_019'].map(id => [id, {textContent: 'packaged sample'}]));
const rows = {'email': {hidden: true}, 'postal': {hidden: true}};
const visibilityNode = hidden => ({hidden, removeAttribute() { this.hidden = false; }, setAttribute() { this.hidden = true; }});
const editButtons = [visibilityNode(true), visibilityNode(true)];
const window = {__energyLensTextBindingContext: expected.context};
const document = {querySelectorAll(selector) {
  if (selector.includes('settings_text_010')) return [nodes.settings_text_010];
  if (selector.includes('settings_text_016')) return [nodes.settings_text_016];
  if (selector.includes('settings_text_019')) return [nodes.settings_text_019];
  if (selector.includes('data-el-settings-email-row')) return [rows.email];
  if (selector.includes('data-el-settings-postal-row')) return [rows.postal];
  if (selector.includes('data-el-settings-edit')) return editButtons;
  return [];
}};
const result = vm.runInNewContext(html, {window, document, TextDecoder, Uint8Array, atob: value => Buffer.from(value, 'base64').toString('binary')});
assert.equal(result, true);
assert.equal(nodes.settings_text_010.textContent, 'Selected Home');
assert.equal(nodes.settings_text_016.textContent, '');
assert.equal(nodes.settings_text_019.textContent, '');
assert.equal(rows.email.hidden, false);
assert.equal(rows.postal.hidden, false);
assert.equal(editButtons.every(button => button.hidden === false), true);
window.__energyLensTextBindingContext.generation++;
assert.equal(vm.runInNewContext(html, {window, document, TextDecoder, Uint8Array, atob: value => Buffer.from(value, 'base64').toString('binary')}), false);
''';
      final payload = jsonEncode({
        'context': {'homeId': _homeId, 'page': 'settings', 'generation': 7},
      });
      final result = await Process.run('node', [
        '-e',
        harness,
        script,
        base64Encode(utf8.encode(payload)),
      ]);
      expect(result.exitCode, 0, reason: '${result.stdout}\n${result.stderr}');
    },
  );

  test('renders authenticated home, email, and postal values in DOM', () async {
    final node = Process.runSync('node', ['--version']);
    if (node.exitCode != 0) return;
    final script = renderer.script(
      ticket: const DesignPageTicket(_homeId, 'settings', 8),
      snapshot: _snapshot(email: 'owner@example.com', ownerName: 'Alex Miller'),
      expectedAccountId: _accountId,
      localAuthSession: true,
    )!;
    const harness = r'''
const assert = require('node:assert/strict');
const vm = require('node:vm');
const html = process.argv[1];
const nodes = Object.fromEntries(['settings_text_010', 'settings_text_016', 'settings_text_019'].map(id => [id, {textContent: ''}]));
const rows = {email: {hidden: true}, postal: {hidden: true}};
const visibilityNode = hidden => ({hidden, removeAttribute() { this.hidden = false; }, setAttribute() { this.hidden = true; }});
const editButtons = [visibilityNode(true), visibilityNode(true)];
const profileNodes = {owner: {textContent: ''}, ownerRow: visibilityNode(true), ownerEdit: visibilityNode(true), emailEdit: visibilityNode(true), passwordChange: visibilityNode(true)};
const window = {__energyLensTextBindingContext: {homeId: '11111111-1111-4111-8111-111111111111', page: 'settings', generation: 8}};
const document = {querySelectorAll(selector) {
  if (selector.includes('settings_text_010')) return [nodes.settings_text_010];
  if (selector.includes('settings_text_016')) return [nodes.settings_text_016];
  if (selector.includes('settings_text_019')) return [nodes.settings_text_019];
  if (selector.includes('data-el-settings-email-row')) return [rows.email];
  if (selector.includes('data-el-settings-postal-row')) return [rows.postal];
  if (selector.includes('data-el-settings-edit')) return editButtons;
  if (selector.includes('data-el-settings-owner-row')) return [profileNodes.ownerRow];
  if (selector.includes('data-el-settings-owner-edit')) return [profileNodes.ownerEdit];
  if (selector.includes('data-el-settings-owner')) return [profileNodes.owner];
  if (selector.includes('data-el-settings-email-edit')) return [profileNodes.emailEdit];
  if (selector.includes('data-el-settings-password-change')) return [profileNodes.passwordChange];
  return [];
}};
const run = () => vm.runInNewContext(html, {window, document, TextDecoder, Uint8Array, atob: value => Buffer.from(value, 'base64').toString('binary')});
assert.equal(run(), true);
assert.equal(nodes.settings_text_010.textContent, 'Selected Home');
assert.equal(nodes.settings_text_016.textContent, 'owner@example.com');
assert.equal(nodes.settings_text_019.textContent, '60601');
assert.equal(rows.email.hidden, false);
assert.equal(rows.postal.hidden, false);
assert.equal(editButtons.every(button => button.hidden === false), true);
assert.equal(profileNodes.owner.textContent, 'Alex Miller');
assert.equal(profileNodes.ownerRow.hidden, false);
assert.equal(profileNodes.ownerEdit.hidden, false);
assert.equal(profileNodes.emailEdit.hidden, false);
assert.equal(profileNodes.passwordChange.hidden, false);
// Returning from another Settings page reloads the packaged hidden attributes before identity hydration.
editButtons.forEach(button => { button.hidden = true; });
for (const control of [profileNodes.ownerRow, profileNodes.ownerEdit, profileNodes.emailEdit, profileNodes.passwordChange]) control.hidden = true;
assert.equal(run(), true);
assert.equal(editButtons.every(button => button.hidden === false), true);
assert.equal(profileNodes.ownerEdit.hidden, false);
assert.equal(profileNodes.emailEdit.hidden, false);
assert.equal(profileNodes.passwordChange.hidden, false);
''';
    final result = await Process.run('node', ['-e', harness, script]);
    expect(result.exitCode, 0, reason: '${result.stdout}\n${result.stderr}');
  });
}
