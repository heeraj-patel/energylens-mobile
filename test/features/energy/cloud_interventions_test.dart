import 'dart:convert';

import 'package:energylens_mobile/core/cloud_api/cloud_api_client.dart';
import 'package:energylens_mobile/core/cloud_api/cloud_interventions.dart';
import 'package:energylens_mobile/core/cloud_auth/cloud_auth.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

const home = '11111111-1111-4111-8111-111111111111';
const appliance = '22222222-2222-4222-8222-222222222222';
const attachment = '33333333-3333-4333-8333-333333333333';
const intervention = '44444444-4444-4444-8444-444444444444';
const key = '55555555-5555-4555-8555-555555555555';

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
      audience: 'cloud',
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
  test('owner-scoped attachment and exact metering gate', () async {
    final api = _api(
      MockClient((request) async {
        expect(request.headers['authorization'], 'Bearer owner-token');
        if (request.url.path.endsWith('/attachments')) {
          return http.Response(
            jsonEncode({
              'attachments': [
                {
                  'id': attachment,
                  'home_id': home,
                  'appliance_id': appliance,
                  'started_at': '2026-09-01T00:00:00Z',
                  'ended_at': null,
                },
              ],
            }),
            200,
          );
        }
        expect(request.url.queryParameters['attachment_id'], attachment);
        return http.Response(
          jsonEncode({
            'granularity': 'day',
            'next_cursor': null,
            'summaries': [
              {
                'kind': 'energy',
                'bucket_start': '2026-10-01T00:00:00Z',
                'computed_at': '2026-10-02T00:00:00Z',
                'sensor_id': appliance,
                'hub_id': home,
                'ownership_epoch': 1,
                'source_refs': [],
                'attachment_id': attachment,
                'energy_wh': 200.0,
                'covered_seconds': 3600.0,
                'interval_count': 1,
                'status': 'complete',
                'allocation_method': 'exact',
              },
            ],
          }),
          200,
        );
      }),
    );
    final listed = await api.attachments(home);
    expect(listed.single.activeAt(DateTime.utc(2026, 10, 1)), isTrue);
    expect(await api.hasExactMeterEvidence(home, attachment), isTrue);
    api.close();
  });

  test(
    'create reuses caller key and outcome preserves noncausal limits',
    () async {
      final now = DateTime.now().toUtc();
      final at = DateTime.utc(now.year, now.month, now.day, now.hour);
      final sent = <String>[];
      final api = _api(
        MockClient((request) async {
          if (request.method == 'POST') {
            expect(request.url.path, '/v1/homes/$home/interventions');
            expect(request.headers['idempotency-key'], key);
            sent.add(request.body);
            return http.Response(
              jsonEncode({
                'id': intervention,
                'status': 'completed',
                'outcome_status': 'collecting',
              }),
              201,
            );
          }
          expect(
            request.url.path,
            '/v1/homes/$home/interventions/$intervention/outcome',
          );
          final period = {
            'from': '2026-09-01T00:00:00Z',
            'to': '2026-09-08T00:00:00Z',
            'expected_hours': 168,
            'measured_hours': 80,
            'covered_seconds': 288000,
            'coverage_fraction': 0.476,
            'known_gap_hours': 3,
            'allocated_hours': 0,
            'energy_wh': null,
          };
          return http.Response(
            jsonEncode({
              'action': {'id': intervention, 'home_id': home},
              'status': 'inconclusive',
              'reasons': ['insufficient_measured_coverage'],
              'before': period,
              'after': period,
              'delta_wh': null,
              'evaluated_at': '2026-10-02T00:00:00Z',
              'interpretation': 'No causal savings conclusion can be drawn.',
            }),
            200,
          );
        }),
      );
      final input = CloudInterventionCreate(
        applianceId: appliance,
        attachmentId: attachment,
        ruleId: 'computer.sleep_settings',
        occurredAt: at,
        comparableUse: false,
        comparableWeather: false,
        confounders: const ['unknown'],
      );
      expect(
        (await api.createIntervention(home, input, idempotencyKey: key)).id,
        intervention,
      );
      expect(
        (await api.createIntervention(home, input, idempotencyKey: key)).id,
        intervention,
      );
      expect(sent, hasLength(2));
      expect(sent.first, sent.last);
      final outcome = await api.interventionOutcome(home, intervention);
      expect(outcome.status, 'inconclusive');
      expect(outcome.deltaWh, isNull);
      expect(outcome.before.knownGapHours, 3);
      expect(outcome.interpretation, contains('No causal savings'));
      api.close();
    },
  );
}
