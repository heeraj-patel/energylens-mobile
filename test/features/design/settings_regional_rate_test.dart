import 'dart:async';
import 'dart:convert';

import 'package:energylens_mobile/core/cloud_api/cloud_api_client.dart';
import 'package:energylens_mobile/core/cloud_api/cloud_home.dart';
import 'package:energylens_mobile/core/cloud_api/cloud_preferences.dart';
import 'package:energylens_mobile/core/cloud_api/cloud_regional_rate.dart';
import 'package:energylens_mobile/core/cloud_auth/cloud_auth.dart';
import 'package:energylens_mobile/features/design/settings_regional_rate_adapter.dart';
import 'package:energylens_mobile/features/design/design_context_coordinator.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

const homeA = '11111111-1111-4111-8111-111111111111';
const homeB = '22222222-2222-4222-8222-222222222222';

Map<String, dynamic> payload() => {
  'rate_usd_per_kwh': 0.17,
  'source': 'state',
  'source_label': 'Published state average',
  'as_of': '2026-09-01',
  'region': 'IL',
  'source_url': 'https://example.test/rates',
  'fetched_at': '2026-10-01T12:00:00Z',
  'is_stale': true,
  'is_static': false,
};

class _Store implements CloudTokenStore {
  @override
  Future<void> clear() async {}
  @override
  Future<CloudTokens?> read() async => null;
  @override
  Future<void> save(CloudTokens value) async {}
}

class _Auth implements CloudAuthenticator {
  @override
  Future<CloudTokens> signIn(CloudAuthConfig config) async =>
      const CloudTokens(accessToken: 'unused');
  @override
  Future<CloudTokens> refresh(CloudAuthConfig config, String token) async =>
      const CloudTokens(accessToken: 'unused');
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

class _Source implements SettingsRegionalRateSource {
  _Source({this.homeRead, this.rateRead});
  final Future<CloudVersioned<CloudHome>> Function(String)? homeRead;
  final Future<CloudRegionalRate> Function(String, String)? rateRead;
  final locations = <(String, String)>[];

  @override
  Future<CloudVersioned<CloudHome>> home(String id) =>
      homeRead?.call(id) ??
      Future.value(
        CloudVersioned(
          value: CloudHome(
            id: id,
            name: 'Home',
            timezone: 'America/Chicago',
            countryCode: 'US',
            postalCode: '60601',
          ),
          etag: '"1"',
        ),
      );
  @override
  Future<CloudRegionalRate> regionalRate(String country, String postal) {
    locations.add((country, postal));
    return rateRead?.call(country, postal) ??
        Future.value(CloudRegionalRate.fromJson(payload()));
  }
}

class _UnusedAdapters implements DesignContextAdapters {
  @override
  void clear() {}
  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

void main() {
  test(
    'public rate uses encoded location without bearer and retains source',
    () async {
      final api = _api(
        MockClient((request) async {
          expect(request.url.path, '/v1/energy/rates');
          expect(request.url.queryParameters, {
            'country': 'US',
            'postal_code': '60601-1234',
          });
          expect(request.headers.containsKey('authorization'), isFalse);
          return http.Response(jsonEncode(payload()), 200);
        }),
      );
      final rate = await api.regionalElectricityRate(
        country: 'US',
        postalCode: '60601-1234',
      );
      expect(rate.usdPerKwh, 0.17);
      expect(rate.source, 'state');
      expect(rate.asOf, '2026-09-01');
      expect(rate.isStale, isTrue);
      expect(rate.fetchedAt, DateTime.utc(2026, 10, 1, 12));
      api.close();
    },
  );

  test('static source keeps unknown EIA fetch time', () {
    final rate = CloudRegionalRate.fromJson({
      ...payload(),
      'source': 'national',
      'region': null,
      'fetched_at': null,
      'is_stale': false,
      'is_static': true,
    });
    expect(rate.fetchedAt, isNull);
    expect(rate.isStatic, isTrue);
  });

  test('rejects invalid rate, dates, source and freshness combinations', () {
    final missingRegion = payload()..remove('region');
    expect(
      () => CloudRegionalRate.fromJson(missingRegion),
      throwsFormatException,
    );
    for (final changed in <Map<String, dynamic>>[
      {'rate_usd_per_kwh': 0},
      {'source': 'utility'},
      {'as_of': '2026-02-30'},
      {'source_label': ''},
      {'is_static': true},
      {'fetched_at': null},
      {'source_url': 'not a uri'},
      {'unexpected': 1},
    ]) {
      expect(
        () => CloudRegionalRate.fromJson({...payload(), ...changed}),
        throwsFormatException,
      );
    }
  });

  test('public lookup preserves HTTP errors', () async {
    final api = _api(
      MockClient(
        (_) async => http.Response(
          jsonEncode({'code': 'rate_temporarily_unavailable'}),
          503,
        ),
      ),
    );
    await expectLater(
      api.regionalElectricityRate(country: 'US', postalCode: '60601'),
      throwsA(
        isA<CloudApiException>().having(
          (e) => e.code,
          'code',
          'rate_temporarily_unavailable',
        ),
      ),
    );
    api.close();
  });

  test('adapter uses owned home location and keeps tariff unknown', () async {
    final source = _Source();
    final result = await SettingsRegionalRateAdapter(source).fetch(homeA);
    expect(source.locations, [('US', '60601')]);
    expect(result?.regionalEstimate?.isStale, isTrue);
    expect(result?.householdTariffUsdPerKwh, isNull);
  });

  test('no regional source is unknown; other errors propagate', () async {
    final unavailable = _Source(
      rateRead: (_, _) async =>
          throw const CloudApiException(404, 'rate_unavailable'),
    );
    expect(
      (await SettingsRegionalRateAdapter(unavailable).fetch(homeA))
          ?.regionalEstimate,
      isNull,
    );
    final failed = _Source(
      rateRead: (_, _) async =>
          throw const CloudApiException(503, 'rate_temporarily_unavailable'),
    );
    await expectLater(
      SettingsRegionalRateAdapter(failed).fetch(homeA),
      throwsA(isA<CloudApiException>()),
    );
  });

  test('adapter rejects wrong home and stale pending rate', () async {
    final wrong = _Source(
      homeRead: (_) async => CloudVersioned(
        value: CloudHome(
          id: homeB,
          name: 'Other',
          timezone: 'America/Chicago',
          countryCode: 'US',
          postalCode: '60601',
        ),
        etag: '"1"',
      ),
    );
    await expectLater(
      SettingsRegionalRateAdapter(wrong).fetch(homeA),
      throwsFormatException,
    );
    final pending = Completer<CloudRegionalRate>();
    final adapter = SettingsRegionalRateAdapter(
      _Source(rateRead: (_, _) => pending.future),
    );
    final old = adapter.fetch(homeA);
    await Future<void>.delayed(Duration.zero);
    adapter.clear();
    pending.complete(CloudRegionalRate.fromJson(payload()));
    expect(await old, isNull);
  });

  test('verified context rejects sample and stale account or home', () async {
    for (final next in [('account-b', homeA), ('account-a', homeB)]) {
      final pending = Completer<CloudRegionalRate>();
      final adapter = SettingsRegionalRateAdapter(
        _Source(rateRead: (_, _) => pending.future),
      );
      final coordinator = DesignContextCoordinator(
        _UnusedAdapters(),
        settingsRegionalRate: adapter,
      );
      coordinator.useVerifiedContext(
        VerifiedDesignContext(
          accountId: 'account-a',
          homeId: homeA,
          mode: DesignContextMode.sample,
        ),
      );
      await expectLater(
        coordinator.readSettingsRegionalRate(),
        throwsStateError,
      );
      coordinator.useVerifiedContext(
        VerifiedDesignContext(
          accountId: 'account-a',
          homeId: homeA,
          mode: DesignContextMode.household,
        ),
      );
      final old = coordinator.readSettingsRegionalRate();
      await Future<void>.delayed(Duration.zero);
      coordinator.useVerifiedContext(
        VerifiedDesignContext(
          accountId: next.$1,
          homeId: next.$2,
          mode: DesignContextMode.household,
        ),
      );
      pending.complete(CloudRegionalRate.fromJson(payload()));
      expect(await old, isNull);
      coordinator.signOut();
      await expectLater(
        coordinator.readSettingsRegionalRate(),
        throwsStateError,
      );
    }
  });
}
