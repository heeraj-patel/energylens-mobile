import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter/material.dart';

import '../../core/cloud_api/cloud_api_client.dart';
import '../../core/cloud_api/cloud_appliance.dart';
import '../../core/cloud_api/cloud_home.dart';
import '../../core/cloud_api/cloud_energy_categories.dart';
import '../discovery/discovery_api.dart';
import '../discovery/discovery_credentials.dart';
import 'photo_capture_service.dart';
import 'cloud_usage_questions_screen.dart';
import 'onboarding_draft_store.dart';
import 'onboarding_persistence_repository.dart';

class OcrIdentityFields {
  const OcrIdentityFields({
    this.model,
    this.serialNumber,
    this.fccId,
    this.icId,
  });
  final String? model;
  final String? serialNumber;
  final String? fccId;
  final String? icId;
}

final _ocrModelPattern = RegExp(
  r'\b(?:MODEL|MOD[ÈE]LE|MOD|M/N|MDL)\b\.?(?:[ \t]*/[ \t]*MOD[ÈE]LE\b\.?)?(?:[ \t]*(?:NO\b\.?|NUMBER\b|#))?[ \t]*[:#.]?\s*([A-Z0-9][A-Z0-9/.\-]{2,31})',
  caseSensitive: false,
);
final _ocrSerialPattern = RegExp(
  r'\b(?:S/N|SN|SER(?:IAL)?\b\.?(?:[ \t]*(?:NO\b\.?|NUMBER\b|#))?)[ \t]*[:#.]?\s*([A-Z0-9][A-Z0-9\-]{3,31})',
  caseSensitive: false,
);
final _ocrFccPattern = RegExp(
  r'\bFCC[ \t]*ID[ \t]*[:#.]?[ \t]*((?:2[A-Z0-9]{4})|(?:[A-Z0-9]{3}))([ \t-]?)([A-Z0-9\-]{1,14})\b',
  caseSensitive: false,
);
final _ocrIcPattern = RegExp(
  r'\b(?:ISED[ \t]+)?IC[ \t]*(?:ID)?[ \t]*[:#.]?[ \t]*(\d{1,6}[A-Z]?)[ \t]*-[ \t]*([A-Z0-9]{1,11})\b',
  caseSensitive: false,
);

RegExpMatch? _firstOcrModelMatch(String text) {
  for (final match in _ocrModelPattern.allMatches(text)) {
    final value = match.group(1)!.replaceFirst(RegExp(r'[./\-]+$'), '');
    if (RegExp(r'\d').hasMatch(value)) return match;
  }
  return null;
}

String? _firstOcrValue(RegExp pattern, String text) {
  for (final match in pattern.allMatches(text)) {
    final value = match.group(1)!.replaceFirst(RegExp(r'[./\-]+$'), '');
    if (RegExp(r'\d').hasMatch(value)) return value.toUpperCase();
  }
  return null;
}

/// Label fields are stored as identity hints; the user still confirms the model.
OcrIdentityFields identityFieldsFromOcr(String text) {
  final model = _firstOcrModelMatch(text)
      ?.group(1)
      ?.replaceFirst(RegExp(r'[./\-]+$'), '')
      .toUpperCase();
  final serial = _firstOcrValue(_ocrSerialPattern, text);
  final fcc = _ocrFccPattern.firstMatch(text);
  final ic = _ocrIcPattern.firstMatch(text);
  return OcrIdentityFields(
    model: model,
    serialNumber: serial,
    fccId: fcc == null
        ? null
        : '${fcc.group(1)}${fcc.group(2) == '-' ? '-' : ''}${fcc.group(3)}'
              .toUpperCase(),
    icId: ic == null ? null : '${ic.group(1)}-${ic.group(2)}'.toUpperCase(),
  );
}

String? modelHintFromOcr(String? text) =>
    text == null ? null : identityFieldsFromOcr(text).model;

/// Returns only a likely maker name; serials and the full OCR text stay local.
String? manufacturerHintFromOcr(String? text) {
  if (text == null) return null;
  final modelMatch = _firstOcrModelMatch(text);
  if (modelMatch == null) return null;
  final lines = text.split(RegExp(r'[\r\n]+'));
  final modelLine = RegExp(r'[\r\n]+')
      .allMatches(text.substring(0, modelMatch.start))
      .length;
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
  final nearbySuggestions = <String>{};
  final explicitKnownMakers = <String>{};
  final first = modelLine - 2 < 0 ? 0 : modelLine - 2;
  final last = modelLine + 2 >= lines.length ? lines.length - 1 : modelLine + 2;
  for (var index = 0; index < lines.length; index++) {
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
    var explicitKnownMaker = false;
    for (final entry in known.entries) {
      if (candidate == entry.key ||
          candidate == '${entry.key} ELECTRONICS' ||
          candidate.startsWith('${entry.key} ELECTRONICS ')) {
        suggestion = entry.value;
        // A maker printed as a company name or in a maker field is useful
        // even when OCR puts several unrelated lines between it and MODEL.
        explicitKnownMaker =
            labeled != null ||
            candidate == '${entry.key} ELECTRONICS' ||
            candidate.startsWith('${entry.key} ELECTRONICS ');
        break;
      }
    }
    if (index >= first &&
        index <= last &&
        suggestion == null &&
        labeled != null &&
        !RegExp(r'\d').hasMatch(candidate)) {
      suggestion = labeled.group(1)!.trim();
    }
    if (explicitKnownMaker && suggestion != null) {
      explicitKnownMakers.add(suggestion);
    }
    if (index >= first && index <= last && suggestion != null) {
      nearbySuggestions.add(suggestion);
    }
  }
  if (nearbySuggestions.length > 1 || explicitKnownMakers.length > 1) {
    return null;
  }
  if (nearbySuggestions.isNotEmpty) {
    final nearby = nearbySuggestions.single;
    if (explicitKnownMakers.isNotEmpty &&
        explicitKnownMakers.single != nearby) {
      return null;
    }
    return nearby;
  }
  return explicitKnownMakers.length == 1 ? explicitKnownMakers.single : null;
}

class ApplianceOnboardingScreen extends StatefulWidget {
  const ApplianceOnboardingScreen({
    required this.method,
    super.key,
    this.plugId,
    this.api = const DiscoveryApi(),
    this.credentials = const DiscoveryCredentials(),
    this.hubAddress,
    this.hubToken,
    this.capture = const PhotoCaptureService(),
    this.cloudHome,
    this.cloudApi,
    this.onboardingDrafts,
    this.nearbyOrigin,
    this.protocolDeviceId,
    this.initialName,
    this.initialManufacturer,
    this.initialModel,
    this.webSearchLauncher,
  }) : assert(method == 'manual' || method == 'photo');

  final String method;
  final String? plugId;
  final DiscoveryApi api;
  final DiscoveryCredentials credentials;
  final String? hubAddress;
  final String? hubToken;
  final PhotoCaptureService capture;
  final CloudHome? cloudHome;
  final CloudApiClient? cloudApi;
  final DurableOnboardingDrafts? onboardingDrafts;
  final CloudNearbyOrigin? nearbyOrigin;
  final String? protocolDeviceId;
  final String? initialName;
  final String? initialManufacturer;
  final String? initialModel;
  final Future<bool> Function(Uri uri)? webSearchLauncher;

  @override
  State<ApplianceOnboardingScreen> createState() =>
      _ApplianceOnboardingScreenState();
}

class _PendingAttachment {
  const _PendingAttachment({
    required this.applianceId,
    required this.hubAddress,
    required this.plugId,
  });

  final int applianceId;
  final String hubAddress;
  final String plugId;
}

class _PhotoRecognition {
  const _PhotoRecognition({
    required this.text,
    required this.upc,
    required this.candidates,
    required this.lookupFailed,
  });

  final String? text;
  final String? upc;
  final List<IdentificationCandidate> candidates;
  final bool lookupFailed;

  String? get modelHint => modelHintFromOcr(text);
  String? get manufacturerHint => manufacturerHintFromOcr(text);
}

class _ApplianceOnboardingScreenState extends State<ApplianceOnboardingScreen> {
  static EnergyCategories? _sessionCategories;
  EnergyCategories? _categories = _sessionCategories;
  String? _categoryGroup;
  final _hub = TextEditingController();
  final _token = TextEditingController();
  final _name = TextEditingController();
  final _room = TextEditingController();
  final _manufacturer = TextEditingController();
  final _model = TextEditingController();
  final _hours = TextEditingController();
  final _bulbs = TextEditingController();
  final _watts = TextEditingController();
  String _category = '';
  String _loadKind = 'appliance';
  String _fuel = 'electricity';
  String _cloudSaveKey = newCloudIdempotencyKey();
  String? _ocrText;
  String? _photoManufacturerHint;
  String? _upc;
  OcrIdentityFields _ocrIdentity = const OcrIdentityFields();
  List<IdentificationCandidate> _photoCandidates = const [];
  bool _candidateLookupFailed = false;
  Uint8List? _photoBytes;
  CapturedPhoto? _photo;
  bool _busy = false;
  String? _error;
  String? _deleteError;
  _PendingAttachment? _pendingAttachment;
  String? _selectedPlugId;
  List<SavedPlug> _savedPlugs = const [];
  bool _savedPlugsLoading = false;
  List<SavedAppliance> _saved = const [];
  final Map<int, EnergyEstimate> _estimates = {};

  bool get _cloudOnly =>
      _selectedPlugId == null &&
      widget.cloudHome != null &&
      widget.cloudApi != null;

  bool get _canSelectSavedPlug =>
      widget.method == 'photo' && widget.plugId == null;

  @override
  void initState() {
    super.initState();
    _selectedPlugId = widget.plugId;
    _name.text = widget.initialName ?? '';
    _manufacturer.text = widget.initialManufacturer ?? '';
    _model.text = widget.initialModel ?? '';
    for (final controller in [_name, _room]) {
      controller.addListener(_cloudInputChanged);
    }
    for (final controller in [_manufacturer, _model]) {
      controller.addListener(_cloudIdentityChanged);
    }
    if (!_cloudOnly) _restore();
    if (_canSelectSavedPlug) unawaited(_loadSavedPlugs());
    unawaited(_loadCategories());
  }

  Future<void> _loadCategories() async {
    try {
      EnergyCategories? fresh;
      if (_cloudOnly) {
        fresh = await widget.cloudApi!.energyCategories(
          etag: _sessionCategories?.etag,
        );
      } else {
        final (address, token) = await _readHub();
        if (address != null && token != null) {
          fresh = await widget.api.energyCategories(address, token);
        }
      }
      if (fresh != null) _sessionCategories = fresh;
      if (!mounted) return;
      setState(() {
        _categories = _sessionCategories;
        for (final group
            in _categories?.groups ?? const <EnergyCategoryGroup>[]) {
          if (group.types.any((type) => type.key == _category)) {
            _categoryGroup = group.key;
            break;
          }
        }
      });
    } catch (_) {
      // Keep the session's last category list while offline.
    }
  }

  Future<(String?, String?)> _readHub() async {
    final address = widget.hubAddress;
    final token = widget.hubToken;
    if (address != null &&
        address.isNotEmpty &&
        token != null &&
        token.isNotEmpty) {
      return (address, token);
    }
    return widget.credentials.read();
  }

  Future<void> _loadSavedPlugs() async {
    if (_savedPlugsLoading) return;
    setState(() => _savedPlugsLoading = true);
    try {
      final (address, token) = await _readHub();
      if (address == null || token == null) {
        if (mounted) setState(() => _savedPlugs = const []);
        return;
      }
      final plugs = await widget.api.saved(address, token);
      if (!mounted) return;
      setState(() {
        _savedPlugs = plugs;
        if (_hub.text.isEmpty) _hub.text = address;
        if (_token.text.isEmpty) _token.text = token;
      });
    } catch (_) {
      // The Cloud-only path remains available when the local hub is offline.
    } finally {
      if (mounted) setState(() => _savedPlugsLoading = false);
    }
  }

  void _selectSavedPlug(String? plugId) {
    if (_busy || _pendingAttachment != null || !_canSelectSavedPlug) return;
    if (plugId != null && !_savedPlugs.any((plug) => plug.id == plugId)) {
      return;
    }
    setState(() {
      _selectedPlugId = plugId;
      _error = null;
    });
    if (plugId != null) unawaited(_refresh());
  }

  void _cloudInputChanged() {
    if (_cloudOnly) _cloudSaveKey = newCloudIdempotencyKey();
  }

  void _cloudIdentityChanged() {
    if (!_cloudOnly) return;
    _cloudInputChanged();
  }

  Future<void> _restore() async {
    try {
      final (address, token) = await _readHub();
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
    CapturedPhoto? captured;
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      final photo = gallery
          ? await widget.capture.pickFromGallery()
          : await widget.capture.capturePhoto();
      if (photo == null) return;
      captured = photo;
      final recognition = await _recognizePhoto(photo);
      if (!mounted) return;
      final previousPhoto = _photo;
      setState(() {
        _setRecognizedPhoto(photo, recognition);
      });
      captured = null;
      if (previousPhoto != null && previousPhoto.path != photo.path) {
        unawaited(widget.capture.discard(previousPhoto));
      }
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
      if (captured != null && captured.path != _photo?.path) {
        unawaited(widget.capture.discard(captured));
      }
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<_PhotoRecognition> _recognizePhoto(
    CapturedPhoto photo, {
    void Function(_PhotoRecognition)? onTextRecognized,
  }) async {
    final details = await Future.wait<String?>([
      widget.capture.extractTextHint(photo.path),
      widget.capture.detectUpc(photo.path),
    ]);
    final hint = modelHintFromOcr(details[0]);
    final modelOnlyOcr = hint == null ? null : 'MODEL NO: $hint';
    onTextRecognized?.call(
      _PhotoRecognition(
        text: details[0],
        upc: details[1],
        candidates: const [],
        lookupFailed: false,
      ),
    );
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
    return _PhotoRecognition(
      text: details[0],
      upc: details[1],
      candidates: candidates,
      lookupFailed: lookupFailed,
    );
  }

  void _setRecognizedPhoto(CapturedPhoto photo, _PhotoRecognition recognition) {
    final hint = recognition.modelHint;
    final manufacturerHint = recognition.manufacturerHint;
    final replaceSuggestedMaker =
        _manufacturer.text.trim().isEmpty ||
        _manufacturer.text.trim() == _photoManufacturerHint;
    _photo = photo;
    _photoBytes = photo.bytes;
    _ocrText = recognition.text?.trim().isNotEmpty == true
        ? (hint ?? '')
        : null;
    _photoManufacturerHint = manufacturerHint;
    _upc = recognition.upc;
    _ocrIdentity = identityFieldsFromOcr(recognition.text ?? '');
    _photoCandidates = recognition.candidates;
    _candidateLookupFailed = recognition.lookupFailed;
    _model.text = hint ?? '';
    if (replaceSuggestedMaker) _manufacturer.text = manufacturerHint ?? '';
  }

  Future<void> _rotatePhoto() async {
    final photo = _photo;
    if (_busy || photo == null) return;
    CapturedPhoto? rotated;
    var adopted = false;
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      final newPhoto = await widget.capture.rotateClockwise(photo);
      rotated = newPhoto;
      final recognition = await _recognizePhoto(
        newPhoto,
        onTextRecognized: (partial) {
          if (!mounted) return;
          setState(() => _setRecognizedPhoto(newPhoto, partial));
          adopted = true;
          if (photo.path != newPhoto.path) {
            unawaited(widget.capture.discard(photo));
          }
        },
      );
      if (!mounted) return;
      setState(() {
        _photoCandidates = recognition.candidates;
        _candidateLookupFailed = recognition.lookupFailed;
      });
    } on FormatException catch (error) {
      if (mounted) setState(() => _error = error.message);
    } catch (_) {
      if (mounted) {
        setState(
          () => _error = 'Could not read this photo. Try again or enter the model manually.',
        );
      }
    } finally {
      if (!adopted && rotated != null) {
        unawaited(widget.capture.discard(rotated));
      }
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _save() async {
    if (_cloudOnly) {
      await _saveCloud();
      return;
    }
    if (_busy) return;
    if (_pendingAttachment != null) {
      await _attachSavedAppliance();
      return;
    }
    final hubAddress = _hub.text.trim();
    final hubToken = _token.text.trim();
    final plugId = _selectedPlugId;
    final hoursText = _hours.text.trim();
    final hours = hoursText.isEmpty ? null : double.tryParse(hoursText);
    final lighting = _category == 'lighting' && _loadKind == 'replaceable_bulb';
    final bulbsText = _bulbs.text.trim();
    final wattsText = _watts.text.trim();
    final bulbs = bulbsText.isEmpty ? null : int.tryParse(bulbsText);
    final watts = wattsText.isEmpty ? null : double.tryParse(wattsText);
    if (_name.text.trim().isEmpty ||
        _category.isEmpty ||
        hubAddress.isEmpty ||
        hubToken.isEmpty ||
        (hoursText.isNotEmpty && (hours == null || hours < 0 || hours > 168)) ||
        (lighting &&
            bulbsText.isNotEmpty &&
            (bulbs == null || bulbs < 1 || bulbs > 8)) ||
        (lighting &&
            wattsText.isNotEmpty &&
            (watts == null || !watts.isFinite || watts <= 0 || watts > 2000)) ||
        (lighting && watts != null && (bulbs == null || hours == null)) ||
        (widget.method == 'photo' && _photoBytes == null)) {
      setState(
        () => _error = 'Enter a name and hub details, check weekly hours, and confirm the photo model.',
      );
      return;
    }
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      final saved = await widget.api.addAppliance(
        hubAddress,
        hubToken,
        ApplianceInput(
          name: _name.text.trim(),
          room: _room.text.trim(),
          category: _category,
          manufacturer: _manufacturer.text.trim(),
          model: _model.text.trim(),
          loadKind: _loadKind,
          onboardingMethod: widget.method,
          protocolDeviceId: widget.protocolDeviceId,
          hoursPerWeek: hours,
          bulbCount: lighting ? bulbs : null,
          combinedInputWatts: lighting ? watts : null,
        ),
      );
      if (!mounted) return;
      setState(() {
        _saved = [..._saved.where((item) => item.id != saved.id), saved];
        if (plugId != null) {
          _pendingAttachment = _PendingAttachment(
            applianceId: saved.id,
            hubAddress: hubAddress,
            plugId: plugId,
          );
        }
      });
      if (plugId != null) {
        await _attachSavedAppliance();
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

  Future<void> _attachSavedAppliance() async {
    final pending = _pendingAttachment;
    if (pending == null) return;
    if (_selectedPlugId != pending.plugId ||
        _hub.text.trim() != pending.hubAddress) {
      setState(
        () => _error = 'Device saved, attachment pending. Return to the original plug and hub address to retry.',
      );
      return;
    }
    final token = _token.text.trim();
    if (token.isEmpty) {
      setState(
        () => _error =
            'Device saved, attachment pending. Enter the hub token to retry.',
      );
      return;
    }
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      final attached = await widget.api.attachAppliance(
        pending.hubAddress,
        token,
        pending.plugId,
        pending.applianceId,
      );
      if (!mounted) return;
      _pendingAttachment = null;
      Navigator.of(context).pop(attached);
    } catch (_) {
      if (mounted) {
        setState(
          () => _error = 'Device saved, attachment pending. Check the hub connection and retry attachment.',
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
        _category.isEmpty ||
        (widget.method == 'photo' && _photoBytes == null)) {
      return;
    }
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      final draft = OnboardingDraft(
        name: name,
        category: _category,
        room: _room.text.trim().isEmpty ? null : _room.text.trim(),
        brand: brand,
        fullModel: model,
        fuel: _fuel,
        fccId: _ocrIdentity.fccId,
        icId: _ocrIdentity.icId,
        serialNumber: _ocrIdentity.serialNumber,
        upc: _upc,
        bulbLabel: _category == 'lighting'
            ? BulbLabel(
                loadKind: _loadKind,
                bulbCount: _loadKind == 'replaceable_bulb'
                    ? int.tryParse(_bulbs.text.trim())
                    : null,
                combinedInputWatts: _loadKind == 'replaceable_bulb'
                    ? double.tryParse(_watts.text.trim())
                    : null,
              )
            : null,
        nearbyOrigin: widget.nearbyOrigin,
      );
      final drafts = widget.onboardingDrafts;
      CloudAppliance saved;
      if (drafts == null) {
        saved = await widget.cloudApi!.createAppliance(
          widget.cloudHome!.id,
          draft.validated(),
          idempotencyKey: _cloudSaveKey,
        );
      } else {
        final pending = await drafts.restore();
        if (pending != null &&
            jsonEncode(pending.draft.validated().toJson()) !=
                jsonEncode(draft.validated().toJson())) {
          throw StateError('A different onboarding draft is pending');
        }
        final confirmed = await drafts.save(draft);
        if (confirmed == null) throw StateError('Onboarding scope changed');
        saved = confirmed;
      }
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
        Navigator.of(context).pop(saved);
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

  Future<void> _checkEnergy(SavedAppliance item) async {
    if (_busy) return;
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      final estimate = await widget.api.estimate(
        _hub.text.trim(),
        _token.text.trim(),
        item.id,
      );
      if (mounted) setState(() => _estimates[item.id] = estimate);
    } catch (_) {
      if (mounted) {
        setState(
          () => _error =
              'Could not check energy data. Try again when the hub is online.',
        );
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  void dispose() {
    final photo = _photo;
    if (photo != null) unawaited(widget.capture.discard(photo));
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
                widget.nearbyOrigin == null
                    ? 'Saving to ${widget.cloudHome!.name} in Cloud. This record is not linked to a local hub or meter.'
                    : widget.cloudHome!.name.trim().isEmpty
                    ? 'Saved to your home'
                    : 'Saved to ${widget.cloudHome!.name.trim()}',
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
                    key: const Key('photoPreview'),
                    _photoBytes!,
                    fit: BoxFit.contain,
                    errorBuilder: (_, _, _) => const Text('Photo captured'),
                  ),
                ),
                Align(
                  alignment: Alignment.center,
                  child: IconButton(
                    tooltip: 'Rotate photo',
                    onPressed: _busy ? null : _rotatePhoto,
                    icon: const Icon(Icons.rotate_90_degrees_cw),
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
              key: ValueKey('applianceGroup-$_categoryGroup'),
              initialValue: _categoryGroup,
              decoration: const InputDecoration(
                labelText: 'Category',
                hintText: 'Choose category',
                border: OutlineInputBorder(),
              ),
              items: [
                for (final group
                    in _categories?.groups ?? const <EnergyCategoryGroup>[])
                  DropdownMenuItem(value: group.key, child: Text(group.label)),
              ],
              onChanged: (value) => setState(() {
                _categoryGroup = value;
                _category = '';
                _loadKind = 'appliance';
              }),
            ),
            const SizedBox(height: 10),
            DropdownButtonFormField<String>(
              key: ValueKey('applianceCategory-$_categoryGroup-$_category'),
              initialValue: _category.isEmpty ? null : _category,
              decoration: InputDecoration(
                labelText: 'Type of Device',
                hintText: _categoryGroup == null
                    ? 'Choose category first'
                    : 'Choose type',
                border: const OutlineInputBorder(),
              ),
              items: [
                for (final type
                    in _categories?.groups
                            .where((group) => group.key == _categoryGroup)
                            .expand((group) => group.types) ??
                        const <EnergyCategoryType>[])
                  DropdownMenuItem(value: type.key, child: Text(type.label)),
                if (_category.isNotEmpty &&
                    !(_categories?.groups.any(
                          (group) =>
                              group.types.any((type) => type.key == _category),
                        ) ??
                        false))
                  DropdownMenuItem(value: _category, child: Text(_category)),
              ],
              onChanged: _categoryGroup == null
                  ? null
                  : (value) => setState(() {
                      _category = value ?? '';
                      _loadKind = _category == 'lighting'
                          ? 'replaceable_bulb'
                          : 'appliance';
                      if (_cloudOnly) {
                        _cloudSaveKey = newCloudIdempotencyKey();
                      }
                    }),
            ),
            if (_category == 'lighting') ...[
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
              if (_loadKind == 'replaceable_bulb') ...[
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
              decoration: InputDecoration(
                labelText: _cloudOnly
                    ? 'Full model'
                    : _loadKind == 'replaceable_bulb'
                    ? 'Bulb model'
                    : 'Exact model',
                border: const OutlineInputBorder(),
              ),
            ),
            if (_canSelectSavedPlug) ...[
              const SizedBox(height: 10),
              DropdownButtonFormField<String?>(
                key: const Key('photoSmartPlug'),
                initialValue: _selectedPlugId,
                decoration: const InputDecoration(
                  labelText: 'Smart plug',
                  border: OutlineInputBorder(),
                ),
                items: [
                  const DropdownMenuItem<String?>(
                    value: null,
                    child: SizedBox.shrink(),
                  ),
                  for (final plug in _savedPlugs)
                    DropdownMenuItem<String?>(
                      value: plug.id,
                      child: Text(plug.name),
                    ),
                ],
                onChanged:
                    _busy || _savedPlugsLoading || _pendingAttachment != null
                    ? null
                    : _selectSavedPlug,
              ),
            ],
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
                  _cloudSaveKey = newCloudIdempotencyKey();
                }),
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
            if (_pendingAttachment != null) ...[
              const SizedBox(height: 10),
              const Text(
                'Device saved, attachment pending. Retry connects the saved device; edits to its details will not be saved.',
                key: Key('attachmentPendingNotice'),
              ),
            ],
            const SizedBox(height: 16),
            FilledButton(
              key: const Key('saveAppliance'),
              onPressed: _busy || _category.isEmpty ? null : _save,
              child: Text(
                _busy
                    ? 'Saving…'
                    : _pendingAttachment != null
                    ? 'Retry attachment'
                    : 'Save device',
              ),
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
                        if (_estimates[item.id]?.estimatedKwh
                            case final kwh?) ...[
                          Text('Energy · ${kwh.toStringAsFixed(1)} kWh'),
                          if (_estimates[item.id]?.estimatedCostUsd
                              case final cost?)
                            Text('Cost · \$${cost.toStringAsFixed(2)}'),
                        ] else
                          const Text('Energy data is not available yet.'),
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
