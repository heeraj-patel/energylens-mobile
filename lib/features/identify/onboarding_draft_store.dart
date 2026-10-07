import 'dart:convert';
import 'dart:math';

import 'package:flutter_secure_storage/flutter_secure_storage.dart';

import '../../core/cloud_api/cloud_appliance.dart';
import '../../core/cloud_api/cloud_catalog.dart';
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
  ]);
  static const storageKey = 'onboarding_draft_v1';
  final FlutterSecureStorage storage;

  @override
  Future<String?> read() => storage.read(key: storageKey);
  @override
  Future<void> write(String value) =>
      storage.write(key: storageKey, value: value);
  @override
  Future<void> clear() => storage.delete(key: storageKey);
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

  /// Passing null signs out. A home or account change discards the old slot.
  Future<void> selectScope(String? userId, String? homeId) =>
      _ordered(() async {
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
            _homeId == homeId;
        if (!same && raw != null) {
          // Preserve an existing draft only when the new authenticated scope
          // matches its stored ownership, including on a fresh app process.
          final record = _parse(raw);
          if (userId == null ||
              record == null ||
              record.userId != userId ||
              record.homeId != homeId ||
              (_userId != null && (_userId != userId || _homeId != homeId))) {
            await storage.clear();
          }
        }
        if (_userId != userId || _homeId != homeId) _scopeGeneration++;
        _userId = userId;
        _homeId = homeId;
        repository.selectHome(homeId);
      });

  Future<PendingOnboardingDraft?> restore() => _ordered(() async {
    _requireScope();
    final raw = await storage.read();
    if (raw == null) return null;
    final record = _parse(raw);
    if (record == null ||
        record.userId != _userId ||
        record.homeId != _homeId) {
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
        current.key != pending.operationKey ||
        jsonEncode(current.draft.validated().toJson()) !=
            jsonEncode(pending.draft.validated().toJson())) {
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
    final input = draft.validated();
    final oldRaw = await storage.read();
    final old = oldRaw == null ? null : _parse(oldRaw);
    final key =
        old != null &&
            old.userId == _userId &&
            old.homeId == _homeId &&
            jsonEncode(old.draft.validated().toJson()) ==
                jsonEncode(input.toJson())
        ? old.key
        : _newKey();
    final record = _Record(_userId!, _homeId!, key, draft);
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
  const _Record(this.userId, this.homeId, this.key, this.draft);
  final String userId;
  final String homeId;
  final String key;
  final OnboardingDraft draft;

  Map<String, Object?> toJson() {
    final product = draft.reviewedProduct;
    return {
      'version': 1,
      'user_id': userId,
      'home_id': homeId,
      'operation_key': key,
      'draft': {
        'name': draft.name,
        'category': draft.category,
        'brand': draft.brand,
        'full_model': draft.fullModel,
        'fuel': draft.fuel,
        'room': draft.room,
        if (product != null)
          'reviewed_catalog': {
            'id': product.id,
            'variant': product.variant,
            'region': product.region,
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
    CloudCatalogProduct? product;
    final reviewed = fields['reviewed_catalog'];
    if (reviewed != null) {
      if (reviewed is! Map<String, dynamic> ||
          reviewed['id'] is! String ||
          !_uuid.hasMatch(reviewed['id'] as String) ||
          reviewed['variant'] != null && reviewed['variant'] is! String ||
          reviewed['region'] != null && reviewed['region'] is! String) {
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
        matchQuality: 'confirmed_exact',
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
    );
    draft.validated();
    return _Record(
      json['user_id'] as String,
      json['home_id'] as String,
      json['operation_key'] as String,
      draft,
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
