import 'dart:convert';
import 'dart:io';
import 'dart:math';

import 'package:flutter/foundation.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';

import 'discovery_api.dart';
import '../../core/cloud_api/cloud_hub_claim.dart';

/// Pilot hub credentials kept in platform-protected storage between launches.
class DiscoveryCredentials {
  const DiscoveryCredentials({
    this.storage = const FlutterSecureKeyValueStore(),
  });

  final SecureKeyValueStore storage;
  static const _pairingStorageKey = 'energylens.hub.pairing';
  static const _buildHubUrl = String.fromEnvironment('ENERGYLENS_HUB_URL');

  Future<void> importDebugPairingFile() async {
    if (kDebugMode && Platform.isIOS) {
      final pairingFile = File(
        '${Directory.systemTemp.path}/energylens-pairing.json',
      );
      if (await pairingFile.exists()) {
        final data = jsonDecode(
          await pairingFile.readAsString(),
        ) as Map<String, dynamic>;
        await pairingFile.delete();
        final devAddress = data['address'] as String?;
        final devToken = data['token'] as String?;
        if (devAddress != null && devToken != null && devToken.isNotEmpty) {
          await storage.delete(_pairingStorageKey);
          await save(devAddress, devToken);
        }
      }
    }
  }

  Future<(String?, String?)> read() async {
    await importDebugPairingFile();
    final pairing = await readPairing();
    if (pairing != null) return (pairing.address, pairing.token);
    final address = await storage.read('energylens.hub.address');
    final token = await storage.read('energylens.hub.discovery_token');
    if (address != null && token != null) return (address, token);
    return (address ?? (_buildHubUrl.isEmpty ? null : _buildHubUrl), token);
  }

  Future<void> save(String address, String token) async {
    HubEndpoint.parse(address);
    await storage.write('energylens.hub.address', address);
    await storage.write('energylens.hub.discovery_token', token);
  }

  /// Stores a completed claim as one secure-storage value. Call only after the
  /// hub has successfully issued the client token; enrollment secrets are never
  /// persisted.
  Future<void> savePairing({
    required String address,
    required String hubId,
    required String clientId,
    required String token,
    int? ownershipEpoch,
  }) async {
    if (HubEndpoint.parse(address).pin == null) {
      throw const FormatException('A certificate pin is required for pairing.');
    }
    if (hubId.isEmpty || clientId.isEmpty || token.isEmpty) {
      throw ArgumentError('Hub ID, client ID, and token are required.');
    }
    await storage.write(
      _pairingStorageKey,
      jsonEncode({
        'address': address,
        'hub_id': hubId,
        'client_id': clientId,
        'token': token,
        if (ownershipEpoch != null) 'ownership_epoch': ownershipEpoch,
      }),
    );
    await storage.delete('energylens.hub.address');
    await storage.delete('energylens.hub.discovery_token');
  }

  Future<PairingClaim> claimAndStore(
    PairingDetails details, {
    required String clientId,
    DiscoveryApi api = const DiscoveryApi(),
  }) async {
    final claim = await api.claimPairing(details, clientId: clientId);
    await savePairing(
      address: details.address,
      hubId: claim.hubId,
      clientId: claim.clientId,
      token: claim.token,
      ownershipEpoch: claim.ownershipEpoch,
    );
    return claim;
  }

  Future<StoredPairingCredential?> readPairing() async {
    final value = await storage.read(_pairingStorageKey);
    if (value == null) return null;
    try {
      final json = jsonDecode(value) as Map<String, dynamic>;
      return StoredPairingCredential(
        address: json['address'] as String,
        hubId: json['hub_id'] as String,
        clientId: json['client_id'] as String,
        token: json['token'] as String,
        ownershipEpoch: json['ownership_epoch'] as int?,
      );
    } on Object {
      return null;
    }
  }

  /// Authenticated records are separate from legacy local-pilot credentials.
  /// The caller must obtain [ownership] from the current owner's Cloud API.
  Future<StoredPairingCredential?> readOwnedPairing(
    OwnedPairingScope scope,
    HubOwnership ownership,
  ) async {
    if (ownership.homeId != scope.homeId) return null;
    final raw = await storage.read(scope.keyFor(ownership));
    if (raw == null) return null;
    try {
      final value = jsonDecode(raw) as Map<String, dynamic>;
      if (value['scope'] != scope.identity ||
          value['hub_id'] != ownership.localHubId ||
          value['ownership_epoch'] != ownership.ownershipEpoch)
        return null;
      final credential = StoredPairingCredential(
        address: value['address'] as String,
        hubId: value['hub_id'] as String,
        clientId: value['client_id'] as String,
        token: value['token'] as String,
        ownershipEpoch: value['ownership_epoch'] as int,
      );
      if (HubEndpoint.parse(credential.address).pin == null ||
          credential.token.isEmpty ||
          credential.clientId.isEmpty)
        return null;
      return credential;
    } catch (_) {
      await storage.delete(scope.keyFor(ownership));
      return null;
    }
  }

  /// Promote only a newly paired token carrying the verified ownership epoch.
  Future<bool> saveOwnedPairing(
    OwnedPairingScope scope,
    HubOwnership ownership,
  ) async {
    final pairing = await readPairing();
    if (pairing == null ||
        ownership.homeId != scope.homeId ||
        pairing.hubId != ownership.localHubId ||
        pairing.ownershipEpoch != ownership.ownershipEpoch)
      return false;
    await storeOwnedPairing(scope, ownership, pairing);
    await storage.delete(_pairingStorageKey);
    return true;
  }

  /// Store an owner-authorized claim directly in its account/home/epoch scope.
  Future<void> storeOwnedPairing(
    OwnedPairingScope scope,
    HubOwnership ownership,
    StoredPairingCredential pairing, {
    bool Function()? isCurrent,
  }) async {
    if (ownership.homeId != scope.homeId ||
        pairing.hubId != ownership.localHubId ||
        pairing.ownershipEpoch != ownership.ownershipEpoch ||
        pairing.clientId.isEmpty ||
        pairing.token.isEmpty ||
        HubEndpoint.parse(pairing.address).pin == null) {
      throw StateError('Invalid owned Hub pairing');
    }
    if (isCurrent != null && !isCurrent()) {
      throw StateError('Hub owner authorization changed');
    }
    final value = jsonEncode({
      'scope': scope.identity,
      'address': pairing.address,
      'hub_id': pairing.hubId,
      'client_id': pairing.clientId,
      'token': pairing.token,
      'ownership_epoch': pairing.ownershipEpoch,
    });
    final key = scope.keyFor(ownership);
    await storage.write(key, value);
    if (isCurrent != null && !isCurrent()) {
      if (await storage.read(key) == value) await storage.delete(key);
      throw StateError('Hub owner authorization changed');
    }
  }

  Future<String> ownedClientId(
    OwnedPairingScope scope,
    HubOwnership ownership,
  ) async {
    final key = '${scope.keyFor(ownership)}.client_id';
    final existing = await storage.read(key);
    if (existing != null && existing.isNotEmpty) return existing;
    final random = Random.secure();
    final id =
        'energylens-mobile-${List.generate(16, (_) => random.nextInt(256)).map((byte) => byte.toRadixString(16).padLeft(2, '0')).join()}';
    await storage.write(key, id);
    return id;
  }

  String _preferenceKey(String name, OwnedPairingScope? scope) => scope == null
      ? 'energylens.household.$name'
      : 'energylens.household.v2.${base64Url.encode(utf8.encode(scope.identity))}.$name';

  Future<String?> readPostalCode({OwnedPairingScope? scope}) =>
      storage.read(_preferenceKey('postal_code', scope));

  Future<void> savePostalCode(String postalCode, {OwnedPairingScope? scope}) =>
      storage.write(_preferenceKey('postal_code', scope), postalCode);

  Future<void> clearPostalCode({OwnedPairingScope? scope}) =>
      storage.delete(_preferenceKey('postal_code', scope));

  Future<bool> readZipPromptDismissed({OwnedPairingScope? scope}) async =>
      await storage.read(_preferenceKey('zip_prompt_dismissed', scope)) ==
      'true';

  Future<void> dismissZipPrompt({OwnedPairingScope? scope}) =>
      storage.write(_preferenceKey('zip_prompt_dismissed', scope), 'true');
}

class OwnedPairingScope {
  OwnedPairingScope({
    required String origin,
    required this.profile,
    required this.accountId,
    required this.homeId,
  }) : origin = Uri.parse(origin).origin;
  final String origin;
  final String profile;
  final String accountId;
  final String homeId;
  String get identity => '$origin|$profile|$accountId|$homeId';
  String keyFor(HubOwnership ownership) =>
      'energylens.hub.pairing.v2.${base64Url.encode(utf8.encode('$identity|${ownership.localHubId}|${ownership.ownershipEpoch}'))}';
}

abstract interface class SecureKeyValueStore {
  Future<String?> read(String key);
  Future<void> write(String key, String value);
  Future<void> delete(String key);
}

class FlutterSecureKeyValueStore implements SecureKeyValueStore {
  const FlutterSecureKeyValueStore();
  static const _storage = FlutterSecureStorage();

  @override
  Future<String?> read(String key) => _storage.read(key: key);

  @override
  Future<void> write(String key, String value) =>
      _storage.write(key: key, value: value);

  @override
  Future<void> delete(String key) => _storage.delete(key: key);
}

class StoredPairingCredential {
  const StoredPairingCredential({
    required this.address,
    required this.hubId,
    required this.clientId,
    required this.token,
    this.ownershipEpoch,
  });

  final String address;
  final String hubId;
  final String clientId;
  final String token;
  final int? ownershipEpoch;
}
