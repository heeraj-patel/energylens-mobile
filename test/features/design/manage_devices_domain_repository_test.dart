import 'dart:async';

import 'package:energylens_mobile/core/cloud_api/cloud_appliance.dart';
import 'package:energylens_mobile/core/cloud_api/cloud_appliance_list.dart';
import 'package:energylens_mobile/core/cloud_api/cloud_interventions.dart';
import 'package:energylens_mobile/core/cloud_api/cloud_sensor.dart';
import 'package:energylens_mobile/features/design/manage_devices_domain_repository.dart';
import 'package:energylens_mobile/features/discovery/discovery_api.dart';
import 'package:flutter_test/flutter_test.dart';

const homeA = '11111111-1111-4111-8111-111111111111';
const homeB = '22222222-2222-4222-8222-222222222222';
const applianceId = '33333333-3333-4333-8333-333333333333';
const sensorId = '44444444-4444-4444-8444-444444444444';
const attachmentId = '55555555-5555-4555-8555-555555555555';
final now = DateTime.utc(2026, 10, 6);

CloudAppliance appliance(String home) => CloudAppliance(
  id: applianceId,
  homeId: home,
  name: 'Washer',
  category: 'washer',
  room: null,
  brand: 'Brand',
  fullModel: 'M1',
  fuel: 'electricity',
  matchQuality: 'unresolved',
);

CloudSensor sensor(
  String home, {
  List<String> capabilities = const ['energy'],
}) => CloudSensor(
  id: sensorId,
  homeId: home,
  kind: 'plug',
  capabilities: capabilities,
  hubId: 'hub',
  ownershipEpoch: 1,
  localSensorId: 'local',
  version: 1,
);

CloudAttachment attachment(String home, {DateTime? start, DateTime? end}) =>
    CloudAttachment(
      id: attachmentId,
      homeId: home,
      applianceId: applianceId,
      startedAt: start ?? now.subtract(const Duration(days: 1)),
      endedAt: end,
      sensorId: sensorId,
    );

class Source implements ManageDevicesDomainSource {
  Source({
    this.applianceRead,
    this.attachmentsRead,
    this.sensorRead,
    this.dataMode = CloudApplianceDataMode.household,
    this.fixtureRevision,
  });
  final Future<List<CloudAppliance>> Function(String)? applianceRead;
  final Future<List<CloudAttachment>> Function(String)? attachmentsRead;
  final Future<List<CloudSensor>> Function(String)? sensorRead;
  final CloudApplianceDataMode dataMode;
  final String? fixtureRevision;

  @override
  Future<CloudApplianceList> applianceList(String home) async =>
      CloudApplianceList(
        appliances:
            await (applianceRead?.call(home) ??
                Future.value([appliance(home)])),
        dataMode: dataMode,
        fixtureRevision: fixtureRevision,
      );
  @override
  Future<List<CloudAttachment>> attachments(String home) =>
      attachmentsRead?.call(home) ?? Future.value([attachment(home)]);
  @override
  Future<List<CloudSensor>> sensors(String home) =>
      sensorRead?.call(home) ?? Future.value([sensor(home)]);
}

ManageDevicesDomainRepository repository(Source source) =>
    ManageDevicesDomainRepository(source, now: () => now);

void main() {
  test(
    'shares only evidence-backed monitored rows across three pages',
    () async {
      final snapshot = await repository(Source()).fetch(homeA);
      expect(snapshot!.monitoredCount, 1);
      expect(snapshot.dataMode, CloudApplianceDataMode.household);
      expect(snapshot.inventoryCount, 1);
      expect(snapshot.monitoredRows.single.appliance.id, applianceId);
      expect(snapshot.manualEntryMonitoredRows, snapshot.monitoredRows);
      expect(snapshot.photoScanMonitoredRows, snapshot.monitoredRows);
      expect(snapshot.circuitCount, isNull);
      expect(snapshot.circuitTotal, isNull);
      expect(snapshot.candidateCount, isNull);
    },
  );

  test(
    'sensor without metering capability does not count as monitored',
    () async {
      final snapshot = await repository(
        Source(
          sensorRead: (home) async => [
            sensor(home, capabilities: ['temperature']),
          ],
        ),
      ).fetch(homeA);
      expect(snapshot!.inventoryCount, 1);
      expect(snapshot.monitoredCount, 0);
    },
  );

  test('future and closed attachments do not count as monitored', () async {
    for (final record in [
      attachment(homeA, start: now.add(const Duration(hours: 1))),
      attachment(homeA, end: now.subtract(const Duration(minutes: 1))),
    ]) {
      final snapshot = await repository(
        Source(attachmentsRead: (_) async => [record]),
      ).fetch(homeA);
      expect(snapshot!.monitoredCount, 0);
    }
  });

  test('OCR candidate remains transient and unconfirmed', () async {
    final snapshot = (await repository(Source()).fetch(homeA))!;
    final reviewed = snapshot.withScanCandidate(
      const IdentificationCandidate(
        manufacturer: 'Bosch',
        model: 'M2',
        confidence: .99,
        source: 'ocr_text',
        matchedKinds: [],
      ),
    );
    expect(reviewed.scanReview!.brandHint, 'Bosch');
    expect(reviewed.scanReview!.recognitionConfidence, .99);
    expect(reviewed.scanReview!.confirmedExact, isFalse);
    expect(reviewed.candidateCount, isNull);
    expect(reviewed.dataMode, CloudApplianceDataMode.household);
    expect(snapshot.scanReview, isNull);
  });

  test('sample inventory stays labeled and cannot become monitored', () async {
    final snapshot = (await repository(
      Source(
        dataMode: CloudApplianceDataMode.sample,
        fixtureRevision: 'synthetic-household-v1',
      ),
    ).fetch(homeA))!;
    expect(snapshot.isSample, isTrue);
    expect(snapshot.fixtureRevision, 'synthetic-household-v1');
    expect(snapshot.inventoryCount, 1);
    expect(snapshot.monitoredRows, isEmpty);
    expect(snapshot.manualEntryMonitoredRows, isEmpty);
    expect(snapshot.photoScanMonitoredRows, isEmpty);
  });

  test('rejects malformed source provenance', () async {
    await expectLater(
      repository(Source(dataMode: CloudApplianceDataMode.sample)).fetch(homeA),
      throwsFormatException,
    );
    await expectLater(
      repository(Source(fixtureRevision: 'wrong')).fetch(homeA),
      throwsFormatException,
    );
  });

  test('cross-home data and duplicate records are rejected', () async {
    await expectLater(
      repository(Source(applianceRead: (_) async => [appliance(homeB)]))
          .fetch(homeA),
      throwsFormatException,
    );
    await expectLater(
      repository(
        Source(
          applianceRead: (home) async => [appliance(home), appliance(home)],
        ),
      ).fetch(homeA),
      throwsFormatException,
    );
  });

  test('home switch and clear discard stale reads', () async {
    final pending = Completer<List<CloudAppliance>>();
    final repo = repository(
      Source(
        applianceRead: (home) =>
            home == homeA ? pending.future : Future.value([appliance(home)]),
      ),
    );
    final old = repo.fetch(homeA);
    expect((await repo.fetch(homeB))!.homeId, homeB);
    pending.complete([appliance(homeA)]);
    expect(await old, isNull);

    final pendingClear = Completer<List<CloudAppliance>>();
    final clearRepo = repository(
      Source(applianceRead: (_) => pendingClear.future),
    );
    final beforeClear = clearRepo.fetch(homeA);
    clearRepo.clear();
    pendingClear.complete([appliance(homeA)]);
    expect(await beforeClear, isNull);
  });
}
