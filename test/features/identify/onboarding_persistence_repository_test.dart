import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:energylens_mobile/core/cloud_api/cloud_appliance.dart';
import 'package:energylens_mobile/core/cloud_api/cloud_catalog.dart';
import 'package:energylens_mobile/features/identify/onboarding_persistence_repository.dart';

const homeA = '11111111-1111-4111-8111-111111111111';
const homeB = '22222222-2222-4222-8222-222222222222';
const applianceId = '33333333-3333-4333-8333-333333333333';
const key = '44444444-4444-4444-8444-444444444444';
const archiveKey = '55555555-5555-4555-8555-555555555555';

CloudAppliance appliance(String home, {String name = 'Fridge'}) =>
    CloudAppliance(
      id: applianceId,
      homeId: home,
      name: name,
      category: 'refrigerator',
      room: null,
      brand: 'Acme',
      fullModel: 'A123',
      fuel: 'electricity',
      matchQuality: 'unresolved',
    );

const draft = OnboardingDraft(
  name: 'Fridge',
  category: 'refrigerator',
  brand: 'Acme',
  fullModel: 'A123',
  fuel: 'electricity',
);

class FakeSource implements OnboardingPersistenceSource {
  int creates = 0;
  int details = 0;
  int inventories = 0;
  int archives = 0;
  bool uncertainCreate = false;
  bool failDetail = false;
  bool uncertainArchive = false;
  bool archived = false;
  CloudApplianceCreate? input;
  String? receivedKey;
  String? archiveEtag;
  Future<CloudAppliance> Function(String)? createWait;
  Future<List<CloudAppliance>> Function(String)? inventoryRead;

  @override
  Future<CloudAppliance> create(
    String home,
    CloudApplianceCreate value,
    String operationKey,
  ) async {
    creates++;
    input = value;
    receivedKey = operationKey;
    if (createWait case final wait?) return wait(home);
    if (uncertainCreate) {
      uncertainCreate = false;
      throw StateError('response lost');
    }
    return appliance(home);
  }

  @override
  Future<CloudAppliance> detail(String home, String id) async {
    details++;
    if (failDetail) {
      failDetail = false;
      throw StateError('read failed');
    }
    return appliance(home);
  }

  @override
  Future<List<CloudAppliance>> inventory(String home) async {
    inventories++;
    if (inventoryRead case final read?) return read(home);
    return archived ? [] : [appliance(home)];
  }

  @override
  Future<String> version(String home, String id) async => '"1"';
  @override
  Future<void> archive(
    String home,
    String id,
    String etag,
    String operationKey,
  ) async {
    archives++;
    archiveEtag = etag;
    archived = true;
    if (uncertainArchive) {
      uncertainArchive = false;
      throw StateError('response lost');
    }
  }
}

void main() {
  test('manual draft is unresolved; uncertain create retries same key and reads back', () async {
    final source = FakeSource()..uncertainCreate = true;
    final repository = OnboardingPersistenceRepository(source)
      ..selectHome(homeA);
    await expectLater(
      repository.save(draft, operationKey: key),
      throwsStateError,
    );
    expect(repository.activeInventory, isNull);
    final saved = await repository.save(draft, operationKey: key);
    expect(saved?.id, applianceId);
    expect(source.creates, 2);
    expect(source.receivedKey, key);
    expect(source.input!.toJson()['identity']['match_quality'], 'unresolved');
    expect(source.details, 1);
    expect(repository.activeInventory?.single.id, applianceId);
  });

  test('detail failure retries readback without another create; duplicate tap shares request', () async {
    final source = FakeSource()..failDetail = true;
    final repository = OnboardingPersistenceRepository(source)
      ..selectHome(homeA);
    await expectLater(
      repository.save(draft, operationKey: key),
      throwsStateError,
    );
    final pending = Completer<CloudAppliance>();
    // A fresh operation models two taps while the POST is in flight.
    final secondSource = FakeSource()..createWait = (_) => pending.future;
    final second = OnboardingPersistenceRepository(secondSource)
      ..selectHome(homeA);
    final firstTap = second.save(draft, operationKey: key);
    final secondTap = second.save(draft, operationKey: key);
    expect(identical(firstTap, secondTap), isTrue);
    pending.complete(appliance(homeA));
    await firstTap;
    expect(secondSource.creates, 1);
    expect((await repository.save(draft, operationKey: key))?.id, applianceId);
    expect(source.creates, 1);
    expect(source.details, 2);
  });

  test('invalid or changed draft never sends a mutation', () async {
    final source = FakeSource();
    final repository = OnboardingPersistenceRepository(source)
      ..selectHome(homeA);
    expect(
      () => repository.save(
        const OnboardingDraft(
          name: ' ',
          category: 'refrigerator',
          brand: 'Acme',
          fullModel: 'A123',
          fuel: 'electricity',
        ),
        operationKey: key,
      ),
      throwsArgumentError,
    );
    await repository.save(draft, operationKey: key);
    expect(
      () => repository.save(
        const OnboardingDraft(
          name: 'Other',
          category: 'refrigerator',
          brand: 'Acme',
          fullModel: 'A123',
          fuel: 'electricity',
        ),
        operationKey: key,
      ),
      throwsStateError,
    );
    expect(source.creates, 1);
  });

  test('only an exact reviewed catalog product can mark a draft exact', () {
    const family = CloudCatalogProduct(
      id: applianceId,
      category: 'refrigerator',
      brand: 'Acme',
      fullModel: 'A123',
      variant: null,
      region: null,
      fuel: 'electricity',
      matchQuality: 'documented_variant_family',
      facts: [],
    );
    const exact = CloudCatalogProduct(
      id: applianceId,
      category: 'refrigerator',
      brand: 'Acme',
      fullModel: 'A123',
      variant: null,
      region: null,
      fuel: 'electricity',
      matchQuality: 'confirmed_exact',
      facts: [],
    );
    expect(
      () => const OnboardingDraft(
        name: 'Fridge',
        category: 'refrigerator',
        brand: 'Acme',
        fullModel: 'A123',
        fuel: 'electricity',
        reviewedProduct: family,
      ).validated(),
      throwsArgumentError,
    );
    final identity =
        const OnboardingDraft(
              name: 'Fridge',
              category: 'refrigerator',
              brand: 'Acme',
              fullModel: 'A123',
              fuel: 'electricity',
              reviewedProduct: exact,
            ).validated().toJson()['identity']
            as Map<String, dynamic>;
    expect(identity['match_quality'], 'confirmed_exact');
    expect(identity['catalog_product_id'], applianceId);
  });

  test(
    'archive retries same version and key, then verifies active inventory',
    () async {
      final source = FakeSource()..uncertainArchive = true;
      final repository = OnboardingPersistenceRepository(source)
        ..selectHome(homeA);
      await repository.refresh();
      await expectLater(
        repository.archive(applianceId, operationKey: archiveKey),
        throwsStateError,
      );
      expect(repository.activeInventory, isNotNull);
      expect(
        await repository.archive(applianceId, operationKey: archiveKey),
        isTrue,
      );
      expect(source.archives, 2);
      expect(source.archiveEtag, '"1"');
      expect(repository.activeInventory, isEmpty);
    },
  );

  test('switching homes discards stale save and inventory responses', () async {
    final pending = Completer<CloudAppliance>();
    final source = FakeSource()..createWait = (_) => pending.future;
    final repository = OnboardingPersistenceRepository(source)
      ..selectHome(homeA);
    final saving = repository.save(draft, operationKey: key);
    repository.selectHome(homeB);
    pending.complete(appliance(homeA));
    expect(await saving, isNull);
    expect(source.details, 0);
    expect(repository.activeInventory, isNull);

    final oldRead = Completer<List<CloudAppliance>>();
    source.inventoryRead = (_) => oldRead.future;
    final reading = repository.refresh();
    repository.selectHome(homeA);
    oldRead.complete([appliance(homeB)]);
    expect(await reading, isNull);
    expect(repository.activeInventory, isNull);
  });
}
