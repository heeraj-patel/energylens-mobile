import 'dart:convert';
import 'dart:io';

import 'package:energylens_mobile/core/cloud_api/cloud_api_client.dart';
import 'package:energylens_mobile/core/cloud_api/cloud_appliance.dart';
import 'package:energylens_mobile/core/cloud_api/cloud_home.dart';
import 'package:energylens_mobile/core/cloud_auth/cloud_auth.dart';
import 'package:energylens_mobile/features/identify/cloud_usage_questions_screen.dart';
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
const appliance = CloudAppliance(
  id: '22222222-2222-4222-8222-222222222222',
  homeId: '11111111-1111-4111-8111-111111111111',
  name: 'Washer',
  category: 'washer',
  room: null,
  brand: 'LG',
  fullModel: 'WM3070HWA',
  fuel: 'electricity',
  matchQuality: 'confirmed_exact',
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

void main() {
  testWidgets('reads current answers and ignores stale question versions', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(800, 1600);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final posts = <http.Request>[];
    Map<String, Object?> question(String id, int version) => {
      'id': id,
      'version': version,
      'purpose': 'onboarding',
      'appliance_id': appliance.id,
      'identity_revision': 3,
      'prompt': id,
      'answer_kind': 'cycles_per_week',
      'unit': 'cycles/week',
      'optional': true,
    };
    Map<String, Object?> answer(
      String id,
      int version,
      String status,
      Object? value, {
      int revision = 3,
    }) => {
      'question_id': id,
      'question_version': version,
      'appliance_id': appliance.id,
      'identity_revision': revision,
      'status': status,
      'value': value,
    };
    final api = _api(
      MockClient((request) async {
        if (request.url.path.endsWith('/questions/answers') &&
            request.method == 'GET') {
          expect(request.url.queryParameters, {'appliance_id': appliance.id});
          return http.Response(
            jsonEncode({
              'answers': [
                answer('zero', 1, 'confirmed', 0),
                answer('unknown', 1, 'unknown', null),
                answer('stale', 1, 'confirmed', 4),
                answer('old-revision', 1, 'confirmed', 5, revision: 2),
              ],
            }),
            200,
          );
        }
        if (request.method == 'GET') {
          return http.Response(
            jsonEncode({
              'questions': [
                question('zero', 1),
                question('unknown', 1),
                question('stale', 2),
                question('old-revision', 1),
                question('unanswered', 1),
              ],
            }),
            200,
          );
        }
        posts.add(request);
        return http.Response('{"answers":[{}]}', 201);
      }),
    );
    await tester.pumpWidget(
      MaterialApp(
        home: CloudUsageQuestionsScreen(
          home: home,
          appliance: appliance,
          api: api,
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.text('Saved: 0 cycles/week'), findsOneWidget);
    expect(find.text('Saved: Unknown'), findsOneWidget);
    expect(find.text('Not answered yet'), findsNWidgets(3));
    expect(find.byKey(const Key('usageValue-zero')), findsOneWidget);
    expect(
      tester
          .widget<TextField>(find.byKey(const Key('usageValue-zero')))
          .controller!
          .text,
      '0',
    );
    await tester.ensureVisible(find.byKey(const Key('saveUsageAnswers')));
    await tester.tap(find.byKey(const Key('saveUsageAnswers')));
    await tester.pumpAndSettle();
    expect(posts, isEmpty);
    api.close();
  });

  testWidgets('confirmed zero retries with identical body and key', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(800, 1400);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final posts = <http.Request>[];
    final api = _api(
      MockClient((request) async {
        if (request.method == 'GET') {
          if (request.url.path.endsWith('/questions/answers')) {
            expect(request.url.queryParameters, {'appliance_id': appliance.id});
            return http.Response('{"answers":[]}', 200);
          }
          expect(request.url.queryParameters, {
            'purpose': 'onboarding',
            'appliance_id': appliance.id,
          });
          return http.Response(
            jsonEncode({
              'questions': [
                {
                  'id': 'washer.cycles_per_week',
                  'version': 1,
                  'purpose': 'onboarding',
                  'appliance_id': appliance.id,
                  'identity_revision': 3,
                  'prompt': 'How many cycles?',
                  'answer_kind': 'cycles_per_week',
                  'unit': 'cycles/week',
                  'optional': true,
                },
              ],
            }),
            200,
          );
        }
        posts.add(request);
        if (posts.length == 1) throw const SocketException('uncertain');
        return http.Response(
          jsonEncode({
            'answers': [{}],
          }),
          201,
        );
      }),
    );
    await tester.pumpWidget(
      MaterialApp(
        home: CloudUsageQuestionsScreen(
          home: home,
          appliance: appliance,
          api: api,
        ),
      ),
    );
    await tester.pumpAndSettle();
    await tester.tap(
      find.byKey(const Key('usageConfirmed-washer.cycles_per_week')),
    );
    await tester.pumpAndSettle();
    await tester.enterText(
      find.byKey(const Key('usageValue-washer.cycles_per_week')),
      '0',
    );
    await tester.ensureVisible(find.byKey(const Key('saveUsageAnswers')));
    await tester.tap(find.byKey(const Key('saveUsageAnswers')));
    await tester.pumpAndSettle();
    expect(find.textContaining('Retry unchanged answers'), findsOneWidget);
    await tester.tap(find.byKey(const Key('saveUsageAnswers')));
    await tester.pumpAndSettle();
    expect(posts, hasLength(2));
    expect(posts[0].body, posts[1].body);
    expect(
      posts[0].headers['idempotency-key'],
      posts[1].headers['idempotency-key'],
    );
    final answer = (jsonDecode(posts[0].body)['answers'] as List).single;
    expect(answer['identity_revision'], 3);
    expect(answer['status'], 'confirmed');
    expect(answer['value'], 0);
    expect(answer['confirmed_at'], isNotNull);
    api.close();
  });

  testWidgets('unknown sends null without confirmation timestamp', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(800, 1400);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    http.Request? post;
    final api = _api(
      MockClient((request) async {
        if (request.method == 'GET') {
          if (request.url.path.endsWith('/questions/answers')) {
            return http.Response('{"answers":[]}', 200);
          }
          return http.Response(
            jsonEncode({
              'questions': [
                {
                  'id': 'washer.cycles_per_week',
                  'version': 1,
                  'purpose': 'onboarding',
                  'appliance_id': appliance.id,
                  'identity_revision': 3,
                  'prompt': 'How many cycles?',
                  'answer_kind': 'cycles_per_week',
                  'unit': 'cycles/week',
                  'optional': true,
                },
              ],
            }),
            200,
          );
        }
        post = request;
        return http.Response('{"answers":[{}]}', 201);
      }),
    );
    await tester.pumpWidget(
      MaterialApp(
        home: CloudUsageQuestionsScreen(
          home: home,
          appliance: appliance,
          api: api,
        ),
      ),
    );
    await tester.pumpAndSettle();
    await tester.tap(
      find.byKey(const Key('usageUnknown-washer.cycles_per_week')),
    );
    await tester.ensureVisible(find.byKey(const Key('saveUsageAnswers')));
    await tester.tap(find.byKey(const Key('saveUsageAnswers')));
    await tester.pumpAndSettle();
    final answer = (jsonDecode(post!.body)['answers'] as List).single;
    expect(answer['status'], 'unknown');
    expect(answer['value'], isNull);
    expect(answer['confirmed_at'], isNull);
    api.close();
  });

  testWidgets('FAQ context saves zero and advances to the next prompt', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(800, 1400);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    http.Request? post;
    var answered = false;
    final api = _api(
      MockClient((request) async {
        if (request.method == 'POST') {
          post = request;
          answered = true;
          return http.Response('{"answers":[{}]}', 201);
        }
        if (request.url.path.endsWith('/questions/answers')) {
          return http.Response('{"answers":[]}', 200);
        }
        expect(request.url.queryParameters['purpose'], 'faq');
        return http.Response(
          jsonEncode({
            'questions': answered
                ? []
                : [
                    {
                      'id': 'faq-contributors/v1.washer.recent_cycles',
                      'version': 1,
                      'purpose': 'faq',
                      'appliance_id': appliance.id,
                      'identity_revision': 3,
                      'prompt': 'Recent cycles?',
                      'answer_kind': 'cycles_per_week',
                      'unit': 'cycles/week',
                      'optional': true,
                    },
                  ],
          }),
          200,
        );
      }),
    );
    await tester.pumpWidget(
      MaterialApp(
        home: CloudUsageQuestionsScreen(
          home: home,
          appliance: appliance,
          api: api,
          purpose: 'faq',
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.text('Recent-use questions'), findsOneWidget);
    await tester.tap(
      find.byKey(
        const Key('usageConfirmed-faq-contributors/v1.washer.recent_cycles'),
      ),
    );
    await tester.pump();
    await tester.enterText(
      find.byKey(
        const Key('usageValue-faq-contributors/v1.washer.recent_cycles'),
      ),
      '0',
    );
    await tester.ensureVisible(find.byKey(const Key('saveUsageAnswers')));
    await tester.tap(find.byKey(const Key('saveUsageAnswers')));
    await tester.pumpAndSettle();
    expect((jsonDecode(post!.body)['answers'] as List).single['value'], 0);
    expect(
      find.textContaining('No more questions are available'),
      findsOneWidget,
    );
    api.close();
  });
}
