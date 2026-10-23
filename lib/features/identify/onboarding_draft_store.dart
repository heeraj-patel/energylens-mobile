import 'dart:convert';
import 'dart:math';

import 'package:flutter_secure_storage/flutter_secure_storage.dart';

import '../../core/cloud_api/cloud_appliance.dart';
import '../../core/cloud_api/cloud_catalog.dart';
import '../../core/cloud_api/cloud_api_client.dart';
import '../../core/cloud_api/cloud_home.dart';
import 'onboarding_persistence_repository.dart';

/// A single, device-local draft slot. No image, OCR text, tokens, or catalog
/// facts are stored. The caller supplies the authenticated account id and home.
abstract interface class OnboardingDraftStorage {
  Future<String?> read();
  Future<void> write(String value);
  Future<void> clear();
}

class SecureOnboardingDraftStorage implements OnboardingDraftStorage {
  const SecureOnboardingDraftStorage([
    this.storage = const FlutterSecureStorage(),
  ]) : key = storageKey;
  const SecureOnboardingDraftStorage.homeCreate([
    this.storage = const FlutterSecureStorage(),
  ]) : key = 'home_create_draft_v1';
  const SecureOnboardingDraftStorage.activeHome([
    this.storage = const FlutterSecureStorage(),
  ]) : key = 'active_home_preference_v1';
  const SecureOnboardingDraftStorage.hubClaim([
    this.storage = const FlutterSecureStorage(),
  ]) : key = 'hub_claim_pending_v1';
  static const storageKey = 'onboarding_draft_v1';
  final FlutterSecureStorage storage;
  final String key;

  @override
  Future<String?> read() => storage.read(key: key);
  @override
  Future<void> write(String value) => storage.write(key: key, value: value);
  @override
  Future<void> clear() => storage.delete(key: key);
}

/// The home-create variant has an account but no home ID until Cloud confirms
/// ownership. It shares the ordered secure slot used by appliance drafts.
class DurableHomeCreateDrafts {
  DurableHomeCreateDrafts(this.storage, this.api);
  final OnboardingDraftStorage storage;
  final CloudApiClient api;
  String? _origin;
  String? _profile;
  String? _accountId;
  int _generation = 0;
  Future<void> _tail = Future.value();

  Future<T> _ordered<T>(Future<T> Function() action) {
    final result = _tail.then((_) => action());
    _tail = result.then<void>((_) {}, onError: (Object _, StackTrace __) {});
    return result;
  }

  Future<void> selectScope(String? origin, String? profile, String? accountId) {
    _generation++;
    return _ordered(() async {
      final raw = await storage.read();
      final record = _HomeCreateRecord.tryParse(raw);
      if (raw != null &&
          (record == null ||
              record.origin != origin ||
              record.profile != profile ||
              record.accountId != accountId)) {
        await storage.clear();
      }
      _origin = origin;
      _profile = profile;
      _accountId = accountId;
    });
  }

  Future<CloudHome?> restoreAndCommit() async {
    final generation = _generation;
    final record = await _ordered(() async {
      final raw = await storage.read();
      final record = _HomeCreateRecord.tryParse(raw);
      if (record == null) {
        if (raw != null) await storage.clear();
        return null;
      }
      return _matches(record) ? record : null;
    });
    if (record == null || generation != _generation) return null;
    return _commit(record, generation);
  }

  /// An authoritative owned-home read supersedes a pending first-home create.
  /// Clear only this account's record so a later restart cannot POST it again.
  Future<void> discardPendingForExistingHome() {
    final generation = _generation;
    return _ordered(() async {
      if (generation != _generation) return;
      final raw = await storage.read();
      final record = _HomeCreateRecord.tryParse(raw);
      if (raw != null && (record == null || _matches(record))) {
        await storage.clear();
      }
    });
  }

  Future<CloudHome?> stageAndCommit(CloudHomeCreate input, String key) async {
    final generation = _generation;
    if (_origin == null || _profile == null || _accountId == null) {
      throw StateError('Verified account required before home creation');
    }
    final record = await _ordered(() async {
      if (generation != _generation) throw StateError('Home scope changed');
      final previous = _HomeCreateRecord.tryParse(await storage.read());
      final candidate = _HomeCreateRecord(
        _origin!,
        _profile!,
        _accountId!,
        key,
        input,
      );
      final chosen =
          previous != null &&
              _matches(previous) &&
              jsonEncode(previous.input.toJson()) == jsonEncode(input.toJson())
          ? previous
          : candidate;
      await storage.write(jsonEncode(chosen.toJson()));
      return chosen;
    });
    if (generation != _generation) return null;
    return _commit(record, generation);
  }

  Future<CloudHome?> _commit(_HomeCreateRecord record, int generation) async {
    if (!_matches(record) || generation != _generation) return null;
    final result = await api.createHome(
      record.input,
      idempotencyKey: record.key,
    );
    if (generation != _generation) return null;
    final homes = await api.homes();
    if (generation != _generation) return null;
    final owned = homes.where((home) => home.id == result.id).firstOrNull;
    if (owned == null)
      throw const FormatException('Created home missing from owner inventory');
    await _ordered(() async {
      if (generation != _generation) return;
      final current = _HomeCreateRecord.tryParse(await storage.read());
      if (current != null && _matches(current) && current.key == record.key) {
        await storage.clear();
      }
    });
    return generation == _generation ? owned : null;
  }

  bool _matches(_HomeCreateRecord record) =>
      record.origin == _origin &&
      record.profile == _profile &&
      record.accountId == _accountId;
}

class _HomeCreateRecord {
  const _HomeCreateRecord(
    this.origin,
    this.profile,
    this.accountId,
    this.key,
    this.input,
  );
  final String origin;
  final String profile;
  final String accountId;
  final String key;
  final CloudHomeCreate input;

  Map<String, Object?> toJson() => {
    'kind': 'home_create',
    'origin': origin,
    'profile': profile,
    'account_id': accountId,
    'operation_key': key,
    'input': input.toJson(),
  };

  static _HomeCreateRecord? tryParse(String? raw) {
    if (raw == null) return null;
    try {
      final data = jsonDecode(raw) as Map<String, dynamic>;
      final input = data['input'] as Map<String, dynamic>;
      final location = input['location'] as Map<String, dynamic>;
      final value = CloudHomeCreate.validate(
        name: input['name'] as String,
        timezone: input['timezone'] as String,
        countryCode: location['country_code'] as String,
        postalCode: location['postal_code'] as String,
      );
      if (data['kind'] != 'home_create' ||
          value == null ||
          data['origin'] is! String ||
          data['profile'] is! String ||
          data['account_id'] is! String ||
          data['operation_key'] is! String)
        return null;
      return _HomeCreateRecord(
        data['origin'] as String,
        data['profile'] as String,
        data['account_id'] as String,
        data['operation_key'] as String,
        value,
      );
    } catch (_) {
      return null;
    }
  }
}

class ActiveHomePreference {
  ActiveHomePreference(this.storage);
  final OnboardingDraftStorage storage;
  String? _origin;
  String? _accountId;
  int _generation = 0;
  Future<void> _tail = Future.value();

  Future<T> _ordered<T>(Future<T> Function() action) {
    final result = _tail.then((_) => action());
    _tail = result.then<void>((_) {}, onError: (Object _, StackTrace __) {});
    return result;
  }

  Future<void> selectScope(String? origin, String? accountId) {
    _generation++;
    return _ordered(() async {
      _origin = origin;
      _accountId = accountId;
    });
  }

  Future<String?> restore(List<CloudHome> ownedHomes) => _ordered(() async {
    final raw = await storage.read();
    if (raw == null) return null;
    try {
      final data = jsonDecode(raw) as Map<String, dynamic>;
      final homes = data['homes'] as Map<String, dynamic>;
      final homeId = homes[_scopeKey];
      if (data['version'] == 1 &&
          homeId is String &&
          ownedHomes.any((home) => home.id == homeId)) {
        return homeId;
      }
      homes.remove(_scopeKey);
      await storage.write(jsonEncode({'version': 1, 'homes': homes}));
      return null;
    } catch (_) {}
    await storage.clear();
    return null;
  });

  Future<void> remember(CloudHome home) {
    final generation = _generation;
    return _ordered(() async {
      if (generation != _generation || _origin == null || _accountId == null)
        return;
      Map<String, dynamic> homes = {};
      try {
        final raw = await storage.read();
        if (raw != null)
          homes =
              (jsonDecode(raw) as Map<String, dynamic>)['homes']
                  as Map<String, dynamic>;
      } catch (_) {}
      homes[_scopeKey] = home.id;
      await storage.write(jsonEncode({'version': 1, 'homes': homes}));
    });
  }

  Future<void> clear() {
    _generation++;
    return _ordered(() => storage.clear());
  }

  String get _scopeKey => '$_origin|$_accountId';
}

class PendingOnboardingDraft {
  const PendingOnboardingDraft(this.draft, this.operationKey);
  final OnboardingDraft draft;
  final String operationKey;
}

/// Persist before POST, reuse the key after restart or an uncertain response,
/// and clear only after the repository confirms readback and inventory refresh.
class DurableOnboardingDrafts {
  DurableOnboardingDrafts(this.storage, this.repository);
  final OnboardingDraftStorage storage;
  final OnboardingPersistenceRepository repository;
  String? _userId;
  String? _homeId;
  String? _origin;
  String? _profile;
  int _scopeGeneration = 0;
  Future<void> _tail = Future.value();

  Future<T> _ordered<T>(Future<T> Function() action) {
    final result = _tail.then((_) => action());
    _tail = result.then<void>(
      (_) {},
      onError: (Object error, StackTrace trace) {},
    );
    return result;
  }

  /// Stop in-flight readback as soon as verified ownership changes, even when
  /// the ordered storage transition must wait for an outstanding POST.
  void invalidatePendingWork() {
    _scopeGeneration++;
    repository.selectHome(null);
  }

  /// Passing null signs out. A home or account change discards the old slot.
  Future<void> selectScope(
    String? userId,
    String? homeId, {
    String? origin,
    String? profile,
  }) => _ordered(() async {
    if ((userId == null) != (homeId == null) ||
        userId != null && !_uuid.hasMatch(userId) ||
        homeId != null && !_uuid.hasMatch(homeId)) {
      throw ArgumentError('Expected an authenticated account and home');
    }
    final raw = await storage.read();
    final same =
        userId != null &&
        homeId != null &&
        _userId == userId &&
        _homeId == homeId &&
        _origin == (origin == null ? null : Uri.parse(origin).origin) &&
        _profile == profile;
    final normalizedOrigin = origin == null ? null : Uri.parse(origin).origin;
    if (!same && raw != null) {
      // Preserve an existing draft only when the new authenticated scope
      // matches its stored ownership, including on a fresh app process.
      final record = _parse(raw);
      if (userId == null ||
          record == null ||
          record.userId != userId ||
          record.homeId != homeId ||
          record.origin != normalizedOrigin ||
          record.profile != profile ||
          (_userId != null && (_userId != userId || _homeId != homeId))) {
        await storage.clear();
      }
    }
    if (!same) _scopeGeneration++;
    _userId = userId;
    _homeId = homeId;
    _origin = normalizedOrigin;
    _profile = profile;
    repository.selectHome(homeId);
  });

  Future<PendingOnboardingDraft?> restore() => _ordered(() async {
    _requireScope();
    final raw = await storage.read();
    if (raw == null) return null;
    final record = _parse(raw);
    if (record == null ||
        record.userId != _userId ||
        record.homeId != _homeId ||
        record.origin != _origin ||
        record.profile != _profile) {
      await storage.clear();
      return null;
    }
    return PendingOnboardingDraft(record.draft, record.key);
  });

  Future<PendingOnboardingDraft> stage(OnboardingDraft draft) =>
      _ordered(() => _stage(draft));

  /// Commits only the draft and retry key already stored for this scope.
  /// A caller must explicitly approve this mutation after reviewing the draft.
  Future<CloudAppliance?> commit(
    PendingOnboardingDraft pending, {
    required bool explicitlyApproved,
  }) => _ordered(() async {
    if (!explicitlyApproved) {
      throw StateError('Onboarding draft requires explicit approval');
    }
    _requireScope();
    final raw = await storage.read();
    final current = raw == null ? null : _parse(raw);
    if (current == null ||
        current.userId != _userId ||
        current.homeId != _homeId ||
        current.origin != _origin ||
        current.profile != _profile ||
        current.key != pending.operationKey ||
        jsonEncode(current.toJson()['draft']) !=
            jsonEncode(
              _Record(
                current.userId,
                current.homeId,
                current.key,
                pending.draft,
              ).toJson()['draft'],
            )) {
      throw StateError('Onboarding draft changed before commit');
    }
    final generation = _scopeGeneration;
    final result = await repository.save(
      current.draft,
      operationKey: current.key,
    );
    if (generation != _scopeGeneration) return null;
    if (result != null) await storage.clear();
    return result;
  });

  Future<CloudAppliance?> save(OnboardingDraft draft) async {
    final generation = _scopeGeneration;
    final pending = await _ordered(() => _stage(draft, generation: generation));
    if (generation != _scopeGeneration) return null;
    final result = await repository.save(
      pending.draft,
      operationKey: pending.operationKey,
    );
    if (result != null) {
      await _ordered(() async {
        final raw = await storage.read();
        final current = raw == null ? null : _parse(raw);
        if (current != null &&
            current.userId == _userId &&
            current.homeId == _homeId &&
            current.origin == _origin &&
            current.profile == _profile &&
            current.key == pending.operationKey) {
          await storage.clear();
        }
      });
    }
    return result;
  }

  Future<void> clear() => _ordered(() => storage.clear());

  Future<PendingOnboardingDraft> _stage(
    OnboardingDraft draft, {
    int? generation,
  }) async {
    if (generation != null && generation != _scopeGeneration) {
      throw StateError('Onboarding scope changed before save');
    }
    _requireScope();
    draft.validated();
    final oldRaw = await storage.read();
    final old = oldRaw == null ? null : _parse(oldRaw);
    final key =
        old != null &&
            old.userId == _userId &&
            old.homeId == _homeId &&
            old.origin == _origin &&
            old.profile == _profile &&
            jsonEncode(old.toJson()['draft']) ==
                jsonEncode(
                  _Record(
                    _userId!,
                    _homeId!,
                    old.key,
                    draft,
                    origin: _origin,
                    profile: _profile,
                  ).toJson()['draft'],
                )
        ? old.key
        : _newKey();
    final record = _Record(
      _userId!,
      _homeId!,
      key,
      draft,
      origin: _origin,
      profile: _profile,
    );
    await storage.write(jsonEncode(record.toJson()));
    return PendingOnboardingDraft(draft, key);
  }

  void _requireScope() {
    if (_userId == null || _homeId == null) {
      throw StateError('Select an authenticated account and home first');
    }
  }
}

class _Record {
  const _Record(
    this.userId,
    this.homeId,
    this.key,
    this.draft, {
    this.origin,
    this.profile,
  });
  final String userId;
  final String homeId;
  final String key;
  final OnboardingDraft draft;
  final String? origin;
  final String? profile;

  Map<String, Object?> toJson() {
    final product = draft.reviewedProduct;
    return {
      'version': 1,
      'user_id': userId,
      'home_id': homeId,
      if (origin != null) 'origin': origin,
      if (profile != null) 'profile': profile,
      'operation_key': key,
      'draft': {
        'name': draft.name,
        'category': draft.category,
        'brand': draft.brand,
        'full_model': draft.fullModel,
        'fuel': draft.fuel,
        'room': draft.room,
        if (draft.fccId != null) 'fcc_id': draft.fccId,
        if (draft.icId != null) 'ic_id': draft.icId,
        if (draft.serialNumber != null) 'serial_number': draft.serialNumber,
        if (draft.upc != null) 'upc': draft.upc,
        if (draft.bulbLabel != null) 'bulb_label': draft.bulbLabel!.toJson(),
        if (draft.nearbyOrigin != null)
          'nearby_origin': draft.nearbyOrigin!.toJson(),
        if (product != null)
          'reviewed_catalog': {
            'id': product.id,
            'variant': product.variant,
            'region': product.region,
            'match_quality': product.matchQuality,
          },
      },
    };
  }
}

_Record? _parse(String raw) {
  try {
    final json = jsonDecode(raw);
    if (json is! Map<String, dynamic> ||
        json['version'] != 1 ||
        json['user_id'] is! String ||
        json['home_id'] is! String ||
        json['operation_key'] is! String ||
        !_uuid.hasMatch(json['user_id'] as String) ||
        !_uuid.hasMatch(json['home_id'] as String) ||
        !_key.hasMatch(json['operation_key'] as String) ||
        json['draft'] is! Map<String, dynamic>) {
      return null;
    }
    final fields = json['draft'] as Map<String, dynamic>;
    for (final key in ['name', 'category', 'brand', 'full_model', 'fuel']) {
      if (fields[key] is! String) return null;
    }
    if (fields['room'] != null && fields['room'] is! String) return null;
    for (final key in ['fcc_id', 'ic_id', 'serial_number', 'upc']) {
      if (fields[key] != null && fields[key] is! String) return null;
    }
    CloudNearbyOrigin? nearbyOrigin;
    final rawOrigin = fields['nearby_origin'];
    if (rawOrigin != null) {
      if (rawOrigin is! Map<String, dynamic> ||
          rawOrigin['hub_id'] is! String ||
          rawOrigin['ownership_epoch'] is! int ||
          rawOrigin['protocol_device_id'] is! String)
        return null;
      nearbyOrigin = CloudNearbyOrigin.fromJson(rawOrigin);
    }
    BulbLabel? bulbLabel;
    if (fields['bulb_label'] != null) {
      final raw = fields['bulb_label'];
      if (raw is! Map<String, dynamic> ||
          raw['load_kind'] is! String ||
          raw['bulb_count'] != null && raw['bulb_count'] is! int ||
          raw['combined_input_watts'] != null &&
              raw['combined_input_watts'] is! num) {
        return null;
      }
      bulbLabel = BulbLabel(
        loadKind: raw['load_kind'] as String,
        bulbCount: raw['bulb_count'] as int?,
        combinedInputWatts: (raw['combined_input_watts'] as num?)?.toDouble(),
      );
    }
    CloudCatalogProduct? product;
    final reviewed = fields['reviewed_catalog'];
    if (reviewed != null) {
      if (reviewed is! Map<String, dynamic> ||
          reviewed['id'] is! String ||
          !_uuid.hasMatch(reviewed['id'] as String) ||
          reviewed['variant'] != null && reviewed['variant'] is! String ||
          reviewed['region'] != null && reviewed['region'] is! String ||
          reviewed['match_quality'] != null &&
              reviewed['match_quality'] is! String) {
        return null;
      }
      product = CloudCatalogProduct(
        id: reviewed['id'] as String,
        category: fields['category'] as String,
        brand: fields['brand'] as String,
        fullModel: fields['full_model'] as String,
        variant: reviewed['variant'] as String?,
        region: reviewed['region'] as String?,
        fuel: fields['fuel'] as String,
        matchQuality: reviewed['match_quality'] as String? ?? 'confirmed_exact',
        facts: const [],
      );
    }
    final draft = OnboardingDraft(
      name: fields['name'] as String,
      category: fields['category'] as String,
      brand: fields['brand'] as String,
      fullModel: fields['full_model'] as String,
      fuel: fields['fuel'] as String,
      room: fields['room'] as String?,
      reviewedProduct: product,
      fccId: fields['fcc_id'] as String?,
      icId: fields['ic_id'] as String?,
      serialNumber: fields['serial_number'] as String?,
      upc: fields['upc'] as String?,
      bulbLabel: bulbLabel,
      nearbyOrigin: nearbyOrigin,
    );
    draft.validated();
    return _Record(
      json['user_id'] as String,
      json['home_id'] as String,
      json['operation_key'] as String,
      draft,
      origin: json['origin'] as String?,
      profile: json['profile'] as String?,
    );
  } catch (_) {
    return null;
  }
}

final _uuid = RegExp(
  r'^[0-9a-fA-F]{8}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{12}$',
);
final _key = RegExp(
  r'^[0-9a-f]{8}-[0-9a-f]{4}-4[0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$',
);
String _newKey() {
  final random = Random.secure();
  final bytes = List<int>.generate(16, (_) => random.nextInt(256));
  bytes[6] = (bytes[6] & 0x0f) | 0x40;
  bytes[8] = (bytes[8] & 0x3f) | 0x80;
  final hex = bytes.map((b) => b.toRadixString(16).padLeft(2, '0')).join();
  return '${hex.substring(0, 8)}-${hex.substring(8, 12)}-${hex.substring(12, 16)}-${hex.substring(16, 20)}-${hex.substring(20)}';
}
