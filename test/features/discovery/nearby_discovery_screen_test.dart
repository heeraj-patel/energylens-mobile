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
  int probeCount = 0;
  bool failInventory = false;
  bool failScan = false;
  Completer<NearbyScan>? pendingStart;
  Completer<List<NearbySavedDevice>>? pendingInventory;
  final cancelledScanIds = <String>[];
  List<NearbySavedDevice> inventory = const [];

  @override
  Future<List<SavedPlug>> saved(String baseUrl, String token) async => [];

  @override
  Future<bool> supportsNearbyDiscovery(String baseUrl, String token) async =>
      true;

  @override
  Future<List<NearbySavedDevice>> nearbyInventory(
    String baseUrl,
    String token,
  ) async {
    if (failInventory) throw StateError('offline');
    if (pendingInventory case final pending?) return pending.future;
    return inventory;
  }

  @override
  Future<NearbyScan> startNearbyScan(String baseUrl, String token) async {
    if (pendingStart case final pending?) return pending.future;
    if (failScan) throw StateError('offline');
    return NearbyScan(
      id: 'scan',
      state: state,
      expiresAtMs: candidate.expiresAtMs,
      candidates: [candidate],
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
    bool requiresAction = false,
    bool manual = false,
  }) => NearbyDeviceCandidate(
    id: 'candidate',
    scanId: 'scan',
    expiresAtMs: 4102444800000,
    requiresAction: requiresAction,
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

  testWidgets('Govee account device sits under From your accounts', (
    tester,
  ) async {
    final govee = NearbyDeviceCandidate.fromJson({
      'candidate_id': 'govee',
      'scan_id': 'scan',
      'expires_at_ms': 4102444800000,
      'manufacturer': 'Govee',
      'name': 'Kitchen cooler plug',
      'model': 'H5086',
      'category': 'smart_plug',
      'device_label': 'Govee Plug',
      'addresses': <dynamic>[],
      'sources': ['govee_cloud'],
      'capabilities': <dynamic>[],
      'requires_action': false,
      'reason_code': null,
    });
    final api = _Api(govee);
    await tester.pumpWidget(
      MaterialApp(
        home: DiscoveryScreen(api: api, credentials: _Credentials()),
      ),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.text('Scan for plugs'));
    await tester.pumpAndSettle();
    await tester.ensureVisible(find.text('From your accounts'));
    expect(find.text('From your accounts'), findsOneWidget);
    expect(find.text('Govee Plug'), findsOneWidget);
    expect(find.text('Kitchen cooler plug'), findsOneWidget);
    expect(find.text('Govee account'), findsOneWidget);
    expect(find.text('Add'), findsOneWidget);
    expect(find.textContaining('H5086'), findsNothing);
    await tester.tap(find.text('Add'));
    await tester.pumpAndSettle();
    expect(api.adoptionCount, 1);
    expect(find.text('From your accounts'), findsNothing);
  });

  testWidgets('Govee device without an app name falls back to its label', (
    tester,
  ) async {
    final govee = NearbyDeviceCandidate.fromJson({
      'candidate_id': 'govee',
      'scan_id': 'scan',
      'expires_at_ms': 4102444800000,
      'model': 'H5086',
      'device_label': 'Govee Plug',
      'addresses': <dynamic>[],
      'sources': ['govee_cloud'],
      'capabilities': <dynamic>[],
      'requires_action': false,
    });
    expect(govee.displayName, 'Govee Plug');
  });

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
