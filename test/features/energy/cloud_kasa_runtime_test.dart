import 'dart:convert';

import 'package:energylens_mobile/core/cloud_api/cloud_api_client.dart';
import 'package:energylens_mobile/core/cloud_api/cloud_home.dart';
import 'package:energylens_mobile/core/cloud_auth/cloud_auth.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

const home = CloudHome(
  id: '11111111-1111-4111-8111-111111111111',
  name: 'Selected home',
  timezone: 'America/Chicago',
  countryCode: 'US',
  postalCode: '60601',
);

class _Store implements CloudTokenStore {
  @override
  Future<void> clear() async {}
  @override
  Future<CloudTokens?> read() async =>
      const CloudTokens(accessToken: 'owner-token');
  @override
  Future<void> save(CloudTokens value) async {}
}

class _Auth implements CloudAuthenticator {
  @override
  Future<CloudTokens> signIn(CloudAuthConfig config) async =>
      const CloudTokens(accessToken: 'owner-token');
  @override
  Future<CloudTokens> refresh(
    CloudAuthConfig config,
    String refreshToken,
  ) async => const CloudTokens(accessToken: 'owner-token');
}

CloudApiClient _api(MockClient client) => CloudApiClient(
  session: CloudSession(
    config: const CloudAuthConfig(
      issuer: 'https://issuer.example',
      audience: 'energylens-cloud',
      clientId: 'client',
      redirectUrl: 'io.energylens.app://login-callback',
      apiUrl: 'https://api.example',
    ),
    store: _Store(),
    authenticator: _Auth(),
  ),
  client: client,
);

Map<String, dynamic> _row(
  String id,
  String label,
  int? minutes, {
  String? homeId,
}) => {
  'snapshot_id': id,
  'hub_id': '33333333-3333-4333-8333-333333333333',
  'ownership_epoch': 2,
  'home_id': homeId ?? home.id,
  'sensor_id': '22222222-2222-4222-8222-222222222222',
  'scope': 'single_plug',
  'window_label': label,
  'native_unit': 'minutes',
  'native_minutes': minutes,
  'duration_seconds': minutes == null ? null : minutes * 60,
  'reported_start': null,
  'reported_end': null,
  'device_clock_valid': false,
  'observed_at': '2026-10-01T11:00:00Z',
  'method': 'get_device_usage',
  'transport': 'kasa_http_klap',
  'quality': minutes == null
      ? 'unavailable'
      : 'protocol_reported_clock_unverified',
};

Map<String, dynamic> _page(List<Map<String, dynamic>> rows, String? next) => {
  'snapshots': rows,
  'from': '2026-09-01T12:00:00Z',
  'to': '2026-10-01T12:00:00Z',
  'next_cursor': next,
};

void main() {
  test('unavailable and wrong-home rows fail closed', () async {
    for (final row in [
      _row('aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa', 'today', null),
      _row(
        'aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa',
        'today',
        1,
        homeId: '99999999-9999-4999-8999-999999999999',
      ),
    ]) {
      final api = _api(
        MockClient(
          (_) async => http.Response(jsonEncode(_page([row], null)), 200),
        ),
      );
      await expectLater(api.kasaRuntimeHistory(home.id), throwsFormatException);
      api.close();
    }
  });
}
