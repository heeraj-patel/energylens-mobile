import 'dart:convert';

import 'package:flutter/material.dart';

import '../../core/cloud_api/cloud_energy_categories.dart';
import '../discovery/discovery_api.dart';
import 'local_pilot_device_lifecycle.dart';
import '../../core/backend_error.dart';

class LocalPilotDeviceReviewSheet extends StatefulWidget {
  const LocalPilotDeviceReviewSheet({
    super.key,
    required this.lifecycle,
    required this.session,
    required this.onboardingMethod,
    this.name = '',
    this.manufacturer = '',
    this.model = '',
    this.initialRoom = '',
    this.initialCategory,
    this.initialCategories,
  });

  final LocalPilotDeviceLifecycle lifecycle;
  final LocalSaveSession session;
  final String onboardingMethod;
  final String name;
  final String manufacturer;
  final String model;
  final String initialRoom;
  final String? initialCategory;
  final EnergyCategories? initialCategories;

  @override
  State<LocalPilotDeviceReviewSheet> createState() =>
      _LocalPilotDeviceReviewSheetState();
}

class _LocalPilotDeviceReviewSheetState
    extends State<LocalPilotDeviceReviewSheet> {
  late final _name = TextEditingController(text: widget.name);
  late final _manufacturer = TextEditingController(text: widget.manufacturer);
  late final _model = TextEditingController(text: widget.model);
  late final _room = TextEditingController(text: widget.initialRoom);
  late EnergyCategories? _categories = widget.initialCategories;
  late String? _category = widget.initialCategory;
  String? _group;
  bool _saving = false;
  bool _attempted = false;
  bool _failed = false;

  bool _withinLimit(String value) => utf8.encode(value.trim()).length <= 100;

  @override
  void initState() {
    super.initState();
    _selectGroupForCategory();
    _loadCategories();
  }

  void _selectGroupForCategory() {
    _group = null;
    for (final group in _categories?.groups ?? const <EnergyCategoryGroup>[]) {
      if (group.types.any((type) => type.key == _category)) {
        _group = group.key;
        return;
      }
    }
  }

  Future<void> _loadCategories() async {
    try {
      final fresh = await widget.lifecycle.energyCategories();
      if (!mounted || fresh == null) return;
      setState(() {
        _categories = fresh;
        _selectGroupForCategory();
      });
    } catch (_) {
      // Retain the list supplied by the current session.
    }
  }

  bool get _valid =>
      _name.text.trim().isNotEmpty &&
      _withinLimit(_name.text) &&
      _manufacturer.text.trim().isNotEmpty &&
      _model.text.trim().isNotEmpty &&
      _withinLimit(_manufacturer.text) &&
      _withinLimit(_model.text) &&
      _withinLimit(_room.text) &&
      _category != null;

  Future<void> _save() async {
    if (_saving || !_valid) return;
    setState(() {
      _saving = true;
      _attempted = true;
    });
    final input = ApplianceInput(
      name: _name.text.trim(),
      room: _room.text.trim(),
      category: _category!,
      manufacturer: _manufacturer.text.trim(),
      model: _model.text.trim(),
      loadKind: 'appliance',
      onboardingMethod: widget.onboardingMethod,
    );
    try {
      final result = await widget.lifecycle.save(widget.session, input);
      if (mounted && result.status == LocalWriteStatus.confirmed) {
        Navigator.of(context).pop<LocalWriteResult>(result);
      } else if (mounted) {
        setState(() => _failed = true);
      }
    } catch (_) {
      if (mounted) setState(() => _failed = true);
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  void dispose() {
    _name.dispose();
    _manufacturer.dispose();
    _model.dispose();
    _room.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => AlertDialog(
    title: const Text('Review device'),
    content: SingleChildScrollView(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          TextField(
            key: const Key('localReviewDeviceName'),
            controller: _name,
            readOnly: _attempted,
            onChanged: (_) => setState(() {}),
            decoration: const InputDecoration(labelText: 'Device name'),
          ),
          TextField(
            key: const Key('localReviewManufacturer'),
            controller: _manufacturer,
            readOnly: _attempted,
            onChanged: (_) => setState(() {}),
            decoration: const InputDecoration(labelText: 'Manufacturer'),
          ),
          TextField(
            key: const Key('localReviewModel'),
            controller: _model,
            readOnly: _attempted,
            onChanged: (_) => setState(() {}),
            decoration: const InputDecoration(labelText: 'Model'),
          ),
          TextField(
            key: const Key('localReviewRoom'),
            controller: _room,
            readOnly: _attempted,
            onChanged: (_) => setState(() {}),
            decoration: const InputDecoration(labelText: 'Room'),
          ),
          DropdownButtonFormField<String>(
            key: const Key('localReviewGroup'),
            initialValue: _group,
            decoration: const InputDecoration(
              labelText: 'Category',
              hintText: 'Choose category',
            ),
            items: [
              for (final group
                  in _categories?.groups ?? const <EnergyCategoryGroup>[])
                DropdownMenuItem(value: group.key, child: Text(group.label)),
            ],
            onChanged: _attempted
                ? null
                : (value) => setState(() {
                    _group = value;
                    _category = null;
                  }),
          ),
          DropdownButtonFormField<String>(
            key: const Key('localReviewCategory'),
            initialValue: _category,
            decoration: InputDecoration(
              labelText: 'Device Type',
              hintText: _group == null
                  ? 'Choose category first'
                  : 'Choose type',
            ),
            items: [
              for (final type
                  in _categories?.groups
                          .where((group) => group.key == _group)
                          .expand((group) => group.types) ??
                      const <EnergyCategoryType>[])
                DropdownMenuItem(value: type.key, child: Text(type.label)),
              if (_category != null &&
                  !(_categories?.groups.any(
                        (group) =>
                            group.types.any((type) => type.key == _category),
                      ) ??
                      false))
                DropdownMenuItem(value: _category, child: Text(_category!)),
            ],
            onChanged: _attempted || _group == null
                ? null
                : (value) => setState(() => _category = value),
          ),
          if (_failed) const Text(internalErrorMessage),
          if (_saving)
            const LinearProgressIndicator(key: Key('localReviewSaving')),
        ],
      ),
    ),
    actions: [
      TextButton(
        onPressed: _saving ? null : () => Navigator.of(context).pop(),
        child: const Text('Cancel'),
      ),
      FilledButton(
        key: const Key('localReviewSave'),
        onPressed: _saving || !_valid ? null : _save,
        child: const Text('Save Device'),
      ),
    ],
  );
}
