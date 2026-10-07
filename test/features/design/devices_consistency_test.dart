import 'dart:async';

import 'package:energylens_mobile/core/cloud_api/cloud_appliance.dart';
import 'package:energylens_mobile/core/cloud_api/cloud_appliance_list.dart';
import 'package:energylens_mobile/features/design/design_context_coordinator.dart';
import 'package:energylens_mobile/features/design/devices_consistency_snapshot.dart';
import 'package:energylens_mobile/features/design/devices_domain_repository.dart';
import 'package:energylens_mobile/features/design/devices_runtime_evidence_adapter.dart';
import 'package:flutter_test/flutter_test.dart';

const home = '11111111-1111-4111-8111-111111111111';
const otherHome = '22222222-2222-4222-8222-222222222222';
const applianceId = '33333333-3333-4333-8333-333333333333';
const attachmentId = '44444444-4444-4444-8444-444444444444';

class _Adapters implements DesignContextAdapters {
  DevicesDomainSnapshot? inventory;
  DevicesRuntimeEvidenceSnapshot? runtime;
  Completer<DevicesDomainSnapshot?>? pendingInventory;
  Completer<DevicesRuntimeEvidenceSnapshot?>? pendingRuntime;
  int inventoryCalls = 0;
  int runtimeCalls = 0;

  @override
  void clear() {}

  @override
  Future<DevicesDomainSnapshot?> devices(String homeId) {
    inventoryCalls++;
    return pendingInventory?.future ?? Future.value(inventory);
  }

  @override
  Future<DevicesRuntimeEvidenceSnapshot?> devicesRuntimeEvidence(
    String homeId,
  ) {
    runtimeCalls++;
    return pendingRuntime?.future ?? Future.value(runtime);
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

VerifiedDesignContext _context({
  String homeId = home,
  String accountId = 'account-a',
  DesignContextMode mode = DesignContextMode.household,
}) => VerifiedDesignContext(accountId: accountId, homeId: homeId, mode: mode);

DeviceInventoryItem _item({
  String id = applianceId,
  String homeId = home,
  List<String> attachments = const [attachmentId],
}) => DeviceInventoryItem(
  appliance: CloudAppliance(
    id: id,
    homeId: homeId,
    name: 'Device',
    category: 'other',
    room: null,
    brand: 'Brand',
    fullModel: 'Model',
    fuel: 'electric',
    matchQuality: 'confirmed_exact',
  ),
  activeAttachmentIds: attachments,
  measuredBuckets: const [],
);

DevicesDomainSnapshot _inventory({
  String homeId = home,
  List<DeviceInventoryItem>? items,
  CloudApplianceDataMode mode = CloudApplianceDataMode.household,
  bool Function()? isCurrent,
}) => DevicesDomainSnapshot(
  homeId: homeId,
  items: items ?? [_item(homeId: homeId)],
  hasMoreMeteredPages: false,
  dataMode: mode,
  fixtureRevision: mode == CloudApplianceDataMode.sample ? 'fixture' : null,
  isCurrent: isCurrent ?? () => true,
);

DeviceRuntimeEvidence _evidence({
  String appliance = applianceId,
  String attachment = attachmentId,
  String snapshot = 'runtime-1',
}) => DeviceRuntimeEvidence(
  applianceId: appliance,
  attachmentId: attachment,
  sensorId: 'sensor-1',
  snapshotId: snapshot,
  windowLabel: 'today',
  nativeMinutes: 42,
  observedAt: DateTime.utc(2026, 10, 6),
  method: 'get_device_usage',
  transport: 'kasa_http_klap',
  deviceClockValid: true,
  quality: 'protocol_reported_clock_verified',
);

DevicesRuntimeEvidenceSnapshot _runtime({
  String homeId = home,
  List<DeviceRuntimeEvidence>? evidence,
  bool isSample = false,
  bool Function()? isCurrent,
}) => DevicesRuntimeEvidenceSnapshot(
  homeId: homeId,
  evidence: evidence ?? [_evidence()],
  isSample: isSample,
  isCurrent: isCurrent ?? () => true,
);

void main() {
  test(
    'keeps valid inventory and runtime separate without derived values',
    () async {
      final adapters = _Adapters()
        ..inventory = _inventory()
        ..runtime = _runtime();
      final coordinator = DesignContextCoordinator(adapters)
        ..useVerifiedContext(_context());
      final read = await coordinator.readDevicesConsistency();
      final value = read!.value as DevicesConsistencySnapshot;
      expect(read.accountId, 'account-a');
      expect(read.homeId, home);
      expect(read.page, 'devices_consistency');
      expect(value.inventory.items.single.appliance.id, applianceId);
      expect(value.runtimeEvidence.evidence.single.nativeMinutes, 42);
      expect(value.householdEnergyWh, isNull);
      expect(value.householdCost, isNull);
      expect(value.householdWasteWh, isNull);
      expect(value.liveState, isNull);
      value.requireCurrent();
      coordinator.signOut();
      expect(value.requireCurrent, throwsStateError);
      expect(() => value.inventory, throwsStateError);
      expect(() => value.runtimeEvidence, throwsStateError);
    },
  );

  test('home and account switches and sign-out discard pending cross-context reads', () async {
    for (final transition in <void Function(DesignContextCoordinator)>[
      (c) => c.useVerifiedContext(_context(homeId: otherHome)),
      (c) => c.useVerifiedContext(_context(accountId: 'account-b')),
      (c) => c.signOut(),
    ]) {
      final adapters = _Adapters();
      final coordinator = DesignContextCoordinator(adapters)
        ..useVerifiedContext(_context());
      final inventory = Completer<DevicesDomainSnapshot?>();
      final runtime = Completer<DevicesRuntimeEvidenceSnapshot?>();
      adapters.pendingInventory = inventory;
      adapters.pendingRuntime = runtime;
      final pending = coordinator.readDevicesConsistency();
      transition(coordinator);
      inventory.complete(_inventory());
      runtime.complete(_runtime());
      expect(await pending, isNull);
    }
  });

  test(
    'sample mode never reads runtime and partial reads return no composition',
    () async {
      final adapters = _Adapters()..inventory = _inventory();
      final coordinator = DesignContextCoordinator(adapters)
        ..useVerifiedContext(_context(mode: DesignContextMode.sample));
      expect(() => coordinator.readDevicesConsistency(), throwsStateError);
      expect(adapters.inventoryCalls, 0);
      expect(adapters.runtimeCalls, 0);
      coordinator.useVerifiedContext(_context());
      expect(await coordinator.readDevicesConsistency(), isNull);
      adapters.runtime = _runtime();
      adapters.inventory = null;
      expect(await coordinator.readDevicesConsistency(), isNull);
    },
  );

  test('sample transition suppresses a pending household error', () async {
    final adapters = _Adapters()..inventory = _inventory();
    final pendingRuntime = Completer<DevicesRuntimeEvidenceSnapshot?>();
    adapters.pendingRuntime = pendingRuntime;
    final coordinator = DesignContextCoordinator(adapters)
      ..useVerifiedContext(_context());
    final pending = coordinator.readDevicesConsistency();
    coordinator.useVerifiedContext(_context(mode: DesignContextMode.sample));
    pendingRuntime.completeError(StateError('old household read'));
    expect(await pending, isNull);
  });

  test('rejects mismatched provenance, homes and ambiguous joins', () async {
    final adapters = _Adapters()
      ..inventory = _inventory()
      ..runtime = _runtime();
    final coordinator = DesignContextCoordinator(adapters)
      ..useVerifiedContext(_context());
    adapters.inventory = _inventory(mode: CloudApplianceDataMode.sample);
    await expectLater(
      coordinator.readDevicesConsistency(),
      throwsFormatException,
    );
    adapters.inventory = _inventory(homeId: otherHome);
    await expectLater(
      coordinator.readDevicesConsistency(),
      throwsFormatException,
    );
    adapters.inventory = _inventory();
    adapters.runtime = _runtime(homeId: otherHome);
    await expectLater(
      coordinator.readDevicesConsistency(),
      throwsFormatException,
    );
    adapters.runtime = _runtime(isSample: true);
    await expectLater(
      coordinator.readDevicesConsistency(),
      throwsFormatException,
    );
    adapters.runtime = _runtime(evidence: [_evidence(attachment: 'wrong')]);
    await expectLater(
      coordinator.readDevicesConsistency(),
      throwsFormatException,
    );
    adapters.runtime = _runtime(evidence: [_evidence(), _evidence()]);
    await expectLater(
      coordinator.readDevicesConsistency(),
      throwsFormatException,
    );
    adapters.runtime = _runtime();
    adapters.inventory = _inventory(items: [_item(), _item()]);
    await expectLater(
      coordinator.readDevicesConsistency(),
      throwsFormatException,
    );
  });

  test('rejects oversized and stale component snapshots', () async {
    final adapters = _Adapters()
      ..inventory = _inventory()
      ..runtime = _runtime();
    final coordinator = DesignContextCoordinator(adapters)
      ..useVerifiedContext(_context());
    adapters.inventory = _inventory(
      items: List.generate(
        101,
        (i) => _item(id: 'item-$i', attachments: const []),
      ),
    );
    await expectLater(
      coordinator.readDevicesConsistency(),
      throwsFormatException,
    );
    adapters.inventory = _inventory();
    adapters.runtime = _runtime(
      evidence: List.generate(251, (i) => _evidence(snapshot: 'snapshot-$i')),
    );
    await expectLater(
      coordinator.readDevicesConsistency(),
      throwsFormatException,
    );
    adapters.runtime = _runtime(isCurrent: () => false);
    expect(await coordinator.readDevicesConsistency(), isNull);
    adapters.runtime = _runtime();
    adapters.inventory = _inventory(isCurrent: () => false);
    expect(await coordinator.readDevicesConsistency(), isNull);
    adapters.inventory = DevicesDomainSnapshot(
      homeId: home,
      items: [_item()],
      hasMoreMeteredPages: false,
      dataMode: CloudApplianceDataMode.household,
      fixtureRevision: null,
    );
    expect(await coordinator.readDevicesConsistency(), isNull);
  });
}
