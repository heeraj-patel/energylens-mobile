import 'dart:convert';

import 'package:energylens_mobile/core/cloud_api/cloud_api_client.dart';
import 'package:energylens_mobile/core/cloud_api/cloud_appliance.dart';
import 'package:energylens_mobile/core/cloud_api/cloud_home.dart';
import 'package:energylens_mobile/core/cloud_api/cloud_question.dart';
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

http.Response _acknowledge(http.Request request) => http.Response(
  jsonEncode({
    'answers': [
      for (final answer in jsonDecode(request.body)['answers'] as List)
        {...answer as Map<String, dynamic>, 'home_id': home.id},
    ],
  }),
  201,
);

void main() {
  test('rejects duplicate prompts for one appliance', () async {
    final api = _api(
      MockClient(
        (request) async => http.Response(
          jsonEncode({
            'questions': [
              for (var i = 0; i < 2; i++)
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
        ),
      ),
    );
    await expectLater(
      api.questions(home.id, appliance.id, purpose: 'onboarding'),
      throwsFormatException,
    );
    api.close();
  });

  test('rejects an acknowledgement for another question', () async {
    final api = _api(
      MockClient((request) async {
        final rows = jsonDecode(request.body)['answers'] as List;
        final changed = Map<String, dynamic>.from(rows.single as Map);
        changed['question_id'] = 'faq.other_question';
        changed['home_id'] = home.id;
        return http.Response(
          jsonEncode({
            'answers': [changed],
          }),
          201,
        );
      }),
    );
    final question = CloudQuestion(
      id: 'faq-contributors/v1.washer.recent_cycles',
      purpose: 'faq',
      version: 1,
      applianceId: appliance.id,
      identityRevision: 3,
      prompt: 'Recent cycles?',
      answerKind: 'cycles_per_week',
      unit: 'cycles/week',
      optional: true,
    );
    await expectLater(
      api.submitQuestionAnswers(home.id, [
        CloudAnswerCreate(
          question: question,
          value: 0,
          confirmedAt: DateTime.utc(2026, 10, 2),
        ),
      ], idempotencyKey: newCloudIdempotencyKey()),
      throwsFormatException,
    );
    api.close();
  });

  test('rejects an acknowledgement for another home', () async {
    final api = _api(
      MockClient((request) async {
        final rows = jsonDecode(request.body)['answers'] as List;
        return http.Response(
          jsonEncode({
            'answers': [
              {...rows.single as Map<String, dynamic>, 'home_id': appliance.id},
            ],
          }),
          201,
        );
      }),
    );
    final question = CloudQuestion(
      id: 'washer.cycles_per_week',
      purpose: 'onboarding',
      version: 1,
      applianceId: appliance.id,
      identityRevision: 3,
      prompt: 'How many cycles?',
      answerKind: 'cycles_per_week',
      unit: 'cycles/week',
      optional: true,
    );
    await expectLater(
      api.submitQuestionAnswers(home.id, [
        CloudAnswerCreate(question: question, value: null, confirmedAt: null),
      ], idempotencyKey: newCloudIdempotencyKey()),
      throwsFormatException,
    );
    api.close();
  });

  group('device detail screen', () {
    Map<String, Object?> choice(
      String id,
      String prompt,
      List<List<Object>> o,
    ) => {
      'id': id,
      'version': 2,
      'purpose': 'onboarding',
      'appliance_id': appliance.id,
      'identity_revision': 3,
      'prompt': prompt,
      'answer_kind': 'choice',
      'unit': 'cycles/week',
      'optional': true,
      'options': [
        for (final e in o) {'key': e[0], 'value': e[1]},
      ],
    };

    final washer = choice(
      'washer.cycles_per_week',
      'About how many loads a week?',
      [
        ['0_2', 1.5],
        ['3_5', 4],
        ['6_8', 7],
        ['9_plus', 10],
      ],
    );

    Future<List<http.Request>> open(
      WidgetTester tester, {
      List<Map<String, Object?>> questions = const [],
      List<Map<String, Object?>> answers = const [],
      http.Response Function(http.Request)? refresh,
    }) async {
      tester.view.physicalSize = const Size(1170, 2532);
      tester.view.devicePixelRatio = 3;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      final posts = <http.Request>[];
      final api = _api(
        MockClient((request) async {
          if (request.url.path.endsWith('/energy-resolution/refresh')) {
            posts.add(request);
            return refresh!(request);
          }
          if (request.url.path.endsWith('/questions/answers')) {
            if (request.method == 'POST') {
              posts.add(request);
              return _acknowledge(request);
            }
            return http.Response(jsonEncode({'answers': answers}), 200);
          }
          return http.Response(jsonEncode({'questions': questions}), 200);
        }),
      );
      addTearDown(api.close);
      await tester.pumpWidget(
        MaterialApp(
          home: CloudUsageQuestionsScreen(
            homeId: home.id,
            applianceId: appliance.id,
            applianceName: appliance.name,
            api: api,
          ),
        ),
      );
      await tester.pumpAndSettle();
      return posts;
    }

    http.Response accepted(http.Request _) => http.Response(
      jsonEncode({
        'appliance_id': appliance.id,
        'reason': 'owner_refresh',
        'queued_at': '2026-10-20T10:00:00Z',
      }),
      202,
    );

    testWidgets('shows the name, options with approved labels and the action', (
      tester,
    ) async {
      await open(tester, questions: [washer]);
      expect(find.text('Washer'), findsOneWidget);
      expect(find.text('About how many loads a week?'), findsOneWidget);
      for (final label in ['0-2', '3-5', '6-8', '9 or more', 'Not sure']) {
        expect(find.text(label), findsOneWidget);
      }
      expect(find.text('Refresh estimate'), findsOneWidget);
      expect(find.text('Skip'), findsNothing);
    });

    testWidgets('shows the saved answer as selected', (tester) async {
      await open(
        tester,
        questions: [washer],
        answers: [
          {
            'question_id': 'washer.cycles_per_week',
            'question_version': 2,
            'appliance_id': appliance.id,
            'identity_revision': 3,
            'status': 'confirmed',
            'value': 7,
          },
        ],
      );
      expect(find.byIcon(Icons.check), findsOneWidget);
    });

    testWidgets('a tapped option saves its numeric value', (tester) async {
      final posts = await open(tester, questions: [washer]);
      await tester.tap(find.text('6-8'));
      await tester.pumpAndSettle();
      final answer = (jsonDecode(posts.single.body)['answers'] as List).single;
      expect(answer['status'], 'confirmed');
      expect(answer['value'], 7);
      expect(find.byIcon(Icons.check), findsOneWidget);
    });

    testWidgets('Not sure saves unknown', (tester) async {
      final posts = await open(tester, questions: [washer]);
      await tester.tap(find.text('Not sure'));
      await tester.pumpAndSettle();
      final answer = (jsonDecode(posts.single.body)['answers'] as List).single;
      expect(answer['status'], 'unknown');
      expect(answer['value'], isNull);
    });

    testWidgets('refresh accepted shows the approved message', (tester) async {
      final posts = await open(tester, refresh: accepted);
      await tester.tap(find.text('Refresh estimate'));
      await tester.pumpAndSettle();
      expect(
        find.text(
          'Checking for newer energy data. This can take a few minutes.',
        ),
        findsOneWidget,
      );
      expect(
        posts.single.headers['Idempotency-Key'],
        matches(
          RegExp(
            r'^[0-9a-f]{8}-[0-9a-f]{4}-4[0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$',
          ),
        ),
      );
    });

    testWidgets('refresh rate limit shows the approved message and waits', (
      tester,
    ) async {
      await open(
        tester,
        refresh: (_) => http.Response(
          jsonEncode({
            'code': 'refresh_rate_limited',
            'details': {'retry_after_seconds': 60},
          }),
          429,
        ),
      );
      await tester.tap(find.text('Refresh estimate'));
      await tester.pump();
      await tester.pump();
      expect(
        find.text('You refreshed this device recently. Try again later.'),
        findsOneWidget,
      );
      expect(
        tester
            .widget<FilledButton>(find.byKey(const Key('refreshEstimate')))
            .onPressed,
        isNull,
      );
      await tester.pump(const Duration(seconds: 61));
      expect(
        tester
            .widget<FilledButton>(find.byKey(const Key('refreshEstimate')))
            .onPressed,
        isNotNull,
      );
    });

    testWidgets('other refresh failures show the one internal error', (
      tester,
    ) async {
      await open(
        tester,
        refresh: (_) => http.Response(
          jsonEncode({'code': 'boom', 'message': 'database down'}),
          500,
        ),
      );
      await tester.tap(find.text('Refresh estimate'));
      await tester.pumpAndSettle();
      expect(find.text('Internal Error, Try again later'), findsOneWidget);
      expect(find.textContaining('database'), findsNothing);
    });

    testWidgets('a failed question load shows the internal error', (
      tester,
    ) async {
      tester.view.physicalSize = const Size(1170, 2532);
      tester.view.devicePixelRatio = 3;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      final api = _api(MockClient((_) async => http.Response('nope', 503)));
      addTearDown(api.close);
      await tester.pumpWidget(
        MaterialApp(
          home: CloudUsageQuestionsScreen(
            homeId: home.id,
            applianceId: appliance.id,
            applianceName: appliance.name,
            api: api,
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(find.text('Internal Error, Try again later'), findsOneWidget);
    });
  });
}
