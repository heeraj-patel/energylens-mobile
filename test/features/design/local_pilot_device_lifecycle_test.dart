import 'dart:async';

import 'package:energylens_mobile/features/design/local_pilot_device_lifecycle.dart';
import 'package:energylens_mobile/features/discovery/discovery_api.dart';
import 'package:energylens_mobile/features/discovery/discovery_credentials.dart';
import 'package:flutter_test/flutter_test.dart';

class _Store implements SecureKeyValueStore {
  final values = <String, String>{};
  @override
  Future<String?> read(String key) async => values[key];
  @override
  Future<void> write(String key, String value) async => values[key] = value;
  @override
  Future<void> delete(String key) async {
    values.remove(key);
  }
}

SavedAppliance _row(int id, ApplianceInput input) => SavedAppliance(
  id: id,
  name: input.name,
  room: input.room,
  category: input.category,
  manufacturer: input.manufacturer,
  model: input.model,
  loadKind: input.loadKind,
  onboardingMethod: input.onboardingMethod,
);

const _input = ApplianceInput(
  name: 'Kitchen Refrigerator',
  room: '',
  category: 'refrigerator',
  manufacturer: '',
  model: '',
  loadKind: 'appliance',
  onboardingMethod: 'manual',
);

class _Api extends DiscoveryApi {
  final rows = <SavedAppliance>[];
  int posts = 0;
  int deletes = 0;
  bool failList = false;
  bool timeoutAfterCreate = false;
  bool failDelete = false;
  Completer<SavedAppliance>? heldPost;

  @override
  Future<void> verifyStoredPairing(StoredHubIdentity pairing) async {}

  @override
  Future<List<SavedAppliance>> appliances(String baseUrl, String token) async {
    if (failList) throw StateError('offline');
    return List.of(rows);
  }

  @override
  Future<SavedAppliance> addAppliance(
    String baseUrl,
    String token,
    ApplianceInput input,
  ) async {
    posts++;
    if (heldPost case final pending?) return pending.future;
    final row = _row(posts, input);
    rows.add(row);
    if (timeoutAfterCreate) throw TimeoutException('lost response');
    return row;
  }

  @override
  Future<void> deleteManualAppliance(
    String baseUrl,
    String token,
    int applianceId,
  ) async {
    deletes++;
    if (failDelete) throw StateError('attachment history');
    rows.removeWhere((row) => row.id == applianceId);
  }
}

void main() {
  late _Store store;
  late _Api api;
  late DiscoveryCredentials credentials;
  late LocalPilotDeviceLifecycle lifecycle;

  setUp(() {
    store = _Store();
    api = _Api();
    credentials = DiscoveryCredentials(storage: store);
    lifecycle = LocalPilotDeviceLifecycle(api: api, credentials: credentials);
  });

  Future<void> connect() =>
      credentials.save('https://127.0.0.1:18787', 'local-token');

  test('missing credential and failed read do not create inventory', () async {
    expect(await lifecycle.inventory(), isNull);
    await connect();
    api.failList = true;
    expect(await lifecycle.inventory(), isNull);
  });

  test(
    'create is confirmed only by matching ID and identity in readback',
    () async {
      await connect();
      final before = (await lifecycle.inventory())!;
      final session = (await lifecycle.beginSave(before))!;
      final result = await lifecycle.save(session, _input);
      expect(result.status, LocalWriteStatus.confirmed);
      expect(result.appliance?.id, 1);
      expect(api.posts, 1);
      expect((await lifecycle.inventory())?.rows.single.id, 1);
    },
  );

  test('lost response reconciles once and retry never posts twice', () async {
    await connect();
    api.timeoutAfterCreate = true;
    final session = (await lifecycle.beginSave(
      (await lifecycle.inventory())!,
    ))!;
    expect(
      (await lifecycle.save(session, _input)).status,
      LocalWriteStatus.confirmed,
    );
    expect(
      (await lifecycle.save(session, _input)).status,
      LocalWriteStatus.confirmed,
    );
    expect(api.posts, 1);
  });

  test(
    'unresolved readback permits reconciliation without another POST',
    () async {
      await connect();
      api.timeoutAfterCreate = true;
      final session = (await lifecycle.beginSave(
        (await lifecycle.inventory())!,
      ))!;
      api.failList = true;
      expect(
        (await lifecycle.save(session, _input)).status,
        LocalWriteStatus.unresolved,
      );
      api.failList = false;
      expect(
        (await lifecycle.save(session, _input)).status,
        LocalWriteStatus.confirmed,
      );
      expect(api.posts, 1);
    },
  );

  test('concurrent duplicate save has one POST', () async {
    await connect();
    final session = (await lifecycle.beginSave(
      (await lifecycle.inventory())!,
    ))!;
    api.heldPost = Completer<SavedAppliance>();
    final first = lifecycle.save(session, _input);
    final second = lifecycle.save(session, _input);
    expect((await second).status, LocalWriteStatus.unresolved);
    await Future<void>.delayed(Duration.zero);
    expect(api.posts, 1);
    api.rows.add(_row(1, _input));
    api.heldPost!.complete(api.rows.single);
    expect((await first).status, LocalWriteStatus.confirmed);
  });

  test(
    'changed credential invalidates prior inventory and late write',
    () async {
      await connect();
      final before = (await lifecycle.inventory())!;
      final session = (await lifecycle.beginSave(before))!;
      await credentials.save('https://127.0.0.1:18788', 'other-token');
      expect(await lifecycle.beginSave(before), isNull);
      expect(
        (await lifecycle.save(session, _input)).status,
        LocalWriteStatus.failed,
      );
      expect(api.posts, 0);
    },
  );

  test('delete needs readback and retains rejected row', () async {
    await connect();
    api.rows.add(_row(7, _input));
    final before = (await lifecycle.inventory())!;
    api.failDelete = true;
    final rejected = await lifecycle.delete(before, 7);
    expect(rejected.status, LocalWriteStatus.failed);
    expect(rejected.inventory?.rows.single.id, 7);
    api.failDelete = false;
    final confirmed = await lifecycle.delete(before, 7);
    expect(confirmed.status, LocalWriteStatus.confirmed);
    expect(confirmed.inventory?.rows, isEmpty);
  });

  test('stored pairing uses Hub identity and credential rotation', () async {
    await credentials.savePairing(
      address: 'https://127.0.0.1:18787#sha256=${'a' * 64}',
      hubId: 'hub-one',
      clientId: 'client-one',
      token: 'token-one',
    );
    final first = (await lifecycle.inventory())!;
    expect(first.identity, contains('hub-one'));
    await credentials.savePairing(
      address: 'https://127.0.0.1:18787#sha256=${'a' * 64}',
      hubId: 'hub-two',
      clientId: 'client-two',
      token: 'token-two',
    );
    expect((await lifecycle.inventory())!.identity, isNot(first.identity));
  });
}
