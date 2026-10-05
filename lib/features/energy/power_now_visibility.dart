import 'dart:convert';

import 'package:flutter_secure_storage/flutter_secure_storage.dart';

/// Local display preference; deleting a row never deletes its appliance.
class PowerNowVisibilityStore {
  const PowerNowVisibilityStore([this._storage = const FlutterSecureStorage()]);

  final FlutterSecureStorage _storage;

  String _key(String hubAddress, String? cloudHomeId) =>
      'power_now_hidden_${base64Url.encode(utf8.encode('${cloudHomeId ?? ''}|$hubAddress'))}';

  Future<Set<int>> read(String hubAddress, String? cloudHomeId) async {
    final raw = await _storage.read(key: _key(hubAddress, cloudHomeId));
    if (raw == null) return {};
    final decoded = jsonDecode(raw);
    if (decoded is! List) return {};
    return decoded.whereType<int>().toSet();
  }

  Future<void> write(
    String hubAddress,
    String? cloudHomeId,
    Set<int> applianceIds,
  ) => _storage.write(
    key: _key(hubAddress, cloudHomeId),
    value: jsonEncode(applianceIds.toList()..sort()),
  );
}
