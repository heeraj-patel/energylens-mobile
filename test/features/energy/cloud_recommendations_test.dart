import 'package:energylens_mobile/core/cloud_api/cloud_api_client.dart';
import 'package:energylens_mobile/core/cloud_api/cloud_home.dart';
import 'package:energylens_mobile/core/cloud_api/cloud_recommendations.dart';
import 'package:energylens_mobile/core/cloud_auth/cloud_auth.dart';
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
  test('accepts owner-scoped candidate and supported scenario benefit', () {
    final body = {
      'actions': [action()],
      'as_of': '2026-10-01T12:00:00Z',
    };
    expect(
      CloudRecommendationBatch.fromJson(body, {appliance}).actions.single.state,
      'candidate',
    );
    expect(
      CloudRecommendationBatch.fromJson(
        {
          'actions': [
            {...action(), 'appliance_id': foreign},
          ],
          'as_of': body['as_of'],
        },
        {appliance},
      ).actions,
      isEmpty,
    );
    final benefit = CloudRecommendation.fromJson(
      {
        ...action(),
        'savings_amount': '20.00',
        'savings_period': 'month',
        'savings_currency': 'USD',
        'savings_basis': 'bill_cost',
        'scenario_refs': [
          {
            'id': 'aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa',
            'kind': 'baseline_alternative',
            'revision': 2,
          },
        ],
      },
      {appliance},
    );
    expect(benefit.savingsAmount, '20.00');
    expect(benefit.scenarioRefs.single['revision'], 2);
    expect(
      () => CloudRecommendation.fromJson(
        {...action(), 'savings_amount': '20.00'},
        {appliance},
      ),
      throwsFormatException,
    );
  });

  test('binds only reviewed HTTPS scenario source URLs', () {
    final reviewed = {
      ...action(),
      'savings_amount': '20.00',
      'savings_period': 'year',
      'savings_currency': 'USD',
      'savings_basis': 'reviewed_action_scenario',
      'scenario_refs': [
        {
          'id': 'aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa',
          'kind': 'reviewed_action_scenario',
          'revision': 1,
        },
      ],
      'source_url': 'https://manufacturer.example/eco-guide',
    };
    expect(
      CloudRecommendation.fromJson(reviewed, {appliance}).sourceUrl.toString(),
      'https://manufacturer.example/eco-guide',
    );
    for (final url in [
      'http://manufacturer.example/eco-guide',
      'https://user@manufacturer.example/eco-guide',
    ]) {
      final actionWithBadLink = CloudRecommendation.fromJson(
        {...reviewed, 'source_url': url},
        {appliance},
      );
      expect(actionWithBadLink.sourceUrl, isNull);
      expect(actionWithBadLink.savingsAmount, '20.00');
    }
    expect(
      CloudRecommendation.fromJson(
        {...action(), 'source_url': reviewed['source_url']},
        {appliance},
      ).sourceUrl,
      isNull,
    );
  });

  test('active action requires evidence and duplicate rules fail closed', () {
    expect(
      CloudRecommendationBatch.fromJson(
        {
          'actions': [
            {...action(), 'state': 'active', 'next_question': null},
          ],
          'as_of': '2026-10-01T12:00:00Z',
        },
        {appliance},
      ).actions,
      isEmpty,
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

  test('accepts every Cloud lifecycle state without dropping the action', () {
    const states = [
      'active',
      'candidate',
      'accepted',
      'completed',
      'snoozed',
      'dismissed',
      'expired',
      'superseded',
    ];
    for (final state in states) {
      final value = {
        ...action(),
        'state': state,
        if (state != 'candidate') 'next_question': null,
        if (state == 'active')
          'evidence_refs': [
            {
              'id': 'aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa',
              'kind': 'annual_energy',
              'revision': 1,
            },
            {
              'id': 'bbbbbbbb-bbbb-4bbb-8bbb-bbbbbbbbbbbb',
              'kind': 'confirmed_answer',
              'revision': 1,
            },
          ],
      };
      expect(CloudRecommendation.fromJson(value, {appliance}).state, state);
    }
  });

  test('parses source tip categories and defaults old servers to general', () {
    final rows = [
      {
        ...action(),
        'rule_id': 'refrigerator.maintenance',
        'tip_category': 'care',
      },
      {
        ...action(),
        'rule_id': 'lighting.equivalent_bulb',
        'tip_category': 'upgrade',
      },
      action(),
    ];
    final parsed = CloudRecommendationBatch.fromJson(
      {'actions': rows, 'as_of': '2026-10-01T12:00:00Z'},
      {appliance},
    );
    expect(parsed.actions.map((item) => item.tipCategory), [
      CloudRecommendationTipCategory.care,
      CloudRecommendationTipCategory.upgrade,
      CloudRecommendationTipCategory.general,
    ]);
    expect(
      () => CloudRecommendation.fromJson(
        {...action(), 'tip_category': 'unclear'},
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
      CloudRecommendationBatch.fromJson(
        {
          'actions': [
            {...action(), 'rule_id': 'unrecognized.future_rule'},
          ],
          'as_of': '2026-10-01T12:00:00Z',
        },
        {appliance},
      ).actions,
      isEmpty,
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
        CloudRecommendationBatch.fromJson(
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
        ).actions,
        isEmpty,
      );
    },
  );

  test('skips malformed and foreign rows while preserving valid order', () {
    final parsed = CloudRecommendationBatch.fromJson(
      {
        'actions': [
          action(),
          'malformed',
          {...action(), 'rule_id': 'unknown'},
          {...action(), 'appliance_id': foreign},
          {...action(), 'rule_id': 'fan.speed_setting'},
        ],
        'as_of': '2026-10-01T12:00:00Z',
      },
      {appliance},
    );
    expect(parsed.actions.map((item) => item.ruleId), [
      'computer.sleep_settings',
      'fan.speed_setting',
    ]);
  });

  test('accepts the seven gas appliance rule IDs', () {
    const ruleIds = [
      'furnace.gas_efficiency_check',
      'furnace.gas_standby',
      'boiler.gas_efficiency_check',
      'boiler.gas_standby',
      'water_heater.gas_cost',
      'water_heater.gas_efficiency_check',
      'space_heater.gas_schedule',
    ];
    final parsed = CloudRecommendationBatch.fromJson(
      {
        'actions': [
          for (final ruleId in ruleIds) {...action(), 'rule_id': ruleId},
        ],
        'as_of': '2026-10-01T12:00:00Z',
      },
      {appliance},
    );
    expect(parsed.actions.map((item) => item.ruleId), ruleIds);
  });

  test('accepts household_size as a next question', () {
    final parsed = CloudRecommendation.fromJson(
      {
        ...action(),
        'rule_id': 'water_heater.gas_cost',
        'next_question': 'household_size',
      },
      {appliance},
    );
    expect(parsed.nextQuestion, 'household_size');
    expect(
      CloudRecommendationBatch.fromJson(
        {
          'actions': [
            {...action(), 'next_question': 'unknown_question'},
          ],
          'as_of': '2026-10-01T12:00:00Z',
        },
        {appliance},
      ).actions,
      isEmpty,
    );
  });

  test('recommendations request sends the gas appliance capability', () async {
    Uri? requested;
    final api = apiFor(
      MockClient((request) async {
        requested = request.url;
        return http.Response(
          '{"actions":[],"as_of":"2026-10-01T12:00:00Z"}',
          200,
          headers: {'content-type': 'application/json'},
        );
      }),
    );
    await api.recommendations(home.id, {appliance});
    expect(requested?.path, endsWith('/recommendations'));
    expect(
      requested?.queryParameters['capability'],
      'gas_appliance_recommendations_v1',
    );
  });

  test('invalid envelope still rejects the batch', () {
    for (final body in [
      {'actions': 'bad', 'as_of': '2026-10-01T12:00:00Z'},
      {'actions': [], 'as_of': 'bad'},
      {'actions': List.filled(201, action()), 'as_of': '2026-10-01T12:00:00Z'},
    ]) {
      expect(
        () => CloudRecommendationBatch.fromJson(body, {appliance}),
        throwsFormatException,
      );
    }
  });
}
