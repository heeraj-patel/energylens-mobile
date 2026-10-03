import 'dart:convert';

import 'package:energylens_mobile/core/cloud_api/cloud_api_client.dart';
import 'package:energylens_mobile/core/cloud_api/cloud_home.dart';
import 'package:energylens_mobile/core/cloud_api/cloud_recommendations.dart';
import 'package:energylens_mobile/core/cloud_auth/cloud_auth.dart';
import 'package:energylens_mobile/features/energy/cloud_recommendations_screen.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

const appliance = '22222222-2222-4222-8222-222222222222';
const foreign = '33333333-3333-4333-8333-333333333333';
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

CloudApiClient apiFor(MockClient client) => CloudApiClient(
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

Map<String, dynamic> action() => {
  'rule_id': 'computer.sleep_settings',
  'rule_version': 1,
  'appliance_id': appliance,
  'state': 'candidate',
  'title': 'Review sleep settings',
  'explanation': 'Check manufacturer-supported settings.',
  'next_question': 'hours_per_week',
  'benefit_group': 'computer_idle',
  'evidence_refs': <Map<String, dynamic>>[],
  'savings_amount': null,
};

void main() {
  test('accepts owner-scoped candidate and rejects unsupported savings', () {
    final body = {
      'actions': [action()],
      'as_of': '2026-10-01T12:00:00Z',
    };
    expect(
      CloudRecommendationBatch.fromJson(body, {appliance}).actions.single.state,
      'candidate',
    );
    expect(
      () => CloudRecommendationBatch.fromJson(
        {
          'actions': [
            {...action(), 'appliance_id': foreign},
          ],
          'as_of': body['as_of'],
        },
        {appliance},
      ),
      throwsFormatException,
    );
    expect(
      () => CloudRecommendationBatch.fromJson(
        {
          'actions': [
            {...action(), 'savings_amount': '20'},
          ],
          'as_of': body['as_of'],
        },
        {appliance},
      ),
      throwsFormatException,
    );
  });

  test('active action requires evidence and duplicate rules fail closed', () {
    expect(
      () => CloudRecommendationBatch.fromJson(
        {
          'actions': [
            {...action(), 'state': 'active', 'next_question': null},
          ],
          'as_of': '2026-10-01T12:00:00Z',
        },
        {appliance},
      ),
      throwsFormatException,
    );
    expect(
      () => CloudRecommendationBatch.fromJson(
        {
          'actions': [action(), action()],
          'as_of': '2026-10-01T12:00:00Z',
        },
        {appliance},
      ),
      throwsFormatException,
    );
  });

  test('accepts the seven Cloud rule IDs and rejects unknown IDs', () {
    const ruleIds = [
      'dishwasher.cycle_options',
      'heat_pump.operating_guidance',
      'water_heater.operating_mode',
      'dehumidifier.humidity_setting',
      'lighting.equivalent_bulb',
      'fan.speed_setting',
      'pool_pump.operating_guidance',
    ];
    final actions = ruleIds
        .map((ruleId) => {...action(), 'rule_id': ruleId})
        .toList();
    final parsed = CloudRecommendationBatch.fromJson(
      {'actions': actions, 'as_of': '2026-10-01T12:00:00Z'},
      {appliance},
    );
    expect(parsed.actions.map((item) => item.ruleId), ruleIds);
    expect(
      () => CloudRecommendationBatch.fromJson(
        {
          'actions': [
            {...action(), 'rule_id': 'unrecognized.future_rule'},
          ],
          'as_of': '2026-10-01T12:00:00Z',
        },
        {appliance},
      ),
      throwsFormatException,
    );
  });

  test(
    'mixed-home batch retains owner actions and rejects foreign appliances',
    () {
      final parsed = CloudRecommendationBatch.fromJson(
        {
          'actions': [action()],
          'as_of': '2026-10-01T12:00:00Z',
        },
        {appliance},
      );
      expect(parsed.actions, hasLength(1));
      expect(parsed.actions.single.applianceId, appliance);
      expect(
        () => CloudRecommendationBatch.fromJson(
          {
            'actions': [
              {
                ...action(),
                'rule_id': 'dishwasher.cycle_options',
                'appliance_id': foreign,
              },
            ],
            'as_of': '2026-10-01T12:00:00Z',
          },
          {appliance},
        ),
        throwsFormatException,
      );
    },
  );

  testWidgets('renders a newly supported recommendation rule', (tester) async {
    const dishwasherId = '44444444-4444-4444-8444-444444444444';
    final api = apiFor(
      MockClient((request) async {
        if (request.url.path.endsWith('/appliances')) {
          return http.Response(
            jsonEncode({
              'appliances': [
                {
                  'id': dishwasherId,
                  'home_id': home.id,
                  'name': 'Dishwasher',
                  'category': 'dishwasher',
                  'identity': {
                    'brand': 'Acme',
                    'full_model': 'DW100',
                    'fuel': 'electricity',
                    'match_quality': 'confirmed_exact',
                  },
                },
              ],
            }),
            200,
          );
        }
        return http.Response(
          jsonEncode({
            'actions': [
              {
                ...action(),
                'rule_id': 'dishwasher.cycle_options',
                'appliance_id': dishwasherId,
                'title': 'Review dishwasher cycle options',
              },
            ],
            'as_of': '2026-10-01T12:00:00Z',
          }),
          200,
        );
      }),
    );
    await tester.pumpWidget(
      MaterialApp(
        home: CloudRecommendationsScreen(api: api, home: home),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.text('Review dishwasher cycle options'), findsOneWidget);
    expect(
      find.byKey(
        const Key('recommendation-dishwasher.cycle_options-$dishwasherId'),
      ),
      findsOneWidget,
    );
    api.close();
  });
}
