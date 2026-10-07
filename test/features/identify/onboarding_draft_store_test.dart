import 'dart:convert';

import 'package:energylens_mobile/core/cloud_api/cloud_appliance.dart';
import 'package:energylens_mobile/features/identify/onboarding_draft_store.dart';
import 'package:energylens_mobile/features/identify/onboarding_persistence_repository.dart';
import 'package:flutter_test/flutter_test.dart';

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
  bool uncertain = false;
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
  );
  @override
  Future<CloudAppliance> create(
    String home,
    CloudApplianceCreate input,
    String key,
  ) async {
    creates++;
    keys.add(key);
    if (uncertain) {
      uncertain = false;
      throw StateError('response lost');
    }
    return row(home);
  }

  @override
  Future<CloudAppliance> detail(String home, String id) async => row(home);
  @override
  Future<List<CloudAppliance>> inventory(String home) async => [row(home)];
  @override
  Future<String> version(String home, String id) async => '"1"';
  @override
  Future<void> archive(String home, String id, String etag, String key) async {}
}

DurableOnboardingDrafts manager(MemoryStorage storage, Source source) =>
    DurableOnboardingDrafts(storage, OnboardingPersistenceRepository(source));

void main() {
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
}
