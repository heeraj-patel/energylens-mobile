import 'package:flutter/material.dart';

import '../../core/cloud_api/cloud_appliance.dart';
import '../../core/cloud_api/cloud_api_client.dart';
import '../../core/cloud_api/cloud_energy_categories.dart';
import '../../core/cloud_auth/cloud_auxiliary_domain_lifecycle.dart';
import '../identify/onboarding_draft_store.dart';
import '../identify/onboarding_persistence_repository.dart';

/// Native review gate for a design-page device draft. Broad design types are
/// deliberately ignored; the owner chooses an exact category and fuel here.
class DeviceReviewSheet extends StatefulWidget {
  const DeviceReviewSheet({
    super.key,
    required this.lifecycle,
    this.api,
    required this.accountId,
    required this.homeId,
    required this.homeName,
    this.name = '',
    this.manufacturer = '',
    this.model = '',
    this.initialCategory,
  });

  final CloudAuxiliaryDomainLifecycle lifecycle;
  final CloudApiClient? api;
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
  static EnergyCategories? _sessionCategories;
  EnergyCategories? _categories = _sessionCategories;
  late String? _category = widget.initialCategory;
  String? _group;
  String? _fuel;
  bool _saving = false;
  PendingOnboardingDraft? _pending;

  @override
  void initState() {
    super.initState();
    _selectGroupForCategory();
    _loadCategories();
  }

  void _selectGroupForCategory() {
    for (final group in _categories?.groups ?? const <EnergyCategoryGroup>[]) {
      if (group.types.any((type) => type.key == _category)) {
        _group = group.key;
        return;
      }
    }
  }

  Future<void> _loadCategories() async {
    final api = widget.api;
    if (api == null) return;
    try {
      final fresh = await api.energyCategories(etag: _sessionCategories?.etag);
      if (fresh != null) _sessionCategories = fresh;
      if (!mounted) return;
      setState(() {
        _categories = _sessionCategories;
        _selectGroupForCategory();
      });
    } catch (_) {
      // Keep the session's last successful category list.
    }
  }

  bool _validText(String value) =>
      value.trim().isNotEmpty && value.trim().length <= 120;

  bool get _valid =>
      _validText(_name.text) &&
      _manufacturer.text.trim().length <= 120 &&
      _model.text.trim().length <= 120 &&
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
            onChanged: _saving
                ? null
                : (value) {
                    _group = value;
                    _category = null;
                    _changed();
                  },
          ),
          DropdownButtonFormField<String>(
            key: const Key('reviewDeviceType'),
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
            onChanged: _saving || _group == null
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
