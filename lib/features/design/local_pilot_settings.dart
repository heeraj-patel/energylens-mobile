import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:path_provider/path_provider.dart';

/// Device-local display details for the demo-only pilot.
class LocalPilotSettings {
  const LocalPilotSettings({
    required this.homeName,
    required this.ownerName,
    required this.postalCode,
  });

  final String homeName;
  final String ownerName;
  final String postalCode;

  LocalPilotSettings copyWith({
    String? homeName,
    String? ownerName,
    String? postalCode,
  }) => LocalPilotSettings(
    homeName: homeName ?? this.homeName,
    ownerName: ownerName ?? this.ownerName,
    postalCode: postalCode ?? this.postalCode,
  );
}

class LocalPilotSettingsStore {
  const LocalPilotSettingsStore({this.directory});

  final Directory? directory;

  Future<File> _file() async {
    final root = directory ?? await getApplicationSupportDirectory();
    return File('${root.path}/energylens_local_pilot_settings.json');
  }

  Future<LocalPilotSettings> load(String defaultHomeName) async {
    try {
      final file = await _file();
      if (!await file.exists()) {
        return LocalPilotSettings(
          homeName: defaultHomeName,
          ownerName: 'Alex Miller',
          postalCode: '',
        );
      }
      final values = jsonDecode(await file.readAsString());
      if (values is! Map<String, dynamic>) throw const FormatException();
      return LocalPilotSettings(
        homeName:
            values['homeName'] is String &&
                (values['homeName'] as String).trim().isNotEmpty
            ? values['homeName'] as String
            : defaultHomeName,
        ownerName:
            values['ownerName'] is String &&
                (values['ownerName'] as String).trim().isNotEmpty
            ? values['ownerName'] as String
            : 'Alex Miller',
        postalCode: values['postalCode'] is String
            ? values['postalCode'] as String
            : '',
      );
    } on FileSystemException {
      return LocalPilotSettings(
        homeName: defaultHomeName,
        ownerName: 'Alex Miller',
        postalCode: '',
      );
    } on FormatException {
      return LocalPilotSettings(
        homeName: defaultHomeName,
        ownerName: 'Alex Miller',
        postalCode: '',
      );
    }
  }

  Future<void> save(LocalPilotSettings value) async {
    final file = await _file();
    await file.parent.create(recursive: true);
    await file.writeAsString(
      jsonEncode({
        'homeName': value.homeName,
        'ownerName': value.ownerName,
        'postalCode': value.postalCode,
      }),
      flush: true,
    );
  }
}

class LocalPilotSettingsEditor extends StatefulWidget {
  const LocalPilotSettingsEditor({
    super.key,
    required this.settings,
    required this.editOwner,
  });

  final LocalPilotSettings settings;
  final bool editOwner;

  @override
  State<LocalPilotSettingsEditor> createState() =>
      _LocalPilotSettingsEditorState();
}

class _LocalPilotSettingsEditorState extends State<LocalPilotSettingsEditor> {
  late final _home = TextEditingController(text: widget.settings.homeName);
  late final _owner = TextEditingController(text: widget.settings.ownerName);
  late final _postal = TextEditingController(text: widget.settings.postalCode);

  @override
  void dispose() {
    _home.dispose();
    _owner.dispose();
    _postal.dispose();
    super.dispose();
  }

  void _save() {
    final homeName = _home.text.trim();
    final ownerName = _owner.text.trim();
    if (homeName.isEmpty || ownerName.isEmpty) return;
    Navigator.of(context).pop(
      widget.settings.copyWith(
        homeName: homeName,
        ownerName: ownerName,
        postalCode: _postal.text.trim(),
      ),
    );
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(
      title: Text(widget.editOwner ? 'Account Owner' : 'Home details'),
    ),
    body: SafeArea(
      child: ListView(
        padding: const EdgeInsets.all(20),
        children: [
          if (widget.editOwner)
            TextField(
              controller: _owner,
              maxLength: 120,
              decoration: const InputDecoration(labelText: 'Account Owner'),
            )
          else ...[
            TextField(
              controller: _home,
              maxLength: 120,
              decoration: const InputDecoration(labelText: 'Home name'),
            ),
            TextField(
              controller: _postal,
              maxLength: 20,
              decoration: const InputDecoration(labelText: 'ZIP code'),
            ),
          ],
          const SizedBox(height: 24),
          FilledButton(onPressed: _save, child: const Text('Save changes')),
          TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: const Text('Cancel'),
          ),
        ],
      ),
    ),
  );
}

String buildLocalPilotSettingsScript(String page, LocalPilotSettings settings) {
  final selectedHomeName = settings.homeName == 'The Miller Home'
      ? ''
      : settings.homeName;
  final homeName = jsonEncode(selectedHomeName);
  final ownerName = jsonEncode(settings.ownerName);
  final postalCode = jsonEncode(settings.postalCode);
  return '''
        document.querySelectorAll('[data-el-bind="${page}_text_001"]').forEach(node => node.textContent = $homeName);
        if ('$page' === 'settings') {
          document.querySelector('[data-el-bind="settings_text_010"]')?.replaceChildren($homeName);
          document.querySelector('[data-el-settings-owner]')?.replaceChildren($ownerName);
          document.querySelector('[data-el-bind="settings_text_019"]')?.replaceChildren($postalCode);
          document.querySelector('[data-el-settings-email-row]')?.removeAttribute('hidden');
          document.querySelector('[data-el-settings-password-row]')?.removeAttribute('hidden');
          document.querySelector('[data-el-settings-password-change]')?.removeAttribute('hidden');
          for (const selector of ['[data-el-settings-owner-row]', '[data-el-settings-postal-row]', '[data-el-action="settings_action_edit_home"]', '[data-el-action="settings_action_edit_owner"]', '[data-el-action="settings_action_edit_zip"]']) {
            document.querySelector(selector)?.removeAttribute('hidden');
          }
        }
      ''';
}
