import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';

/// Pilot hub credentials kept in platform-protected storage between launches.
class DiscoveryCredentials {
  const DiscoveryCredentials();

  static const _storage = FlutterSecureStorage();
  static const _buildHubUrl = String.fromEnvironment('ENERGYLENS_HUB_URL');

  Future<(String?, String?)> read() async {
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
          await save(devAddress, devToken);
          return (devAddress, devToken);
        }
      }
    }
    final address = await _storage.read(key: 'energylens.hub.address');
    final token = await _storage.read(key: 'energylens.hub.discovery_token');
    if (address != null && token != null) return (address, token);
    return (address ?? (_buildHubUrl.isEmpty ? null : _buildHubUrl), token);
  }

  Future<void> save(String address, String token) async {
    await _storage.write(key: 'energylens.hub.address', value: address);
    await _storage.write(key: 'energylens.hub.discovery_token', value: token);
  }

  Future<String?> readPostalCode() =>
      _storage.read(key: 'energylens.household.postal_code');

  Future<void> savePostalCode(String postalCode) => _storage.write(
    key: 'energylens.household.postal_code',
    value: postalCode,
  );
}
