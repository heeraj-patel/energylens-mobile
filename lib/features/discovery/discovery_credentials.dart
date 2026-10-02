import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';

import 'discovery_api.dart';

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
      );
    } on Object {
      return null;
    }
  }

  Future<String?> readPostalCode() =>
      storage.read('energylens.household.postal_code');

  Future<void> savePostalCode(String postalCode) =>
      storage.write('energylens.household.postal_code', postalCode);

  Future<void> clearPostalCode() =>
      storage.delete('energylens.household.postal_code');

  Future<bool> readZipPromptDismissed() async =>
      await storage.read('energylens.household.zip_prompt_dismissed') == 'true';

  Future<void> dismissZipPrompt() =>
      storage.write('energylens.household.zip_prompt_dismissed', 'true');
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
  });

  final String address;
  final String hubId;
  final String clientId;
  final String token;
}
