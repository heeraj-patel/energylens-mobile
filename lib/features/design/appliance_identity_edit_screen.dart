import 'dart:convert';

import 'package:flutter/material.dart';

import '../../core/backend_error.dart';
import '../../core/cloud_api/cloud_api_client.dart';
import '../../core/cloud_api/cloud_home.dart' show newCloudIdempotencyKey;
import 'appliance_identity_editor.dart';

class ApplianceIdentityEditScreen extends StatefulWidget {
  const ApplianceIdentityEditScreen({
    super.key,
    this.api,
    this.source,
    required this.homeId,
    required this.applianceId,
    required this.isCurrentScope,
  }) : assert(api != null || source != null);

  final CloudApiClient? api;
  final ApplianceIdentityEditSource? source;
  final String homeId;
  final String applianceId;
  final bool Function() isCurrentScope;

  @override
  State<ApplianceIdentityEditScreen> createState() =>
      _ApplianceIdentityEditScreenState();
}

class _ApplianceIdentityEditScreenState
    extends State<ApplianceIdentityEditScreen> {
  late final ApplianceIdentityEditor _editor = ApplianceIdentityEditor(
    source: widget.source ?? CloudApplianceIdentityEditSource(widget.api!),
    homeId: widget.homeId,
    applianceId: widget.applianceId,
    isCurrentScope: widget.isCurrentScope,
    newOperationKey: newCloudIdempotencyKey,
  );
  final _brand = TextEditingController();
  final _model = TextEditingController();
  bool _loading = true;
  bool _ready = false;
  bool _saving = false;
  bool _conflict = false;
  bool _failed = false;

  bool get _validInput =>
      utf8.encode(_brand.text.trim()).length <= 120 &&
      utf8.encode(_model.text.trim()).length <= 240;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    try {
      final appliance = await _editor.load();
      if (!mounted || !widget.isCurrentScope()) return;
      setState(() {
        _loading = false;
        _ready = appliance != null;
        _brand.text = appliance?.brand ?? '';
        _model.text = appliance?.fullModel ?? '';
      });
    } catch (_) {
      if (mounted && widget.isCurrentScope()) {
        setState(() {
          _loading = false;
          _failed = true;
        });
      }
    }
  }

  Future<void> _save() async {
    if (!_ready || _saving || !widget.isCurrentScope()) return;
    setState(() {
      _saving = true;
      _conflict = false;
      _failed = false;
    });
    try {
      final saved = await _editor.save(_brand.text, _model.text);
      if (saved != null && mounted && widget.isCurrentScope()) {
        Navigator.of(context).pop(true);
      }
    } on CloudApiException catch (error) {
      if (mounted && widget.isCurrentScope()) {
        setState(() {
          _conflict = error.statusCode == 409 || error.statusCode == 412;
          _failed = !_conflict;
        });
      }
    } catch (_) {
      if (mounted && widget.isCurrentScope()) {
        setState(() => _failed = true);
      }
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  void dispose() {
    _editor.dispose();
    _brand.dispose();
    _model.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: const Text('Edit device')),
    body: SafeArea(
      child: ListView(
        padding: const EdgeInsets.all(20),
        children: [
          if (_loading) const LinearProgressIndicator(),
          TextField(
            controller: _brand,
            maxLength: 120,
            enabled:
                _ready && !_saving && !_conflict && !_editor.hasPendingMutation,
            onChanged: (_) => setState(() {}),
            decoration: const InputDecoration(labelText: 'Manufacturer'),
          ),
          TextField(
            controller: _model,
            maxLength: 240,
            enabled:
                _ready && !_saving && !_conflict && !_editor.hasPendingMutation,
            onChanged: (_) => setState(() {}),
            decoration: const InputDecoration(labelText: 'Full model'),
          ),
          if (_conflict)
            const Text(
              'Device details changed elsewhere. Reopen and try again.',
            ),
          if (_failed) const Text(internalErrorMessage),
          const SizedBox(height: 24),
          FilledButton(
            onPressed: _ready && !_saving && !_conflict && _validInput
                ? _save
                : null,
            child: const Text('Save changes'),
          ),
          TextButton(
            onPressed: _saving ? null : () => Navigator.of(context).pop(false),
            child: const Text('Cancel'),
          ),
        ],
      ),
    ),
  );
}
