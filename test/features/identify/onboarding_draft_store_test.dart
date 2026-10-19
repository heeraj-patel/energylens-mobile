import 'dart:convert';

import 'package:energylens_mobile/core/cloud_api/cloud_appliance.dart';
import 'package:energylens_mobile/core/cloud_api/cloud_api_client.dart';
import 'package:energylens_mobile/core/cloud_api/cloud_catalog.dart';
import 'package:energylens_mobile/core/cloud_api/cloud_home.dart';
import 'package:energylens_mobile/core/cloud_auth/cloud_auth.dart';
import 'package:energylens_mobile/features/identify/onboarding_draft_store.dart';
import 'package:energylens_mobile/features/identify/onboarding_persistence_repository.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

class _TokenStore implements CloudTokenStore {
  @override
  Future<void> clear() async {}
  @override
  Future<CloudTokens?> read() async => const CloudTokens(accessToken: 'token');
  @override
  Future<void> save(CloudTokens value) async {}
}

class _Auth implements CloudAuthenticator {
  @override
  Future<CloudTokens> signIn(CloudAuthConfig config) async =>
      const CloudTokens(accessToken: 'token');
  @override
  Future<CloudTokens> refresh(CloudAuthConfig config, String token) async =>
      const CloudTokens(accessToken: 'token');
}

const userA = 'aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa';
const userB = 'bbbbbbbb-bbbb-4bbb-8bbb-bbbbbbbbbbbb';
const homeA = '11111111-1111-4111-8111-111111111111';
const homeB = '22222222-2222-4222-8222-222222222222';
const applianceId = '33333333-3333-4333-8333-333333333333';
const draft = OnboardingDraft(
  name: 'Fridge',
  category: 'refrigerator',
  brand: 'Acme',
  fullModel: 'A123',
  fuel: 'electricity',
);

class MemoryStorage implements OnboardingDraftStorage {
  String? value;
  bool failWrite = false;
  @override
  Future<String?> read() async => value;
  @override
  Future<void> write(String data) async {
    if (failWrite) throw StateError('storage unavailable');
    value = data;
  }

  @override
  Future<void> clear() async => value = null;
}

class Source implements OnboardingPersistenceSource {
  int creates = 0;
  final List<String> keys = [];
  CloudApplianceCreate? lastInput;
  bool uncertain = false;
  bool omitFromInventory = false;
  CloudAppliance row(String home) => CloudAppliance(
    id: applianceId,
    homeId: home,
    name: 'Fridge',
    category: 'refrigerator',
    room: null,
    brand: 'Acme',
    fullModel: 'A123',
    fuel: 'electricity',
    matchQuality: 'unresolved',
    fccId: lastInput?.fccId,
    icId: lastInput?.icId,
    serialNumber: lastInput?.serialNumber,
    upc: lastInput?.upc,
  );
  @override
  Future<CloudAppliance> create(
    String home,
    CloudApplianceCreate input,
    String key,
  ) async {
    creates++;
    keys.add(key);
    lastInput = input;
    if (uncertain) {
      uncertain = false;
      throw StateError('response lost');
    }
    return row(home);
  }

  @override
  Future<CloudAppliance> detail(String home, String id) async => row(home);
  @override
  Future<List<CloudAppliance>> inventory(String home) async =>
      omitFromInventory ? [] : [row(home)];
  @override
  Future<String> version(String home, String id) async => '"1"';
  @override
  Future<void> archive(String home, String id, String etag, String key) async {}
}

DurableOnboardingDrafts manager(MemoryStorage storage, Source source) =>
    DurableOnboardingDrafts(storage, OnboardingPersistenceRepository(source));

void main() {
  test(
    'lost home POST response resumes with persisted key and owner readback',
    () async {
      const key = '11111111-1111-4111-8111-111111111111';
      final storage = MemoryStorage();
      final seenKeys = <String?>[];
      var lost = true;
      final api = CloudApiClient(
        session: CloudSession(
          config: const CloudAuthConfig(
            issuer: 'https://issuer.example',
            audience: 'cloud',
            clientId: 'client',
            redirectUrl: 'io.energylens.app://login-callback',
            apiUrl: 'https://api.example',
          ),
          store: _TokenStore(),
          authenticator: _Auth(),
        ),
        client: MockClient((request) async {
          if (request.method == 'POST') {
            seenKeys.add(request.headers['Idempotency-Key']);
            if (lost) {
              lost = false;
              throw StateError('response lost');
            }
          }
          final row = {
            'id': homeA,
            'name': 'Home',
            'timezone': 'America/Chicago',
            'location': {'country_code': 'US', 'postal_code': '60601'},
          };
          return http.Response(
            jsonEncode(
              request.method == 'GET'
                  ? {
                      'homes': [row],
                    }
                  : row,
            ),
            200,
          );
        }),
      );
      final input = CloudHomeCreate.validate(
        name: 'Home',
        timezone: 'America/Chicago',
        countryCode: 'US',
        postalCode: '60601',
      )!;
      final first = DurableHomeCreateDrafts(storage, api);
      await first.selectScope(
        'https://api.example',
        'username_password',
        userA,
      );
      await expectLater(first.stageAndCommit(input, key), throwsStateError);
      final resumed = DurableHomeCreateDrafts(storage, api);
      await resumed.selectScope(
        'https://api.example',
        'username_password',
        userA,
      );
      expect((await resumed.restoreAndCommit())?.id, homeA);
      expect(seenKeys, [key, key]);
      expect(storage.value, isNull);
      api.close();
    },
  );

  test(
    'restart and uncertain response reuse key then clear after readback',
    () async {
      final storage = MemoryStorage();
      final source = Source()..uncertain = true;
      final first = manager(storage, source);
      await first.selectScope(userA, homeA);
      await expectLater(first.save(draft), throwsStateError);
      final key = (await first.restore())!.operationKey;
      final restarted = manager(storage, source);
      await restarted.selectScope(userA, homeA);
      expect((await restarted.restore())!.operationKey, key);
      expect((await restarted.save(draft))?.id, applianceId);
      expect(source.keys, [key, key]);
      expect(await restarted.restore(), isNull);
    },
  );
  test('duplicate stage retains key, edit allocates new key, duplicate save coalesces', () async {
    final storage = MemoryStorage();
    final source = Source();
    final store = manager(storage, source);
    await store.selectScope(userA, homeA);
    final first = await store.stage(draft);
    expect((await store.stage(draft)).operationKey, first.operationKey);
    final changed = await store.stage(
      const OnboardingDraft(
        name: 'Second',
        category: 'refrigerator',
        brand: 'Acme',
        fullModel: 'A123',
        fuel: 'electricity',
      ),
    );
    expect(changed.operationKey, isNot(first.operationKey));
    await Future.wait([store.save(draft), store.save(draft)]);
    expect(source.creates, 1);
  });
  test(
    'missing inventory readback keeps draft and retry key after restart',
    () async {
      final storage = MemoryStorage();
      final source = Source()..omitFromInventory = true;
      final first = manager(storage, source);
      await first.selectScope(userA, homeA);
      final pending = await first.stage(draft);
      await expectLater(
        first.commit(pending, explicitlyApproved: true),
        throwsFormatException,
      );
      expect((await first.restore())!.operationKey, pending.operationKey);

      source.omitFromInventory = false;
      final restarted = manager(storage, source);
      await restarted.selectScope(userA, homeA);
      final restored = (await restarted.restore())!;
      expect(restored.operationKey, pending.operationKey);
      expect(
        (await restarted.commit(restored, explicitlyApproved: true))?.id,
        applianceId,
      );
      expect(source.keys, [pending.operationKey, pending.operationKey]);
      expect(await restarted.restore(), isNull);
    },
  );
  test('exact draft identity controls key reuse and explicit commit', () async {
    final source = Source();
    final store = manager(MemoryStorage(), source);
    await store.selectScope(userA, homeA);
    final first = await store.stage(draft);
    final whitespaceEdit = const OnboardingDraft(
      name: ' Fridge ',
      category: 'refrigerator',
      brand: 'Acme',
      fullModel: 'A123',
      fuel: 'electricity',
    );
    final second = await store.stage(whitespaceEdit);
    expect(second.operationKey, isNot(first.operationKey));
    await expectLater(
      store.commit(first, explicitlyApproved: true),
      throwsStateError,
    );
    expect(source.creates, 0);
    expect((await store.restore())!.operationKey, second.operationKey);
  });
  test('corrupt, unknown version and invalid key are discarded', () async {
    final storage = MemoryStorage();
    final store = manager(storage, Source());
    await store.selectScope(userA, homeA);
    for (final bad in [
      '{',
      '{"version":2}',
      jsonEncode({
        'version': 1,
        'user_id': userA,
        'home_id': homeA,
        'operation_key': 'bad',
        'draft': {'name': 'Fridge'},
      }),
    ]) {
      storage.value = bad;
      expect(await store.restore(), isNull);
      expect(storage.value, isNull);
    }
  });
  test('account, home and sign-out transitions clear draft', () async {
    final storage = MemoryStorage();
    final store = manager(storage, Source());
    await store.selectScope(userA, homeA);
    await store.stage(draft);
    await store.selectScope(userA, homeB);
    expect(await store.restore(), isNull);
    await store.stage(draft);
    await store.selectScope(userB, homeB);
    expect(await store.restore(), isNull);
    await store.stage(draft);
    await store.selectScope(null, null);
    expect(storage.value, isNull);
  });
  test(
    'fresh process with another account cannot restore prior draft',
    () async {
      final storage = MemoryStorage();
      final first = manager(storage, Source());
      await first.selectScope(userA, homeA);
      await first.stage(draft);
      final second = manager(storage, Source());
      await second.selectScope(userB, homeA);
      expect(await second.restore(), isNull);
      expect(storage.value, isNull);
    },
  );
  test(
    'failed persistence blocks create and manual restore remains unresolved',
    () async {
      final storage = MemoryStorage()..failWrite = true;
      final source = Source();
      final store = manager(storage, source);
      await store.selectScope(userA, homeA);
      await expectLater(store.save(draft), throwsStateError);
      expect(source.creates, 0);
      storage.failWrite = false;
      await store.stage(draft);
      final restarted = manager(storage, Source());
      await restarted.selectScope(userA, homeA);
      expect(
        (await restarted.restore())!.draft.validated().matchQuality,
        'unresolved',
      );
      expect(storage.value, isNot(contains('confirmed_exact')));
    },
  );

  test('reviewed catalog match quality survives staging and restart', () async {
    final storage = MemoryStorage();
    final first = manager(storage, Source());
    await first.selectScope(userA, homeA);
    await first.stage(
      const OnboardingDraft(
        name: 'Fridge',
        category: 'refrigerator',
        brand: 'Edited brand',
        fullModel: 'Edited model',
        fuel: 'electricity',
        reviewedProduct: CloudCatalogProduct(
          id: applianceId,
          category: 'water_heater',
          brand: 'Catalog brand',
          fullModel: 'Catalog model',
          variant: null,
          region: null,
          fuel: 'electricity',
          matchQuality: 'documented_variant_family',
          facts: [],
        ),
      ),
    );
    final restarted = manager(storage, Source());
    await restarted.selectScope(userA, homeA);
    final restored = (await restarted.restore())!.draft.validated();
    expect(restored.brand, 'Edited brand');
    expect(restored.fullModel, 'Edited model');
    expect(restored.catalogProductId, applianceId);
    expect(restored.matchQuality, 'documented_variant_family');

    final legacy = jsonDecode(storage.value!) as Map<String, dynamic>;
    final fields = legacy['draft'] as Map<String, dynamic>;
    (fields['reviewed_catalog'] as Map<String, dynamic>).remove(
      'match_quality',
    );
    storage.value = jsonEncode(legacy);
    final legacyReader = manager(storage, Source());
    await legacyReader.selectScope(userA, homeA);
    expect(
      (await legacyReader.restore())!.draft.validated().matchQuality,
      'confirmed_exact',
    );
  });

  test(
    'edited scan identifiers survive restart, uncertain save and retry',
    () async {
      final storage = MemoryStorage();
      final source = Source()..uncertain = true;
      final first = manager(storage, source);
      await first.selectScope(userA, homeA);
      const scanned = OnboardingDraft(
        name: 'Fridge',
        category: 'refrigerator',
        brand: 'Acme',
        fullModel: 'A123',
        fuel: 'electricity',
        serialNumber: 'ORIGINAL123',
        fccId: 'A3LWRF555',
        icId: '649E-WRF555',
        upc: '012345678905',
      );
      const edited = OnboardingDraft(
        name: 'Fridge',
        category: 'refrigerator',
        brand: 'Acme',
        fullModel: 'A123',
        fuel: 'electricity',
        serialNumber: 'CORRECTED123',
        fccId: 'A3LWRF555',
        icId: '649E-WRF555',
        upc: '012345678905',
      );
      final scannedKey = (await first.stage(scanned)).operationKey;
      final pending = await first.stage(edited);
      expect(pending.operationKey, isNot(scannedKey));
      await expectLater(
        first.commit(pending, explicitlyApproved: true),
        throwsStateError,
      );

      final restarted = manager(storage, source);
      await restarted.selectScope(userA, homeA);
      final restored = (await restarted.restore())!;
      expect(restored.operationKey, pending.operationKey);
      expect(restored.draft.serialNumber, 'CORRECTED123');
      expect(restored.draft.fccId, 'A3LWRF555');
      expect(restored.draft.icId, '649E-WRF555');
      expect(restored.draft.upc, '012345678905');
      expect(
        (await restarted.commit(restored, explicitlyApproved: true))?.id,
        applianceId,
      );
      expect(source.keys, [pending.operationKey, pending.operationKey]);
      final identity =
          source.lastInput!.toJson()['identity'] as Map<String, dynamic>;
      expect(identity['serial_number'], 'CORRECTED123');
      expect(identity['fcc_id'], 'A3LWRF555');
      expect(identity['ic_id'], '649E-WRF555');
      expect(identity['upc'], '012345678905');
      expect(await restarted.restore(), isNull);
    },
  );

  test(
    'older draft without optional scan identifiers still restores',
    () async {
      final storage = MemoryStorage();
      final first = manager(storage, Source());
      await first.selectScope(userA, homeA);
      await first.stage(draft);
      final legacy = jsonDecode(storage.value!) as Map<String, dynamic>;
      final fields = legacy['draft'] as Map<String, dynamic>;
      expect(fields.keys, isNot(contains('serial_number')));
      storage.value = jsonEncode(legacy);
      final restarted = manager(storage, Source());
      await restarted.selectScope(userA, homeA);
      final restored = (await restarted.restore())!.draft;
      expect(restored.serialNumber, isNull);
      expect(restored.fccId, isNull);
      expect(restored.icId, isNull);
      expect(restored.upc, isNull);
    },
  );
}
