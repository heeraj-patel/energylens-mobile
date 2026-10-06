import 'dart:async';

import 'package:energylens_mobile/core/cloud_api/cloud_appliance.dart';
import 'package:energylens_mobile/core/cloud_api/cloud_interventions.dart';
import 'package:energylens_mobile/core/cloud_api/cloud_metered_summary.dart';
import 'package:energylens_mobile/core/cloud_api/cloud_sensor.dart';
import 'package:energylens_mobile/features/design/devices_domain_repository.dart';
import 'package:flutter_test/flutter_test.dart';

const homeA = '11111111-1111-4111-8111-111111111111';
const homeB = '22222222-2222-4222-8222-222222222222';
const applianceId = '33333333-3333-4333-8333-333333333333';
const attachmentId = '44444444-4444-4444-8444-444444444444';
const sensorId = '55555555-5555-4555-8555-555555555555';

final day = DateTime.utc(2026, 10, 6);

CloudAppliance appliance(String home) => CloudAppliance(
  id: applianceId,
  homeId: home,
  name: 'Test appliance',
  category: 'other',
  room: null,
  brand: 'Brand',
  fullModel: 'Model',
  fuel: 'electric',
  matchQuality: 'confirmed_exact',
);

CloudAttachment attachment(String home, {String? sensor = sensorId}) =>
    CloudAttachment(
      id: attachmentId,
      homeId: home,
      applianceId: applianceId,
      startedAt: day.subtract(const Duration(days: 1)),
      sensorId: sensor,
    );

CloudSensor sensor(String home, {int epoch = 2}) => CloudSensor(
  id: sensorId,
  homeId: home,
  kind: 'plug',
  capabilities: const ['power'],
  hubId: 'hub',
  ownershipEpoch: epoch,
  localSensorId: 'local',
  version: 1,
);

CloudMeteredSummary measured({
  String? attachment = attachmentId,
  String status = 'complete',
  String method = 'exact',
  int epoch = 2,
}) => CloudMeteredSummary(
  kind: 'energy',
  bucketStart: day,
  sensorId: sensorId,
  hubId: 'hub',
  ownershipEpoch: epoch,
  computedAt: day.add(const Duration(days: 1)),
  sourceCount: 1,
  attachmentId: attachment,
  energyWh: status == 'complete' ? 1250 : null,
  coveredSeconds: status == 'complete' ? 3600 : null,
  intervalCount: 1,
  status: status,
  allocationMethod: method,
);

class FakeSource implements DevicesDomainSource {
  FakeSource({
    required this.applianceRead,
    required this.attachmentRead,
    required this.sensorRead,
    required this.summaryRead,
  });
  final Future<List<CloudAppliance>> Function(String) applianceRead;
  final Future<List<CloudAttachment>> Function(String) attachmentRead;
  final Future<List<CloudSensor>> Function(String) sensorRead;
  final Future<CloudMeteredSummaryPage> Function(String) summaryRead;
  int calls = 0;

  @override
  Future<List<CloudAppliance>> appliances(String homeId) {
    calls++;
    return applianceRead(homeId);
  }

  @override
  Future<List<CloudAttachment>> attachments(String homeId) {
    calls++;
    return attachmentRead(homeId);
  }

  @override
  Future<List<CloudSensor>> sensors(String homeId) {
    calls++;
    return sensorRead(homeId);
  }

  @override
  Future<CloudMeteredSummaryPage> meteredSummaries(String homeId) {
    calls++;
    return summaryRead(homeId);
  }
}

FakeSource fixed({
  List<CloudMeteredSummary>? summaries,
  String? nextCursor,
  String? applianceHome,
  int sensorEpoch = 2,
}) => FakeSource(
  applianceRead: (home) async => [appliance(applianceHome ?? home)],
  attachmentRead: (home) async => [attachment(home)],
  sensorRead: (home) async => [sensor(home, epoch: sensorEpoch)],
  summaryRead: (_) async => CloudMeteredSummaryPage(
    granularity: 'day',
    summaries: summaries ?? [measured()],
    nextCursor: nextCursor,
  ),
);

void main() {
  test(
    'keeps exact measured bucket and all unsupported values unknown',
    () async {
      final result = await DevicesDomainRepository(fixed(nextCursor: 'more'))
          .fetch(homeA);
      expect(result?.homeId, homeA);
      expect(result?.items, hasLength(1));
      final item = result!.items.single;
      expect(item.activeAttachmentIds, [attachmentId]);
      expect(item.measuredBuckets.single.energyWh, 1250);
      expect(item.measuredBuckets.single.coveredSeconds, 3600);
      expect(result.hasMoreMeteredPages, isTrue);
      expect(item.cost, isNull);
      expect(item.wasteEnergyWh, isNull);
      expect(item.liveState, isNull);
      expect(result.householdEnergyWh, isNull);
      expect(result.householdCost, isNull);
      expect(result.householdWasteWh, isNull);
    },
  );

  test('rejects cross-home inventory instead of combining it', () async {
    await expectLater(
      DevicesDomainRepository(fixed(applianceHome: homeB)).fetch(homeA),
      throwsFormatException,
    );
  });

  test('withholds unverified, conflicting and mismatched energy', () async {
    final source = fixed(
      summaries: [
        measured(status: 'overlap_conflict'),
        measured(method: 'duration_proportional'),
        measured(epoch: 99),
        measured(attachment: '66666666-6666-4666-8666-666666666666'),
      ],
    );
    final result = await DevicesDomainRepository(source).fetch(homeA);
    expect(result?.items.single.measuredBuckets, isEmpty);
  });

  test('home switch and sign-out discard stale responses', () async {
    final oldAppliances = Completer<List<CloudAppliance>>();
    final source = FakeSource(
      applianceRead: (home) => home == homeA
          ? oldAppliances.future
          : Future.value([appliance(home)]),
      attachmentRead: (home) async => [attachment(home)],
      sensorRead: (home) async => [sensor(home)],
      summaryRead: (_) async => CloudMeteredSummaryPage(
        granularity: 'day',
        summaries: const [],
        nextCursor: null,
      ),
    );
    final repository = DevicesDomainRepository(source);
    final oldRead = repository.fetch(homeA);
    expect((await repository.fetch(homeB))?.homeId, homeB);
    oldAppliances.complete([appliance(homeA)]);
    expect(await oldRead, isNull);

    final pendingAppliances = Completer<List<CloudAppliance>>();
    final signOut = DevicesDomainRepository(
      FakeSource(
        applianceRead: (_) => pendingAppliances.future,
        attachmentRead: (home) async => [attachment(home)],
        sensorRead: (home) async => [sensor(home)],
        summaryRead: (_) async => CloudMeteredSummaryPage(
          granularity: 'day',
          summaries: const [],
          nextCursor: null,
        ),
      ),
    );
    final pending = signOut.fetch(homeA);
    signOut.clear();
    pendingAppliances.complete([appliance(homeA)]);
    expect(await pending, isNull);
  });

  test('invalid home and active read errors are explicit', () async {
    final source = fixed();
    final repository = DevicesDomainRepository(source);
    await expectLater(repository.fetch('invalid'), throwsArgumentError);
    expect(source.calls, 0);
    final failing = DevicesDomainRepository(
      FakeSource(
        applianceRead: (_) async => throw StateError('offline'),
        attachmentRead: (_) async => const [],
        sensorRead: (_) async => const [],
        summaryRead: (_) async => const CloudMeteredSummaryPage(
          granularity: 'day',
          summaries: [],
          nextCursor: null,
        ),
      ),
    );
    await expectLater(failing.fetch(homeA), throwsStateError);
  });
}
