import 'dart:convert';

import 'package:energylens_mobile/core/cloud_api/cloud_api_client.dart';
import 'package:energylens_mobile/core/cloud_api/cloud_home.dart';
import 'package:energylens_mobile/core/cloud_auth/cloud_auth.dart';
import 'package:energylens_mobile/features/discovery/discovery_credentials.dart';
import 'package:energylens_mobile/main.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

const _home = CloudHome(
  id: '11111111-1111-4111-8111-111111111111',
  name: 'Selected Home',
  timezone: 'America/Chicago',
  countryCode: 'US',
  postalCode: '60601',
);

class _Credentials extends DiscoveryCredentials {
  @override
  Future<(String?, String?)> read() async => (null, null);
}

class _Store implements CloudTokenStore {
  @override
  Future<void> clear() async {}
  @override
  Future<CloudTokens?> read() async => const CloudTokens(accessToken: 'owner');
  @override
  Future<void> save(CloudTokens tokens) async {}
}

class _Auth implements CloudAuthenticator {
  @override
  Future<CloudTokens> signIn(CloudAuthConfig config) async =>
      const CloudTokens(accessToken: 'owner');
  @override
  Future<CloudTokens> refresh(CloudAuthConfig config, String token) async =>
      const CloudTokens(accessToken: 'owner');
}

void main() {
  testWidgets('selected Cloud home opens actions and FAQ from Stop Waste', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(390, 844);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final paths = <String>[];
    final api = CloudApiClient(
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
      client: MockClient((request) async {
        paths.add(request.url.path);
        expect(request.headers['authorization'], 'Bearer owner');
        expect(request.url.path, startsWith('/v1/homes/${_home.id}/'));
        if (request.url.path.endsWith('/appliances')) {
          return http.Response('{"appliances":[]}', 200);
        }
        if (request.url.path.endsWith('/programs')) {
          return http.Response(
            '{"programs":[],"as_of":"2026-10-02T00:00:00Z","coverage":null}',
            200,
          );
        }
        if (request.url.path.endsWith('/recommendations')) {
          return http.Response(
            '{"actions":[],"as_of":"2026-10-02T00:00:00Z"}',
            200,
          );
        }
        if (request.url.path.contains('/faq/answers/')) {
          return http.Response(
            jsonEncode({
              'question_id': 'high_bill_possible_contributors',
              'status': 'insufficient_information',
              'answer': 'More usage information is needed.',
              'findings': [],
              'evidence_refs': [],
              'as_of': '2026-10-02T00:00:00Z',
              'next_action': {
                'kind': 'adaptive_questions',
                'flow_id': 'faq-contributors/v1',
              },
            }),
            200,
          );
        }
        if (request.url.path.endsWith('/estimates')) {
          return http.Response(
            '{"estimates":[],"as_of":"2026-10-02T00:00:00Z"}',
            200,
          );
        }
        return http.Response('', 404);
      }),
    );

    await tester.pumpWidget(
      MaterialApp(
        home: HomeScreen(
          credentials: _Credentials(),
          cloudHome: _home,
          cloudApi: api,
          initialTabIndex: 1,
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.text('Explore ways to reduce use'), findsOneWidget);
    expect(find.textContaining('Waste is not yet assessed'), findsOneWidget);
    expect(find.text('MONITORING NOT CONNECTED'), findsNothing);
    expect(find.text('Programs'), findsOneWidget);
    expect(find.byKey(const Key('localPilotWapProgram')), findsNothing);
    expect(paths, ['/v1/homes/${_home.id}/programs']);

    await tester.ensureVisible(find.byKey(const Key('stopWasteCloudActions')));
    await tester.tap(find.byKey(const Key('stopWasteCloudActions')));
    await tester.pumpAndSettle();
    expect(
      find.text('No actions are available for this home’s current appliances.'),
      findsOneWidget,
    );
    expect(paths, contains('/v1/homes/${_home.id}/recommendations'));
    await tester.pageBack();
    await tester.pumpAndSettle();

    await tester.ensureVisible(find.byKey(const Key('stopWasteCloudFaq')));
    await tester.tap(find.byKey(const Key('stopWasteCloudFaq')));
    await tester.pumpAndSettle();
    expect(find.text('More usage information is needed.'), findsOneWidget);
    expect(
      paths,
      contains(
        '/v1/homes/${_home.id}/faq/answers/high_bill_possible_contributors',
      ),
    );
    await tester.pageBack();
    await tester.pumpAndSettle();

    await tester.ensureVisible(
      find.byKey(const Key('stopWasteCloudEstimates')),
    );
    await tester.tap(find.byKey(const Key('stopWasteCloudEstimates')));
    await tester.pumpAndSettle();
    expect(
      find.text('Appliance energy'),
      findsOneWidget,
    );
    expect(paths, contains('/v1/homes/${_home.id}/estimates'));
    api.close();
  });
}
