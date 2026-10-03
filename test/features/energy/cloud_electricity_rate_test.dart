import 'dart:convert';

import 'package:energylens_mobile/core/cloud_api/cloud_api_client.dart';
import 'package:energylens_mobile/core/cloud_api/cloud_home.dart';
import 'package:energylens_mobile/core/cloud_auth/cloud_auth.dart';
import 'package:energylens_mobile/features/energy/cloud_electricity_rate_screen.dart';
import 'package:energylens_mobile/features/energy/cloud_recommendations_screen.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

const home = CloudHome(
  id: '11111111-1111-4111-8111-111111111111',
  name: 'Home',
  timezone: 'America/Chicago',
  countryCode: 'US',
  postalCode: '60601',
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
  Future<CloudTokens> refresh(CloudAuthConfig config, String token) async =>
      const CloudTokens(accessToken: 'owner');
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

void main() {
  testWidgets('missing-rate recommendation opens this Cloud home rate', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(800, 1500);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    const appliance = '22222222-2222-4222-8222-222222222222';
    final api = _api(
      MockClient((request) async {
        if (request.url.path.endsWith('/appliances')) {
          return http.Response(
            jsonEncode({
              'appliances': [
                {
                  'id': appliance,
                  'home_id': home.id,
                  'name': 'Washer',
                  'category': 'washer',
                  'identity': {
                    'brand': 'LG',
                    'full_model': 'WM3070HWA',
                    'fuel': 'electricity',
                    'match_quality': 'confirmed_exact',
                  },
                },
              ],
            }),
            200,
          );
        }
        if (request.url.path.endsWith('/recommendations')) {
          return http.Response(
            jsonEncode({
              'actions': [
                {
                  'rule_id': 'general.gather_information',
                  'rule_version': 1,
                  'appliance_id': appliance,
                  'state': 'candidate',
                  'title': 'Add a home rate',
                  'explanation': 'A home electricity rate is needed.',
                  'next_question': 'add_electricity_rate',
                  'benefit_group': 'information',
                  'evidence_refs': <Object>[],
                  'savings_amount': null,
                },
              ],
              'as_of': '2026-10-01T00:00:00Z',
            }),
            200,
          );
        }
        expect(request.url.path, '/v1/homes/${home.id}/tariffs');
        return http.Response('{"tariffs":[]}', 200);
      }),
    );
    await tester.pumpWidget(
      MaterialApp(
        home: CloudRecommendationsScreen(api: api, home: home),
      ),
    );
    await tester.pumpAndSettle();
    await tester.ensureVisible(
      find.byKey(const Key('recommendationRate-$appliance')),
    );
    await tester.tap(find.byKey(const Key('recommendationRate-$appliance')));
    await tester.pumpAndSettle();
    expect(find.text('Cloud electricity rate'), findsOneWidget);
    expect(find.text('Save Cloud electricity rate'), findsOneWidget);
    api.close();
  });

  testWidgets(
    'capable gas dryer action opens therm rate without electric outcome',
    (tester) async {
      tester.view.physicalSize = const Size(800, 1500);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      const appliance = '22222222-2222-4222-8222-222222222222';
      final api = _api(
        MockClient((request) async {
          if (request.url.path.endsWith('/appliances')) {
            return http.Response(
              jsonEncode({
                'appliances': [
                  {
                    'id': appliance,
                    'home_id': home.id,
                    'name': 'Gas dryer',
                    'category': 'dryer',
                    'identity': {
                      'brand': 'Acme',
                      'full_model': 'G123',
                      'variant': 'US-GAS',
                      'fuel': 'natural_gas',
                      'match_quality': 'confirmed_exact',
                    },
                  },
                ],
              }),
              200,
            );
          }
          if (request.url.path.endsWith('/recommendations')) {
            expect(
              request.url.queryParameters['capability'],
              'gas_dryer_recommendations_v1',
            );
            return http.Response(
              jsonEncode({
                'actions': [
                  {
                    'rule_id': 'dryer.gas_cycle_options',
                    'rule_version': 1,
                    'appliance_id': appliance,
                    'state': 'candidate',
                    'title': 'Review gas dryer cycle options',
                    'explanation': 'No numeric savings or waste claim.',
                    'next_question': 'add_gas_rate',
                    'benefit_group': 'laundry_cycle',
                    'evidence_refs': [
                      {
                        'id': '33333333-3333-4333-8333-333333333333',
                        'kind': 'gas_cycle_energy',
                        'revision': 1,
                      },
                      {
                        'id': '44444444-4444-4444-8444-444444444444',
                        'kind': 'confirmed_answer',
                        'revision': 1,
                      },
                    ],
                    'savings_amount': null,
                  },
                ],
                'as_of': '2026-10-01T00:00:00Z',
              }),
              200,
            );
          }
          expect(request.url.path, '/v1/homes/${home.id}/tariffs');
          return http.Response('{"tariffs":[]}', 200);
        }),
      );
      await tester.pumpWidget(
        MaterialApp(
          home: CloudRecommendationsScreen(api: api, home: home),
        ),
      );
      await tester.pumpAndSettle();
      expect(find.text('Review Cloud natural gas rate'), findsOneWidget);
      expect(find.text('Record a manual change'), findsNothing);
      await tester.tap(find.text('Review Cloud natural gas rate'));
      await tester.pumpAndSettle();
      expect(find.text('Cloud gas rate'), findsOneWidget);
      api.close();
    },
  );

  test('rejects another home’s electricity tariff', () async {
    final api = _api(
      MockClient(
        (_) async => http.Response(
          jsonEncode({
            'tariffs': [
              {
                'id': '22222222-2222-4222-8222-222222222222',
                'home_id': '33333333-3333-4333-8333-333333333333',
                'revision': 1,
                'fuel': 'electricity',
                'rate': '0.15',
                'rate_unit': 'kWh',
                'currency': 'USD',
                'rate_kind': 'user_tariff',
                'source_ref': 'bill',
                'source_as_of': '2026-10-01T00:00:00Z',
                'is_fallback': false,
                'effective_from': '2026-10-01T00:00:00Z',
              },
            ],
          }),
          200,
        ),
      ),
    );
    await expectLater(api.electricityTariffs(home.id), throwsFormatException);
    api.close();
  });

  test('gas tariffs accept only selected-home therm revisions', () async {
    Map<String, dynamic> gasRow({
      String fuel = 'natural_gas',
      String unit = 'therm',
      String? homeId,
    }) => {
      'id': '22222222-2222-4222-8222-222222222222',
      'home_id': homeId ?? home.id,
      'revision': 1,
      'fuel': fuel,
      'rate': '1.25',
      'rate_unit': unit,
      'currency': 'USD',
      'rate_kind': 'user_tariff',
      'source_ref': 'Customer-entered natural gas bill',
      'source_as_of': '2026-10-01T00:00:00Z',
      'is_fallback': false,
      'effective_from': '2026-10-01T00:00:00Z',
    };

    for (final badRow in [
      gasRow(unit: 'kWh'),
      gasRow(homeId: '33333333-3333-4333-8333-333333333333'),
    ]) {
      final api = _api(
        MockClient(
          (_) async => http.Response(
            jsonEncode({
              'tariffs': [badRow],
            }),
            200,
          ),
        ),
      );
      await expectLater(api.gasTariffs(home.id), throwsFormatException);
      api.close();
    }
    final api = _api(
      MockClient(
        (_) async => http.Response(
          jsonEncode({
            'tariffs': [gasRow(), gasRow(fuel: 'electricity', unit: 'kWh')],
          }),
          200,
        ),
      ),
    );
    final rows = await api.gasTariffs(home.id);
    expect(rows, hasLength(1));
    expect(rows.single.rate, '1.25');
    api.close();
  });

  testWidgets(
    'gas bill rate saves USD per therm with stable retry and no usage claim',
    (tester) async {
      tester.view.physicalSize = const Size(800, 1500);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      final posted = <http.Request>[];
      final api = _api(
        MockClient((request) async {
          expect(request.url.path, '/v1/homes/${home.id}/tariffs');
          expect(request.headers['authorization'], 'Bearer owner');
          if (request.method == 'GET') {
            return http.Response('{"tariffs":[]}', 200);
          }
          posted.add(request);
          if (posted.length == 1) {
            return http.Response('{"code":"unavailable"}', 503);
          }
          return http.Response(
            jsonEncode({
              'id': '22222222-2222-4222-8222-222222222222',
              'home_id': home.id,
              'revision': 1,
              ...jsonDecode(request.body) as Map<String, dynamic>,
            }),
            201,
          );
        }),
      );
      await tester.pumpWidget(
        MaterialApp(
          home: CloudGasRateScreen(api: api, home: home),
        ),
      );
      await tester.pumpAndSettle();
      expect(find.text('Cloud gas rate'), findsOneWidget);
      expect(
        find.textContaining(
          'A rate alone does not establish gas consumption, Useful cost, Waste',
        ),
        findsOneWidget,
      );
      await tester.enterText(find.byKey(const Key('cloudRate')), '1.25');
      await tester.tap(find.text('Save Cloud gas rate'));
      await tester.pumpAndSettle();
      expect(posted, isEmpty);
      final today = DateTime.now().toUtc().toIso8601String().substring(0, 10);
      await tester.enterText(
        find.byKey(const Key('cloudRateSourceDate')),
        today,
      );
      await tester.enterText(
        find.byKey(const Key('cloudRateEffectiveDate')),
        today,
      );
      await tester.ensureVisible(find.text('Save Cloud gas rate'));
      await tester.tap(find.text('Save Cloud gas rate'));
      await tester.pumpAndSettle();
      expect(find.byKey(const Key('cloudRateError')), findsOneWidget);
      await tester.tap(find.text('Save Cloud gas rate'));
      await tester.pumpAndSettle();
      expect(posted, hasLength(2));
      expect(posted.last.body, posted.first.body);
      expect(
        posted.last.headers['idempotency-key'],
        posted.first.headers['idempotency-key'],
      );
      final payload = jsonDecode(posted.last.body) as Map<String, dynamic>;
      expect(payload['fuel'], 'natural_gas');
      expect(payload['rate'], '1.25');
      expect(payload['rate_unit'], 'therm');
      expect(payload['fixed_charge'], isNull);
      expect(payload['source_ref'], 'Customer-entered natural gas bill');
      expect(find.textContaining('Cloud gas rate saved'), findsOneWidget);
      api.close();
    },
  );

  testWidgets('Cloud rate saves owner-home bill details with stable retry', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(800, 1500);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final posted = <http.Request>[];
    final api = _api(
      MockClient((request) async {
        expect(request.url.path, '/v1/homes/${home.id}/tariffs');
        expect(request.headers['authorization'], 'Bearer owner');
        if (request.method == 'GET') {
          return http.Response('{"tariffs":[]}', 200);
        }
        posted.add(request);
        if (posted.length == 1) {
          return http.Response('{"code":"internal_error"}', 503);
        }
        return http.Response(
          jsonEncode({
            'id': '22222222-2222-4222-8222-222222222222',
            'home_id': home.id,
            'revision': 1,
            ...jsonDecode(request.body) as Map<String, dynamic>,
          }),
          201,
        );
      }),
    );
    await tester.pumpWidget(
      MaterialApp(
        home: CloudElectricityRateScreen(api: api, home: home),
      ),
    );
    await tester.pumpAndSettle();
    await tester.enterText(find.byKey(const Key('cloudRate')), '-0.2');
    await tester.tap(find.text('Save Cloud electricity rate'));
    await tester.pumpAndSettle();
    expect(posted, isEmpty);
    final today = DateTime.now().toUtc();
    final sourceDay = today.toIso8601String().substring(0, 10);
    final effectiveDay = today
        .subtract(const Duration(days: 10))
        .toIso8601String()
        .substring(0, 10);
    await tester.enterText(find.byKey(const Key('cloudRate')), '0.1588');
    await tester.enterText(
      find.byKey(const Key('cloudRateSourceDate')),
      sourceDay,
    );
    await tester.enterText(
      find.byKey(const Key('cloudRateEffectiveDate')),
      effectiveDay,
    );
    await tester.ensureVisible(find.text('Save Cloud electricity rate'));
    await tester.tap(find.text('Save Cloud electricity rate'));
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('cloudRateError')), findsOneWidget);
    await tester.tap(find.text('Save Cloud electricity rate'));
    await tester.pumpAndSettle();
    expect(posted, hasLength(2));
    expect(posted[1].body, posted[0].body);
    expect(
      posted[1].headers['idempotency-key'],
      posted[0].headers['idempotency-key'],
    );
    final payload = jsonDecode(posted.first.body) as Map<String, dynamic>;
    expect(payload['fuel'], 'electricity');
    expect(payload['rate'], '0.1588');
    expect(payload['rate_unit'], 'kWh');
    expect(payload['fixed_charge'], isNull);
    expect(payload['source_ref'], 'Customer-entered electricity bill');
    expect(find.textContaining('Cloud electricity rate saved'), findsOneWidget);
    api.close();
  });
}
