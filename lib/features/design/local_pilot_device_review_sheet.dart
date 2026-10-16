import 'dart:convert';

import 'package:flutter/material.dart';

import '../discovery/discovery_api.dart';
import 'local_pilot_device_lifecycle.dart';

class LocalPilotDeviceReviewSheet extends StatefulWidget {
  const LocalPilotDeviceReviewSheet({
    super.key,
    required this.lifecycle,
    required this.session,
    required this.onboardingMethod,
    this.name = '',
    this.manufacturer = '',
    this.model = '',
    this.initialCategory,
  });

  final LocalPilotDeviceLifecycle lifecycle;
  final LocalSaveSession session;
  final String onboardingMethod;
  final String name;
  final String manufacturer;
  final String model;
  final String? initialCategory;

  @override
  State<LocalPilotDeviceReviewSheet> createState() =>
      _LocalPilotDeviceReviewSheetState();
}

class _LocalPilotDeviceReviewSheetState
    extends State<LocalPilotDeviceReviewSheet> {
  late final _name = TextEditingController(text: widget.name);
  late final _manufacturer = TextEditingController(text: widget.manufacturer);
  late final _model = TextEditingController(text: widget.model);
  late String? _category = widget.initialCategory;
  bool _saving = false;
  bool _attempted = false;

  bool _withinLimit(String value) => utf8.encode(value.trim()).length <= 100;

  bool get _valid =>
      _name.text.trim().isNotEmpty &&
      _withinLimit(_name.text) &&
      _manufacturer.text.trim().isNotEmpty &&
      _model.text.trim().isNotEmpty &&
      _withinLimit(_manufacturer.text) &&
      _withinLimit(_model.text) &&
      _category != null;

  Future<void> _save() async {
    if (_saving || !_valid) return;
    setState(() {
      _saving = true;
      _attempted = true;
    });
    final input = ApplianceInput(
      name: _name.text.trim(),
      room: '',
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
      }
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  void dispose() {
    _name.dispose();
    _manufacturer.dispose();
    _model.dispose();
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
          DropdownButtonFormField<String>(
            key: const Key('localReviewCategory'),
            initialValue: _category,
            decoration: const InputDecoration(labelText: 'Category'),
            items: const [
              DropdownMenuItem(value: 'computer', child: Text('Computer')),
              DropdownMenuItem(value: 'lighting', child: Text('Lamp or bulb')),
              DropdownMenuItem(
                value: 'refrigerator',
                child: Text('Refrigerator'),
              ),
              DropdownMenuItem(value: 'television', child: Text('TV')),
              DropdownMenuItem(value: 'washer', child: Text('Washer')),
              DropdownMenuItem(value: 'dryer', child: Text('Dryer')),
              DropdownMenuItem(value: 'dishwasher', child: Text('Dishwasher')),
              DropdownMenuItem(
                value: 'space_heater',
                child: Text('Space heater'),
              ),
              DropdownMenuItem(
                value: 'air_conditioner',
                child: Text('Air conditioner'),
              ),
              DropdownMenuItem(
                value: 'water_heater',
                child: Text('Water Heater'),
              ),
              DropdownMenuItem(value: 'other', child: Text('Other appliance')),
            ],
            onChanged: _attempted
                ? null
                : (value) => setState(() => _category = value),
          ),
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
