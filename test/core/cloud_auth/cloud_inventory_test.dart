import 'dart:convert';
import 'dart:io';

import 'package:energylens_mobile/core/cloud_api/cloud_api_client.dart';
import 'package:energylens_mobile/core/cloud_api/cloud_home.dart';
import 'package:energylens_mobile/core/cloud_auth/cloud_auth.dart';
import 'package:energylens_mobile/features/identify/appliance_onboarding_screen.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

const _config = CloudAuthConfig(
  issuer: 'https://issuer.example',
  audience: 'energylens-cloud',
  clientId: 'client',
  redirectUrl: 'io.energylens.app://login-callback',
  apiUrl: 'https://api.example',
);
const _home = CloudHome(
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
    config: _config,
    store: _Store(),
    authenticator: _Auth(),
  ),
  client: MockClient((request) async {
    if (request.url.path == '/v1/energy-categories') {
      return http.Response(
        jsonEncode({
          'version': 1,
          'groups': [
            {
              'key': 'laundry',
              'label': 'Laundry',
              'types': [
                {'key': 'washer', 'label': 'Washer'},
              ],
            },
          ],
        }),
        200,
        headers: {'etag': '"1"'},
      );
    }
    final forwarded = http.Request(request.method, request.url)
      ..headers.addAll(request.headers)
      ..bodyBytes = request.bodyBytes;
    return http.Response.fromStream(await client.send(forwarded));
  }),
);

Future<void> _chooseWasher(WidgetTester tester) async {
  await tester.pumpAndSettle();
  await tester.tap(find.byKey(const ValueKey('applianceGroup-null')));
  await tester.pumpAndSettle();
  await tester.tap(find.text('Laundry').last);
  await tester.pumpAndSettle();
  await tester.tap(find.byKey(const ValueKey('applianceCategory-laundry-')));
  await tester.pumpAndSettle();
  await tester.tap(find.text('Washer').last);
  await tester.pumpAndSettle();
}

void main() {
  test(
    'model-only catalog search omits brand and fuel and returns every result',
    () async {
      http.Request? seen;
      final api = _api(
        MockClient((request) async {
          seen = request;
          return http.Response(
            jsonEncode({
              'products': [
                for (final id in [
                  '44444444-4444-4444-8444-444444444444',
                  '55555555-5555-4555-8555-555555555555',
                ])
                  {
                    'id': id,
                    'category': 'washer',
                    'brand': 'LG',
                    'full_model': 'WM3070HWA',
                    'variant': null,
                    'region': null,
                    'fuel': 'electricity',
                    'match_quality': 'confirmed_exact',
                    'facts': [],
                  },
              ],
            }),
            200,
          );
        }),
      );
      final products = await api.searchCatalogModels(model: 'WM3070HWA');
      expect(jsonDecode(seen!.body), {'model': 'WM3070HWA'});
      expect(products.map((product) => product.id), [
        '44444444-4444-4444-8444-444444444444',
        '55555555-5555-4555-8555-555555555555',
      ]);
      api.close();
    },
  );

  test('reviewed model search sends only confirmed identity fields and reads facts', () async {
    final seen = <http.Request>[];
    final product = {
      'id': '33333333-3333-4333-8333-333333333333',
      'category': 'washer',
      'brand': 'LG',
      'full_model': 'WM3070HWA',
      'variant': 'USW',
      'region': 'US',
      'fuel': 'electricity',
      'match_quality': 'confirmed_exact',
      'facts': [
        {
          'kind': 'annual_energy',
          'value': '111',
          'unit': 'kWh',
          'source_kind': 'oem_exact',
          'source_url': 'https://example.test/spec',
          'test_basis': {'cycles_per_year': 392},
          'reviewed_at': '2026-09-30T00:00:00Z',
        },
      ],
    };
    final api = _api(
      MockClient((request) async {
        seen.add(request);
        if (request.method == 'POST') {
          return http.Response(
            jsonEncode({
              'products': [product],
            }),
            200,
          );
        }
        return http.Response(jsonEncode(product), 200);
      }),
    );
    final results = await api.searchCatalogModels(
      brand: 'LG',
      model: 'WM3070HWA',
      fuel: 'electricity',
      region: 'US',
    );
    expect(results.single.isConfirmedExact, isTrue);
    final details = await api.catalogProduct(results.single.id);
    expect(details.facts.single.value, '111');
    expect(seen[0].url.path, '/v1/catalog/model-search');
    expect(jsonDecode(seen[0].body), {
      'brand': 'LG',
      'model': 'WM3070HWA',
      'fuel': 'electricity',
      'region': 'US',
    });
    expect(seen[0].headers['idempotency-key'], isNotEmpty);
    expect(seen[1].url.path, '/v1/catalog/products/${results.single.id}');
    api.close();
  });

  test(
    'family candidate search rejects attached representative facts',
    () async {
      final api = _api(
        MockClient(
          (_) async => http.Response(
            jsonEncode({
              'products': [
                {
                  'id': '44444444-4444-4444-8444-444444444444',
                  'category': 'washer',
                  'brand': 'LG',
                  'full_model': 'WM3070HWA',
                  'variant': null,
                  'region': 'US',
                  'fuel': 'electricity',
                  'match_quality': 'documented_variant_family',
                  'query_match': 'documented_family',
                  'matched_model': 'WM3070HXA',
                  'variant_match': 'unresolved',
                  'facts': [
                    {
                      'kind': 'annual_energy',
                      'value': '111',
                      'unit': 'kWh',
                      'source_kind': 'oem_family',
                      'source_url': 'https://example.test/family',
                      'test_basis': <String, Object>{},
                      'reviewed_at': '2026-09-30T00:00:00Z',
                    },
                  ],
                },
              ],
            }),
            200,
          ),
        ),
      );
      await expectLater(
        api.searchCatalogModels(
          brand: 'LG',
          model: 'WM3070HXA',
          fuel: 'electricity',
          region: 'US',
        ),
        throwsFormatException,
      );
      api.close();
    },
  );

  for (final (model, expectedModel) in [('', ''), ('WM3070HWA', 'WM3070HWA')]) {
    testWidgets(
      'explicit type saves ${model.isEmpty ? 'category-only' : 'model-only'} identity',
      (tester) async {
        tester.view.physicalSize = const Size(800, 1500);
        tester.view.devicePixelRatio = 1;
        addTearDown(tester.view.resetPhysicalSize);
        addTearDown(tester.view.resetDevicePixelRatio);
        http.Request? created;
        final api = _api(
          MockClient((request) async {
            if (request.url.path == '/v1/me/preferences') {
              return http.Response(
                '{"version":2,"schema_version":1,"email_reports_enabled":false}',
                200,
                headers: {'etag': '"2"'},
              );
            }
            if (request.url.path.endsWith('/questions/answers')) {
              return http.Response('{"answers":[]}', 200);
            }
            if (request.url.path.endsWith('/questions')) {
              return http.Response('{"questions":[]}', 200);
            }
            if (request.method == 'POST' &&
                request.url.path.endsWith('/appliances')) {
              created = request;
              final input = jsonDecode(request.body) as Map<String, dynamic>;
              return http.Response(
                jsonEncode({
                  'id': '22222222-2222-4222-8222-222222222222',
                  'home_id': _home.id,
                  'name': input['name'],
                  'category': input['category'],
                  'room': input['room'],
                  'identity': input['identity'],
                  'version': 1,
                  'created_at': '2026-09-30T00:00:00Z',
                  'updated_at': '2026-09-30T00:00:00Z',
                  'archived_at': null,
                }),
                201,
              );
            }
            return http.Response('', 404);
          }),
        );
        await tester.pumpWidget(
          MaterialApp(
            home: ApplianceOnboardingScreen(
              method: 'manual',
              cloudHome: _home,
              cloudApi: api,
            ),
          ),
        );
        await tester.enterText(
          find.byKey(const Key('applianceName')),
          'Washer',
        );
        expect(
          tester
              .widget<FilledButton>(find.byKey(const Key('saveAppliance')))
              .onPressed,
          isNull,
        );
        await _chooseWasher(tester);
        if (model.isNotEmpty) {
          await tester.enterText(
            find.byKey(const Key('applianceModel')),
            model,
          );
        }
        expect(find.byKey(const Key('searchReviewedCatalog')), findsNothing);
        await tester.ensureVisible(find.byKey(const Key('saveAppliance')));
        await tester.tap(find.byKey(const Key('saveAppliance')));
        await tester.pumpAndSettle();
        final payload = jsonDecode(created!.body) as Map<String, dynamic>;
        expect(payload['category'], 'washer');
        expect(payload['identity'], {
          'brand': '',
          'full_model': expectedModel,
          'fuel': 'electricity',
          'match_quality': 'unresolved',
        });
        api.close();
      },
    );
  }

  test(
    'owned cloud inventory list parses identity without adding local devices',
    () async {
      final api = _api(
        MockClient((request) async {
          expect(request.url.path, '/v1/homes/${_home.id}/appliances');
          expect(request.headers['authorization'], 'Bearer owner-token');
          return http.Response(
            jsonEncode({
              'appliances': [
                {
                  'id': '22222222-2222-4222-8222-222222222222',
                  'home_id': _home.id,
                  'name': 'Washer',
                  'category': 'other',
                  'room': 'Laundry',
                  'identity': {
                    'brand': 'LG',
                    'full_model': 'WM3070HWA',
                    'fuel': 'electricity',
                    'match_quality': 'confirmed_exact',
                  },
                  'version': 1,
                  'created_at': '2026-09-30T00:00:00Z',
                  'updated_at': '2026-09-30T00:00:00Z',
                  'archived_at': null,
                },
              ],
            }),
            200,
          );
        }),
      );
      final rows = await api.appliances(_home.id);
      expect(rows.single.fullModel, 'WM3070HWA');
      expect(rows.single.room, 'Laundry');
      api.close();
    },
  );

  testWidgets(
    'cloud save retries unchanged details with one key',
    (tester) async {
      tester.view.physicalSize = const Size(800, 1500);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      final posts = <http.Request>[];
      final api = _api(
        MockClient((request) async {
          if (request.url.path == '/v1/me/preferences') {
            return http.Response(
              '{"version":2,"schema_version":1,"email_reports_enabled":false}',
              200,
              headers: {'etag': '"2"'},
            );
          }
          if (request.url.path.endsWith('/questions/answers') &&
              request.method == 'GET') {
            return http.Response('{"answers":[]}', 200);
          }
          if (request.url.path.endsWith('/questions')) {
            return http.Response('{"questions":[]}', 200);
          }
          posts.add(request);
          if (posts.length == 1) {
            throw const SocketException('connection dropped');
          }
          return http.Response(
            jsonEncode({
              'id': '22222222-2222-4222-8222-222222222222',
              'home_id': _home.id,
              'name': 'Washer',
              'category': 'other',
              'room': null,
              'identity': {
                'brand': 'LG',
                'full_model': 'WM3070HWA',
                'fuel': 'electricity',
                'match_quality': 'confirmed_exact',
              },
              'version': 1,
              'created_at': '2026-09-30T00:00:00Z',
              'updated_at': '2026-09-30T00:00:00Z',
              'archived_at': null,
            }),
            201,
          );
        }),
      );
      await tester.pumpWidget(
        MaterialApp(
          home: ApplianceOnboardingScreen(
            method: 'manual',
            cloudHome: _home,
            cloudApi: api,
          ),
        ),
      );
      await tester.enterText(find.byKey(const Key('applianceName')), 'Washer');
      await _chooseWasher(tester);
      await tester.enterText(
        find.byKey(const Key('applianceManufacturer')),
        'LG',
      );
      await tester.enterText(
        find.byKey(const Key('applianceModel')),
        'WM3070HWA',
      );
      await tester.ensureVisible(find.byKey(const Key('saveAppliance')));
      await tester.tap(find.byKey(const Key('saveAppliance')));
      await tester.pumpAndSettle();
      expect(find.text('Internal Error, Try again later'), findsOneWidget);
      await tester.tap(find.byKey(const Key('saveAppliance')));
      await tester.pumpAndSettle();
      expect(posts, hasLength(2));
      expect(
        posts[0].headers['idempotency-key'],
        posts[1].headers['idempotency-key'],
      );
      final payload = jsonDecode(posts[0].body) as Map<String, dynamic>;
      expect(payload['identity'], {
        'brand': 'LG',
        'full_model': 'WM3070HWA',
        'fuel': 'electricity',
        'match_quality': 'unresolved',
      });
      expect(payload.containsKey('catalog_product_id'), isFalse);
      api.close();
    },
  );
}
