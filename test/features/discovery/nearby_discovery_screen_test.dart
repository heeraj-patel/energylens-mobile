import 'dart:async';

import 'package:energylens_mobile/features/discovery/discovery_api.dart';
import 'package:energylens_mobile/features/discovery/discovery_credentials.dart';
import 'package:energylens_mobile/features/discovery/discovery_screen.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

class _Credentials extends DiscoveryCredentials {
  @override
  Future<StoredPairingCredential?> readPairing() async => null;

  @override
  Future<(String?, String?)> read() async =>
      ('https://192.168.1.20:8787', 'token');
}

class _Api extends DiscoveryApi {
  _Api(this.candidate, {this.state = 'complete'});

  final NearbyDeviceCandidate candidate;
  final String state;
  int adoptionCount = 0;
  int scanCount = 0;
  int probeCount = 0;
  bool expireFirstAdoption = false;
  bool failInventory = false;
  bool failScan = false;
  String? refreshedState;
  bool failInventoryAfterAdoption = false;
  List<NearbyDeviceCandidate>? refreshedCandidates;
  NearbySavedDevice? adoptedDevice;
  SavedPlug? legacyPlug;
  bool failFirstSavedAfterAdoption = false;
  int savedCallsAfterAdoption = 0;
  Completer<NearbyScan>? pendingStart;
  Completer<List<NearbySavedDevice>>? pendingInventory;
  Completer<NearbySavedDevice>? pendingAdoption;
  final cancelledScanIds = <String>[];
  List<NearbySavedDevice> inventory = const [];

  @override
  Future<List<SavedPlug>> saved(String baseUrl, String token) async {
    if (failFirstSavedAfterAdoption && adoptionCount == 0) return [];
    if (adoptionCount > 0) {
      savedCallsAfterAdoption++;
      if (failFirstSavedAfterAdoption && savedCallsAfterAdoption == 1) {
        throw StateError('offline');
      }
    }
    return legacyPlug == null ? [] : [legacyPlug!];
  }

  @override
  Future<List<SavedAppliance>> appliances(String baseUrl, String token) async =>
      [];

  @override
  Future<bool> supportsNearbyDiscovery(String baseUrl, String token) async =>
      true;

  @override
  Future<List<NearbySavedDevice>> nearbyInventory(
    String baseUrl,
    String token,
  ) async {
    if (failInventory || (failInventoryAfterAdoption && adoptionCount > 0)) {
      throw StateError('offline');
    }
    if (pendingInventory case final pending?) return pending.future;
    return inventory;
  }

  @override
  Future<NearbyScan> startNearbyScan(String baseUrl, String token) async {
    scanCount++;
    if (pendingStart case final pending?) return pending.future;
    if (failScan) throw StateError('offline');
    final candidates = scanCount > 1
        ? refreshedCandidates ?? [candidate]
        : [candidate];
    return NearbyScan(
      id: 'scan-$scanCount',
      state: scanCount > 1 ? refreshedState ?? state : state,
      expiresAtMs: candidates.firstOrNull?.expiresAtMs ?? 4102444800000,
      candidates: candidates,
    );
  }

  @override
  Future<NearbyScan> cancelNearbyScan(
    String baseUrl,
    String token,
    String scanId,
  ) async {
    cancelledScanIds.add(scanId);
    return NearbyScan(
      id: scanId,
      state: 'cancelled',
      expiresAtMs: 4102444800000,
    );
  }

  @override
  Future<NearbySavedDevice> adoptNearby(
    String baseUrl,
    String token,
    NearbyDeviceCandidate candidate,
    String name,
  ) async {
    adoptionCount++;
    if (expireFirstAdoption && adoptionCount == 1) {
      throw HubRequestException(409, 'candidate_expired', 'expired');
    }
    if (pendingAdoption case final pending?) return pending.future;
    if (adoptedDevice case final device?) {
      inventory = [device];
      return device;
    }
    inventory = [NearbySavedDevice('device', name)];
    return inventory.single;
  }

  @override
  Future<DiscoveredPlug> probe(
    String baseUrl,
    String token,
    String ipv4, {
    String protocol = 'kasa',
  }) async {
    probeCount++;
    return DiscoveredPlug(
      id: 'verified',
      ip: ipv4,
      model: 'Plug',
      meterStatus: 'absent',
      localProtocol: protocol,
    );
  }
}

void main() {
  NearbyDeviceCandidate candidate({
    String id = 'candidate',
    int expiresAtMs = 4102444800000,
    bool requiresAction = false,
    bool manual = false,
    bool alreadySaved = false,
    String? savedDeviceId,
    NearbyStableIdentity? stableIdentity,
  }) => NearbyDeviceCandidate(
    id: id,
    scanId: 'scan',
    expiresAtMs: expiresAtMs,
    requiresAction: requiresAction,
    alreadySaved: alreadySaved,
    savedDeviceId: savedDeviceId,
    stableIdentity: stableIdentity,
    addresses: [
      NearbyDeviceAddress(
        manual ? 'ipv4' : 'service_id',
        manual ? '192.168.1.30' : 'tv-id',
        null,
      ),
    ],
    sources: manual ? const ['shelly_gen2'] : const ['ssdp'],
    capabilities: const [NearbyDeviceCapability('energy', 'unknown')],
    model: 'Living room TV',
  );

  testWidgets('generic discovery shows a simple name and Add row', (
    tester,
  ) async {
    final api = _Api(candidate());
    await tester.pumpWidget(
      MaterialApp(
        home: DiscoveryScreen(api: api, credentials: _Credentials()),
      ),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.text('Scan for plugs'));
    await tester.pumpAndSettle();
    await tester.ensureVisible(find.text('Living room TV'));
    expect(find.text('Nearby devices'), findsOneWidget);
    expect(find.text('Living room TV'), findsOneWidget);
    expect(find.text('Add'), findsOneWidget);
    expect(find.textContaining('energy meter'), findsNothing);
    await tester.tap(find.text('Add'));
    await tester.pumpAndSettle();
    expect(api.adoptionCount, 1);
    expect(find.text('Add'), findsNothing);
  });

  testWidgets('rediscovered saved device has no Add action', (tester) async {
    final api = _Api(candidate(alreadySaved: true))
      ..inventory = const [NearbySavedDevice('device', 'Saved television')];
    await tester.pumpWidget(
      MaterialApp(
        home: DiscoveryScreen(api: api, credentials: _Credentials()),
      ),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.text('Scan for plugs'));
    await tester.pumpAndSettle();
    expect(find.text('Saved television'), findsOneWidget);
    expect(find.text('Living room TV'), findsOneWidget);
    expect(find.widgetWithText(TextButton, 'Add'), findsNothing);
    expect(api.adoptionCount, 0);
  });

  testWidgets('saved identity stays without Add if inventory refresh fails', (
    tester,
  ) async {
    final api = _Api(candidate(alreadySaved: true))..failInventory = true;
    await tester.pumpWidget(
      MaterialApp(
        home: DiscoveryScreen(api: api, credentials: _Credentials()),
      ),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.text('Scan for plugs'));
    await tester.pumpAndSettle();
    expect(find.text('Living room TV'), findsOneWidget);
    expect(find.widgetWithText(TextButton, 'Add'), findsNothing);
    expect(api.adoptionCount, 0);
  });

  testWidgets('expired candidate is re-resolved by exact identity once', (
    tester,
  ) async {
    const identity = NearbyStableIdentity('ssdp', 'uuid:tv-one');
    final api = _Api(
      candidate(expiresAtMs: 1, stableIdentity: identity),
    )..refreshedCandidates = [candidate(id: 'fresh', stableIdentity: identity)];
    await tester.pumpWidget(
      MaterialApp(
        home: DiscoveryScreen(api: api, credentials: _Credentials()),
      ),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.text('Scan for plugs'));
    await tester.pumpAndSettle();
    await tester.ensureVisible(find.text('Add'));
    await tester.tap(find.text('Add'));
    await tester.pumpAndSettle();
    expect(api.scanCount, 2);
    expect(api.adoptionCount, 1);
    expect(find.widgetWithText(TextButton, 'Add'), findsNothing);
  });

  testWidgets('server expiry race gets one verified refresh and retry', (
    tester,
  ) async {
    const identity = NearbyStableIdentity('ssdp', 'uuid:tv-one');
    final api = _Api(candidate(stableIdentity: identity))
      ..expireFirstAdoption = true
      ..refreshedCandidates = [
        candidate(id: 'fresh', stableIdentity: identity),
      ];
    await tester.pumpWidget(
      MaterialApp(
        home: DiscoveryScreen(api: api, credentials: _Credentials()),
      ),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.text('Scan for plugs'));
    await tester.pumpAndSettle();
    await tester.ensureVisible(find.text('Add'));
    await tester.tap(find.text('Add'));
    await tester.pumpAndSettle();
    expect(api.scanCount, 2);
    expect(api.adoptionCount, 2);
    expect(find.widgetWithText(TextButton, 'Add'), findsNothing);
  });

  testWidgets('ambiguous fresh identity never adopts a stale candidate', (
    tester,
  ) async {
    const identity = NearbyStableIdentity('ssdp', 'uuid:tv-one');
    final api = _Api(candidate(expiresAtMs: 1, stableIdentity: identity))
      ..refreshedCandidates = [
        candidate(id: 'fresh-one', stableIdentity: identity),
        candidate(id: 'fresh-two', stableIdentity: identity),
      ];
    await tester.pumpWidget(
      MaterialApp(
        home: DiscoveryScreen(api: api, credentials: _Credentials()),
      ),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.text('Scan for plugs'));
    await tester.pumpAndSettle();
    await tester.ensureVisible(find.text('Add'));
    await tester.tap(find.text('Add'));
    await tester.pumpAndSettle();
    expect(api.scanCount, 2);
    expect(api.adoptionCount, 0);
    expect(find.text('Search stopped. Try again.'), findsOneWidget);
  });

  for (final terminalState in ['partial', 'failed', 'cancelled']) {
    testWidgets('$terminalState refresh cannot authorize stale adoption', (
      tester,
    ) async {
      const identity = NearbyStableIdentity('ssdp', 'uuid:tv-one');
      final api = _Api(candidate(expiresAtMs: 1, stableIdentity: identity))
        ..refreshedState = terminalState
        ..refreshedCandidates = [
          candidate(id: 'fresh', stableIdentity: identity),
        ];
      await tester.pumpWidget(
        MaterialApp(
          home: DiscoveryScreen(api: api, credentials: _Credentials()),
        ),
      );
      await tester.pumpAndSettle();
      await tester.tap(find.text('Scan for plugs'));
      await tester.pumpAndSettle();
      await tester.ensureVisible(find.text('Add'));
      await tester.tap(find.text('Add'));
      await tester.pumpAndSettle();
      expect(api.adoptionCount, 0);
      expect(api.cancelledScanIds, contains('scan-2'));
    });
  }

  testWidgets('successful adoption stays saved when inventory GET fails', (
    tester,
  ) async {
    final api = _Api(candidate())..failInventoryAfterAdoption = true;
    await tester.pumpWidget(
      MaterialApp(
        home: DiscoveryScreen(api: api, credentials: _Credentials()),
      ),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.text('Scan for plugs'));
    await tester.pumpAndSettle();
    await tester.ensureVisible(find.text('Add'));
    await tester.tap(find.text('Add'));
    await tester.pumpAndSettle();
    expect(api.adoptionCount, 1);
    expect(find.byKey(const Key('nearby-saved-device')), findsOneWidget);
    expect(find.widgetWithText(TextButton, 'Add'), findsNothing);
  });

  testWidgets(
    'refreshed saved identity stays visible after inventory failure',
    (tester) async {
      const identity = NearbyStableIdentity('ssdp', 'uuid:tv-one');
      final api = _Api(candidate(expiresAtMs: 1, stableIdentity: identity))
        ..refreshedCandidates = [
          candidate(
            id: 'fresh',
            stableIdentity: identity,
            alreadySaved: true,
            savedDeviceId: 'saved-tv',
          ),
        ]
        ..failInventory = true;
      await tester.pumpWidget(
        MaterialApp(
          home: DiscoveryScreen(api: api, credentials: _Credentials()),
        ),
      );
      await tester.pumpAndSettle();
      await tester.tap(find.text('Scan for plugs'));
      await tester.pumpAndSettle();
      await tester.ensureVisible(find.text('Add'));
      await tester.tap(find.text('Add'));
      await tester.pumpAndSettle();
      expect(find.byKey(const Key('nearby-candidate')), findsOneWidget);
      expect(find.widgetWithText(TextButton, 'Add'), findsNothing);
      expect(find.text('Couldn’t connect. Try again.'), findsOneWidget);
      expect(api.adoptionCount, 0);
    },
  );

  testWidgets('linked local device cannot reopen the create form', (
    tester,
  ) async {
    final api = _Api(candidate(alreadySaved: true))
      ..inventory = const [
        NearbySavedDevice(
          'protocol-device',
          'Saved television',
          applianceId: 42,
          bindings: [
            NearbyDeviceBinding(
              'binding',
              'ssdp',
              'upnp-local',
              'local',
              'uuid:tv-one',
            ),
          ],
        ),
      ];
    await tester.pumpWidget(
      MaterialApp(
        home: DiscoveryScreen(api: api, credentials: _Credentials()),
      ),
    );
    await tester.pumpAndSettle();
    final row = tester.widget<ListTile>(
      find.byKey(const Key('nearby-saved-protocol-device')),
    );
    expect(row.onTap, isNull);
    expect(find.byKey(const Key('saveAppliance')), findsNothing);
    expect(api.adoptionCount, 0);
  });

  testWidgets('expired candidate without stable identity cannot be adopted', (
    tester,
  ) async {
    final api = _Api(candidate(expiresAtMs: 1));
    await tester.pumpWidget(
      MaterialApp(
        home: DiscoveryScreen(api: api, credentials: _Credentials()),
      ),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.text('Scan for plugs'));
    await tester.pumpAndSettle();
    await tester.ensureVisible(find.text('Add'));
    await tester.tap(find.text('Add'));
    await tester.pumpAndSettle();
    expect(api.scanCount, 1);
    expect(api.adoptionCount, 0);
    expect(find.text('Search stopped. Try again.'), findsOneWidget);
  });

  testWidgets('two Add taps start one adoption', (tester) async {
    final api = _Api(candidate())
      ..pendingAdoption = Completer<NearbySavedDevice>();
    await tester.pumpWidget(
      MaterialApp(
        home: DiscoveryScreen(api: api, credentials: _Credentials()),
      ),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.text('Scan for plugs'));
    await tester.pumpAndSettle();
    await tester.ensureVisible(find.text('Add'));
    await tester.tap(find.text('Add'));
    await tester.tap(find.text('Add'));
    await tester.pump();
    expect(api.adoptionCount, 1);
    api.pendingAdoption!.complete(const NearbySavedDevice('device', 'TV'));
    await tester.pumpAndSettle();
  });

  testWidgets('adopted legacy plug opens existing appliance workflow', (
    tester,
  ) async {
    final api = _Api(candidate())
      ..adoptedDevice = const NearbySavedDevice(
        'plug-1',
        'Plug',
        bindings: [
          NearbyDeviceBinding(
            'binding',
            'kasa',
            'legacy-local',
            'legacy-local',
            'plug-1',
          ),
        ],
      )
      ..legacyPlug = const SavedPlug(
        id: 'plug-1',
        ip: '192.168.1.30',
        model: 'KP115',
        name: 'Plug',
        room: '',
        meterStatus: 'verified',
        lastVerifiedAt: 1,
      );
    await tester.pumpWidget(
      MaterialApp(
        home: DiscoveryScreen(api: api, credentials: _Credentials()),
      ),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.text('Scan for plugs'));
    await tester.pumpAndSettle();
    await tester.ensureVisible(find.text('Add'));
    await tester.tap(find.text('Add'));
    await tester.pumpAndSettle();
    expect(api.adoptionCount, 1);
    expect(find.text('Connected appliance or lamp'), findsOneWidget);
    await tester.tapAt(const Offset(5, 5));
    await tester.pumpAndSettle();
    expect(api.inventory.single.id, 'plug-1');
    expect(find.widgetWithText(TextButton, 'Add'), findsNothing);
  });

  testWidgets(
    'saved legacy row retries v1 inventory after adoption read fails',
    (tester) async {
      final api = _Api(candidate())
        ..failFirstSavedAfterAdoption = true
        ..adoptedDevice = const NearbySavedDevice(
          'plug-1',
          'Plug',
          bindings: [
            NearbyDeviceBinding(
              'binding',
              'kasa',
              'legacy-local',
              'legacy-local',
              'plug-1',
            ),
          ],
        )
        ..legacyPlug = const SavedPlug(
          id: 'plug-1',
          ip: '192.168.1.30',
          model: 'KP115',
          name: 'Plug',
          room: '',
          meterStatus: 'verified',
          lastVerifiedAt: 1,
        );
      await tester.pumpWidget(
        MaterialApp(
          home: DiscoveryScreen(api: api, credentials: _Credentials()),
        ),
      );
      await tester.pumpAndSettle();
      await tester.tap(find.text('Scan for plugs'));
      await tester.pumpAndSettle();
      await tester.ensureVisible(find.text('Add'));
      await tester.tap(find.text('Add'));
      await tester.pumpAndSettle();
      expect(find.byKey(const Key('nearby-saved-plug-1')), findsOneWidget);
      await tester.tap(find.byKey(const Key('nearby-saved-plug-1')));
      await tester.pumpAndSettle();
      expect(api.savedCallsAfterAdoption, 2);
      expect(find.text('Connected appliance or lamp'), findsOneWidget);
    },
  );

  testWidgets('unsupported candidate cannot be silently adopted', (
    tester,
  ) async {
    final api = _Api(candidate(requiresAction: true));
    await tester.pumpWidget(
      MaterialApp(
        home: DiscoveryScreen(api: api, credentials: _Credentials()),
      ),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.text('Scan for plugs'));
    await tester.pumpAndSettle();
    await tester.ensureVisible(find.text('Add'));
    final button = tester.widget<TextButton>(
      find.widgetWithText(TextButton, 'Add'),
    );
    expect(button.onPressed, isNull);
    expect(api.adoptionCount, 0);
  });

  testWidgets('supported setup continues through existing manual probe', (
    tester,
  ) async {
    final api = _Api(candidate(requiresAction: true, manual: true));
    await tester.pumpWidget(
      MaterialApp(
        home: DiscoveryScreen(api: api, credentials: _Credentials()),
      ),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.text('Scan for plugs'));
    await tester.pumpAndSettle();
    await tester.ensureVisible(find.text('Add'));
    await tester.tap(find.text('Add'));
    await tester.pumpAndSettle();
    expect(find.text('Finish setup'), findsOneWidget);
    await tester.tap(find.text('Continue'));
    await tester.pumpAndSettle();
    expect(api.probeCount, 1);
    expect(api.adoptionCount, 0);
  });

  testWidgets('partial result retains candidate and offers retry', (
    tester,
  ) async {
    final api = _Api(candidate(requiresAction: true), state: 'partial');
    await tester.pumpWidget(
      MaterialApp(
        home: DiscoveryScreen(api: api, credentials: _Credentials()),
      ),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.text('Scan for plugs'));
    await tester.pumpAndSettle();
    expect(find.text('Search stopped. Try again.'), findsOneWidget);
    expect(find.text('Living room TV'), findsOneWidget);
    expect(find.text('Try again'), findsOneWidget);
  });

  testWidgets('failed scan keeps previously loaded generic inventory', (
    tester,
  ) async {
    final api = _Api(candidate())
      ..inventory = const [NearbySavedDevice('persisted', 'Kitchen plug')]
      ..failScan = true;
    await tester.pumpWidget(
      MaterialApp(
        home: DiscoveryScreen(api: api, credentials: _Credentials()),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.text('Kitchen plug'), findsOneWidget);
    await tester.tap(find.text('Scan for plugs'));
    await tester.pumpAndSettle();
    expect(find.text('Kitchen plug'), findsOneWidget);
    expect(find.text('Search stopped. Try again.'), findsOneWidget);
  });

  testWidgets('late inventory from an old Hub does not reappear', (
    tester,
  ) async {
    final api = _Api(candidate())
      ..pendingInventory = Completer<List<NearbySavedDevice>>();
    await tester.pumpWidget(
      MaterialApp(
        home: DiscoveryScreen(api: api, credentials: _Credentials()),
      ),
    );
    await tester.pump();
    await tester.pump();
    await tester.tap(find.text('Connection details'));
    await tester.pump();
    await tester.enterText(
      find.byKey(const Key('hubAddress')),
      'https://192.168.1.30:8787',
    );
    api.pendingInventory!.complete(const [
      NearbySavedDevice('old-device', 'Old hub device'),
    ]);
    await tester.pumpAndSettle();
    expect(find.text('Old hub device'), findsNothing);
  });

  testWidgets('Cancel before start response still cancels Hub scan', (
    tester,
  ) async {
    final api = _Api(candidate())..pendingStart = Completer<NearbyScan>();
    await tester.pumpWidget(
      MaterialApp(
        home: DiscoveryScreen(api: api, credentials: _Credentials()),
      ),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.text('Scan for plugs'));
    await tester.pump();
    await tester.tap(find.widgetWithText(TextButton, 'Cancel'));
    await tester.pump();
    api.pendingStart!.complete(
      const NearbyScan(
        id: 'late-scan',
        state: 'queued',
        expiresAtMs: 4102444800000,
      ),
    );
    await tester.pumpAndSettle();
    expect(api.cancelledScanIds, ['late-scan']);
    expect(find.text('Search stopped. Try again.'), findsOneWidget);
  });
}
