import 'package:flutter/material.dart';

import '../../core/cloud_api/cloud_appliance.dart';
import '../../core/cloud_api/cloud_api_client.dart';
import '../../core/cloud_api/cloud_catalog.dart';
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
    this.serialNumber,
    this.fccId,
    this.icId,
    this.upc,
    this.initialRoom = '',
    this.initialCategory,
    this.catalogResults = const [],
    this.catalogSearchFailed = false,
    this.modelNotFoundOnLabel = false,
  });

  final CloudAuxiliaryDomainLifecycle lifecycle;
  final CloudApiClient? api;
  final String accountId;
  final String homeId;
  final String homeName;
  final String name;
  final String manufacturer;
  final String model;
  final String? serialNumber;
  final String? fccId;
  final String? icId;
  final String? upc;
  final String initialRoom;
  final String? initialCategory;
  final List<CloudCatalogProduct> catalogResults;
  final bool catalogSearchFailed;
  final bool modelNotFoundOnLabel;

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
  late final TextEditingController _serialNumber = TextEditingController(
    text: widget.serialNumber,
  );
  late final TextEditingController _fccId = TextEditingController(
    text: widget.fccId,
  );
  late final TextEditingController _icId = TextEditingController(
    text: widget.icId,
  );
  late final TextEditingController _upc = TextEditingController(
    text: widget.upc,
  );
  late final TextEditingController _room = TextEditingController(
    text: widget.initialRoom,
  );
  static EnergyCategories? _sessionCategories;
  EnergyCategories? _categories = _sessionCategories;
  late String? _category = widget.initialCategory;
  String? _group;
  String? _fuel;
  CloudCatalogProduct? _reviewedProduct;
  bool _saving = false;
  PendingOnboardingDraft? _pending;

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
      _serialNumber.text.trim().length <= 120 &&
      _fccId.text.trim().length <= 120 &&
      _icId.text.trim().length <= 120 &&
      _upc.text.trim().length <= 120 &&
      _room.text.trim().length <= 120 &&
      _category != null &&
      _fuel != null;

  void _changed() {
    _pending = null;
    setState(() {});
  }

  void _selectCatalogProduct(CloudCatalogProduct product) {
    if (_saving) return;
    _manufacturer.text = product.brand;
    _model.text = product.fullModel;
    _category = product.category;
    _reviewedProduct = product;
    _selectGroupForCategory();
    _changed();
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
        room: _room.text.trim(),
        reviewedProduct: _reviewedProduct,
        serialNumber: _serialNumber.text.trim(),
        fccId: _fccId.text.trim(),
        icId: _icId.text.trim(),
        upc: _upc.text.trim(),
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
    _serialNumber.dispose();
    _fccId.dispose();
    _icId.dispose();
    _upc.dispose();
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
          if (widget.modelNotFoundOnLabel) ...[
            const Align(
              alignment: Alignment.centerLeft,
              child: Text('No model found on the label. Enter it below.'),
            ),
            const SizedBox(height: 8),
          ],
          Align(
            alignment: Alignment.centerLeft,
            child: Text(
              widget.catalogSearchFailed
                  ? 'Catalog is unavailable. Check the details and save.'
                  : widget.catalogResults.isEmpty
                  ? 'No catalog match. Check the details and save.'
                  : 'Found in catalog. Pick your model or edit below.',
            ),
          ),
          if (widget.catalogResults.isNotEmpty) ...[
            const SizedBox(height: 16),
            Align(
              alignment: Alignment.centerLeft,
              child: Text(
                'Catalog matches',
                style: Theme.of(context).textTheme.titleSmall,
              ),
            ),
            for (final product in widget.catalogResults)
              ListTile(
                key: Key('catalogProduct-${product.id}'),
                contentPadding: EdgeInsets.zero,
                title: Text('${product.brand} ${product.fullModel}'.trim()),
                selected: _reviewedProduct?.id == product.id,
                onTap: _saving ? null : () => _selectCatalogProduct(product),
              ),
            const SizedBox(height: 8),
          ] else
            const SizedBox(height: 16),
          if (widget.upc?.trim().isNotEmpty == true) ...[
            Align(
              alignment: Alignment.centerLeft,
              child: Chip(label: Text('Barcode ${widget.upc!.trim()}')),
            ),
            const SizedBox(height: 8),
          ],
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
          TextField(
            key: const Key('reviewSerialNumber'),
            controller: _serialNumber,
            readOnly: _saving,
            onChanged: (_) => _changed(),
            decoration: const InputDecoration(labelText: 'Serial number'),
          ),
          TextField(
            key: const Key('reviewFccId'),
            controller: _fccId,
            readOnly: _saving,
            onChanged: (_) => _changed(),
            decoration: const InputDecoration(labelText: 'FCC ID'),
          ),
          TextField(
            key: const Key('reviewIcId'),
            controller: _icId,
            readOnly: _saving,
            onChanged: (_) => _changed(),
            decoration: const InputDecoration(labelText: 'IC ID'),
          ),
          TextField(
            key: const Key('reviewUpc'),
            controller: _upc,
            readOnly: _saving,
            onChanged: (_) => _changed(),
            decoration: const InputDecoration(labelText: 'UPC'),
          ),
          TextField(
            key: const Key('reviewRoom'),
            controller: _room,
            readOnly: _saving,
            onChanged: (_) => _changed(),
            decoration: const InputDecoration(labelText: 'Room'),
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
