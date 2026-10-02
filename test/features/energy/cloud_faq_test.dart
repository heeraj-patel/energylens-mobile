import 'dart:convert';

import 'package:energylens_mobile/core/cloud_api/cloud_api_client.dart';
import 'package:energylens_mobile/core/cloud_api/cloud_faq.dart';
import 'package:energylens_mobile/core/cloud_api/cloud_home.dart';
import 'package:energylens_mobile/core/cloud_auth/cloud_auth.dart';
import 'package:energylens_mobile/features/energy/cloud_faq_screen.dart';
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
const appliance = '22222222-2222-4222-8222-222222222222';
const catalog = '33333333-3333-4333-8333-333333333333';
const tariff = '44444444-4444-4444-8444-444444444444';

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

Map<String, Object?> _fallback(String intent) => {
  'question_id': intent,
  'status': 'insufficient_information',
  'answer': faqInsufficientAnswer,
  'findings': [],
  'evidence_refs': [],
  'next_action': {
    'kind': 'adaptive_questions',
    'flow_id': 'faq-contributors/v1',
  },
  'as_of': '2026-10-01T00:00:00Z',
};

Map<String, Object?> _cost() {
  final refs = [
    {'id': catalog, 'kind': 'catalog_fact', 'revision': 2},
    {'id': tariff, 'kind': 'tariff', 'revision': 1},
  ];
  return {
    'question_id': 'device_operating_cost',
    'status': 'supported',
    'answer': 'An operating cost estimate is available for this device.',
    'findings': [
      {
        'label': 'estimate',
        'text':
            'Estimated operating cost: 0.00 USD for 2026-10-01 to 2026-11-01.',
        'evidence_refs': refs,
      },
    ],
    'evidence_refs': refs,
    'as_of': '2026-10-01T00:00:00Z',
  };
}

void main() {
  test('rejects unsourced or fabricated device cost', () {
    expect(
      CloudFaqAnswer.fromJson(
        _cost(),
        'device_operating_cost',
      ).findings.single.text,
      contains('0.00 USD'),
    );
    final unsourced = _cost();
    final finding =
        (unsourced['findings'] as List).single as Map<String, Object?>;
    finding['evidence_refs'] = [
      {'id': catalog, 'kind': 'catalog_fact', 'revision': 2},
    ];
    unsourced['evidence_refs'] = finding['evidence_refs'];
    expect(
      () => CloudFaqAnswer.fromJson(unsourced, 'device_operating_cost'),
      throwsFormatException,
    );
    final invented = _cost();
    (invented['findings'] as List).single['text'] =
        'Your bill increased by 20%.';
    expect(
      () => CloudFaqAnswer.fromJson(invented, 'device_operating_cost'),
      throwsFormatException,
    );
  });

  testWidgets('owner FAQ uses all intents, fallback link and sourced cost', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(900, 1800);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final requests = <http.Request>[];
    final api = _api(
      MockClient((request) async {
        requests.add(request);
        expect(request.headers['authorization'], 'Bearer owner');
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
        final intent = request.url.pathSegments.last;
        expect(request.url.path, '/v1/homes/${home.id}/faq/answers/$intent');
        if (intent == 'device_operating_cost') {
          expect(request.url.queryParameters['appliance_id'], appliance);
        } else {
          expect(request.url.queryParameters, isEmpty);
        }
        return http.Response(
          jsonEncode(
            intent == 'device_operating_cost' ? _cost() : _fallback(intent),
          ),
          200,
        );
      }),
    );
    await tester.pumpWidget(
      MaterialApp(
        home: CloudFaqScreen(api: api, home: home),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.text(faqInsufficientAnswer), findsOneWidget);
    expect(find.byKey(const Key('faqQuestions-$appliance')), findsOneWidget);
    for (final intent in faqIntents.keys.where(
      (i) => i != 'device_operating_cost',
    )) {
      await tester.tap(find.byKey(Key('faqIntent-$intent')));
      await tester.pumpAndSettle();
      expect(find.text(faqInsufficientAnswer), findsOneWidget);
    }
    await tester.tap(find.byKey(const Key('faqIntent-device_operating_cost')));
    await tester.pumpAndSettle();
    expect(
      find.text('Select an appliance to see its sourced operating cost.'),
      findsOneWidget,
    );
    await tester.tap(find.byKey(const Key('faqAppliance')));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Washer').last);
    await tester.pumpAndSettle();
    expect(
      find.text(
        'Estimated operating cost: 0.00 USD for 2026-10-01 to 2026-11-01.',
      ),
      findsOneWidget,
    );
    expect(
      requests.where((r) => r.url.path.contains('/faq/answers/')).length,
      5,
    );
    api.close();
  });
}
