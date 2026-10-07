import 'package:energylens_mobile/core/cloud_api/cloud_appliance.dart';
import 'package:energylens_mobile/core/cloud_api/cloud_appliance_list.dart';
import 'package:energylens_mobile/core/cloud_api/cloud_interventions.dart';
import 'package:energylens_mobile/core/cloud_api/cloud_kasa_runtime.dart';
import 'package:energylens_mobile/core/cloud_api/cloud_sensor.dart';
import 'package:energylens_mobile/features/design/devices_runtime_evidence_adapter.dart';
import 'package:flutter_test/flutter_test.dart';

const home = '11111111-1111-4111-8111-111111111111';
const otherHome = '22222222-2222-4222-8222-222222222222';
const applianceId = '33333333-3333-4333-8333-333333333333';
const attachmentId = '44444444-4444-4444-8444-444444444444';
const sensorId = '55555555-5555-4555-8555-555555555555';
final observed = DateTime.utc(2026, 10, 6, 12);

CloudAppliance appliance(String homeId) => CloudAppliance(
  id: applianceId,
  homeId: homeId,
  name: 'Plugged device',
  category: 'other',
  room: null,
  brand: 'Brand',
  fullModel: 'Model',
  fuel: 'electric',
  matchQuality: 'confirmed_exact',
);

CloudAttachment attachment({
  String homeId = home,
  String id = attachmentId,
  String appliance = applianceId,
  String? sensor = sensorId,
  DateTime? endedAt,
}) => CloudAttachment(
  id: id,
  homeId: homeId,
  applianceId: appliance,
  startedAt: observed.subtract(const Duration(days: 10)),
  endedAt: endedAt,
  sensorId: sensor,
);

CloudSensor sensor({String homeId = home, String id = sensorId}) => CloudSensor(
  id: id,
  homeId: homeId,
  kind: 'plug',
  capabilities: const ['runtime'],
  hubId: 'hub',
  ownershipEpoch: 1,
  localSensorId: 'local',
  version: 1,
);

CloudKasaRuntimeSnapshot runtime({
  String id = 'snapshot-1',
  String homeId = home,
  String sensor = sensorId,
  String window = 'today',
  DateTime? time,
}) => CloudKasaRuntimeSnapshot(
  snapshotId: id,
  homeId: homeId,
  sensorId: sensor,
  windowLabel: window,
  nativeMinutes: 42,
  observedAt: time ?? observed,
  method: 'get_device_usage',
  transport: 'kasa_http_klap',
  deviceClockValid: true,
  quality: 'protocol_reported_clock_verified',
);

class FakeRuntimeSource implements DevicesRuntimeEvidenceSource {
  FakeRuntimeSource({
    this.appliances = const [],
    this.attachmentRows = const [],
    this.sensorRows = const [],
    required this.pages,
    this.mode = CloudApplianceDataMode.household,
  });
  final List<CloudAppliance> appliances;
  final List<CloudAttachment> attachmentRows;
  final List<CloudSensor> sensorRows;
  final Map<String?, CloudKasaRuntimePage> pages;
  final CloudApplianceDataMode mode;
  final cursors = <String?>[];

  @override
  Future<CloudApplianceList> applianceList(String homeId) async =>
      CloudApplianceList(
        appliances: appliances,
        dataMode: mode,
        fixtureRevision: mode == CloudApplianceDataMode.sample
            ? 'fixture-1'
            : null,
      );
  @override
  Future<List<CloudAttachment>> attachments(String homeId) async =>
      attachmentRows;
  @override
  Future<List<CloudSensor>> sensors(String homeId) async => sensorRows;
  @override
  Future<CloudKasaRuntimePage> kasaRuntimeHistory(
    String homeId, {
    String? cursor,
  }) async {
    cursors.add(cursor);
    return pages[cursor]!;
  }
}

CloudKasaRuntimePage page(
  List<CloudKasaRuntimeSnapshot> rows, {
  String? next,
}) => CloudKasaRuntimePage(
  snapshots: rows,
  from: observed.subtract(const Duration(days: 30)),
  to: observed,
  nextCursor: next,
);

void main() {
  test(
    'joins runtime through home, sensor, active attachment and appliance IDs',
    () async {
      final source = FakeRuntimeSource(
        appliances: [appliance(home)],
        attachmentRows: [attachment()],
        sensorRows: [sensor()],
        pages: {
          null: page([runtime()]),
        },
      );
      final result = (await DevicesRuntimeEvidenceAdapter(source).fetch(home))!;
      expect(result.evidence, hasLength(1));
      expect(result.evidence.single.applianceId, applianceId);
      expect(result.evidence.single.attachmentId, attachmentId);
      expect(result.energyWh, isNull);
      expect(result.cost, isNull);
      expect(result.wasteEnergyWh, isNull);
      expect(result.liveState, isNull);
    },
  );

  test(
    'keeps overlapping runtime windows as separate reported entries',
    () async {
      final source = FakeRuntimeSource(
        appliances: [appliance(home)],
        attachmentRows: [attachment()],
        sensorRows: [sensor()],
        pages: {
          null: page([
            runtime(id: 'today', window: 'today'),
            runtime(id: 'week', window: 'past7'),
            runtime(id: 'month', window: 'past30'),
          ]),
        },
      );
      final result = (await DevicesRuntimeEvidenceAdapter(source).fetch(home))!;
      expect(
        result.evidence.map((e) => e.windowLabel),
        containsAll(['today', 'past7', 'past30']),
      );
      expect(result.evidence.map((e) => e.nativeMinutes), [42, 42, 42]);
    },
  );

  test('sample inventory skips household runtime read', () async {
    final source = FakeRuntimeSource(
      appliances: [appliance(home)],
      attachmentRows: [attachment()],
      sensorRows: [sensor()],
      mode: CloudApplianceDataMode.sample,
      pages: {
        null: page([runtime()]),
      },
    );
    final result = (await DevicesRuntimeEvidenceAdapter(source).fetch(home))!;
    expect(result.isSample, isTrue);
    expect(result.evidence, isEmpty);
    expect(source.cursors, isEmpty);
  });

  test(
    'rejects cross-home reads, duplicate runtime and ambiguous active joins',
    () async {
      final crossHome = FakeRuntimeSource(
        appliances: [appliance(home)],
        attachmentRows: [attachment()],
        sensorRows: [sensor()],
        pages: {
          null: page([runtime(homeId: otherHome)]),
        },
      );
      await expectLater(
        DevicesRuntimeEvidenceAdapter(crossHome).fetch(home),
        throwsFormatException,
      );

      final duplicate = FakeRuntimeSource(
        appliances: [appliance(home)],
        attachmentRows: [attachment()],
        sensorRows: [sensor()],
        pages: {
          null: page([runtime(), runtime()]),
        },
      );
      await expectLater(
        DevicesRuntimeEvidenceAdapter(duplicate).fetch(home),
        throwsFormatException,
      );

      final ambiguous = FakeRuntimeSource(
        appliances: [appliance(home)],
        attachmentRows: [
          attachment(),
          attachment(id: '66666666-6666-4666-8666-666666666666'),
        ],
        sensorRows: [sensor()],
        pages: {
          null: page([runtime()]),
        },
      );
      await expectLater(
        DevicesRuntimeEvidenceAdapter(ambiguous).fetch(home),
        throwsFormatException,
      );
    },
  );

  test('bounds history pages and rejects cursor loops', () async {
    final loop = FakeRuntimeSource(
      appliances: [appliance(home)],
      attachmentRows: [attachment()],
      sensorRows: [sensor()],
      pages: {
        null: page([], next: 'same'),
        'same': page([], next: 'same'),
      },
    );
    await expectLater(
      DevicesRuntimeEvidenceAdapter(loop).fetch(home),
      throwsFormatException,
    );
    expect(loop.cursors, [null, 'same']);
  });

  test('snapshot becomes stale after invalidation', () async {
    final source = FakeRuntimeSource(
      appliances: [appliance(home)],
      attachmentRows: [attachment()],
      sensorRows: [sensor()],
      pages: {
        null: page([runtime()]),
      },
    );
    final adapter = DevicesRuntimeEvidenceAdapter(source);
    final result = (await adapter.fetch(home))!;
    expect(result.isCurrent(), isTrue);
    adapter.invalidate();
    expect(result.isCurrent(), isFalse);
  });
}
