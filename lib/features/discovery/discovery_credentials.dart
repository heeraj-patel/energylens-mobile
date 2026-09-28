import 'package:flutter_secure_storage/flutter_secure_storage.dart';

/// Pilot hub credentials kept in platform-protected storage between launches.
class DiscoveryCredentials {
  const DiscoveryCredentials();

  static const _storage = FlutterSecureStorage();

  Future<(String?, String?)> read() async => (
    await _storage.read(key: 'energylens.hub.address'),
    await _storage.read(key: 'energylens.hub.discovery_token'),
  );

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
