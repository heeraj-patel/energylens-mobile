import 'dart:convert';

import 'package:energylens_mobile/core/backend_error.dart';
import 'package:energylens_mobile/core/cloud_api/cloud_api_client.dart';
import 'package:energylens_mobile/core/cloud_auth/cloud_auth.dart';
import 'package:energylens_mobile/features/design/home_details_screen.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

const _homeId = '11111111-1111-4111-8111-111111111111';

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

Map<String, Object?> _homeJson([
  String name = 'Original Home',
  int version = 1,
]) => {
  'id': _homeId,
  'name': name,
  'timezone': 'America/Chicago',
  'location': {'country_code': 'US', 'postal_code': '60601'},
  'version': version,
};

Future<void> _openHome(
  WidgetTester tester, {
  String fuel = 'natural_gas',
  http.Response Function(http.Request)? onTariff,
  http.Response Function(http.Request)? onPatch,
  void Function(http.Request)? onRequest,
  void Function(bool?)? onResult,
}) async {
  tester.view.physicalSize = const Size(800, 2400);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);
  var name = 'Original Home';
  var version = 1;
  final client = MockClient((request) async {
    onRequest?.call(request);
    final path = request.url.path;
    http.Response ok(Object body, [Map<String, String>? headers]) =>
        http.Response(jsonEncode(body), 200, headers: headers ?? {});
    if (path == '/v1/me') {
      return ok({
        'id': 'owner',
        'email': 'owner@example.com',
        'email_verified': true,
      });
    }
    if (path == '/v1/homes' && request.method == 'GET') {
      return ok({
        'homes': [_homeJson()],
      });
    }
    if (path == '/v1/me/preferences') {
      return ok(
        {'schema_version': 1, 'version': 1, 'email_reports_enabled': false},
        {'etag': '"1"'},
      );
    }
    if (path == '/v1/homes/$_homeId/preferences') {
      return ok(
        {
          'schema_version': 1,
          'version': 1,
          'goal': 'unspecified',
          'comfort_priority': 'unknown',
        },
        {'etag': '"1"'},
      );
    }
    if (path == '/v1/homes/$_homeId/appliances') {
      return ok({
        'appliances': [
          {
            'id': '22222222-2222-4222-8222-222222222222',
            'home_id': _homeId,
            'name': 'Furnace',
            'category': 'other',
            'identity': {
              'brand': 'Acme',
              'full_model': 'F1',
              'fuel': fuel,
              'match_quality': 'confirmed_exact',
            },
          },
        ],
      });
    }
    if (path == '/v1/homes/$_homeId' && request.method == 'GET') {
      return ok(_homeJson(name, version), {'etag': '"$version"'});
    }
    if (path == '/v1/homes/$_homeId' && request.method == 'PATCH') {
      final failure = onPatch?.call(request);
      if (failure != null) return failure;
      name = (jsonDecode(request.body) as Map)['name'] as String? ?? name;
      version++;
      return ok(_homeJson(name, version), {'etag': '"$version"'});
    }
    if (path == '/v1/homes/$_homeId/tariffs' && request.method == 'POST') {
      return onTariff?.call(request) ?? http.Response(jsonEncode({}), 500);
    }
    fail('Unexpected ${request.method} $path');
  });
  await tester.pumpWidget(
    MaterialApp(
      home: Builder(
        builder: (context) => TextButton(
          onPressed: () async {
            final result = await Navigator.of(context).push<bool>(
              MaterialPageRoute(
                builder: (_) => HomeDetailsScreen(
                  api: _api(client),
                  homeId: _homeId,
                  isCurrentHome: () => true,
                ),
              ),
            );
            onResult?.call(result);
          },
          child: const Text('Open'),
        ),
      ),
    ),
  );
  await tester.tap(find.text('Open'));
  await tester.pumpAndSettle();
}

void main() {
  testWidgets(
    'home form saves through selected-home versioned API and readback',
    (tester) async {
      var name = 'Original Home';
      var version = 1;
      var writes = 0;
      String? notifiedHomeName;
      final client = MockClient((request) async {
        expect(request.headers['authorization'], 'Bearer owner-token');
        final path = request.url.path;
        if (path == '/v1/me') {
          return http.Response(
            jsonEncode({
              'id': 'owner',
              'email': 'owner@example.com',
              'email_verified': true,
            }),
            200,
          );
        }
        Map<String, Object?> home() => {
          'id': _homeId,
          'name': name,
          'timezone': 'America/Chicago',
          'location': {'country_code': 'US', 'postal_code': '60601'},
          'version': version,
        };
        if (path == '/v1/homes' && request.method == 'GET') {
          return http.Response(
            jsonEncode({
              'homes': [home()],
            }),
            200,
          );
        }
        if (path == '/v1/me/preferences') {
          return http.Response(
            jsonEncode({
              'schema_version': 1,
              'version': 1,
              'email_reports_enabled': false,
            }),
            200,
            headers: {'etag': '"1"'},
          );
        }
        if (path == '/v1/homes/$_homeId/preferences') {
          return http.Response(
            jsonEncode({
              'schema_version': 1,
              'version': 1,
              'goal': 'unspecified',
              'comfort_priority': 'unknown',
            }),
            200,
            headers: {'etag': '"1"'},
          );
        }
        if (path == '/v1/homes/$_homeId/appliances') {
          return http.Response(jsonEncode({'appliances': []}), 200);
        }
        if (path == '/v1/homes/$_homeId' && request.method == 'PATCH') {
          writes++;
          expect(request.headers['if-match'], '"1"');
          expect(
            request.headers['idempotency-key'],
            matches(
              RegExp(
                r'^[0-9a-f]{8}-[0-9a-f]{4}-4[0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$',
              ),
            ),
          );
          final patch = jsonDecode(request.body) as Map<String, dynamic>;
          expect(patch, {'name': 'Updated Home'});
          name = patch['name'] as String;
          version++;
          return http.Response(
            jsonEncode(home()),
            200,
            headers: {'etag': '"2"'},
          );
        }
        if (path == '/v1/homes/$_homeId' && request.method == 'GET') {
          return http.Response(
            jsonEncode(home()),
            200,
            headers: {'etag': '"$version"'},
          );
        }
        fail('Unexpected ${request.method} $path');
      });
      bool? result;
      await tester.pumpWidget(
        MaterialApp(
          home: Builder(
            builder: (context) => TextButton(
              onPressed: () async {
                result = await Navigator.of(context).push<bool>(
                  MaterialPageRoute(
                    builder: (_) => HomeDetailsScreen(
                      api: _api(client),
                      homeId: _homeId,
                      isCurrentHome: () => true,
                      onHomeNameChanged: (value) => notifiedHomeName = value,
                    ),
                  ),
                );
              },
              child: const Text('Open'),
            ),
          ),
        ),
      );
      await tester.tap(find.text('Open'));
      await tester.pumpAndSettle();
      expect(find.text('Home details'), findsOneWidget);
      expect(find.text('Original Home'), findsOneWidget);
      await tester.enterText(
        find.widgetWithText(TextField, 'Home name'),
        'Updated Home',
      );
      await tester.tap(find.text('Save changes'));
      await tester.pumpAndSettle();
      expect(writes, 1);
      expect(result, true);
      expect(notifiedHomeName, 'Updated Home');
      expect(find.text('Open'), findsOneWidget);
    },
  );

  testWidgets('G-C9: gas rate saves a natural_gas therm tariff', (
    tester,
  ) async {
    final tariffBodies = <Map<String, dynamic>>[];
    var patches = 0;
    final client = MockClient((request) async {
      final path = request.url.path;
      Map<String, Object?> home() => {
        'id': _homeId,
        'name': 'Original Home',
        'timezone': 'America/Chicago',
        'location': {'country_code': 'US', 'postal_code': '60601'},
        'version': 1,
      };
      if (path == '/v1/me') {
        return http.Response(
          jsonEncode({
            'id': 'owner',
            'email': 'owner@example.com',
            'email_verified': true,
          }),
          200,
        );
      }
      if (path == '/v1/homes' && request.method == 'GET') {
        return http.Response(
          jsonEncode({
            'homes': [home()],
          }),
          200,
        );
      }
      if (path == '/v1/me/preferences') {
        return http.Response(
          jsonEncode({
            'schema_version': 1,
            'version': 1,
            'email_reports_enabled': false,
          }),
          200,
          headers: {'etag': '"1"'},
        );
      }
      if (path == '/v1/homes/$_homeId/preferences') {
        return http.Response(
          jsonEncode({
            'schema_version': 1,
            'version': 1,
            'goal': 'unspecified',
            'comfort_priority': 'unknown',
          }),
          200,
          headers: {'etag': '"1"'},
        );
      }
      if (path == '/v1/homes/$_homeId/appliances') {
        return http.Response(jsonEncode({'appliances': []}), 200);
      }
      if (path == '/v1/homes/$_homeId' && request.method == 'GET') {
        return http.Response(jsonEncode(home()), 200, headers: {'etag': '"1"'});
      }
      if (path == '/v1/homes/$_homeId' && request.method == 'PATCH') {
        patches++;
        return http.Response(jsonEncode(home()), 200);
      }
      if (path == '/v1/homes/$_homeId/tariffs' && request.method == 'POST') {
        final body = jsonDecode(request.body) as Map<String, dynamic>;
        tariffBodies.add(body);
        return http.Response(
          jsonEncode({
            ...body,
            'id': 'tariff-1',
            'home_id': _homeId,
            'revision': 1,
          }),
          201,
        );
      }
      fail('Unexpected ${request.method} $path');
    });
    bool? result;
    await tester.pumpWidget(
      MaterialApp(
        home: Builder(
          builder: (context) => TextButton(
            onPressed: () async {
              result = await Navigator.of(context).push<bool>(
                MaterialPageRoute(
                  builder: (_) => HomeDetailsScreen(
                    api: _api(client),
                    homeId: _homeId,
                    isCurrentHome: () => true,
                  ),
                ),
              );
            },
            child: const Text('Open'),
          ),
        ),
      ),
    );
    await tester.tap(find.text('Open'));
    await tester.pumpAndSettle();
    final gasField = find.widgetWithText(TextField, 'Gas rate (\$/therm)');
    expect(gasField, findsOneWidget);
    await tester.enterText(gasField, 'abc');
    await tester.pump();
    expect(
      tester.widget<FilledButton>(find.byType(FilledButton)).onPressed,
      isNull,
    );
    await tester.enterText(gasField, '1.25');
    await tester.pump();
    await tester.tap(find.text('Save changes'));
    await tester.pumpAndSettle();
    expect(patches, 0);
    expect(tariffBodies, hasLength(1));
    expect(tariffBodies.single['fuel'], 'natural_gas');
    expect(tariffBodies.single['rate'], '1.25');
    expect(tariffBodies.single['rate_unit'], 'therm');
    expect(tariffBodies.single['rate_kind'], 'user_tariff');
    expect(tariffBodies.single['is_fallback'], false);
    expect(result, true);
  });

  group('gas rate range and fuel', () {
    const rangeText = 'Enter a gas rate between \$0.20 and \$10.00 per therm.';
    final gasField = find.widgetWithText(TextField, 'Gas rate (\$/therm)');
    bool saveEnabled(WidgetTester t) =>
        t.widget<FilledButton>(find.byType(FilledButton)).onPressed != null;

    testWidgets('accepts 0.20 and 10.00, rejects outside with the copy', (
      tester,
    ) async {
      await _openHome(tester);
      for (final bad in ['0.19', '0', '10.01', '1500']) {
        await tester.enterText(gasField, bad);
        await tester.pump();
        expect(saveEnabled(tester), isFalse, reason: bad);
        expect(find.text(rangeText), findsOneWidget, reason: bad);
      }
      for (final good in ['0.20', '10.00', '1.25']) {
        await tester.enterText(gasField, good);
        await tester.pump();
        expect(saveEnabled(tester), isTrue, reason: good);
        expect(find.text(rangeText), findsNothing, reason: good);
      }
    });

    testWidgets('hides the gas rate input for a propane home', (tester) async {
      await _openHome(tester, fuel: 'propane');
      expect(gasField, findsNothing);
      expect(saveEnabled(tester), isTrue);
    });
  });
  group('partial save', () {
    const gasText = "Home details saved. Your gas rate didn't save. Try again.";
    const conflictText =
        'Home details changed elsewhere. Reload and try again.';

    for (final status in [500, 409, 412]) {
      testWidgets('tariff $status after home PATCH shows the gas-rate error', (
        tester,
      ) async {
        bool? result;
        await _openHome(
          tester,
          onTariff: (_) => http.Response(jsonEncode({}), status),
          onResult: (value) => result = value,
        );
        await tester.enterText(
          find.widgetWithText(TextField, 'Home name'),
          'Renamed',
        );
        await tester.enterText(
          find.widgetWithText(TextField, 'Gas rate (\$/therm)'),
          '1.25',
        );
        await tester.pump();
        await tester.tap(find.text('Save changes'));
        await tester.pumpAndSettle();
        expect(find.text(gasText), findsOneWidget);
        expect(find.text(conflictText), findsNothing);
        expect(find.text(internalErrorMessage), findsNothing);
        expect(find.byType(HomeDetailsScreen), findsOneWidget);
        expect(result, isNull);
      });
    }

    testWidgets('home PATCH 409 keeps the home-conflict text', (tester) async {
      await _openHome(tester, onPatch: (_) => http.Response('{}', 409));
      await tester.enterText(
        find.widgetWithText(TextField, 'Home name'),
        'Renamed',
      );
      await tester.pump();
      await tester.tap(find.text('Save changes'));
      await tester.pumpAndSettle();
      expect(find.text(conflictText), findsOneWidget);
      expect(find.text(gasText), findsNothing);
    });
  });
}
