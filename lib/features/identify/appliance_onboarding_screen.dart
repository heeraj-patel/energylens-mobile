import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../core/cloud_api/cloud_api_client.dart';
import '../../core/cloud_api/cloud_appliance.dart';
import '../../core/cloud_api/cloud_catalog.dart';
import '../../core/cloud_api/cloud_home.dart';
import '../discovery/discovery_api.dart';
import '../discovery/discovery_credentials.dart';
import 'photo_capture_service.dart';
import 'cloud_usage_questions_screen.dart';

/// A photo suggestion is a prefill only. The user confirms the exact model.
String? modelHintFromOcr(String? text) {
  if (text == null) return null;
  final labeled = RegExp(
    r'\b(?:MODEL(?:[ \t]+NUMBER|[ \t]+NO)?|M/N|MDL)[ \t]*[:#]?[ \t]*([A-Z0-9][A-Z0-9-]{2,24})\b',
    caseSensitive: false,
  ).allMatches(text);
  for (final match in labeled) {
    final model = match.group(1);
    if (model != null && RegExp(r'\d').hasMatch(model)) {
      return model.toUpperCase();
    }
  }
  return null;
}

/// Returns only a likely maker name; serials and the full OCR text stay local.
String? manufacturerHintFromOcr(String? text) {
  if (text == null) return null;
  final lines = text.split(RegExp(r'[\r\n]+'));
  var modelLine = -1;
  for (var index = 0; index < lines.length; index++) {
    if (modelHintFromOcr(lines[index]) != null) {
      modelLine = index;
      break;
    }
  }
  if (modelLine < 0) return null;
  const known = <String, String>{
    'LG': 'LG',
    'SAMSUNG': 'Samsung',
    'WHIRLPOOL': 'Whirlpool',
    'BOSCH': 'Bosch',
    'FRIGIDAIRE': 'Frigidaire',
    'MAYTAG': 'Maytag',
    'ELECTROLUX': 'Electrolux',
    'GE': 'GE',
    'HAIER': 'Haier',
    'HISENSE': 'Hisense',
    'PANASONIC': 'Panasonic',
    'SONY': 'Sony',
    'PHILIPS': 'Philips',
    'MIDEA': 'Midea',
  };
  final suggestions = <String>{};
  final first = modelLine - 2 < 0 ? 0 : modelLine - 2;
  final last = modelLine + 2 >= lines.length ? lines.length - 1 : modelLine + 2;
  for (var index = first; index <= last; index++) {
    final rawLine = lines[index];
    final line = rawLine
        .split(
          RegExp(r'\b(?:SERIAL|S/N|SN|MODEL)\b\s*[:#]?', caseSensitive: false),
        )
        .first
        .trim();
    if (line.isEmpty) continue;
    final labeled = RegExp(
      r'^(?:MANUFACTURER|MFR\.?|BRAND|MAKE)\s*[:#-]?\s*([A-Za-z][A-Za-z .&-]{1,45})$',
      caseSensitive: false,
    ).firstMatch(line);
    final candidate = (labeled?.group(1) ?? line).trim().toUpperCase();
    String? suggestion;
    for (final entry in known.entries) {
      if (candidate == entry.key ||
          candidate == '${entry.key} ELECTRONICS' ||
          candidate.startsWith('${entry.key} ELECTRONICS ')) {
        suggestion = entry.value;
        break;
      }
    }
    if (suggestion == null &&
        labeled != null &&
        !RegExp(r'\d').hasMatch(candidate)) {
      suggestion = labeled.group(1)!.trim();
    }
    if (suggestion != null) suggestions.add(suggestion);
  }
  return suggestions.length == 1 ? suggestions.single : null;
}

class ApplianceOnboardingScreen extends StatefulWidget {
  const ApplianceOnboardingScreen({
    required this.method,
    super.key,
    this.plugId,
    this.api = const DiscoveryApi(),
    this.credentials = const DiscoveryCredentials(),
    this.capture = const PhotoCaptureService(),
    this.cloudHome,
    this.cloudApi,
  }) : assert(method == 'manual' || method == 'photo');

  final String method;
  final String? plugId;
  final DiscoveryApi api;
  final DiscoveryCredentials credentials;
  final PhotoCaptureService capture;
  final CloudHome? cloudHome;
  final CloudApiClient? cloudApi;

  @override
  State<ApplianceOnboardingScreen> createState() =>
      _ApplianceOnboardingScreenState();
}

class _ApplianceOnboardingScreenState extends State<ApplianceOnboardingScreen> {
  final _hub = TextEditingController();
  final _token = TextEditingController();
  final _name = TextEditingController();
  final _room = TextEditingController();
  final _manufacturer = TextEditingController();
  final _model = TextEditingController();
  final _hours = TextEditingController();
  final _bulbs = TextEditingController();
  final _watts = TextEditingController();
  String _category = 'computer';
  String _loadKind = 'appliance';
  String _fuel = 'electricity';
  String _cloudSaveKey = newCloudIdempotencyKey();
  String? _ocrText;
  String? _photoManufacturerHint;
  String? _upc;
  List<IdentificationCandidate> _photoCandidates = const [];
  List<CloudCatalogProduct> _catalogResults = const [];
  CloudCatalogProduct? _catalogDetail;
  CloudCatalogProduct? _selectedCatalogProduct;
  String? _catalogMessage;
  bool _catalogBusy = false;
  bool _candidateLookupFailed = false;
  Uint8List? _photoBytes;
  bool _confirmedModel = false;
  bool _busy = false;
  (String, String, String, String, String)? _checkedModelKey;
  EnergyLookup? _modelCheck;
  String? _error;
  String? _deleteError;
  List<SavedAppliance> _saved = const [];
  final Map<int, EnergyEstimate> _estimates = {};
  final Map<int, String> _lookupStatuses = {};

  bool get _cloudOnly =>
      widget.plugId == null &&
      widget.cloudHome != null &&
      widget.cloudApi != null;

  @override
  void initState() {
    super.initState();
    for (final controller in [_name, _room]) {
      controller.addListener(_cloudInputChanged);
    }
    for (final controller in [_manufacturer, _model]) {
      controller.addListener(_cloudIdentityChanged);
    }
    if (!_cloudOnly) _restore();
  }

  void _cloudInputChanged() {
    if (_cloudOnly) _cloudSaveKey = newCloudIdempotencyKey();
  }

  void _cloudIdentityChanged() {
    if (!_cloudOnly) return;
    _cloudInputChanged();
    _selectedCatalogProduct = null;
    _catalogDetail = null;
    _catalogResults = const [];
    _catalogMessage = null;
    _confirmedModel = false;
  }

  Future<void> _restore() async {
    try {
      final (address, token) = await widget.credentials.read();
      if (!mounted) return;
      if (address != null) _hub.text = address;
      if (token != null) _token.text = token;
      if (address != null && token != null) await _refresh();
    } catch (_) {
      // Hub details can be entered manually when secure storage is unavailable.
    }
  }

  Future<void> _refresh() async {
    try {
      final rows = await widget.api.appliances(
        _hub.text.trim(),
        _token.text.trim(),
      );
      if (mounted) {
        setState(() {
          _saved = rows;
          _error = null;
        });
        for (final item in rows) {
          try {
            final estimate = await widget.api.estimate(
              _hub.text.trim(),
              _token.text.trim(),
              item.id,
            );
            if (mounted) {
              setState(() {
                _estimates[item.id] = estimate;
                if (estimate.reason == 'no_match') {
                  _lookupStatuses[item.id] = 'no_match';
                } else if (estimate.evidence != null) {
                  _lookupStatuses.remove(item.id);
                }
              });
            }
          } catch (_) {
            // A single estimate failure does not hide the saved device list.
          }
        }
      }
    } catch (_) {
      if (mounted) {
        setState(
          () => _error = 'Could not load saved appliances from the hub.',
        );
      }
    }
  }

  (String, String, String, String, String) get _modelKey => (
    _category,
    _manufacturer.text.trim(),
    _model.text.trim(),
    _hub.text.trim(),
    _token.text.trim(),
  );

  Future<void> _checkModelBeforeSave() async {
    if (_busy) return;
    final key = _modelKey;
    if (_hub.text.trim().isEmpty || _token.text.trim().isEmpty) {
      setState(
        () => _error = 'Enter the hub address and token to check the model.',
      );
      return;
    }
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      final lookup = await widget.api.checkModel(
        _hub.text.trim(),
        _token.text.trim(),
        category: key.$1,
        manufacturer: key.$2,
        model: key.$3,
      );
      if (mounted && _modelKey == key) {
        setState(() {
          _checkedModelKey = key;
          _modelCheck = lookup;
        });
      }
    } catch (error) {
      if (mounted) {
        setState(
          () => _error = error is StateError ? error.message : 'Could not check the model. Try again when the hub is reachable.',
        );
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _searchReviewedCatalog() async {
    if (!_cloudOnly || _catalogBusy || _busy) return;
    final brand = _manufacturer.text.trim();
    final model = _model.text.trim();
    final fuel = _fuel;
    if (brand.isEmpty || model.length < 2) {
      setState(
        () => _catalogMessage =
            'Enter a manufacturer and full model to check reviewed products.',
      );
      return;
    }
    setState(() {
      _catalogBusy = true;
      _catalogResults = const [];
      _catalogDetail = null;
      _selectedCatalogProduct = null;
      _catalogMessage = null;
    });
    try {
      final results = await widget.cloudApi!.searchCatalogModels(
        brand: brand,
        model: model,
        fuel: fuel,
        region: widget.cloudHome!.countryCode,
      );
      if (!mounted ||
          _manufacturer.text.trim() != brand ||
          _model.text.trim() != model ||
          _fuel != fuel) {
        return;
      }
      setState(() {
        _catalogResults = results;
        _catalogMessage = results.isEmpty
            ? 'No reviewed product matches this full model and fuel. You can still save the confirmed label identity without a catalog link.'
            : null;
      });
    } catch (_) {
      if (mounted) {
        setState(
          () => _catalogMessage = 'Reviewed catalog unavailable. You can save a confirmed label identity without a catalog link.',
        );
      }
    } finally {
      if (mounted) setState(() => _catalogBusy = false);
    }
  }

  Future<void> _openCatalogProduct(CloudCatalogProduct result) async {
    if (_catalogBusy || _busy) return;
    if (result.isDocumentedFamilyCandidate) {
      setState(() {
        _catalogDetail = result;
        _selectedCatalogProduct = null;
        _confirmedModel = false;
        _catalogMessage = null;
      });
      return;
    }
    setState(() {
      _catalogBusy = true;
      _catalogMessage = null;
      _selectedCatalogProduct = null;
      _confirmedModel = false;
    });
    try {
      final detail = await widget.cloudApi!.catalogProduct(result.id);
      if (!mounted) return;
      if (detail.id != result.id ||
          detail.brand.toLowerCase() !=
              _manufacturer.text.trim().toLowerCase() ||
          detail.fullModel.toLowerCase() != _model.text.trim().toLowerCase() ||
          detail.fuel != _fuel ||
          detail.region != null &&
              detail.region!.toLowerCase() !=
                  widget.cloudHome!.countryCode.toLowerCase()) {
        setState(
          () => _catalogMessage = 'Product details no longer match the entered model and fuel. Search again.',
        );
        return;
      }
      setState(() => _catalogDetail = detail);
    } catch (_) {
      if (mounted) {
        setState(
          () => _catalogMessage =
              'Could not load reviewed product details. Try again.',
        );
      }
    } finally {
      if (mounted) setState(() => _catalogBusy = false);
    }
  }

  void _selectExactCatalog() {
    final detail = _catalogDetail;
    if (detail == null || !detail.isConfirmedExact) return;
    setState(() {
      // Cloud inventory checks canonical fields byte-for-byte at linkage.
      _category = detail.category;
      _manufacturer.text = detail.brand;
      _model.text = detail.fullModel;
      _selectedCatalogProduct = detail;
      _confirmedModel = false;
      _catalogMessage = 'Exact reviewed product selected. Confirm the full label model and fuel before saving.';
    });
  }

  String _modelCheckMessage(EnergyLookup lookup) {
    if (lookup.evidence case final source?) {
      final isFamilySource =
          source.sourceKind == 'oem_family' ||
          source.sourceKind == 'energuide_family';
      return '${isFamilySource ? 'Family source' : 'Matched'} ${source.matchedBrand} ${source.matchedModel} · ${energySourceLabel(source)}';
    }
    return switch (lookup.status) {
      'missing_identity' => 'No manufacturer and model to check. You can save without a sourced estimate.',
      'source_unavailable' =>
        'Energy source unavailable. You can save now and check again later.',
      'ambiguous' || 'truncated' =>
        'Model match needs review. You can save without a sourced estimate.',
      'unsupported_category' => 'No energy model catalog for this category. You can save without a sourced estimate.',
      'no_usable_energy' => 'A product record was found, but it has no usable energy rating. You can save without an estimate.',
      _ => 'No energy rating was found in the catalog for this model. You can save without a sourced estimate.',
    };
  }

  Future<void> _searchWebForModel() async {
    final query =
        '${_category.replaceAll('_', ' ')} ${_manufacturer.text.trim()} ${_model.text.trim()}';
    final uri = Uri.https('www.google.com', '/search', {'q': query});
    await launchUrl(uri, mode: LaunchMode.externalApplication);
  }

  Future<void> _deleteManualAppliance(SavedAppliance item) async {
    if (_busy || item.onboardingMethod != 'manual') return;
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Delete device?'),
        content: Text(
          'Delete “${item.name}” from this hub? This cannot be undone.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Delete'),
          ),
        ],
      ),
    );
    if (confirmed != true || !mounted) return;
    setState(() {
      _busy = true;
      _deleteError = null;
    });
    try {
      await widget.api.deleteManualAppliance(
        _hub.text.trim(),
        _token.text.trim(),
        item.id,
      );
      if (!mounted) return;
      setState(() {
        _saved = _saved.where((row) => row.id != item.id).toList();
        _estimates.remove(item.id);
        _lookupStatuses.remove(item.id);
      });
      await _refresh();
    } catch (error) {
      if (mounted) {
        setState(
          () => _deleteError = error is StateError
              ? error.message
              : 'Could not delete the device. Check the hub connection.',
        );
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _takePhoto({required bool gallery}) async {
    if (_busy) return;
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      final photo = gallery
          ? await widget.capture.pickFromGallery()
          : await widget.capture.capturePhoto();
      if (photo == null) return;
      final details = await Future.wait<String?>([
        widget.capture.extractTextHint(photo.path),
        widget.capture.detectUpc(photo.path),
      ]);
      await widget.capture.discard(photo);
      if (!mounted) return;
      final hint = modelHintFromOcr(details[0]);
      final manufacturerHint = manufacturerHintFromOcr(details[0]);
      // The full label can include a serial number beside the model. Only
      // send the locally extracted model hint for catalog suggestions.
      final modelOnlyOcr = hint == null ? null : 'MODEL NO: $hint';
      List<IdentificationCandidate> candidates = const [];
      var lookupFailed = false;
      if (modelOnlyOcr != null || details[1] != null) {
        try {
          candidates = await widget.api.identifyCandidates(
            _hub.text.trim(),
            _token.text.trim(),
            targetKind: widget.plugId == null ? 'appliance' : 'connected_load',
            ocrText: modelOnlyOcr,
            upc: details[1],
          );
        } catch (_) {
          lookupFailed = true;
        }
      }
      if (!mounted) return;
      setState(() {
        final replaceSuggestedMaker =
            _manufacturer.text.trim().isEmpty ||
            _manufacturer.text.trim() == _photoManufacturerHint;
        _photoBytes = photo.bytes;
        _ocrText = details[0]?.trim().isNotEmpty == true ? (hint ?? '') : null;
        _photoManufacturerHint = manufacturerHint;
        _upc = details[1];
        _photoCandidates = candidates;
        _candidateLookupFailed = lookupFailed;
        _confirmedModel = false;
        _model.text = hint ?? '';
        if (replaceSuggestedMaker) _manufacturer.text = manufacturerHint ?? '';
      });
    } on CameraPermissionDeniedException {
      if (mounted) {
        setState(
          () => _error = 'Camera access was denied. Allow it in settings or choose a photo.',
        );
      }
    } on PhotoLibraryPermissionDeniedException {
      if (mounted) {
        setState(
          () => _error = 'Photo access was denied. Allow it in settings or use the camera.',
        );
      }
    } on FormatException catch (error) {
      if (mounted) setState(() => _error = error.message);
    } catch (_) {
      if (mounted) {
        setState(
          () => _error = 'Could not read this photo. Try again or enter the model manually.',
        );
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _save() async {
    if (_cloudOnly) {
      await _saveCloud();
      return;
    }
    if (_busy) return;
    final hoursText = _hours.text.trim();
    final hours = hoursText.isEmpty ? null : double.tryParse(hoursText);
    final lighting = _category == 'lighting' && _loadKind == 'replaceable_bulb';
    final bulbsText = _bulbs.text.trim();
    final wattsText = _watts.text.trim();
    final bulbs = bulbsText.isEmpty ? null : int.tryParse(bulbsText);
    final watts = wattsText.isEmpty ? null : double.tryParse(wattsText);
    if (_name.text.trim().isEmpty ||
        _hub.text.trim().isEmpty ||
        _token.text.trim().isEmpty ||
        (hoursText.isNotEmpty && (hours == null || hours < 0 || hours > 168)) ||
        (lighting &&
            bulbsText.isNotEmpty &&
            (bulbs == null || bulbs < 1 || bulbs > 8)) ||
        (lighting &&
            wattsText.isNotEmpty &&
            (watts == null || !watts.isFinite || watts <= 0 || watts > 2000)) ||
        (lighting && watts != null && (bulbs == null || hours == null)) ||
        (widget.method == 'photo' && _photoBytes == null) ||
        (widget.method == 'photo' &&
            _model.text.trim().isNotEmpty &&
            !_confirmedModel)) {
      setState(
        () => _error = 'Enter a name and hub details, check weekly hours, and confirm the photo model.',
      );
      return;
    }
    if (widget.method == 'manual' && _checkedModelKey != _modelKey) {
      setState(() => _error = 'Check this model before saving the device.');
      return;
    }
    final checkedLookup = widget.method == 'manual' ? _modelCheck : null;
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      final saved = await widget.api.addAppliance(
        _hub.text.trim(),
        _token.text.trim(),
        ApplianceInput(
          name: _name.text.trim(),
          room: _room.text.trim(),
          category: _category,
          manufacturer: _manufacturer.text.trim(),
          model: _model.text.trim(),
          loadKind: _loadKind,
          onboardingMethod: widget.method,
          hoursPerWeek: hours,
          bulbCount: lighting ? bulbs : null,
          combinedInputWatts: lighting ? watts : null,
        ),
      );
      if (!mounted) return;
      setState(() {
        _saved = [..._saved.where((item) => item.id != saved.id), saved];
        if (checkedLookup != null) {
          _lookupStatuses[saved.id] = checkedLookup.status;
        }
        _checkedModelKey = null;
        _modelCheck = null;
      });
      if (checkedLookup != null ||
          (widget.method == 'photo' &&
              saved.manufacturer.trim().isNotEmpty &&
              saved.model.trim().isNotEmpty)) {
        try {
          final lookup = await widget.api.lookupEnergy(
            _hub.text.trim(),
            _token.text.trim(),
            saved.id,
          );
          if (mounted && lookup.status != 'source_unavailable') {
            setState(() => _lookupStatuses[saved.id] = lookup.status);
          }
          if (lookup.evidence != null) {
            final estimate = await widget.api.estimate(
              _hub.text.trim(),
              _token.text.trim(),
              saved.id,
            );
            if (mounted) setState(() => _estimates[saved.id] = estimate);
          }
        } catch (_) {
          // The saved record stays visible with its pre-save source result.
        }
      }
      if (widget.plugId != null) {
        final attached = await widget.api.attachAppliance(
          _hub.text.trim(),
          _token.text.trim(),
          widget.plugId!,
          saved.id,
        );
        if (mounted) Navigator.pop(context, attached);
        return;
      }
      try {
        await widget.credentials.save(_hub.text.trim(), _token.text.trim());
      } catch (_) {
        if (mounted) {
          setState(
            () =>
                _error = 'Device saved. Enter the hub details again next time.',
          );
        }
      }
      if (mounted && Navigator.of(context).canPop()) {
        Navigator.of(context).pop(saved);
      }
    } catch (error) {
      if (mounted) {
        setState(
          () => _error = error is StateError
              ? error.message
              : 'Could not save the device. Check the hub connection.',
        );
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _saveCloud() async {
    if (_busy) return;
    final name = _name.text.trim();
    final brand = _manufacturer.text.trim();
    final model = _model.text.trim();
    if (name.isEmpty ||
        brand.isEmpty ||
        model.isEmpty ||
        !_confirmedModel ||
        (widget.method == 'photo' && _photoBytes == null)) {
      setState(
        () => _error = 'Enter a name, manufacturer and full model, then confirm the label model and fuel.',
      );
      return;
    }
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      final preferences = await widget.cloudApi!.accountPreferences();
      if (!preferences.value.historyAccepted) {
        if (mounted) {
          setState(
            () => _error = 'Accept the required history disclosure in Cloud settings before saving.',
          );
        }
        return;
      }
      final saved = await widget.cloudApi!.createAppliance(
        widget.cloudHome!.id,
        CloudApplianceCreate(
          name: name,
          category: _category,
          room: _room.text.trim().isEmpty ? null : _room.text.trim(),
          brand: brand,
          fullModel: model,
          fuel: _fuel,
          variant: _selectedCatalogProduct?.variant,
          region: _selectedCatalogProduct?.region,
          catalogProductId: _selectedCatalogProduct?.id,
        ),
        idempotencyKey: _cloudSaveKey,
      );
      if (!mounted) return;
      await Navigator.of(context).push(
        MaterialPageRoute<void>(
          builder: (_) => CloudUsageQuestionsScreen(
            home: widget.cloudHome!,
            appliance: saved,
            api: widget.cloudApi!,
          ),
        ),
      );
      if (mounted && Navigator.of(context).canPop()) {
        Navigator.of(context).pop();
      }
    } on CloudApiException catch (error) {
      if (mounted) {
        setState(
          () => _error = error.statusCode == 409
              ? 'Cloud reported a conflict. Refresh your home inventory before trying again.'
              : 'Could not confirm Cloud save (${error.code}). Refresh inventory before retrying unchanged details.',
        );
      }
    } catch (_) {
      if (mounted) {
        setState(
          () => _error = 'Could not confirm Cloud save. Refresh inventory before retrying unchanged details.',
        );
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _checkEnergy(
    SavedAppliance item, {
    bool fetchSource = true,
  }) async {
    if (_busy) return;
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      if (fetchSource) {
        final lookup = await widget.api.lookupEnergy(
          _hub.text.trim(),
          _token.text.trim(),
          item.id,
        );
        if (mounted) setState(() => _lookupStatuses[item.id] = lookup.status);
        if (lookup.evidence == null) return;
      }
      final estimate = await widget.api.estimate(
        _hub.text.trim(),
        _token.text.trim(),
        item.id,
      );
      if (mounted) setState(() => _estimates[item.id] = estimate);
    } catch (error) {
      if (mounted) {
        setState(
          () => _error = error is StateError ? error.message : 'Could not check energy data. Try again when the hub is online.',
        );
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  String _estimateStatus(int id) =>
      switch (_lookupStatuses[id] ?? _estimates[id]?.reason) {
        'not_checked' || null => 'Estimate unavailable · Check energy data',
        'unsupported_category' =>
          'Estimate unavailable · No matched energy data for this category',
        'missing_identity' =>
          'Estimate unavailable · Exact manufacturer and model needed',
        'ambiguous' ||
        'truncated' => 'Estimate unavailable · Model match needs review',
        'source_unavailable' =>
          'Estimate unavailable · ENERGY STAR data could not be reached',
        'no_usable_energy' =>
          'Estimate unavailable · Matched record has no usable energy figure',
        'no_match' => 'Estimate unavailable · No exact source model match',
        _ => 'Estimate unavailable',
      };

  void _showSource(EnergyEvidence source, EnergyEstimate estimate) {
    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      builder: (context) => SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(20),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                energySourceHeading(source),
                style: Theme.of(context).textTheme.titleLarge,
              ),
              const SizedBox(height: 10),
              if (source.sourceKind != 'user_label')
                Text(
                  '${source.sourceKind == 'oem_family' || source.sourceKind == 'energuide_family' ? 'Source covers' : 'Matched model'}: ${source.matchedBrand} ${source.matchedModel}',
                ),
              Text(
                source.sourceKind == 'user_label'
                    ? 'Calculated energy: ${source.annualKwh.toStringAsFixed(1)} kWh/year'
                    : 'Published energy${estimate.bulbCount != null && estimate.bulbCount! > 1 ? ' per bulb' : ''}: ${source.annualKwh.toStringAsFixed(1)} kWh/year',
              ),
              Text('Basis: ${source.usageBasis}'),
              if (source.sourceKind != 'user_label')
                Text('Dataset: ${source.datasetId}'),
              Text(energyRateDescription(estimate)),
              if (estimate.rateSourceUrl case final url?) SelectableText(url),
              Text(
                'Retrieved: ${DateTime.fromMillisecondsSinceEpoch(source.retrievedAt * 1000).toLocal()}',
              ),
              const SizedBox(height: 10),
              if (source.sourceUrl.isNotEmpty) SelectableText(source.sourceUrl),
              const SizedBox(height: 12),
              const Text(
                'This is an estimate for the identified appliance, not a measured reading.',
              ),
            ],
          ),
        ),
      ),
    );
  }

  @override
  void dispose() {
    for (final controller in [
      _hub,
      _token,
      _name,
      _room,
      _manufacturer,
      _model,
      _hours,
      _bulbs,
      _watts,
    ]) {
      controller.dispose();
    }
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final photo = widget.method == 'photo';
    return Scaffold(
      appBar: AppBar(
        title: Text(
          widget.plugId != null
              ? 'Identify connected appliance'
              : photo
              ? 'Identify from a photo'
              : 'Enter device details',
        ),
      ),
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.all(20),
          children: [
            Text(
              photo
                  ? 'Find a model from its label'
                  : 'Add an appliance by hand',
              style: theme.textTheme.titleLarge,
            ),
            const SizedBox(height: 8),
            Text(
              photo
                  ? _cloudOnly
                        ? 'Take a photo or choose the one you already took. EnergyLens reads the model on the phone and checks reviewed suggestions. Confirm the exact label model before saving.'
                        : 'Take a photo or choose the one you already took. Label recognition stays on this phone. Confirm the exact model and maker; a paired local hub is needed to check suggestions or save this device. This does not add it to a Cloud home.'
                  : _cloudOnly
                  ? 'Enter the full model from its label and confirm its fuel. This saves an inventory record to your cloud home; energy source matching comes later.'
                  : 'Enter the model from the appliance label or manual, then check it before saving. A model without a matching source can still be saved without an estimate.',
            ),
            if (_cloudOnly) ...[
              const SizedBox(height: 8),
              Text(
                'Saving to ${widget.cloudHome!.name} in Cloud. This record is not linked to a local hub or meter.',
              ),
            ],
            if (widget.plugId != null) ...[
              const SizedBox(height: 8),
              const Text(
                'For appliance-specific readings, connect only this appliance to the plug. A shared plug measures the combined load.',
              ),
            ],
            if (photo) ...[
              const SizedBox(height: 16),
              Wrap(
                spacing: 8,
                children: [
                  FilledButton.icon(
                    onPressed: _busy ? null : () => _takePhoto(gallery: false),
                    icon: const Icon(Icons.photo_camera_outlined),
                    label: const Text('Take photo'),
                  ),
                  OutlinedButton.icon(
                    onPressed: _busy ? null : () => _takePhoto(gallery: true),
                    icon: const Icon(Icons.photo_library_outlined),
                    label: const Text('Choose photo'),
                  ),
                ],
              ),
              if (_photoBytes != null) ...[
                const SizedBox(height: 12),
                Text('Photo search result', style: theme.textTheme.titleMedium),
                const SizedBox(height: 6),
                SizedBox(
                  height: 180,
                  child: Image.memory(
                    _photoBytes!,
                    fit: BoxFit.contain,
                    errorBuilder: (_, _, _) => const Text('Photo captured'),
                  ),
                ),
                Text(
                  _ocrText == null
                      ? 'No label text found. Enter the model yourself.'
                      : 'Label text found. Check the suggested model below.',
                ),
                if (_photoManufacturerHint != null)
                  Text(
                    'Maker suggested from label: $_photoManufacturerHint · confirm before saving',
                  ),
                if (_upc != null)
                  Text('Barcode found: $_upc · Model still needs confirmation'),
                if (_photoCandidates.isNotEmpty) ...[
                  const SizedBox(height: 8),
                  Text(
                    'Possible models',
                    style: Theme.of(context).textTheme.titleSmall,
                  ),
                  for (final candidate in _photoCandidates)
                    ListTile(
                      key: Key('photoCandidate-${candidate.model}'),
                      contentPadding: EdgeInsets.zero,
                      title: Text(
                        '${candidate.manufacturer.isEmpty ? '' : '${candidate.manufacturer} '}${candidate.model}',
                      ),
                      subtitle: Text(
                        '${candidate.evidenceLabel}${candidate.category == null ? '' : ' · ${candidate.category}'} · Check against the label',
                      ),
                      trailing: const Icon(Icons.chevron_right),
                      onTap: () => setState(() {
                        _manufacturer.text = candidate.manufacturer;
                        _model.text = candidate.model;
                        _confirmedModel = false;
                      }),
                    ),
                ] else if (_candidateLookupFailed)
                  const Text(
                    'Model suggestions unavailable. Enter or confirm the label model manually.',
                  ),
              ],
            ],
            const SizedBox(height: 16),
            TextField(
              key: const Key('applianceName'),
              controller: _name,
              decoration: const InputDecoration(
                labelText: 'Device name',
                border: OutlineInputBorder(),
              ),
            ),
            const SizedBox(height: 10),
            TextField(
              key: const Key('applianceRoom'),
              controller: _room,
              decoration: const InputDecoration(
                labelText: 'Room',
                border: OutlineInputBorder(),
              ),
            ),
            const SizedBox(height: 10),
            DropdownButtonFormField<String>(
              key: ValueKey('applianceCategory-$_category'),
              initialValue: _category,
              decoration: const InputDecoration(
                labelText: 'Category',
                border: OutlineInputBorder(),
              ),
              items: [
                const DropdownMenuItem(
                  value: 'computer',
                  child: Text('Computer'),
                ),
                const DropdownMenuItem(
                  value: 'lighting',
                  child: Text('Lamp or bulb'),
                ),
                const DropdownMenuItem(
                  value: 'refrigerator',
                  child: Text('Refrigerator'),
                ),
                DropdownMenuItem(
                  value: _cloudOnly ? 'television' : 'tv',
                  child: const Text('TV'),
                ),
                if (_cloudOnly) ...const [
                  DropdownMenuItem(value: 'washer', child: Text('Washer')),
                  DropdownMenuItem(value: 'dryer', child: Text('Dryer')),
                  DropdownMenuItem(
                    value: 'dishwasher',
                    child: Text('Dishwasher'),
                  ),
                  DropdownMenuItem(
                    value: 'space_heater',
                    child: Text('Space heater'),
                  ),
                  DropdownMenuItem(
                    value: 'air_conditioner',
                    child: Text('Air conditioner'),
                  ),
                ],
                const DropdownMenuItem(
                  value: 'other',
                  child: Text('Other appliance'),
                ),
                if (_cloudOnly &&
                    !const {
                      'computer',
                      'lighting',
                      'refrigerator',
                      'tv',
                      'television',
                      'washer',
                      'dryer',
                      'dishwasher',
                      'space_heater',
                      'air_conditioner',
                      'other',
                    }.contains(_category))
                  DropdownMenuItem(
                    value: _category,
                    child: Text('Reviewed: $_category'),
                  ),
              ],
              onChanged: (value) => setState(() {
                _category = value ?? _category;
                _loadKind = _category == 'lighting'
                    ? 'replaceable_bulb'
                    : 'appliance';
                if (_cloudOnly) {
                  _confirmedModel = false;
                  _cloudSaveKey = newCloudIdempotencyKey();
                  _selectedCatalogProduct = null;
                  _catalogDetail = null;
                  _catalogResults = const [];
                }
              }),
            ),
            if (_category == 'lighting' && !_cloudOnly) ...[
              const SizedBox(height: 10),
              DropdownButtonFormField<String>(
                initialValue: _loadKind,
                decoration: const InputDecoration(
                  labelText: 'Light source',
                  border: OutlineInputBorder(),
                ),
                items: const [
                  DropdownMenuItem(
                    value: 'replaceable_bulb',
                    child: Text('Replaceable bulb'),
                  ),
                  DropdownMenuItem(
                    value: 'integrated_lamp',
                    child: Text('Integrated LED lamp'),
                  ),
                ],
                onChanged: (value) =>
                    setState(() => _loadKind = value ?? _loadKind),
              ),
              if (_loadKind == 'replaceable_bulb' && !_cloudOnly) ...[
                const SizedBox(height: 10),
                TextField(
                  key: const Key('bulbCount'),
                  controller: _bulbs,
                  decoration: const InputDecoration(
                    labelText: 'Number of installed bulbs',
                    hintText: '2',
                    border: OutlineInputBorder(),
                  ),
                  keyboardType: TextInputType.number,
                ),
                const SizedBox(height: 10),
                TextField(
                  key: const Key('combinedBulbWatts'),
                  controller: _watts,
                  decoration: const InputDecoration(
                    labelText: 'Combined actual bulb watts (optional)',
                    hintText: 'For two 9.5 W bulbs, enter 19',
                    helperText: 'Add wattages from the installed bulb labels; do not use the fixture maximum.',
                    border: OutlineInputBorder(),
                  ),
                  keyboardType: const TextInputType.numberWithOptions(
                    decimal: true,
                  ),
                ),
              ],
            ],
            const SizedBox(height: 10),
            TextField(
              key: const Key('applianceManufacturer'),
              controller: _manufacturer,
              onChanged: (_) => setState(() {}),
              decoration: const InputDecoration(
                labelText: 'Manufacturer',
                border: OutlineInputBorder(),
              ),
            ),
            const SizedBox(height: 10),
            TextField(
              key: const Key('applianceModel'),
              controller: _model,
              onChanged: (_) => setState(() => _confirmedModel = false),
              decoration: InputDecoration(
                labelText: _cloudOnly
                    ? 'Full model'
                    : _loadKind == 'replaceable_bulb'
                    ? 'Bulb model'
                    : 'Exact model',
                border: const OutlineInputBorder(),
              ),
            ),
            if ((photo || _cloudOnly) && _model.text.trim().isNotEmpty)
              CheckboxListTile(
                value: _confirmedModel,
                onChanged: (value) =>
                    setState(() => _confirmedModel = value ?? false),
                title: Text(
                  _cloudOnly
                      ? 'I checked this full model and fuel against the label'
                      : 'I checked this model against the label',
                ),
                contentPadding: EdgeInsets.zero,
              ),
            if (_cloudOnly) ...[
              DropdownButtonFormField<String>(
                key: const Key('cloudApplianceFuel'),
                initialValue: _fuel,
                decoration: const InputDecoration(
                  labelText: 'Fuel or energy source',
                ),
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
                onChanged: (value) => setState(() {
                  _fuel = value ?? _fuel;
                  _confirmedModel = false;
                  _cloudSaveKey = newCloudIdempotencyKey();
                  _selectedCatalogProduct = null;
                  _catalogDetail = null;
                  _catalogResults = const [];
                }),
              ),
              const SizedBox(height: 12),
              OutlinedButton.icon(
                key: const Key('searchReviewedCatalog'),
                onPressed: _catalogBusy || _busy
                    ? null
                    : _searchReviewedCatalog,
                icon: const Icon(Icons.fact_check_outlined),
                label: const Text('Check reviewed catalog'),
              ),
              if (_catalogBusy) const LinearProgressIndicator(),
              if (_catalogMessage != null)
                Text(_catalogMessage!, key: const Key('catalogMessage')),
              for (final product in _catalogResults)
                Card(
                  child: ListTile(
                    key: Key('catalogProduct-${product.id}'),
                    title: Text('${product.brand} ${product.fullModel}'),
                    subtitle: Text(
                      product.isConfirmedExact
                          ? 'Reviewed exact model · ${product.fuel}'
                          : product.isDocumentedFamilyCandidate
                          ? 'Documented family candidate for ${product.matchedModel} · representative SKU ${product.fullModel} · ${product.fuel}'
                          : 'Documented family or unresolved model · ${product.fuel}',
                    ),
                    trailing: const Icon(Icons.chevron_right),
                    onTap: _catalogBusy
                        ? null
                        : () => _openCatalogProduct(product),
                  ),
                ),
              if (_catalogDetail case final detail?) ...[
                const SizedBox(height: 8),
                Text(
                  'Reviewed product details',
                  style: theme.textTheme.titleMedium,
                ),
                Text(
                  '${detail.brand} ${detail.fullModel}${detail.variant == null ? '' : ' · ${detail.variant}'} · ${detail.fuel}${detail.region == null ? '' : ' · ${detail.region}'} · ${detail.category}',
                ),
                if (detail.isDocumentedFamilyCandidate)
                  Text(
                    'Entered model: ${detail.matchedModel}. Representative catalog SKU: ${detail.fullModel}. ${detail.variantMatch == 'confirmed' ? 'Variant matched to the documented family.' : 'Variant remains unresolved.'} Confirm the model and fuel from the appliance label before saving. This family candidate will not be linked or used for an energy cost estimate.',
                  ),
                Text(
                  detail.isConfirmedExact
                      ? 'Exact reviewed identity. Select it only if the full label model and fuel agree.'
                      : 'Documented family or unresolved identity. It cannot be linked as an exact product.',
                ),
                if (detail.facts.isEmpty)
                  const Text(
                    'No reviewed energy facts are attached to this product.',
                  ),
                for (final fact in detail.facts) ...[
                  Text(
                    '${fact.kind}: ${fact.value} ${fact.unit} · ${fact.sourceKind}',
                  ),
                  Text(
                    'Test basis: ${fact.testBasis.isEmpty ? 'not stated' : fact.testBasis.entries.map((entry) => '${entry.key}: ${entry.value}').join(', ')}',
                  ),
                  Text('Reviewed ${fact.reviewedAt.toUtc().toIso8601String()}'),
                  SelectableText(fact.sourceUrl),
                ],
                const Text(
                  'A reviewed identity or fact does not establish this home’s actual energy use.',
                ),
                if (detail.isConfirmedExact)
                  FilledButton(
                    key: const Key('selectExactCatalogProduct'),
                    onPressed: _catalogBusy ? null : _selectExactCatalog,
                    child: const Text('Select exact reviewed product'),
                  ),
              ],
              if (_selectedCatalogProduct != null)
                Text(
                  'Selected exact reviewed product: ${_selectedCatalogProduct!.brand} ${_selectedCatalogProduct!.fullModel}',
                ),
            ],
            if (!photo && !_cloudOnly) ...[
              const SizedBox(height: 10),
              OutlinedButton.icon(
                key: const Key('checkModelBeforeSave'),
                onPressed: _busy ? null : _checkModelBeforeSave,
                icon: const Icon(Icons.search),
                label: const Text('Check model'),
              ),
              if (_checkedModelKey == _modelKey && _modelCheck != null)
                Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      _modelCheckMessage(_modelCheck!),
                      key: const Key('modelCheckResult'),
                      style: TextStyle(
                        color: _modelCheck!.evidence == null
                            ? theme.colorScheme.error
                            : theme.colorScheme.primary,
                      ),
                    ),
                    if (_modelCheck!.evidence == null &&
                        _model.text.trim().isNotEmpty &&
                        _modelCheck!.status != 'missing_identity' &&
                        _modelCheck!.status != 'source_unavailable')
                      TextButton.icon(
                        key: const Key('searchWebForModel'),
                        onPressed: _searchWebForModel,
                        icon: const Icon(Icons.open_in_new),
                        label: const Text('Search web'),
                      ),
                  ],
                ),
            ],
            if (!_cloudOnly) ...[
              const SizedBox(height: 10),
              TextField(
                key: const Key('applianceHours'),
                controller: _hours,
                decoration: const InputDecoration(
                  labelText: 'Hours used per week (optional)',
                  border: OutlineInputBorder(),
                ),
                keyboardType: const TextInputType.numberWithOptions(
                  decimal: true,
                ),
              ),
              const SizedBox(height: 12),
              TextField(
                key: const Key('hubAddress'),
                controller: _hub,
                onChanged: (_) => setState(() {}),
                decoration: const InputDecoration(
                  labelText: 'Hub address',
                  hintText: 'https://192.168.68.136:18787#sha256=…',
                  border: OutlineInputBorder(),
                ),
              ),
              const SizedBox(height: 10),
              TextField(
                key: const Key('hubToken'),
                controller: _token,
                onChanged: (_) => setState(() {}),
                obscureText: true,
                decoration: const InputDecoration(
                  labelText: 'Hub token',
                  border: OutlineInputBorder(),
                ),
              ),
            ],
            if (_error != null) ...[
              const SizedBox(height: 10),
              Text(_error!, style: TextStyle(color: theme.colorScheme.error)),
            ],
            const SizedBox(height: 16),
            FilledButton(
              key: const Key('saveAppliance'),
              onPressed: _busy ? null : _save,
              child: Text(_busy ? 'Saving…' : 'Save device'),
            ),
            if (!_cloudOnly) ...[
              const SizedBox(height: 24),
              Text('Saved appliances', style: theme.textTheme.titleLarge),
              if (_deleteError != null)
                Text(
                  _deleteError!,
                  style: TextStyle(color: theme.colorScheme.error),
                ),
              TextButton(
                onPressed: _refresh,
                child: const Text('Refresh saved appliances'),
              ),
              if (_saved.isEmpty)
                const Text('No appliances saved on this hub yet.'),
              for (final item in _saved)
                Card(
                  child: Padding(
                    padding: const EdgeInsets.all(16),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(item.name, style: theme.textTheme.titleMedium),
                        Text(
                          '${item.category} · ${item.onboardingMethod == 'photo' ? 'Added from photo' : 'Manually added'}',
                        ),
                        if (item.model.isNotEmpty)
                          Text('${item.manufacturer} ${item.model}'.trim()),
                        if (item.bulbCount != null)
                          Text(
                            '${item.bulbCount} installed bulb(s)${item.combinedInputWatts == null ? '' : ' · ${item.combinedInputWatts} W combined'}',
                          ),
                        const Text('No live readings'),
                        const SizedBox(height: 8),
                        if (_estimates[item.id]?.evidence
                            case final source?) ...[
                          Text(
                            _estimates[item.id]!.estimatedCostUsd == null
                                ? 'Estimated monthly energy: ${_estimates[item.id]!.estimatedKwh!.toStringAsFixed(1)} kWh'
                                : '${source.sourceKind == 'energy_star_archive'
                                      ? 'Historical test-profile cost'
                                      : source.sourceKind == 'oem_family'
                                      ? 'Manufacturer family test-profile cost'
                                      : source.sourceKind == 'energuide_family'
                                      ? 'Historical EnerGuide family test-profile cost'
                                      : 'Estimated monthly cost'}: \$${_estimates[item.id]!.estimatedCostUsd!.toStringAsFixed(2)} · ${_estimates[item.id]!.estimatedKwh!.toStringAsFixed(1)} kWh',
                            style: theme.textTheme.titleSmall,
                          ),
                          TextButton.icon(
                            onPressed: () =>
                                _showSource(source, _estimates[item.id]!),
                            icon: Icon(
                              source.sourceKind == 'energy_star'
                                  ? Icons.verified_outlined
                                  : Icons.info_outline,
                            ),
                            label: Text(energySourceLabel(source)),
                          ),
                          OutlinedButton(
                            onPressed: _busy
                                ? null
                                : () => _checkEnergy(item, fetchSource: false),
                            child: const Text('Update cost with my rate'),
                          ),
                        ] else
                          Text(_estimateStatus(item.id)),
                        if ((_lookupStatuses[item.id] ??
                                _estimates[item.id]?.reason) !=
                            'no_match')
                          TextButton(
                            onPressed: _busy ? null : () => _checkEnergy(item),
                            child: const Text('Check energy data'),
                          ),
                        if (item.onboardingMethod == 'manual' &&
                            widget.plugId == null)
                          TextButton.icon(
                            key: Key('delete-appliance-${item.id}'),
                            onPressed: _busy
                                ? null
                                : () => _deleteManualAppliance(item),
                            icon: const Icon(Icons.delete_outline),
                            label: const Text('Delete device'),
                          ),
                      ],
                    ),
                  ),
                ),
            ],
          ],
        ),
      ),
    );
  }
}
