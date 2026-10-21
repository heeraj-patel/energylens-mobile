import 'dart:convert';

import '../../core/cloud_api/cloud_api_client.dart';
import '../../core/cloud_api/cloud_appliance.dart';
import '../../core/cloud_api/cloud_appliance_detail.dart';
import '../../core/cloud_api/cloud_preferences.dart';

abstract interface class ApplianceIdentityEditSource {
  Future<CloudApplianceDetail> detail(String homeId, String applianceId);
  Future<CloudVersioned<CloudAppliance>> patch(
    String homeId,
    String applianceId,
    CloudAppliancePatch input, {
    required String ifMatch,
    required String idempotencyKey,
  });
}

class CloudApplianceIdentityEditSource implements ApplianceIdentityEditSource {
  const CloudApplianceIdentityEditSource(this.api);
  final CloudApiClient api;

  @override
  Future<CloudApplianceDetail> detail(String homeId, String applianceId) =>
      api.applianceDetail(homeId, applianceId);

  @override
  Future<CloudVersioned<CloudAppliance>> patch(
    String homeId,
    String applianceId,
    CloudAppliancePatch input, {
    required String ifMatch,
    required String idempotencyKey,
  }) => api.updateAppliance(
    homeId,
    applianceId,
    input,
    ifMatch: ifMatch,
    idempotencyKey: idempotencyKey,
  );
}

/// A single verified-home edit. Keep the original validator and mutation key
/// through uncertain retries; a changed field requires a fresh read/session.
class ApplianceIdentityEditor {
  ApplianceIdentityEditor({
    required this.source,
    required this.homeId,
    required this.applianceId,
    required this.isCurrentScope,
    required this.newOperationKey,
  });

  final ApplianceIdentityEditSource source;
  final String homeId;
  final String applianceId;
  final bool Function() isCurrentScope;
  final String Function() newOperationKey;

  CloudApplianceDetail? _loaded;
  CloudAppliancePatch? _pendingPatch;
  String? _pendingBrand;
  String? _pendingModel;
  String? _pendingKey;
  CloudVersioned<CloudAppliance>? _acknowledged;
  Future<CloudAppliance?>? _running;
  CloudAppliance? _confirmed;
  bool _disposed = false;

  void dispose() => _disposed = true;

  bool get hasPendingMutation => _pendingPatch != null && _confirmed == null;

  bool get _current => !_disposed && isCurrentScope();

  Future<CloudAppliance?> load() async {
    if (!_current) return null;
    if (_pendingPatch != null) {
      throw StateError('Cannot reload an appliance while an edit is pending');
    }
    final detail = await source.detail(homeId, applianceId);
    if (!_current) return null;
    _validateDetail(detail);
    _loaded = detail;
    return detail.appliance;
  }

  Future<CloudAppliance?> save(String brand, String fullModel) {
    if (!_current) return Future.value(null);
    final loaded = _loaded;
    if (loaded == null) throw StateError('Load the appliance before editing');
    final nextBrand = brand.trim();
    final nextModel = fullModel.trim();
    if (utf8.encode(nextBrand).length > 120 ||
        utf8.encode(nextModel).length > 240) {
      throw ArgumentError('Invalid appliance identity length');
    }
    if (_running case final running?) {
      if (_pendingBrand != nextBrand || _pendingModel != nextModel) {
        throw StateError('An appliance edit is already pending');
      }
      return running;
    }
    if (_confirmed case final confirmed?) {
      if (_pendingBrand != nextBrand || _pendingModel != nextModel) {
        throw StateError('Start a new edit to change saved details');
      }
      return Future.value(confirmed);
    }
    if (_pendingPatch == null) {
      if (nextBrand == loaded.appliance.brand &&
          nextModel == loaded.appliance.fullModel) {
        return Future.value(loaded.appliance);
      }
      final appliance = loaded.appliance;
      _pendingBrand = nextBrand;
      _pendingModel = nextModel;
      _pendingKey = newOperationKey();
      _pendingPatch = CloudAppliancePatch(
        identity: CloudApplianceIdentityPatch(
          brand: nextBrand,
          fullModel: nextModel,
          fuel: appliance.fuel,
          matchQuality: 'unresolved',
          variant: appliance.variant,
          region: appliance.region,
          fccId: appliance.fccId,
          icId: appliance.icId,
          serialNumber: appliance.serialNumber,
          upc: appliance.upc,
          buildYear: appliance.buildYear,
          bulbLabel: appliance.bulbLabel,
        ),
      );
    } else if (_pendingBrand != nextBrand || _pendingModel != nextModel) {
      throw StateError('An appliance edit is already pending');
    }
    final running = _save(loaded);
    _running = running;
    running.whenComplete(() => _running = null).ignore();
    return running;
  }

  Future<CloudAppliance?> _save(CloudApplianceDetail loaded) async {
    if (!_current) return null;
    if (_acknowledged == null) {
      final response = await source.patch(
        homeId,
        applianceId,
        _pendingPatch!,
        ifMatch: loaded.etag,
        idempotencyKey: _pendingKey!,
      );
      if (!_current) return null;
      _validateIdentity(response.value);
      if (response.value.version == null ||
          loaded.appliance.version == null ||
          response.value.version! <= loaded.appliance.version!) {
        throw const FormatException('Appliance edit version did not advance');
      }
      _acknowledged = response;
    }
    if (!_current) return null;
    final detail = await source.detail(homeId, applianceId);
    if (!_current) return null;
    _validateDetail(detail);
    final expected = _acknowledged!.value;
    final actual = detail.appliance;
    if (detail.etag != _acknowledged!.etag ||
        actual.version != expected.version ||
        actual.brand != expected.brand ||
        actual.fullModel != expected.fullModel ||
        actual.catalogProductId != expected.catalogProductId ||
        actual.matchQuality != expected.matchQuality) {
      throw const FormatException('Edited appliance readback differs');
    }
    _confirmed = actual;
    return actual;
  }

  void _validateDetail(CloudApplianceDetail detail) {
    if (detail.isSample ||
        detail.appliance.demoDeviceId != null ||
        !RegExp(r'^"[1-9][0-9]*"$').hasMatch(detail.etag)) {
      throw const FormatException('Appliance is not editable');
    }
    _validateIdentity(detail.appliance);
  }

  void _validateIdentity(CloudAppliance appliance) {
    if (appliance.homeId != homeId ||
        appliance.id != applianceId ||
        appliance.archivedAt != null ||
        (_pendingBrand != null && appliance.brand != _pendingBrand) ||
        (_pendingModel != null && appliance.fullModel != _pendingModel)) {
      throw const FormatException('Appliance edit scope or identity changed');
    }
  }
}
