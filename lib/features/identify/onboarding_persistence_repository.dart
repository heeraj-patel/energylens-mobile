import '../../core/cloud_api/cloud_api_client.dart';
import '../../core/cloud_api/cloud_appliance.dart';
import '../../core/cloud_api/cloud_catalog.dart';

abstract interface class OnboardingPersistenceSource {
  Future<CloudAppliance> create(
    String homeId,
    CloudApplianceCreate input,
    String key,
  );
  Future<CloudAppliance> detail(String homeId, String applianceId);
  Future<List<CloudAppliance>> inventory(String homeId);
  Future<String> version(String homeId, String applianceId);
  Future<void> archive(
    String homeId,
    String applianceId,
    String etag,
    String key,
  );
}

class CloudOnboardingPersistenceSource implements OnboardingPersistenceSource {
  const CloudOnboardingPersistenceSource(this.api);
  final CloudApiClient api;

  @override
  Future<CloudAppliance> create(
    String homeId,
    CloudApplianceCreate input,
    String key,
  ) => api.createAppliance(homeId, input, idempotencyKey: key);
  @override
  Future<CloudAppliance> detail(String homeId, String applianceId) async =>
      (await api.appliance(homeId, applianceId)).value;
  @override
  Future<List<CloudAppliance>> inventory(String homeId) =>
      api.appliances(homeId);
  @override
  Future<String> version(String homeId, String applianceId) async =>
      (await api.appliance(homeId, applianceId)).etag;
  @override
  Future<void> archive(
    String homeId,
    String applianceId,
    String etag,
    String key,
  ) => api.archiveAppliance(
    homeId,
    applianceId,
    ifMatch: etag,
    idempotencyKey: key,
  );
}

/// The caller keeps [operationKey] with the draft across app restarts and uses
/// the same key for an uncertain retry. A new key represents a new operation.
class OnboardingDraft {
  const OnboardingDraft({
    required this.name,
    required this.category,
    required this.brand,
    required this.fullModel,
    required this.fuel,
    this.room,
    this.reviewedProduct,
    this.fccId,
    this.icId,
    this.serialNumber,
    this.upc,
    this.bulbLabel,
  });
  final String name;
  final String category;
  final String brand;
  final String fullModel;
  final String fuel;
  final String? room;
  final CloudCatalogProduct? reviewedProduct;
  final String? fccId;
  final String? icId;
  final String? serialNumber;
  final String? upc;
  final BulbLabel? bulbLabel;

  CloudApplianceCreate validated() {
    String requiredText(String value, String field) {
      final trimmed = value.trim();
      if (trimmed.isEmpty || trimmed.length > 120) {
        throw ArgumentError.value(value, field);
      }
      return trimmed;
    }

    final normalizedName = requiredText(name, 'name');
    final normalizedCategory = requiredText(category, 'category');
    String optionalText(String value, String field) {
      final trimmed = value.trim();
      if (trimmed.length > 120) throw ArgumentError.value(value, field);
      return trimmed;
    }

    String? optionalIdentity(String? value, String field) {
      final trimmed = value?.trim();
      if (trimmed == null || trimmed.isEmpty) return null;
      if (trimmed.length > 120) throw ArgumentError.value(value, field);
      return trimmed;
    }

    final normalizedBrand = optionalText(brand, 'brand');
    final normalizedModel = optionalText(fullModel, 'fullModel');
    final normalizedRoom = room?.trim();
    if (normalizedRoom != null && normalizedRoom.length > 120) {
      throw ArgumentError.value(room, 'room');
    }
    if (!const {
      'electricity',
      'natural_gas',
      'propane',
      'fuel_oil',
    }.contains(fuel)) {
      throw ArgumentError.value(fuel, 'fuel');
    }
    final product = reviewedProduct;
    if (product != null && !_uuid.hasMatch(product.id)) {
      throw ArgumentError.value(product, 'reviewedProduct');
    }
    return CloudApplianceCreate(
      name: normalizedName,
      category: normalizedCategory,
      room: normalizedRoom == null || normalizedRoom.isEmpty
          ? null
          : normalizedRoom,
      brand: normalizedBrand,
      fullModel: normalizedModel,
      fuel: fuel,
      variant: product?.variant,
      region: product?.region,
      catalogProductId: product?.id,
      matchQuality: product == null ? 'unresolved' : product.matchQuality,
      fccId: optionalIdentity(fccId, 'fccId'),
      icId: optionalIdentity(icId, 'icId'),
      serialNumber: optionalIdentity(serialNumber, 'serialNumber'),
      upc: optionalIdentity(upc, 'upc'),
      bulbLabel: bulbLabel,
    );
  }
}

final _uuid = RegExp(
  r'^[0-9a-fA-F]{8}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{12}$',
);
final _key = RegExp(
  r'^[0-9a-f]{8}-[0-9a-f]{4}-4[0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$',
);

class _SaveOperation {
  _SaveOperation(this.fingerprint);
  final String fingerprint;
  String? applianceId;
  CloudAppliance? confirmed;
  Future<CloudAppliance?>? running;
}

class _ArchiveOperation {
  String? etag;
  Future<bool?>? running;
  bool confirmed = false;
}

class OnboardingPersistenceRepository {
  OnboardingPersistenceRepository(this.source);
  final OnboardingPersistenceSource source;
  final Map<String, _SaveOperation> _saves = {};
  final Map<String, _ArchiveOperation> _archives = {};
  String? _homeId;
  int _homeGeneration = 0;
  int _readGeneration = 0;
  List<CloudAppliance>? _inventory;

  List<CloudAppliance>? get activeInventory => _inventory;

  void selectHome(String? homeId) {
    if (homeId != null && !_uuid.hasMatch(homeId)) {
      throw ArgumentError.value(homeId, 'homeId');
    }
    if (_homeId == homeId) return;
    _homeId = homeId;
    _homeGeneration++;
    _readGeneration++;
    _inventory = null;
    _saves.clear();
    _archives.clear();
  }

  Future<List<CloudAppliance>?> refresh() async {
    final home = _homeId;
    if (home == null) return null;
    final generation = ++_readGeneration;
    final rows = await source.inventory(home);
    if (_homeId != home || _readGeneration != generation) return null;
    if (rows.any((row) => row.homeId != home) ||
        rows.map((row) => row.id).toSet().length != rows.length) {
      throw const FormatException('Invalid active inventory');
    }
    _inventory = List.unmodifiable(rows);
    return _inventory;
  }

  Future<CloudAppliance?> save(
    OnboardingDraft draft, {
    required String operationKey,
  }) {
    final home = _homeId;
    if (home == null) throw StateError('Select a home before saving');
    if (!_key.hasMatch(operationKey)) {
      throw ArgumentError.value(operationKey, 'operationKey');
    }
    final input = draft.validated();
    final fingerprint = input.toJson().toString();
    final operation = _saves.putIfAbsent(
      operationKey,
      () => _SaveOperation(fingerprint),
    );
    if (operation.fingerprint != fingerprint) {
      throw StateError(
        'An operation key cannot be reused for different details',
      );
    }
    if (operation.running case final running?) return running;
    if (operation.confirmed case final confirmed?) {
      return Future.value(confirmed);
    }
    final generation = _homeGeneration;
    final future = _save(home, generation, input, operationKey, operation);
    operation.running = future;
    future.whenComplete(() {
      operation.running = null;
    }).ignore();
    return future;
  }

  Future<CloudAppliance?> _save(
    String home,
    int generation,
    CloudApplianceCreate input,
    String key,
    _SaveOperation operation,
  ) async {
    if (operation.applianceId == null) {
      final created = await source.create(home, input, key);
      if (_homeId != home || _homeGeneration != generation) return null;
      if (created.homeId != home || !_uuid.hasMatch(created.id)) {
        throw const FormatException('Created appliance ownership changed');
      }
      operation.applianceId = created.id;
    }
    final detail = await source.detail(home, operation.applianceId!);
    if (_homeId != home || _homeGeneration != generation) return null;
    if (detail.homeId != home ||
        detail.id != operation.applianceId ||
        detail.name != input.name ||
        detail.category != input.category ||
        detail.brand != input.brand ||
        detail.fullModel != input.fullModel ||
        detail.fuel != input.fuel ||
        detail.room != input.room ||
        detail.variant != input.variant ||
        detail.region != input.region ||
        detail.matchQuality != input.matchQuality ||
        detail.catalogProductId != input.catalogProductId) {
      throw const FormatException('Saved appliance readback differs');
    }
    _inventory = null;
    final inventory = await refresh();
    if (_homeId != home || _homeGeneration != generation) return null;
    if (inventory == null ||
        !inventory.any((row) => row.id == detail.id && row.homeId == home)) {
      throw const FormatException('Saved appliance missing from inventory');
    }
    operation.confirmed = detail;
    return _homeId == home && _homeGeneration == generation ? detail : null;
  }

  Future<bool?> archive(String applianceId, {required String operationKey}) {
    final home = _homeId;
    if (home == null) throw StateError('Select a home before archiving');
    if (!_uuid.hasMatch(applianceId) || !_key.hasMatch(operationKey)) {
      throw ArgumentError('Invalid appliance or operation key');
    }
    final slot = '$home/$applianceId/$operationKey';
    final operation = _archives.putIfAbsent(slot, _ArchiveOperation.new);
    if (operation.running case final running?) return running;
    if (operation.confirmed) return Future.value(true);
    final generation = _homeGeneration;
    final future = _archive(
      home,
      generation,
      applianceId,
      operationKey,
      operation,
    );
    operation.running = future;
    future.whenComplete(() {
      operation.running = null;
    }).ignore();
    return future;
  }

  Future<bool?> _archive(
    String home,
    int generation,
    String applianceId,
    String key,
    _ArchiveOperation operation,
  ) async {
    operation.etag ??= await source.version(home, applianceId);
    if (_homeId != home || _homeGeneration != generation) return null;
    await source.archive(home, applianceId, operation.etag!, key);
    if (_homeId != home || _homeGeneration != generation) return null;
    _inventory = null;
    final rows = await refresh();
    if (rows == null) return null;
    if (rows.any((row) => row.id == applianceId)) {
      throw const FormatException('Archived appliance remains active');
    }
    _saves.removeWhere((_, save) => save.applianceId == applianceId);
    operation.confirmed = true;
    return true;
  }
}
