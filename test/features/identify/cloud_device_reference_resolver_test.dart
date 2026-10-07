import 'dart:convert';
import 'dart:io';
import 'dart:async';

import 'package:energylens_mobile/core/cloud_api/cloud_api_client.dart';
import 'package:energylens_mobile/core/cloud_api/cloud_appliance.dart';
import 'package:energylens_mobile/core/cloud_api/cloud_appliance_list.dart';
import 'package:energylens_mobile/core/cloud_auth/cloud_auth.dart';
import 'package:energylens_mobile/features/design/devices_domain_repository.dart';
import 'package:energylens_mobile/features/identify/cloud_device_reference_resolver.dart';
import 'package:energylens_mobile/features/identify/device_reference_inventory_observer.dart';
import 'package:energylens_mobile/features/identify/unresolved_device_help_report.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

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

CloudAppliance _appliance({String? productId}) => CloudAppliance(
  id: 'device-1',
  homeId: 'private-home',
  name: 'Kitchen washer',
  category: 'washer',
  room: 'Kitchen',
  brand: 'LG',
  fullModel: 'WM3070HWA',
  variant: 'USW',
  region: 'US',
  fuel: 'electricity',
  catalogProductId: productId,
  matchQuality: 'confirmed_exact',
);

Map<String, Object?> _product({
  String model = 'WM3070HWA',
  String? variant = 'USW',
  String quality = 'confirmed_exact',
  String source = 'epa_exact',
  List<Map<String, Object?>>? facts,
}) => {
  'id': 'product-1',
  'category': 'washer',
  'brand': 'LG',
  'full_model': model,
  'variant': variant,
  'region': 'US',
  'fuel': 'electricity',
  'match_quality': quality,
  'facts': facts ?? [_fact(source: source)],
};

Map<String, Object?> _fact({
  String source = 'epa_exact',
  String kind = 'annual_energy',
  String unit = 'kWh',
}) => {
  'kind': kind,
  'value': '111',
  'unit': unit,
  'source_kind': source,
  'source_url': 'https://example.org/rating',
  'test_basis': {'cycles_per_year': 392},
  'reviewed_at': '2026-09-30T00:00:00Z',
};

DevicesDomainSnapshot _snapshot({
  CloudApplianceDataMode mode = CloudApplianceDataMode.household,
  CloudAppliance? appliance,
}) => DevicesDomainSnapshot(
  homeId: 'private-home',
  items: [
    DeviceInventoryItem(
      appliance: appliance ?? _appliance(),
      activeAttachmentIds: const [],
      measuredBuckets: const [],
    ),
  ],
  hasMoreMeteredPages: false,
  dataMode: mode,
  fixtureRevision: mode == CloudApplianceDataMode.sample ? 'sample' : null,
);

void main() {
  late Directory directory;
  late File reportFile;
  setUp(() async {
    directory = await Directory.systemTemp.createTemp('reference-resolver-');
    reportFile = File('${directory.path}/internal/help.jsonl');
  });
  tearDown(() async => directory.delete(recursive: true));

  test(
    'exact reviewed EPA rating retains provenance and creates no help row',
    () async {
      final seen = <String>[];
      final api = _api(
        MockClient((request) async {
          seen.add(request.url.path);
          if (request.url.path.endsWith('/model-search')) {
            return http.Response(
              jsonEncode({
                'products': [_product()],
              }),
              200,
            );
          }
          return http.Response(jsonEncode(_product()), 200);
        }),
      );
      final result = await CloudDeviceReferenceResolver(
        api,
        helpReport: UnresolvedDeviceHelpReport(reportFile),
      ).resolve(_appliance());
      expect(result.status, DeviceReferenceStatus.resolved);
      expect(
        result.reference!.facts.single.metric,
        DeviceReferenceMetric.annualKwh,
      );
      expect(result.reference!.facts.single.value, 111);
      expect(result.reference!.facts.single.sourceKind, 'epa_exact');
      expect(
        result.reference!.facts.single.sourceUrl.toString(),
        'https://example.org/rating',
      );
      expect(result.reference!.facts.single.testBasis['cycles_per_year'], 392);
      expect(seen, [
        '/v1/catalog/model-search',
        '/v1/catalog/products/product-1',
      ]);
      expect(await reportFile.exists(), isFalse);
      api.close();
    },
  );

  test('family and wrong variant cannot supply a rating', () async {
    final api = _api(
      MockClient((request) async {
        if (request.url.path.endsWith('/model-search')) {
          return http.Response(
            jsonEncode({
              'products': [
                _product(variant: 'OTHER'),
                _product(quality: 'documented_variant_family', facts: []),
              ],
            }),
            200,
          );
        }
        return http.Response(jsonEncode(_product()), 200);
      }),
    );
    final result = await CloudDeviceReferenceResolver(
      api,
      helpReport: UnresolvedDeviceHelpReport(reportFile),
      clock: () => DateTime.utc(2026, 10, 7),
    ).resolve(_appliance());
    expect(result.status, DeviceReferenceStatus.noExactMatch);
    final row = jsonDecode((await reportFile.readAsLines()).single);
    expect(row['manufacturer'], 'LG');
    expect(row['model'], 'WM3070HWA');
    expect(row['lookup_status'], 'noExactMatch');
    expect(row['sources_attempted'], contains('reviewed KB catalog'));
    api.close();
  });

  test('unreviewed source is rejected and queued for help', () async {
    final product = _product(source: 'oem_family');
    final api = _api(
      MockClient(
        (request) async => http.Response(
          request.url.path.endsWith('/model-search')
              ? jsonEncode({
                  'products': [product],
                })
              : jsonEncode(product),
          200,
        ),
      ),
    );
    final result = await CloudDeviceReferenceResolver(
      api,
      helpReport: UnresolvedDeviceHelpReport(reportFile),
    ).resolve(_appliance());
    expect(result.status, DeviceReferenceStatus.noReviewedFacts);
    expect(await reportFile.exists(), isTrue);
    api.close();
  });

  test('linked exact OEM rating resolves without a model search', () async {
    final seen = <String>[];
    final api = _api(
      MockClient((request) async {
        seen.add(request.url.path);
        return http.Response(jsonEncode(_product(source: 'oem_exact')), 200);
      }),
    );
    final result = await CloudDeviceReferenceResolver(
      api,
      helpReport: UnresolvedDeviceHelpReport(reportFile),
    ).resolve(_appliance(productId: 'product-1'));
    expect(result.status, DeviceReferenceStatus.resolved);
    expect(result.reference!.facts.single.sourceKind, 'oem_exact');
    expect(seen, ['/v1/catalog/products/product-1']);
    expect(await reportFile.exists(), isFalse);
    api.close();
  });

  test(
    'catalog outage is recorded without claiming a missing rating',
    () async {
      final api = _api(
        MockClient((_) async => http.Response('unavailable', 503)),
      );
      final result = await CloudDeviceReferenceResolver(
        api,
        helpReport: UnresolvedDeviceHelpReport(reportFile),
      ).resolve(_appliance());
      expect(result.status, DeviceReferenceStatus.lookupFailed);
      final row = jsonDecode((await reportFile.readAsLines()).single);
      expect(row['lookup_status'], 'lookupFailed');
      api.close();
    },
  );

  test(
    'household observer caches identity and skips sample inventory',
    () async {
      var searches = 0;
      final api = _api(
        MockClient((request) async {
          if (request.url.path.endsWith('/model-search')) {
            searches++;
            return http.Response(
              jsonEncode({
                'products': [_product()],
              }),
              200,
            );
          }
          return http.Response(jsonEncode(_product()), 200);
        }),
      );
      final observer = DeviceReferenceInventoryObserver(
        CloudDeviceReferenceResolver(api),
      );
      await observer.observe(_snapshot(mode: CloudApplianceDataMode.sample));
      expect(searches, 0);
      await observer.observe(_snapshot());
      await observer.observe(_snapshot());
      expect(searches, 1);
      expect(observer.resultFor('device-1')?.isResolved, isTrue);
      observer.clear();
      expect(observer.resultFor('device-1'), isNull);
      await observer.observe(_snapshot());
      expect(searches, 2);
      api.close();
    },
  );

  test('observer suppresses an in-flight result after context clear', () async {
    final delayed = Completer<http.Response>();
    var searches = 0;
    final api = _api(
      MockClient((request) async {
        if (request.url.path.endsWith('/model-search')) {
          searches++;
          return delayed.future;
        }
        return http.Response(jsonEncode(_product()), 200);
      }),
    );
    final observer = DeviceReferenceInventoryObserver(
      CloudDeviceReferenceResolver(api),
    );
    final pending = observer.observe(_snapshot());
    await Future<void>.delayed(Duration.zero);
    observer.clear();
    delayed.complete(
      http.Response(
        jsonEncode({
          'products': [_product()],
        }),
        200,
      ),
    );
    await pending;
    expect(observer.resultFor('device-1'), isNull);
    expect(searches, 1);
    api.close();
  });

  test('observer swallows lookup outage and permits retry', () async {
    var searches = 0;
    final api = _api(
      MockClient((request) async {
        if (request.url.path.endsWith('/model-search')) searches++;
        return http.Response('unavailable', 503);
      }),
    );
    final observer = DeviceReferenceInventoryObserver(
      CloudDeviceReferenceResolver(api),
    );
    await observer.observe(_snapshot());
    expect(observer.resultFor('device-1'), isNull);
    await observer.observe(_snapshot());
    expect(searches, 2);
    expect(await reportFile.exists(), isFalse);
    api.close();
  });
}
