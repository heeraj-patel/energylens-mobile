import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:energylens_mobile/features/design/local_pilot_device_lifecycle.dart';
import 'package:energylens_mobile/features/discovery/device_data_refresh.dart';
import 'package:energylens_mobile/features/discovery/discovery_api.dart';
import 'package:energylens_mobile/features/discovery/discovery_credentials.dart';

class _Store implements SecureKeyValueStore {
  final values = <String, String>{};
  @override
  Future<String?> read(String key) async => values[key];
  @override
  Future<void> write(String key, String value) async => values[key] = value;
  @override
  Future<void> delete(String key) async => values.remove(key);
}

class _Lifecycle extends LocalPilotDeviceLifecycle {
  _Lifecycle({required super.api, required super.credentials});
  String? identity = 'local-identity';
  @override
  Future<String?> currentIdentity() async => identity;
}

class _Api extends DiscoveryApi {
  bool v2 = true;
  String scanState = 'complete';
  bool failRefresh = false;
  int scans = 0;
  int v2Refreshes = 0;
  int legacyRefreshes = 0;
  int adoptions = 0;
  int v2InventoryReads = 0;
  int savedReads = 0;
  Completer<void>? scanStarted;
  Completer<void>? scanBarrier;
  List<NearbySavedDevice> devices = const [];
  List<SavedPlug> plugs = const [];

  @override
  Future<bool> supportsNearbyDiscovery(String address, String token) async =>
      v2;
  @override
  Future<NearbyScan> startNearbyScan(String address, String token) async {
    scans++;
    scanStarted?.complete();
    await scanBarrier?.future;
    return NearbyScan(id: 'scan', state: scanState, expiresAtMs: 9999999999999);
  }

  @override
  Future<List<DiscoveredPlug>> scan(String address, String token) async {
    scans++;
    return const [];
  }

  @override
  Future<List<NearbySavedDevice>> nearbyInventory(
    String address,
    String token,
  ) async {
    v2InventoryReads++;
    return devices;
  }

  @override
  Future<List<SavedPlug>> saved(String address, String token) async {
    savedReads++;
    return plugs;
  }

  @override
  Future<NearbySavedDevice> refreshNearbyDevice(
    String address,
    String token,
    String id,
  ) async {
    v2Refreshes++;
    if (failRefresh) throw StateError('unreachable');
    return devices.singleWhere((device) => device.id == id);
  }

  @override
  Future<SavedPlug> refreshPlugStatus(
    String address,
    String token,
    String id,
  ) async {
    legacyRefreshes++;
    if (failRefresh) throw StateError('unreachable');
    return plugs.singleWhere((plug) => plug.id == id);
  }

  @override
  Future<NearbySavedDevice> adoptNearby(
    String address,
    String token,
    NearbyDeviceCandidate candidate,
    String name,
  ) async {
    adoptions++;
    throw StateError('Unexpected adoption');
  }
}

void main() {
  const address = 'https://192.168.1.2:18787';
  late _Store store;
  late DiscoveryCredentials credentials;
  late _Api api;
  late _Lifecycle lifecycle;
  late DateTime now;
  DeviceDataRefresh coordinator() => DeviceDataRefresh(
    api: api,
    credentials: credentials,
    clock: () => now,
    delay: (_) async {},
  );

  setUp(() async {
    store = _Store();
    credentials = DiscoveryCredentials(storage: store);
    await credentials.save(address, 'token');
    api = _Api();
    lifecycle = _Lifecycle(api: api, credentials: credentials);
    now = DateTime.utc(2026, 10, 20, 12);
  });

  test('durable marker skips 59 and 60 seconds, refreshes after 61', () async {
    expect(
      await coordinator().refreshLocal(
        lifecycle: lifecycle,
        isCurrent: () => true,
      ),
      isTrue,
    );
    expect(api.scans, 1);
    now = now.add(const Duration(seconds: 59));
    expect(
      await coordinator().refreshLocal(
        lifecycle: lifecycle,
        isCurrent: () => true,
      ),
      isFalse,
    );
    now = now.add(const Duration(seconds: 1));
    expect(
      await coordinator().refreshLocal(
        lifecycle: lifecycle,
        isCurrent: () => true,
      ),
      isFalse,
    );
    now = now.add(const Duration(seconds: 1));
    expect(
      await coordinator().refreshLocal(
        lifecycle: lifecycle,
        isCurrent: () => true,
      ),
      isTrue,
    );
    expect(api.scans, 2);
  });

  test('malformed and future marker are stale', () async {
    await coordinator().refreshLocal(
      lifecycle: lifecycle,
      isCurrent: () => true,
    );
    final key = store.values.keys.singleWhere(
      (key) => key.contains('device_refresh'),
    );
    store.values[key] = 'broken';
    await coordinator().refreshLocal(
      lifecycle: lifecycle,
      isCurrent: () => true,
    );
    expect(api.scans, 2);
    store.values[key] = '{"version":1,"completed_at_ms":9999999999999}';
    await coordinator().refreshLocal(
      lifecycle: lifecycle,
      isCurrent: () => true,
    );
    expect(api.scans, 3);
  });

  test('failed scan or device leaves marker due and never adopts', () async {
    api.scanState = 'partial';
    await coordinator().refreshLocal(
      lifecycle: lifecycle,
      isCurrent: () => true,
    );
    api.scanState = 'complete';
    api.devices = const [
      NearbySavedDevice(
        'tv',
        'TV',
        bindings: [
          NearbyDeviceBinding('binding', 'upnp', 'upnp-local', 'local', 'tv'),
        ],
      ),
    ];
    api.failRefresh = true;
    await coordinator().refreshLocal(
      lifecycle: lifecycle,
      isCurrent: () => true,
    );
    api.failRefresh = false;
    await coordinator().refreshLocal(
      lifecycle: lifecycle,
      isCurrent: () => true,
    );
    expect(api.scans, 3);
    expect(api.v2Refreshes, 2);
    expect(api.adoptions, 0);
  });

  test(
    'partial scan still refreshes saved devices without marking fresh',
    () async {
      api.scanState = 'partial';
      api.devices = const [
        NearbySavedDevice(
          'tv',
          'TV',
          bindings: [
            NearbyDeviceBinding('binding', 'upnp', 'upnp-local', 'local', 'tv'),
          ],
        ),
      ];
      await coordinator().refreshLocal(
        lifecycle: lifecycle,
        isCurrent: () => true,
      );
      expect(api.v2Refreshes, 1);
      expect(api.v2InventoryReads, 2);
      expect(api.savedReads, 2);
      expect(
        store.values.keys.where((key) => key.contains('device_refresh')),
        isEmpty,
      );
      await coordinator().refreshLocal(
        lifecycle: lifecycle,
        isCurrent: () => true,
      );
      expect(api.v2Refreshes, 2);
    },
  );

  test('pairing change during discovery stops old-Hub requests', () async {
    api.scanStarted = Completer<void>();
    api.scanBarrier = Completer<void>();
    api.devices = const [
      NearbySavedDevice(
        'tv',
        'TV',
        bindings: [
          NearbyDeviceBinding('binding', 'upnp', 'upnp-local', 'local', 'tv'),
        ],
      ),
    ];
    final refresh = coordinator().refreshLocal(
      lifecycle: lifecycle,
      isCurrent: () => true,
    );
    await api.scanStarted!.future;
    await credentials.save(address, 'replacement-token');
    api.scanBarrier!.complete();
    await refresh;
    expect(api.v2InventoryReads, 0);
    expect(api.v2Refreshes, 0);
    expect(api.savedReads, 0);
    expect(
      store.values.keys.where((key) => key.contains('device_refresh')),
      isEmpty,
    );
  });

  test('legacy Kasa status refresh and scope invalidation', () async {
    api.v2 = false;
    api.plugs = const [
      SavedPlug(
        id: 'plug',
        ip: '192.168.1.3',
        model: 'P110',
        name: 'Plug',
        room: '',
        meterStatus: 'supported',
        lastVerifiedAt: 1,
        localProtocol: 'legacy_tcp',
      ),
    ];
    await coordinator().refreshLocal(
      lifecycle: lifecycle,
      isCurrent: () => true,
    );
    expect(api.legacyRefreshes, 1);
    lifecycle.identity = 'changed';
    await credentials.save(address, 'new-token');
    await coordinator().refreshLocal(
      lifecycle: lifecycle,
      isCurrent: () => true,
    );
    expect(api.legacyRefreshes, 2);
  });
}
