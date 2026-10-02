import 'dart:convert';

import 'package:energylens_mobile/core/cloud_api/cloud_api_client.dart';
import 'package:energylens_mobile/core/cloud_api/cloud_home.dart';
import 'package:energylens_mobile/core/cloud_api/cloud_estimate.dart';
import 'package:energylens_mobile/core/cloud_auth/cloud_auth.dart';
import 'package:energylens_mobile/features/energy/cloud_estimates_section.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

const _home = CloudHome(
  id: '11111111-1111-4111-8111-111111111111',
  name: 'Home',
  timezone: 'America/Chicago',
  countryCode: 'US',
  postalCode: '60601',
);
const _config = CloudAuthConfig(
  issuer: 'https://issuer.example',
  audience: 'energylens-cloud',
  clientId: 'client',
  redirectUrl: 'io.energylens.app://login-callback',
  apiUrl: 'https://api.example',
);

class _Store implements CloudTokenStore {
  @override
  Future<void> clear() async {}
  @override
  Future<CloudTokens?> read() async => const CloudTokens(accessToken: 'owner');
  @override
  Future<void> save(CloudTokens value) async {}
}

class _Auth implements CloudAuthenticator {
  @override
  Future<CloudTokens> signIn(CloudAuthConfig config) async =>
      const CloudTokens(accessToken: 'owner');
  @override
  Future<CloudTokens> refresh(
    CloudAuthConfig config,
    String refreshToken,
  ) async => const CloudTokens(accessToken: 'owner');
}

Map<String, dynamic> _appliance(
  String id,
  String name, {
  String fuel = 'electricity',
}) => {
  'id': id,
  'home_id': _home.id,
  'name': name,
  'category': 'refrigerator',
  'room': null,
  'identity': {
    'brand': 'Acme',
    'full_model': 'A123',
    'fuel': fuel,
    'match_quality': 'confirmed_exact',
  },
  'version': 1,
  'created_at': '2026-10-01T00:00:00Z',
  'updated_at': '2026-10-01T00:00:00Z',
  'archived_at': null,
};
Map<String, dynamic> _run(
  String id,
  String applianceId,
  String kind, {
  String asOf = '2026-10-01T12:00:00Z',
  String? reason,
}) {
  final result = <String, dynamic>{
    'id': id,
    'appliance_id': applianceId,
    'kind': kind,
    'period': {
      'start': '2026-10-01',
      'end': '2026-11-01',
      'timezone': 'America/Chicago',
    },
    'energy': kind == 'unavailable'
        ? null
        : {'value': '54.916667', 'unit': 'kWh', 'fuel': 'electricity'},
    'cost': kind == 'unavailable'
        ? null
        : {'value': '10.983333', 'currency': 'USD', 'rate_kind': 'user_tariff'},
    'quality': {
      'identity': 'confirmed_exact',
      'consumption': kind == 'unavailable'
          ? 'unavailable'
          : 'published_test_basis',
      'source': kind == 'unavailable' ? 'unavailable' : 'reviewed_exact',
      'context': 'unknown',
      'rate': kind == 'unavailable' ? 'unavailable' : 'user_tariff',
    },
    'waste': 'not_yet_assessed',
    'evidence_refs': kind == 'unavailable'
        ? <Object>[]
        : [
            {
              'id': '77777777-7777-4777-8777-777777777777',
              'kind': 'catalog_fact',
              'revision': 2,
            },
            {
              'id': '88888888-8888-4888-8888-888888888888',
              'kind': 'tariff',
              'revision': 3,
            },
          ],
    'formula_version': 'reviewed-energy/v1',
    'as_of': asOf,
  };
  if (reason != null) {
    result['unavailable_reason'] = reason;
  }
  return result;
}

void main() {
  testWidgets(
    'selected home renders modeled run and unavailable reason separately',
    (tester) async {
      tester.view.physicalSize = const Size(800, 1600);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      const fridgeId = '22222222-2222-4222-8222-222222222222';
      const washerId = '33333333-3333-4333-8333-333333333333';
      const dryerId = '66666666-6666-4666-8666-666666666666';
      final paths = <String>[];
      final api = CloudApiClient(
        session: CloudSession(
          config: _config,
          store: _Store(),
          authenticator: _Auth(),
        ),
        client: MockClient((request) async {
          paths.add(request.url.path);
          if (request.url.path.endsWith('/appliances')) {
            return http.Response(
              jsonEncode({
                'appliances': [
                  _appliance(fridgeId, 'Fridge'),
                  _appliance(washerId, 'Washer'),
                  _appliance(dryerId, 'Dryer'),
                ],
              }),
              200,
            );
          }
          return http.Response(
            jsonEncode({
              'as_of': '2026-10-01T12:01:00Z',
              'estimates': [
                _run(
                  '44444444-4444-4444-8444-444444444444',
                  fridgeId,
                  'estimated_operating_cost',
                ),
                _run(
                  '99999999-9999-4999-8999-999999999999',
                  fridgeId,
                  'estimated_operating_cost',
                  asOf: '2026-09-30T12:00:00Z',
                ),
                _run(
                  '55555555-5555-4555-8555-555555555555',
                  washerId,
                  'unavailable',
                  reason: 'source_unreviewed',
                ),
                _run(
                  'aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa',
                  dryerId,
                  'estimated_useful_cost',
                ),
              ],
            }),
            200,
          );
        }),
      );
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: SingleChildScrollView(
              child: CloudEstimatesSection(api: api, home: _home),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(paths, [
        '/v1/homes/${_home.id}/appliances',
        '/v1/homes/${_home.id}/estimates',
      ]);
      expect(find.text('Estimated operating cost'), findsOneWidget);
      expect(find.text('Estimated useful cost'), findsOneWidget);
      expect(find.text('10.983333 USD · 54.916667 kWh'), findsNWidgets(2));
      expect(
        find.textContaining('2026-10-01 to before 2026-11-01'),
        findsNWidgets(3),
      );
      expect(find.textContaining('reviewed exact source'), findsNWidgets(2));
      expect(find.textContaining('catalog fact revision 2'), findsNWidgets(2));
      expect(find.text('Waste: not yet assessed'), findsNWidgets(3));
      expect(
        find.text(
          'No reviewed energy fact is available for this exact product.',
        ),
        findsOneWidget,
      );
      expect(find.textContaining('totals are not combined'), findsOneWidget);
      api.close();
    },
  );

  testWidgets('rejects estimate for appliance outside selected inventory', (
    tester,
  ) async {
    final api = CloudApiClient(
      session: CloudSession(
        config: _config,
        store: _Store(),
        authenticator: _Auth(),
      ),
      client: MockClient(
        (request) async => request.url.path.endsWith('/appliances')
            ? http.Response(jsonEncode({'appliances': []}), 200)
            : http.Response(
                jsonEncode({
                  'as_of': '2026-10-01T12:01:00Z',
                  'estimates': [
                    _run(
                      '44444444-4444-4444-8444-444444444444',
                      '99999999-9999-4999-8999-999999999999',
                      'estimated_operating_cost',
                    ),
                  ],
                }),
                200,
              ),
      ),
    );
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: CloudEstimatesSection(api: api, home: _home),
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('cloudEstimatesError')), findsOneWidget);
    expect(find.text('Estimated operating cost'), findsNothing);
    api.close();
  });

  test('priced estimate validates fuel and energy unit as a pair', () {
    const id = '22222222-2222-4222-8222-222222222222';
    Map<String, dynamic> withEnergy(String fuel, String unit) => _run(
      '44444444-4444-4444-8444-444444444444',
      id,
      'estimated_useful_cost',
    )..['energy'] = {'value': '7.750000', 'fuel': fuel, 'unit': unit};

    final gas = CloudEstimate.fromJson(withEnergy('natural_gas', 'therm'));
    expect(gas.energy?.fuel, 'natural_gas');
    expect(gas.energy?.unit, 'therm');
    for (final (fuel, unit) in [
      ('natural_gas', 'kWh'),
      ('electricity', 'therm'),
      ('propane', 'therm'),
    ]) {
      expect(
        () => CloudEstimate.fromJson(withEnergy(fuel, unit)),
        throwsFormatException,
      );
    }
  });

  testWidgets('reviewed gas cycle estimate shows therms and assessed status', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(800, 1600);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    const dryerId = '66666666-6666-4666-8666-666666666666';
    final gasRun =
        _run(
            'aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa',
            dryerId,
            'estimated_useful_cost',
          )
          ..['energy'] = {
            'value': '7.750000',
            'unit': 'therm',
            'fuel': 'natural_gas',
          }
          ..['cost'] = {
            'value': '9.300000',
            'currency': 'USD',
            'rate_kind': 'user_tariff',
          };
    final api = CloudApiClient(
      session: CloudSession(
        config: _config,
        store: _Store(),
        authenticator: _Auth(),
      ),
      client: MockClient(
        (request) async => request.url.path.endsWith('/appliances')
            ? http.Response(
                jsonEncode({
                  'appliances': [
                    _appliance(dryerId, 'Gas Dryer', fuel: 'natural_gas'),
                  ],
                }),
                200,
              )
            : http.Response(
                jsonEncode({
                  'as_of': '2026-10-01T12:01:00Z',
                  'estimates': [gasRun],
                }),
                200,
              ),
      ),
    );
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: SingleChildScrollView(
            child: CloudEstimatesSection(api: api, home: _home),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.text('Estimated useful gas cost'), findsOneWidget);
    expect(find.text('9.300000 USD · 7.750000 therm'), findsOneWidget);
    expect(find.text('Waste: not yet assessed'), findsOneWidget);
    expect(find.textContaining('totals are not combined'), findsOneWidget);
    expect(find.text('Estimated useful cost'), findsNothing);
    api.close();
  });

  testWidgets('mismatched appliance and estimate fuel fails closed', (
    tester,
  ) async {
    const dryerId = '66666666-6666-4666-8666-666666666666';
    final gasRun =
        _run(
            'aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa',
            dryerId,
            'estimated_useful_cost',
          )
          ..['energy'] = {
            'value': '7.750000',
            'unit': 'therm',
            'fuel': 'natural_gas',
          };
    final api = CloudApiClient(
      session: CloudSession(
        config: _config,
        store: _Store(),
        authenticator: _Auth(),
      ),
      client: MockClient(
        (request) async => request.url.path.endsWith('/appliances')
            ? http.Response(
                jsonEncode({
                  'appliances': [_appliance(dryerId, 'Electric Dryer')],
                }),
                200,
              )
            : http.Response(
                jsonEncode({
                  'as_of': '2026-10-01T12:01:00Z',
                  'estimates': [gasRun],
                }),
                200,
              ),
      ),
    );
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: CloudEstimatesSection(api: api, home: _home),
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('cloudEstimatesError')), findsOneWidget);
    expect(find.text('Estimated useful gas cost'), findsNothing);
    api.close();
  });
}
