import 'package:flutter/material.dart';

import '../../core/cloud_api/cloud_appliance.dart';
import '../../core/cloud_auth/cloud_auxiliary_domain_lifecycle.dart';
import '../identify/onboarding_draft_store.dart';
import '../identify/onboarding_persistence_repository.dart';

/// Native review gate for a design-page device draft. Broad design types are
/// deliberately ignored; the owner chooses an exact category and fuel here.
class DeviceReviewSheet extends StatefulWidget {
  const DeviceReviewSheet({
    super.key,
    required this.lifecycle,
    required this.accountId,
    required this.homeId,
    required this.homeName,
    this.name = '',
    this.manufacturer = '',
    this.model = '',
    this.initialCategory,
  });

  final CloudAuxiliaryDomainLifecycle lifecycle;
  final String accountId;
  final String homeId;
  final String homeName;
  final String name;
  final String manufacturer;
  final String model;
  final String? initialCategory;

  @override
  State<DeviceReviewSheet> createState() => _DeviceReviewSheetState();
}

class _DeviceReviewSheetState extends State<DeviceReviewSheet> {
  late final TextEditingController _name = TextEditingController(
    text: widget.name,
  );
  late final TextEditingController _manufacturer = TextEditingController(
    text: widget.manufacturer,
  );
  late final TextEditingController _model = TextEditingController(
    text: widget.model,
  );
  late String? _category =
      const {
        'computer',
        'lighting',
        'refrigerator',
        'television',
        'washer',
        'dryer',
        'dishwasher',
        'space_heater',
        'air_conditioner',
        'water_heater',
        'other',
      }.contains(widget.initialCategory)
      ? widget.initialCategory
      : null;
  String? _fuel;
  bool _saving = false;
  PendingOnboardingDraft? _pending;

  bool _validText(String value) =>
      value.trim().isNotEmpty && value.trim().length <= 120;

  bool get _valid =>
      _validText(_name.text) &&
      _validText(_manufacturer.text) &&
      _validText(_model.text) &&
      _category != null &&
      _fuel != null;

  void _changed() {
    _pending = null;
    setState(() {});
  }

  Future<void> _save() async {
    if (_saving ||
        !_valid ||
        !widget.lifecycle.isVerifiedScope(widget.accountId, widget.homeId)) {
      return;
    }
    setState(() => _saving = true);
    try {
      final draft = OnboardingDraft(
        name: _name.text.trim(),
        category: _category!,
        brand: _manufacturer.text.trim(),
        fullModel: _model.text.trim(),
        fuel: _fuel!,
      );
      final pending =
          _pending ??
          await widget.lifecycle.stageOnboardingDraft(
            widget.accountId,
            widget.homeId,
            draft,
          );
      _pending = pending;
      final saved = await widget.lifecycle.commitOnboardingDraft(
        widget.accountId,
        widget.homeId,
        pending,
        explicitlyApproved: true,
      );
      if (mounted &&
          saved != null &&
          widget.lifecycle.isVerifiedScope(widget.accountId, widget.homeId)) {
        Navigator.of(context).pop<CloudAppliance>(saved);
      }
    } catch (_) {
      // Keep the reviewed draft and operation key for an unchanged retry.
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
            key: const Key('reviewDeviceName'),
            controller: _name,
            readOnly: _saving,
            onChanged: (_) => _changed(),
            decoration: const InputDecoration(labelText: 'Device name'),
          ),
          TextField(
            key: const Key('reviewManufacturer'),
            controller: _manufacturer,
            readOnly: _saving,
            onChanged: (_) => _changed(),
            decoration: const InputDecoration(labelText: 'Manufacturer'),
          ),
          TextField(
            key: const Key('reviewModel'),
            controller: _model,
            readOnly: _saving,
            onChanged: (_) => _changed(),
            decoration: const InputDecoration(labelText: 'Model'),
          ),
          DropdownButtonFormField<String>(
            key: const Key('reviewCategory'),
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
            onChanged: _saving
                ? null
                : (value) {
                    _category = value;
                    _changed();
                  },
          ),
          DropdownButtonFormField<String>(
            key: const Key('reviewEnergySource'),
            initialValue: _fuel,
            decoration: const InputDecoration(labelText: 'Energy source'),
            items: const [
              DropdownMenuItem(
                value: 'electricity',
                child: Text('Electricity'),
              ),
              DropdownMenuItem(
                value: 'natural_gas',
                child: Text('Natural gas'),
              ),
              DropdownMenuItem(value: 'propane', child: Text('Propane')),
              DropdownMenuItem(value: 'fuel_oil', child: Text('Fuel oil')),
            ],
            onChanged: _saving
                ? null
                : (value) {
                    _fuel = value;
                    _changed();
                  },
          ),
          if (_saving) const LinearProgressIndicator(key: Key('reviewSaving')),
        ],
      ),
    ),
    actions: [
      TextButton(
        onPressed: _saving
            ? null
            : () => Navigator.of(context).pop<CloudAppliance>(),
        child: const Text('Cancel'),
      ),
      FilledButton(
        key: const Key('reviewSave'),
        onPressed: _saving || !_valid ? null : _save,
        child: Text('Save to ${widget.homeName}'),
      ),
    ],
  );
}
