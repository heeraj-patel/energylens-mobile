import 'dart:convert';

import 'package:energylens_mobile/core/cloud_api/cloud_api_client.dart';
import 'package:energylens_mobile/core/cloud_api/cloud_appliance.dart';
import 'package:energylens_mobile/core/cloud_api/cloud_home.dart';
import 'package:energylens_mobile/core/cloud_api/cloud_programs.dart';
import 'package:energylens_mobile/core/cloud_auth/cloud_auth.dart';
import 'package:energylens_mobile/features/energy/cloud_programs_screen.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

const home = '11111111-1111-4111-8111-111111111111';
const appliance = '22222222-2222-4222-8222-222222222222';
const foreign = '33333333-3333-4333-8333-333333333333';
const refreshId = '77777777-7777-4777-8777-777777777777';
const requestKey = '88888888-8888-4888-8888-888888888888';

Map<String, dynamic> refreshStatus(String state, {bool withCoverage = false}) =>
    {
      'request_id': refreshId,
      'state': state,
      'created_at': '2026-10-01T11:00:00Z',
      'finished_at': state == 'pending' || state == 'running'
          ? null
          : '2026-10-01T11:01:00Z',
      'coverage': withCoverage ? coverage() : null,
    };

Map<String, dynamic> program() => {
  'program_id': '44444444-4444-4444-8444-444444444444',
  'revision_id': '55555555-5555-4555-8555-555555555555',
  'title': 'Appliance program',
  'administrator_name': 'City utility',
  'administrator_kind': 'city',
  'benefit_kind': 'rebate',
  'benefit_display': 'Up to 100 back',
  'benefit_terms': {'amount': '100'},
  'eligibility_terms': {'category': 'washer'},
  'stacking_terms': {'status': 'unknown'},
  'availability_status': 'open',
  'status': 'unknown',
  'reasons': ['provider_unknown'],
  'source_url': 'https://utility.example/program',
  'source_sha256': 'a' * 64,
  'review_expires_at': '2026-11-01T12:00:00Z',
};
Map<String, dynamic> page([List<Map<String, dynamic>>? rows]) => {
  'programs': rows ?? [program()],
  'as_of': '2026-10-01T12:00:00Z',
  'coverage': null,
};

Map<String, dynamic> coverage() => {
  'run_id': '66666666-6666-4666-8666-666666666666',
  'category': 'washer',
  'state': 'partial',
  'started_at': '2026-10-01T11:00:00Z',
  'finished_at': '2026-10-01T11:01:00Z',
  'limitations': ['zip_provider_discovery_incomplete'],
  'resolution_provenance': {},
  'scopes': [
    {
      'kind': 'utility',
      'key': 'utility-a',
      'name': 'Utility A',
      'provider_role': 'electric_distributor',
      'status': 'checked',
      'checked_at': '2026-10-01T11:00:30Z',
      'retry_after': null,
      'failure_code': null,
    },
    {
      'kind': 'county',
      'key': 'travis',
      'name': 'Travis County',
      'provider_role': null,
      'status': 'pending',
      'checked_at': null,
      'retry_after': null,
      'failure_code': 'probe_unconfigured',
    },
  ],
};

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

class _ProgramsScreenApi extends CloudApiClient {
  _ProgramsScreenApi()
    : super(
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
      );

  @override
  Future<List<CloudAppliance>> appliances(String homeId) async => [
    CloudAppliance(
      id: appliance,
      homeId: homeId,
      name: 'Washer',
      category: 'washer',
      room: null,
      brand: 'LG',
      fullModel: 'WM3070HWA',
      fuel: 'electricity',
      matchQuality: 'confirmed_exact',
    ),
  ];

  @override
  Future<CloudProgramPage> programs(
    String homeId,
    String applianceId,
    Set<String> ownedApplianceIds,
  ) async => CloudProgramPage.fromJson({...page([]), 'coverage': coverage()});
}

class _RefreshScreenApi extends _ProgramsScreenApi {
  final requests = <String>[];

  @override
  Future<CloudProgramRefresh> requestProgramRefresh(
    String homeId,
    String applianceId,
    Set<String> ownedApplianceIds, {
    required String idempotencyKey,
  }) async {
    requests.add(idempotencyKey);
    if (requests.length == 1) throw Exception('uncertain response');
    return CloudProgramRefresh.fromJson(refreshStatus('pending'));
  }

  @override
  Future<CloudProgramRefresh> programRefresh(
    String homeId,
    String requestId,
  ) async => CloudProgramRefresh.fromJson(refreshStatus('failed'));
}

void main() {
  test('refresh DTO enforces state and coverage shape', () {
    expect(
      CloudProgramRefresh.fromJson(refreshStatus('pending')).isFinished,
      false,
    );
    expect(
      CloudProgramRefresh.fromJson(refreshStatus('failed')).isFinished,
      true,
    );
    expect(
      CloudProgramRefresh.fromJson(refreshStatus('partial', withCoverage: true))
          .coverage
          ?.state,
      'partial',
    );
    for (final bad in [
      {...refreshStatus('pending'), 'finished_at': '2026-10-01T11:01:00Z'},
      {...refreshStatus('complete'), 'coverage': null},
      {...refreshStatus('failed'), 'unknown': true},
      {...refreshStatus('pending'), 'request_id': 'bad'},
      {...refreshStatus('pending'), 'state': 'all_checked'},
      {...refreshStatus('pending'), 'created_at': '2026-10-01'},
    ]) {
      expect(() => CloudProgramRefresh.fromJson(bad), throwsFormatException);
    }
  });

  testWidgets(
    'uncertain refresh retries same key and failed status keeps caveat',
    (tester) async {
      final api = _RefreshScreenApi();
      await tester.pumpWidget(
        MaterialApp(
          home: CloudProgramsScreen(
            api: api,
            home: const CloudHome(
              id: home,
              name: 'Home',
              timezone: 'America/Chicago',
              countryCode: 'US',
              postalCode: '78732',
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('programAppliance')));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Washer').last);
      await tester.pumpAndSettle();
      await tester.ensureVisible(
        find.byKey(const Key('requestProgramRefresh')),
      );
      await tester.tap(find.byKey(const Key('requestProgramRefresh')));
      await tester.pumpAndSettle();
      expect(
        find.textContaining('Retry sends the same request'),
        findsOneWidget,
      );
      await tester.tap(find.byKey(const Key('requestProgramRefresh')));
      await tester.pump();
      expect(api.requests, hasLength(2));
      expect(api.requests[0], api.requests[1]);
      expect(find.textContaining('queued'), findsOneWidget);
      // A failed check is still shown as limited discovery, not full coverage.
      await tester.pump(const Duration(seconds: 5));
      await tester.pump();
      expect(find.textContaining('Source discovery failed'), findsOneWidget);
    },
  );

  test('parses offline resolver evidence and neutral role', () {
    final parsed = CloudProgramPage.fromJson({
      ...page([]),
      'coverage': coverage(),
    });
    expect(parsed.coverage?.scopes.length, 2);
    final candidate = coverage();
    (candidate['scopes'] as List).first['provider_role'] =
        'electric_service_candidate';
    expect(
      CloudProgramPage.fromJson({...page([]), 'coverage': candidate})
          .coverage
          ?.scopes
          .first
          .providerRole,
      'electric_service_candidate',
    );
  });
  testWidgets('empty program results disclose missing source coverage', (
    tester,
  ) async {
    await tester.pumpWidget(
      MaterialApp(
        home: CloudProgramsScreen(
          api: _ProgramsScreenApi(),
          home: const CloudHome(
            id: home,
            name: 'Home',
            timezone: 'America/Chicago',
            countryCode: 'US',
            postalCode: '78732',
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('programAppliance')));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Washer').last);
    await tester.pumpAndSettle();
    await tester.scrollUntilVisible(
      find.textContaining('Other sources may not have been checked'),
      120,
    );
    expect(
      find.textContaining('Other sources may not have been checked'),
      findsOneWidget,
    );
    await tester.scrollUntilVisible(
      find.textContaining('Catalog results loaded'),
      120,
    );
    expect(find.textContaining('Catalog results loaded'), findsOneWidget);
    expect(
      find.textContaining('Utility A (utility) · source checked'),
      findsOneWidget,
    );
    expect(
      find.textContaining('Travis County (county) · not checked'),
      findsOneWidget,
    );
    expect(
      find.textContaining('ZIP candidates do not confirm'),
      findsOneWidget,
    );
  });

  test('accepts unknown source-cited results and location required', () {
    final candidate = CloudProgramPage.fromJson(page()).programs.single;
    expect(candidate.title, 'Appliance program');
    expect(candidate.administratorKind, 'city');
    expect(candidate.benefitTerms['amount'], '100');
    expect(candidate.benefitDisplay, 'Up to 100 back');
    expect(candidate.eligibilityTerms['category'], 'washer');
    expect(candidate.stackingTerms['status'], 'unknown');
    expect(candidate.availabilityStatus, 'open');
    expect(candidate.status, 'unknown');
    expect(
      CloudProgramPage.fromJson({
        ...page([])..remove('coverage'),
        'reason': 'location_required',
      }).locationRequired,
      isTrue,
    );
  });

  test('rejects unsupported claims and malformed candidates', () {
    for (final bad in [
      {...program(), 'status': 'eligible'},
      {...program(), 'availability_status': 'awarded'},
      {...program(), 'benefit_terms': '100'},
      {...program(), 'savings_amount': 100},
      {...program(), 'source_url': 'http://utility.example/program'},
      {...program(), 'source_sha256': 'bad'},
    ]) {
      expect(
        () => CloudProgramPage.fromJson(page([bad])),
        throwsFormatException,
      );
    }
    expect(
      () =>
          CloudProgramPage.fromJson({...page(), 'reason': 'location_required'}),
      throwsFormatException,
    );
    expect(
      () => CloudProgramPage.fromJson(page([program(), program()])),
      throwsFormatException,
    );
    expect(
      () => CloudProgramPage.fromJson({
        ...page(),
        'coverage': {...coverage(), 'state': 'all_checked'},
      }),
      throwsFormatException,
    );
    expect(
      () => CloudProgramPage.fromJson({
        ...page(),
        'coverage': {
          ...coverage(),
          'scopes': [
            {
              ...((coverage()['scopes'] as List).first as Map<String, dynamic>),
              'checked_at': null,
            },
          ],
        },
      }),
      throwsFormatException,
    );
  });

  test('validates concise single-line benefit display text', () {
    expect(
      CloudProgramPage.fromJson(
        page([
          {...program(), 'benefit_display': '💡' * 160},
        ]),
      ).programs.single.benefitDisplay.runes.length,
      160,
    );

    final missing = program()..remove('benefit_display');
    for (final candidate in [
      missing,
      {...program(), 'benefit_display': ''},
      {...program(), 'benefit_display': '  offer'},
      {...program(), 'benefit_display': 'offer  '},
      {...program(), 'benefit_display': 'line one\nline two'},
      {...program(), 'benefit_display': 'line one\rline two'},
      {...program(), 'benefit_display': 'offer\there'},
      {...program(), 'benefit_display': 'offer\u0000'},
      {...program(), 'benefit_display': '💡' * 161},
    ]) {
      expect(
        () => CloudProgramPage.fromJson(page([candidate])),
        throwsFormatException,
      );
    }
  });

  test('accepts only the supported administrator kinds', () {
    for (final kind in [
      'utility',
      'city',
      'county',
      'state',
      'tribal',
      'federal',
      'manufacturer',
    ]) {
      expect(
        CloudProgramPage.fromJson(
          page([
            {...program(), 'administrator_kind': kind},
          ]),
        ).programs.single.administratorKind,
        kind,
      );
    }

    final missingKind = program()..remove('administrator_kind');
    for (final candidate in [
      missingKind,
      {...program(), 'administrator_kind': 'other'},
      {...program(), 'administrator_kind': 'Utility'},
    ]) {
      expect(
        () => CloudProgramPage.fromJson(page([candidate])),
        throwsFormatException,
      );
    }
  });

  test('requests only selected owned appliance with bearer session', () async {
    final seen = <http.Request>[];
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
        seen.add(request);
        return http.Response(jsonEncode(page()), 200);
      }),
    );
    expect(
      (await api.programs(home, appliance, {appliance})).programs.single.title,
      'Appliance program',
    );
    expect(seen.single.url.path, '/v1/homes/$home/programs');
    expect(seen.single.url.queryParameters['appliance_id'], appliance);
    expect(seen.single.headers['authorization'], 'Bearer owner-token');
    await expectLater(
      api.programs(home, foreign, {appliance}),
      throwsArgumentError,
    );
    expect(seen.length, 1);
    expect(
      (await api.homePrograms(home)).programs.single.title,
      'Appliance program',
    );
    expect(seen.last.url.path, '/v1/homes/$home/programs');
    expect(seen.last.url.query, isEmpty);
    await expectLater(api.homePrograms('invalid'), throwsArgumentError);
    expect(seen.length, 2);
  });

  test('refresh POST and GET use owner-scoped paths and header key', () async {
    final seen = <http.Request>[];
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
        seen.add(request);
        return http.Response(
          jsonEncode(refreshStatus('pending')),
          request.method == 'POST' ? 202 : 200,
        );
      }),
    );
    await api.requestProgramRefresh(home, appliance, {
      appliance,
    }, idempotencyKey: requestKey);
    expect(seen.single.url.path, '/v1/homes/$home/programs/discovery-refresh');
    expect(jsonDecode(seen.single.body), {'appliance_id': appliance});
    expect(seen.single.headers['idempotency-key'], requestKey);
    expect(seen.single.headers['authorization'], 'Bearer owner-token');
    await api.programRefresh(home, refreshId);
    expect(
      seen.last.url.path,
      '/v1/homes/$home/programs/discovery-refresh/$refreshId',
    );
    await expectLater(
      api.requestProgramRefresh(home, foreign, {
        appliance,
      }, idempotencyKey: requestKey),
      throwsArgumentError,
    );
    expect(seen, hasLength(2));
  });
}
