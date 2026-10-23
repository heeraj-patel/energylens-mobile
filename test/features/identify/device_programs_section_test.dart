import 'dart:convert';

import 'package:energylens_mobile/core/cloud_api/cloud_api_client.dart';
import 'package:energylens_mobile/core/cloud_auth/cloud_auth.dart';
import 'package:energylens_mobile/features/identify/cloud_usage_questions_screen.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

const _home = '11111111-1111-4111-8111-111111111111';
const _appliance = '22222222-2222-4222-8222-222222222222';
final _now = DateTime.utc(2026, 10, 22, 12);

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
  Future<CloudTokens> refresh(CloudAuthConfig config, String token) async =>
      const CloudTokens(accessToken: 'owner-token');
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

Map<String, dynamic> _program(
  int n, {
  String expires = '2027-01-15T12:00:00Z',
  String display = 'Up to 100 back',
}) => {
  'program_id': '44444444-4444-4444-8444-44444444444$n',
  'revision_id': '55555555-5555-4555-8555-555555555555',
  'title': 'Program $n',
  'administrator_name': 'Utility $n',
  'administrator_kind': 'utility',
  'benefit_kind': 'rebate',
  'benefit_display': display,
  'benefit_terms': <String, dynamic>{},
  'eligibility_terms': <String, dynamic>{},
  'stacking_terms': <String, dynamic>{},
  'availability_status': 'open',
  'status': 'unknown',
  'reasons': ['provider_unknown'],
  'source_url': 'https://utility.example/p$n',
  'source_sha256': 'a' * 64,
  'review_expires_at': expires,
};

http.Response _page(List<Map<String, dynamic>> rows) => http.Response(
  jsonEncode({
    'programs': rows,
    'as_of': '2026-10-22T12:00:00Z',
    'coverage': null,
  }),
  200,
);

Future<List<Uri>> _open(
  WidgetTester tester,
  http.Response Function() programs,
) async {
  final opened = <Uri>[];
  final api = _api(
    MockClient((request) async {
      if (request.url.path.endsWith('/programs')) return programs();
      if (request.url.path.endsWith('/questions/answers')) {
        return http.Response(jsonEncode({'answers': []}), 200);
      }
      return http.Response(jsonEncode({'questions': []}), 200);
    }),
  );
  addTearDown(api.close);
  await tester.pumpWidget(
    MaterialApp(
      home: CloudUsageQuestionsScreen(
        homeId: _home,
        applianceId: _appliance,
        applianceName: 'Washer',
        api: api,
        ownedApplianceIds: const {_appliance},
        programsNow: () => _now,
        openProgramUrl: (url) async => opened.add(url),
      ),
    ),
  );
  await tester.pumpAndSettle();
  return opened;
}

void main() {
  testWidgets('lists programs with amount, provider, expiry and link', (
    tester,
  ) async {
    final opened = await _open(tester, () => _page([_program(1), _program(2)]));
    expect(find.text('Programs and rebates'), findsOneWidget);
    expect(find.text('Program 1'), findsOneWidget);
    expect(find.text('Up to 100 back'), findsNWidgets(2));
    expect(find.text('Utility 2'), findsOneWidget);
    expect(find.text('Jan 15, 2027'), findsNWidgets(2));
    await tester.tap(find.text('Program 1'));
    expect(opened.single.toString(), 'https://utility.example/p1');
  });

  testWidgets('shows the empty message', (tester) async {
    await _open(tester, () => _page([]));
    expect(
      find.text('No programs found for this device in your area yet.'),
      findsOneWidget,
    );
  });

  testWidgets('programs failure shows the error and keeps the questions', (
    tester,
  ) async {
    await _open(tester, () => http.Response('{}', 500));
    expect(
      find.text("Couldn't load programs. Pull down to try again."),
      findsOneWidget,
    );
    expect(find.text('Refresh estimate'), findsOneWidget);
  });

  testWidgets('expands in place past three programs', (tester) async {
    await _open(
      tester,
      () => _page([for (var i = 1; i <= 5; i++) _program(i)]),
    );
    expect(find.text('Program 3'), findsOneWidget);
    expect(find.text('Program 4'), findsNothing);
    await tester.ensureVisible(find.text('See all 5 programs'));
    await tester.tap(find.text('See all 5 programs'));
    await tester.pumpAndSettle();
    expect(find.text('Program 5'), findsOneWidget);
    expect(find.text('See all 5 programs'), findsNothing);
  });

  testWidgets('hides expired programs', (tester) async {
    await _open(
      tester,
      () => _page([_program(1, expires: '2026-10-01T00:00:00Z'), _program(2)]),
    );
    expect(find.text('Program 1'), findsNothing);
    expect(find.text('Program 2'), findsOneWidget);
  });

  testWidgets('pull to refresh reloads programs', (tester) async {
    var calls = 0;
    await _open(tester, () {
      calls++;
      return _page([_program(calls)]);
    });
    expect(find.text('Program 1'), findsOneWidget);
    await tester.drag(find.byType(ListView), const Offset(0, 400));
    await tester.pumpAndSettle();
    expect(find.text('Program 2'), findsOneWidget);
  });
}
