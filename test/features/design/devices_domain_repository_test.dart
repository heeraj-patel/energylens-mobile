import 'dart:async';

import 'package:energylens_mobile/core/cloud_api/cloud_appliance.dart';
import 'package:energylens_mobile/core/cloud_api/cloud_api_client.dart';
import 'package:energylens_mobile/core/cloud_api/cloud_appliance_list.dart';
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

CloudAppliance namedAppliance(String home, String id, String name) =>
    CloudAppliance(
      id: id,
      homeId: home,
      name: name,
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

CloudSensor sensor(
  String home, {
  int epoch = 2,
  List<String> capabilities = const ['power'],
}) => CloudSensor(
  id: sensorId,
  homeId: home,
  kind: 'plug',
  capabilities: capabilities,
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
  int dayOffset = 0,
  double energyWh = 1250,
}) => CloudMeteredSummary(
  kind: 'energy',
  bucketStart: day.add(Duration(days: dayOffset)),
  sensorId: sensorId,
  hubId: 'hub',
  ownershipEpoch: epoch,
  computedAt: day.add(const Duration(days: 1)),
  sourceCount: 1,
  attachmentId: attachment,
  energyWh: status == 'complete' ? energyWh : null,
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
    this.dataMode = CloudApplianceDataMode.household,
    this.fixtureRevision,
    this.inventoryRevision,
    this.inventoryRevisionRead,
  });
  final Future<List<CloudAppliance>> Function(String) applianceRead;
  final Future<List<CloudAttachment>> Function(String) attachmentRead;
  final Future<List<CloudSensor>> Function(String) sensorRead;
  final Future<CloudMeteredSummaryPage> Function(String, String?) summaryRead;
  final CloudApplianceDataMode dataMode;
  String? fixtureRevision;
  String? inventoryRevision;
  final String? Function()? inventoryRevisionRead;
  int calls = 0;

  @override
  Future<CloudApplianceList> applianceList(String homeId) async {
    calls++;
    return CloudApplianceList(
      appliances: await applianceRead(homeId),
      dataMode: dataMode,
      fixtureRevision: fixtureRevision,
      inventoryRevision: inventoryRevisionRead?.call() ?? inventoryRevision,
    );
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
  Future<CloudMeteredSummaryPage> meteredSummaries(
    String homeId, {
    String? cursor,
  }) {
    calls++;
    return summaryRead(homeId, cursor);
  }
}

FakeSource fixed({
  List<CloudMeteredSummary>? summaries,
  String? nextCursor,
  String? applianceHome,
  int sensorEpoch = 2,
  CloudApplianceDataMode dataMode = CloudApplianceDataMode.household,
  String? fixtureRevision,
  String? inventoryRevision,
}) => FakeSource(
  dataMode: dataMode,
  fixtureRevision: fixtureRevision,
  inventoryRevision: inventoryRevision,
  applianceRead: (home) async => [appliance(applianceHome ?? home)],
  attachmentRead: (home) async => [attachment(home)],
  sensorRead: (home) async => [sensor(home, epoch: sensorEpoch)],
  summaryRead: (_, cursor) async => CloudMeteredSummaryPage(
    granularity: 'day',
    summaries: cursor == null ? (summaries ?? [measured()]) : const [],
    nextCursor: cursor == null ? nextCursor : null,
    dataMode: dataMode,
    fixtureRevision: fixtureRevision,
  ),
);

FakeSource paged(
  Future<CloudMeteredSummaryPage> Function(String, String?) read, {
  CloudApplianceDataMode dataMode = CloudApplianceDataMode.household,
  String? fixtureRevision,
  String? inventoryRevision,
}) => FakeSource(
  applianceRead: (home) async => [appliance(home)],
  attachmentRead: (home) async => [attachment(home)],
  sensorRead: (home) async => [sensor(home)],
  summaryRead: read,
  dataMode: dataMode,
  fixtureRevision: fixtureRevision,
  inventoryRevision: inventoryRevision,
);

void main() {
  test(
    'energy monitoring requires an active power and energy sensor',
    () async {
      Future<DeviceInventoryItem> inventory(
        List<CloudAttachment> attachments,
        List<CloudSensor> sensors,
      ) async {
        final source = FakeSource(
          applianceRead: (home) async => [appliance(home)],
          attachmentRead: (_) async => attachments,
          sensorRead: (_) async => sensors,
          summaryRead: (_, _) async => const CloudMeteredSummaryPage(
            granularity: 'day',
            summaries: [],
            nextCursor: null,
          ),
        );
        return (await DevicesDomainRepository(source).fetch(homeA))!
            .items
            .single;
      }

      final meter = sensor(homeA, capabilities: const ['power', 'energy']);
      final relay = sensor(homeA, capabilities: const ['relay']);
      final power = sensor(homeA);
      final energy = sensor(homeA, capabilities: const ['energy']);
      final link = attachment(homeA);
      expect((await inventory([], [meter])).hasEnergyMonitoring, isFalse);
      expect((await inventory([link], [meter])).hasEnergyMonitoring, isTrue);
      for (final endpoint in [relay, power, energy]) {
        final result = await inventory([link], [endpoint]);
        expect(result.hasEnergyMonitoring, isFalse);
        expect(result.activeAttachmentIds, [attachmentId]);
      }
      expect(
        (await inventory(
          [
            CloudAttachment(
              id: attachmentId,
              homeId: homeA,
              applianceId: applianceId,
              startedAt: day.subtract(const Duration(days: 1)),
              endedAt: day,
              sensorId: sensorId,
            ),
          ],
          [meter],
        )).hasEnergyMonitoring,
        isFalse,
      );
      expect((await inventory([link], [])).hasEnergyMonitoring, isFalse);
      final otherSensor = CloudSensor(
        id: '66666666-6666-4666-8666-666666666666',
        homeId: homeA,
        kind: 'relay',
        capabilities: const ['relay'],
        hubId: 'hub',
        ownershipEpoch: 2,
        localSensorId: 'other',
        version: 1,
      );
      final otherLink = CloudAttachment(
        id: '77777777-7777-4777-8777-777777777777',
        homeId: homeA,
        applianceId: applianceId,
        startedAt: day,
        sensorId: otherSensor.id,
      );
      final mixed = await inventory([otherLink, link], [otherSensor, meter]);
      expect(mixed.hasEnergyMonitoring, isTrue);
      expect(mixed.activeAttachmentIds, [otherLink.id, link.id]);
    },
  );

  test(
    'sensor inventory failure does not invent Standalone evidence',
    () async {
      final source = FakeSource(
        applianceRead: (home) async => [appliance(home)],
        attachmentRead: (home) async => [attachment(home)],
        sensorRead: (_) async =>
            throw StateError('sensor inventory unavailable'),
        summaryRead: (_, _) async => const CloudMeteredSummaryPage(
          granularity: 'day',
          summaries: [],
          nextCursor: null,
        ),
      );
      await expectLater(
        DevicesDomainRepository(source).fetch(homeA),
        throwsA(isA<StateError>()),
      );
    },
  );

  test(
    'traverses unchanged pages and keeps local ranking non-global',
    () async {
      final cursors = <String?>[];
      final result = (await DevicesDomainRepository(
        paged((_, cursor) async {
          cursors.add(cursor);
          return CloudMeteredSummaryPage(
            granularity: 'day',
            summaries: [measured(dayOffset: cursor == null ? 0 : -1)],
            nextCursor: cursor == null ? 'next' : null,
          );
        }),
      ).fetch(homeA))!;
      expect(cursors, [null, 'next']);
      expect(result.items.single.measuredBuckets, hasLength(2));
      expect(result.hasMoreMeteredPages, isFalse);
      expect(
        result
            .localPage(sort: DeviceLocalSort.latestMeasuredBucketDesc)
            .isGlobalEnergyRanking,
        isFalse,
      );
      expect(result.householdEnergyWh, isNull);
    },
  );

  test('stable revision rechecks first page after bounded traversal', () async {
    final cursors = <String?>[];
    final result = (await DevicesDomainRepository(
      paged((_, cursor) async {
        cursors.add(cursor);
        return CloudMeteredSummaryPage(
          granularity: 'day',
          summaries: [measured(dayOffset: cursor == null ? 0 : -1)],
          nextCursor: cursor == null ? 'next' : null,
          evidenceRevision: 'v1-1',
        );
      }),
    ).fetch(homeA))!;
    expect(cursors, [null, 'next', null]);
    expect(result.items.single.measuredBuckets, hasLength(2));
  });

  test(
    'revision change on later page retries full Devices read once',
    () async {
      final cursors = <String?>[];
      var firstPages = 0;
      final source = paged((_, cursor) async {
        cursors.add(cursor);
        if (cursor == null) firstPages++;
        final revision = firstPages == 1 && cursor != null ? 'v1-2' : 'v1-1';
        return CloudMeteredSummaryPage(
          granularity: 'day',
          summaries: [measured(dayOffset: cursor == null ? 0 : -1)],
          nextCursor: cursor == null ? 'next' : null,
          evidenceRevision: revision,
        );
      });
      final result = (await DevicesDomainRepository(source).fetch(homeA))!;
      expect(cursors, [null, 'next', null, 'next', null]);
      expect(source.calls, 14);
      expect(result.items.single.measuredBuckets, hasLength(2));
    },
  );

  test(
    'single page correction after traversal retries then withholds',
    () async {
      var reads = 0;
      final source = paged((_, _) async {
        reads++;
        return CloudMeteredSummaryPage(
          granularity: 'day',
          summaries: [measured(energyWh: reads.toDouble())],
          nextCursor: null,
          evidenceRevision: 'v1-$reads',
        );
      });
      await expectLater(
        DevicesDomainRepository(source).fetch(homeA),
        throwsFormatException,
      );
      expect(reads, 4);
      expect(source.calls, 10);
    },
  );

  test(
    'one-page correction after traversal restarts and uses new data',
    () async {
      var reads = 0;
      final source = paged((_, _) async {
        reads++;
        final corrected = reads > 1;
        return CloudMeteredSummaryPage(
          granularity: 'day',
          summaries: [measured(energyWh: corrected ? 20 : 10)],
          nextCursor: null,
          evidenceRevision: corrected ? 'v1-2' : 'v1-1',
        );
      });
      final result = (await DevicesDomainRepository(source).fetch(homeA))!;
      expect(reads, 4);
      expect(result.items.single.latestMeasuredBucketWh, 20);
    },
  );

  test('evidence correction discards old pages and restarts once', () async {
    final cursors = <String?>[];
    var firstPages = 0;
    final result = (await DevicesDomainRepository(
      paged((_, cursor) async {
        cursors.add(cursor);
        if (cursor == 'old') {
          throw const CloudApiException(409, 'evidence_changed');
        }
        if (cursor == null) {
          firstPages++;
          return CloudMeteredSummaryPage(
            granularity: 'day',
            summaries: [measured(energyWh: firstPages == 1 ? 10 : 20)],
            nextCursor: firstPages == 1 ? 'old' : 'new',
          );
        }
        return CloudMeteredSummaryPage(
          granularity: 'day',
          summaries: [measured(dayOffset: -1)],
          nextCursor: null,
        );
      }),
    ).fetch(homeA))!;
    expect(cursors, [null, 'old', null, 'new']);
    expect(result.items.single.measuredBuckets.map((b) => b.energyWh), [
      20,
      1250,
    ]);
    expect(result.hasMoreMeteredPages, isFalse);
  });

  test('concurrent evidence conflict restarts every Devices source', () async {
    final oldCursorEntered = Completer<void>();
    final oldCursor = Completer<CloudMeteredSummaryPage>();
    var corrected = false;
    var applianceReads = 0;
    var attachmentReads = 0;
    var sensorReads = 0;
    final source = FakeSource(
      applianceRead: (home) async {
        applianceReads++;
        return [namedAppliance(home, applianceId, corrected ? 'New' : 'Old')];
      },
      attachmentRead: (home) async {
        attachmentReads++;
        return [attachment(home)];
      },
      sensorRead: (home) async {
        sensorReads++;
        return [sensor(home)];
      },
      summaryRead: (_, cursor) {
        if (cursor == 'old') {
          oldCursorEntered.complete();
          return oldCursor.future;
        }
        return Future.value(
          CloudMeteredSummaryPage(
            granularity: 'day',
            summaries: [measured(energyWh: corrected ? 20 : 10)],
            nextCursor: corrected ? null : 'old',
          ),
        );
      },
    );
    final pending = DevicesDomainRepository(source).fetch(homeA);
    await oldCursorEntered.future;
    corrected = true;
    oldCursor.completeError(const CloudApiException(409, 'evidence_changed'));
    final result = (await pending)!;
    expect(result.items.single.appliance.name, 'New');
    expect(result.items.single.latestMeasuredBucketWh, 20);
    expect(applianceReads, 3);
    expect(attachmentReads, 3);
    expect(sensorReads, 3);
  });

  test(
    'post-pagination revalidation retries changed inventory and versions',
    () async {
      final pageEntered = Completer<void>();
      final oldPage = Completer<CloudMeteredSummaryPage>();
      var corrected = false;
      var applianceReads = 0;
      var attachmentReads = 0;
      var sensorReads = 0;
      final source = FakeSource(
        applianceRead: (home) async {
          applianceReads++;
          return [namedAppliance(home, applianceId, corrected ? 'New' : 'Old')];
        },
        attachmentRead: (home) async {
          attachmentReads++;
          return [
            CloudAttachment(
              id: attachmentId,
              homeId: home,
              applianceId: applianceId,
              startedAt: day.subtract(const Duration(days: 1)),
              sensorId: sensorId,
              version: corrected ? 2 : 1,
            ),
          ];
        },
        sensorRead: (home) async {
          sensorReads++;
          return [
            CloudSensor(
              id: sensorId,
              homeId: home,
              kind: 'plug',
              capabilities: const ['power'],
              hubId: 'hub',
              ownershipEpoch: 2,
              localSensorId: 'local',
              version: corrected ? 2 : 1,
            ),
          ];
        },
        summaryRead: (_, _) {
          if (!corrected) {
            pageEntered.complete();
            return oldPage.future;
          }
          return Future.value(
            CloudMeteredSummaryPage(
              granularity: 'day',
              summaries: [measured(energyWh: 20)],
              nextCursor: null,
            ),
          );
        },
      );
      final pending = DevicesDomainRepository(source).fetch(homeA);
      await pageEntered.future;
      corrected = true;
      oldPage.complete(
        CloudMeteredSummaryPage(
          granularity: 'day',
          summaries: [measured(energyWh: 10)],
          nextCursor: null,
        ),
      );
      final result = (await pending)!;
      expect(result.items.single.appliance.name, 'New');
      expect(result.items.single.latestMeasuredBucketWh, 20);
      expect(applianceReads, 4);
      expect(attachmentReads, 4);
      expect(sensorReads, 4);
    },
  );

  test(
    'continuously changing inventory is withheld after bounded retry',
    () async {
      var reads = 0;
      final source = FakeSource(
        applianceRead: (home) async => [
          namedAppliance(home, applianceId, 'Revision ${++reads}'),
        ],
        attachmentRead: (_) async => [],
        sensorRead: (_) async => [],
        summaryRead: (_, _) async => const CloudMeteredSummaryPage(
          granularity: 'day',
          summaries: [],
          nextCursor: null,
        ),
      );
      await expectLater(
        DevicesDomainRepository(source).fetch(homeA),
        throwsFormatException,
      );
      expect(reads, 4);
    },
  );

  for (final changedField in ['version', 'archived_at', 'identity']) {
    test(
      'appliance $changedField mutation without revision retries read',
      () async {
        final pageEntered = Completer<void>();
        final oldPage = Completer<CloudMeteredSummaryPage>();
        var changed = false;
        var applianceReads = 0;
        var pageReads = 0;
        final source = FakeSource(
          applianceRead: (home) async {
            applianceReads++;
            return [
              CloudAppliance(
                id: applianceId,
                homeId: home,
                name: 'Appliance',
                category: 'other',
                room: null,
                brand: changedField == 'identity' && changed ? 'New' : 'Old',
                fullModel: 'Model',
                fuel: 'electric',
                matchQuality: 'confirmed_exact',
                version: changedField == 'version' && changed ? 2 : 1,
                archivedAt: changedField == 'archived_at' && changed
                    ? day
                    : null,
              ),
            ];
          },
          attachmentRead: (_) async => [],
          sensorRead: (_) async => [],
          summaryRead: (_, _) {
            pageReads++;
            if (pageReads == 1) {
              pageEntered.complete();
              return oldPage.future;
            }
            return Future.value(
              const CloudMeteredSummaryPage(
                granularity: 'day',
                summaries: [],
                nextCursor: null,
              ),
            );
          },
        );
        final pending = DevicesDomainRepository(source).fetch(homeA);
        await pageEntered.future;
        changed = true;
        oldPage.complete(
          const CloudMeteredSummaryPage(
            granularity: 'day',
            summaries: [],
            nextCursor: null,
          ),
        );
        final result = (await pending)!;
        expect(applianceReads, 4);
        expect(pageReads, 2);
        expect(
          result.items.single.appliance.version,
          changedField == 'version' ? 2 : 1,
        );
        expect(
          result.items.single.appliance.archivedAt,
          changedField == 'archived_at' ? day : null,
        );
        expect(
          result.items.single.appliance.brand,
          changedField == 'identity' ? 'New' : 'Old',
        );
      },
    );
  }

  test(
    'continuous appliance version churn without revision is bounded',
    () async {
      var applianceReads = 0;
      final source = FakeSource(
        applianceRead: (home) async => [
          CloudAppliance(
            id: applianceId,
            homeId: home,
            name: 'Appliance',
            category: 'other',
            room: null,
            brand: 'Brand',
            fullModel: 'Model',
            fuel: 'electric',
            matchQuality: 'confirmed_exact',
            version: ++applianceReads,
          ),
        ],
        attachmentRead: (_) async => [],
        sensorRead: (_) async => [],
        summaryRead: (_, _) async => const CloudMeteredSummaryPage(
          granularity: 'day',
          summaries: [],
          nextCursor: null,
        ),
      );
      await expectLater(
        DevicesDomainRepository(source).fetch(homeA),
        throwsFormatException,
      );
      expect(applianceReads, 4);
      expect(source.calls, 14);
    },
  );

  test(
    'inventory revision detects same-row ABA during metered pagination',
    () async {
      final nextPageEntered = Completer<void>();
      final oldNextPage = Completer<CloudMeteredSummaryPage>();
      var firstPages = 0;
      late final FakeSource source;
      source = FakeSource(
        inventoryRevision: 'rev-1',
        applianceRead: (home) async => [appliance(home)],
        attachmentRead: (home) async => [attachment(home)],
        sensorRead: (home) async => [sensor(home)],
        summaryRead: (_, cursor) {
          if (cursor == 'old') {
            nextPageEntered.complete();
            return oldNextPage.future;
          }
          firstPages++;
          return Future.value(
            CloudMeteredSummaryPage(
              granularity: 'day',
              summaries: [measured(energyWh: firstPages == 1 ? 10 : 20)],
              nextCursor: firstPages == 1 ? 'old' : null,
            ),
          );
        },
      );
      final pending = DevicesDomainRepository(source).fetch(homeA);
      await nextPageEntered.future;
      // The visible rows return to their original values, but the server token
      // advances across the mutation and must invalidate the old metered read.
      source.inventoryRevision = 'rev-3';
      oldNextPage.complete(
        CloudMeteredSummaryPage(
          granularity: 'day',
          summaries: [measured(dayOffset: -1, energyWh: 10)],
          nextCursor: null,
        ),
      );
      final result = (await pending)!;
      expect(result.items.single.latestMeasuredBucketWh, 20);
      expect(result.items.single.measuredBuckets, hasLength(1));
      expect(firstPages, 2);
      expect(source.calls, 15); // Four full inventory reads, three pages.
    },
  );

  test('continuous revision churn exhausts the bounded retry', () async {
    var applianceReads = 0;
    final source = FakeSource(
      applianceRead: (home) async => [appliance(home)],
      attachmentRead: (home) async => [attachment(home)],
      sensorRead: (home) async => [sensor(home)],
      inventoryRevisionRead: () => 'rev-${++applianceReads}',
      summaryRead: (_, _) async => const CloudMeteredSummaryPage(
        granularity: 'day',
        summaries: [],
        nextCursor: null,
      ),
    );
    await expectLater(
      DevicesDomainRepository(source).fetch(homeA),
      throwsFormatException,
    );
    expect(applianceReads, 4);
    expect(
      source.calls,
      14,
    ); // Two attempts, each with two inventories and a page.
  });

  test('changed sample provenance after metering retries whole read', () async {
    final pageEntered = Completer<void>();
    final oldPage = Completer<CloudMeteredSummaryPage>();
    var summaryReads = 0;
    late final FakeSource source;
    source = FakeSource(
      dataMode: CloudApplianceDataMode.sample,
      fixtureRevision: 'fixture-v1',
      applianceRead: (home) async => [appliance(home)],
      attachmentRead: (_) async => [],
      sensorRead: (_) async => [],
      summaryRead: (_, _) {
        summaryReads++;
        if (summaryReads == 1) {
          pageEntered.complete();
          return oldPage.future;
        }
        return Future.value(
          CloudMeteredSummaryPage(
            granularity: 'day',
            summaries: const [],
            nextCursor: null,
            dataMode: CloudApplianceDataMode.sample,
            fixtureRevision: source.fixtureRevision,
          ),
        );
      },
    );
    final pending = DevicesDomainRepository(source).fetch(homeA);
    await pageEntered.future;
    source.fixtureRevision = 'fixture-v2';
    oldPage.complete(
      const CloudMeteredSummaryPage(
        granularity: 'day',
        summaries: [],
        nextCursor: null,
        dataMode: CloudApplianceDataMode.sample,
        fixtureRevision: 'fixture-v1',
      ),
    );
    final result = (await pending)!;
    expect(result.fixtureRevision, 'fixture-v2');
    expect(summaryReads, 2);
    expect(source.calls, 14);
  });

  test('repeated evidence conflict and other errors propagate', () async {
    for (final error in [
      const CloudApiException(409, 'evidence_changed'),
      const CloudApiException(401, 'unauthorized'),
      const CloudApiException(500, 'server_error'),
    ]) {
      var firstPages = 0;
      final source = paged((_, cursor) async {
        if (cursor != null) throw error;
        firstPages++;
        return CloudMeteredSummaryPage(
          granularity: 'day',
          summaries: [measured()],
          nextCursor: 'next',
        );
      });
      await expectLater(
        DevicesDomainRepository(source).fetch(homeA),
        throwsA(same(error)),
      );
      expect(firstPages, error.statusCode == 409 ? 2 : 1);
    }
  });

  test('page bound keeps an explicit incomplete marker', () async {
    var calls = 0;
    final result = (await DevicesDomainRepository(
      paged((_, cursor) async {
        calls++;
        return CloudMeteredSummaryPage(
          granularity: 'day',
          summaries: [measured(dayOffset: calls)],
          nextCursor: 'page-$calls',
        );
      }),
    ).fetch(homeA))!;
    expect(calls, DevicesDomainRepository.maxMeteredPages);
    expect(
      result.items.single.measuredBuckets,
      hasLength(DevicesDomainRepository.maxMeteredPages),
    );
    expect(result.hasMoreMeteredPages, isTrue);
  });

  test('row bound keeps an explicit incomplete marker', () async {
    var calls = 0;
    final result = (await DevicesDomainRepository(
      paged((_, cursor) async {
        calls++;
        return CloudMeteredSummaryPage(
          granularity: 'day',
          summaries: List.generate(
            100,
            (index) => measured(dayOffset: calls * 100 + index),
          ),
          nextCursor: 'page-$calls',
        );
      }),
    ).fetch(homeA))!;
    expect(calls, 3);
    expect(
      result.items.single.measuredBuckets,
      hasLength(DevicesDomainRepository.maxMeteredRows),
    );
    expect(result.hasMoreMeteredPages, isTrue);
  });

  test('cursor loops and duplicate bucket identities fail closed', () async {
    final loop = paged(
      (_, cursor) async => CloudMeteredSummaryPage(
        granularity: 'day',
        summaries: [measured(dayOffset: cursor == null ? 0 : -1)],
        nextCursor: 'again',
      ),
    );
    await expectLater(
      DevicesDomainRepository(loop).fetch(homeA),
      throwsFormatException,
    );
    final duplicate = paged(
      (_, cursor) async => CloudMeteredSummaryPage(
        granularity: 'day',
        summaries: [measured()],
        nextCursor: cursor == null ? 'next' : null,
      ),
    );
    await expectLater(
      DevicesDomainRepository(duplicate).fetch(homeA),
      throwsFormatException,
    );
  });

  test('sample inventory reads only matching sample metering', () async {
    final source = paged(
      (_, _) async => CloudMeteredSummaryPage(
        granularity: 'day',
        summaries: [measured(status: 'no_intervals', method: 'none')],
        nextCursor: null,
        dataMode: CloudApplianceDataMode.sample,
        fixtureRevision: 'synthetic-household-v1',
      ),
      dataMode: CloudApplianceDataMode.sample,
      fixtureRevision: 'synthetic-household-v1',
    );
    final result = (await DevicesDomainRepository(source).fetch(homeA))!;
    expect(source.calls, 7);
    expect(result.sampleMeteredSummaries.single.status, 'no_intervals');
    expect(result.sampleMeteredSummaries.single.energyWh, isNull);
    expect(result.items.single.measuredBuckets, isEmpty);
    expect(result.items.single.activeAttachmentIds, isEmpty);
    expect(result.hasMoreMeteredPages, isFalse);
    expect(result.householdEnergyWh, isNull);
    expect(result.householdCost, isNull);
  });

  test('mixed inventory retains seeded and persisted appliance rows', () async {
    const seededId = '66666666-6666-4666-8666-666666666666';
    final seeded = CloudAppliance(
      id: seededId,
      homeId: homeA,
      name: 'Demo television',
      category: 'tv',
      room: null,
      brand: 'Demo',
      fullModel: 'Television',
      fuel: 'electricity',
      matchQuality: 'user_entered',
      demoDeviceId: 'demo-device-01',
    );
    final source = FakeSource(
      dataMode: CloudApplianceDataMode.mixed,
      fixtureRevision: 'synthetic-household-v1',
      applianceRead: (_) async => [appliance(homeA), seeded],
      attachmentRead: (home) async => [attachment(home)],
      sensorRead: (home) async => [sensor(home)],
      summaryRead: (_, _) async => const CloudMeteredSummaryPage(
        granularity: 'day',
        summaries: [],
        nextCursor: null,
        dataMode: CloudApplianceDataMode.mixed,
        fixtureRevision: 'synthetic-household-v1',
      ),
    );
    final result = (await DevicesDomainRepository(source).fetch(homeA))!;
    expect(result.dataMode, CloudApplianceDataMode.mixed);
    expect(result.hasSeededRows, isTrue);
    expect(result.items, hasLength(2));
    expect(
      result.items.map((item) => item.appliance.demoDeviceId),
      contains('demo-device-01'),
    );
    expect(
      result.items
          .singleWhere((item) => item.appliance.id == applianceId)
          .activeAttachmentIds,
      [attachmentId],
    );
  });

  test('rejects sample and household metering provenance mismatch', () async {
    for (final page in [
      const CloudMeteredSummaryPage(
        granularity: 'day',
        summaries: [],
        nextCursor: null,
      ),
      const CloudMeteredSummaryPage(
        granularity: 'day',
        summaries: [],
        nextCursor: null,
        dataMode: CloudApplianceDataMode.sample,
        fixtureRevision: 'another-fixture',
      ),
    ]) {
      await expectLater(
        DevicesDomainRepository(
          paged(
            (_, _) async => page,
            dataMode: CloudApplianceDataMode.sample,
            fixtureRevision: 'synthetic-household-v1',
          ),
        ).fetch(homeA),
        throwsFormatException,
      );
    }
    await expectLater(
      DevicesDomainRepository(
        paged(
          (_, _) async => const CloudMeteredSummaryPage(
            granularity: 'day',
            summaries: [],
            nextCursor: null,
            dataMode: CloudApplianceDataMode.sample,
            fixtureRevision: 'synthetic-household-v1',
          ),
        ),
      ).fetch(homeA),
      throwsFormatException,
    );
  });

  test('rejects changed fixture revision on a later metered page', () async {
    final source = paged(
      (_, cursor) async => CloudMeteredSummaryPage(
        granularity: 'day',
        summaries: const [],
        nextCursor: cursor == null ? 'next' : null,
        dataMode: CloudApplianceDataMode.sample,
        fixtureRevision: cursor == null
            ? 'synthetic-household-v1'
            : 'synthetic-household-v2',
      ),
      dataMode: CloudApplianceDataMode.sample,
      fixtureRevision: 'synthetic-household-v1',
    );
    await expectLater(
      DevicesDomainRepository(source).fetch(homeA),
      throwsFormatException,
    );
  });

  test('home switch discards pending sample metering', () async {
    final pendingPage = Completer<CloudMeteredSummaryPage>();
    final source = paged(
      (home, _) => home == homeA
          ? pendingPage.future
          : Future.value(
              const CloudMeteredSummaryPage(
                granularity: 'day',
                summaries: [],
                nextCursor: null,
                dataMode: CloudApplianceDataMode.sample,
                fixtureRevision: 'synthetic-household-v1',
              ),
            ),
      dataMode: CloudApplianceDataMode.sample,
      fixtureRevision: 'synthetic-household-v1',
    );
    final repository = DevicesDomainRepository(source);
    final old = repository.fetch(homeA);
    await Future<void>.delayed(Duration.zero);
    expect((await repository.fetch(homeB))?.homeId, homeB);
    pendingPage.complete(
      const CloudMeteredSummaryPage(
        granularity: 'day',
        summaries: [],
        nextCursor: null,
        dataMode: CloudApplianceDataMode.sample,
        fixtureRevision: 'synthetic-household-v1',
      ),
    );
    expect(await old, isNull);
  });

  test('home switch discards pending cursor response', () async {
    final oldPage = Completer<CloudMeteredSummaryPage>();
    final source = paged((home, cursor) {
      if (home == homeA && cursor != null) return oldPage.future;
      return Future.value(
        CloudMeteredSummaryPage(
          granularity: 'day',
          summaries: home == homeA ? [measured()] : const [],
          nextCursor: home == homeA ? 'next' : null,
        ),
      );
    });
    final repository = DevicesDomainRepository(source);
    final pending = repository.fetch(homeA);
    await Future<void>.delayed(Duration.zero);
    expect((await repository.fetch(homeB))?.homeId, homeB);
    oldPage.complete(
      const CloudMeteredSummaryPage(
        granularity: 'day',
        summaries: [],
        nextCursor: null,
      ),
    );
    expect(await pending, isNull);
  });

  test(
    'keeps exact measured bucket and all unsupported values unknown',
    () async {
      final result = await DevicesDomainRepository(fixed(nextCursor: 'more'))
          .fetch(homeA);
      expect(result?.homeId, homeA);
      expect(result?.dataMode, CloudApplianceDataMode.household);
      expect(result?.fixtureRevision, isNull);
      expect(result?.items, hasLength(1));
      final item = result!.items.single;
      expect(item.activeAttachmentIds, [attachmentId]);
      expect(item.measuredBuckets.single.energyWh, 1250);
      expect(item.measuredBuckets.single.coveredSeconds, 3600);
      expect(result.hasMoreMeteredPages, isFalse);
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

  test(
    'sample inventory cannot acquire household measurement or attachment',
    () async {
      final result = await DevicesDomainRepository(
        fixed(
          dataMode: CloudApplianceDataMode.sample,
          fixtureRevision: 'synthetic-household-v1',
        ),
      ).fetch(homeA);
      expect(result?.isSample, isTrue);
      expect(result?.fixtureRevision, 'synthetic-household-v1');
      expect(result?.items.single.activeAttachmentIds, isEmpty);
      expect(result?.items.single.measuredBuckets, isEmpty);
      expect(result?.hasMoreMeteredPages, isFalse);
      expect(result?.householdEnergyWh, isNull);
    },
  );

  test('rejects malformed source provenance', () async {
    await expectLater(
      DevicesDomainRepository(fixed(dataMode: CloudApplianceDataMode.sample))
          .fetch(homeA),
      throwsFormatException,
    );
    await expectLater(
      DevicesDomainRepository(fixed(fixtureRevision: 'wrong')).fetch(homeA),
      throwsFormatException,
    );
  });

  test('withholds unverified, conflicting and mismatched energy', () async {
    final source = fixed(
      summaries: [
        measured(status: 'overlap_conflict'),
        measured(method: 'duration_proportional', dayOffset: 1),
        measured(epoch: 99, dayOffset: 2),
        measured(
          attachment: '66666666-6666-4666-8666-666666666666',
          dayOffset: 3,
        ),
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
      summaryRead: (_, _) async => CloudMeteredSummaryPage(
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
        summaryRead: (_, _) async => CloudMeteredSummaryPage(
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
        summaryRead: (_, _) async => const CloudMeteredSummaryPage(
          granularity: 'day',
          summaries: [],
          nextCursor: null,
        ),
      ),
    );
    await expectLater(failing.fetch(homeA), throwsStateError);
  });

  test(
    'bounded local pages sort names with stable ID ties and filter',
    () async {
      final rows = [
        namedAppliance(homeA, 'z', 'Lamp'),
        namedAppliance(homeA, 'b', 'Fan'),
        namedAppliance(homeA, 'a', 'fan'),
      ];
      final result = (await DevicesDomainRepository(
        FakeSource(
          applianceRead: (_) async => rows,
          attachmentRead: (_) async => [],
          sensorRead: (_) async => [],
          summaryRead: (_, _) async => const CloudMeteredSummaryPage(
            granularity: 'day',
            summaries: [],
            nextCursor: null,
          ),
        ),
      ).fetch(homeA))!;
      final first = result.localPage(limit: 1);
      expect(first.items.single.appliance.id, 'a');
      expect(first.matchingCount, 3);
      expect(first.nextOffset, 1);
      expect(
        result
            .localPage(offset: first.nextOffset!, limit: 1)
            .items
            .single
            .appliance
            .id,
        'b',
      );
      expect(result.localPage(nameContains: ' la ').matchingCount, 1);
      expect(() => result.localPage(limit: 101), throwsRangeError);
      expect(() => result.localPage(offset: -1), throwsRangeError);
    },
  );

  test('observed energy sorts known first and remains non-global', () async {
    final rows = [
      appliance(homeA),
      namedAppliance(homeA, 'a', 'Unknown'),
      namedAppliance(homeA, 'b', 'Unknown'),
    ];
    final result = (await DevicesDomainRepository(
      FakeSource(
        applianceRead: (_) async => rows,
        attachmentRead: (_) async => [attachment(homeA)],
        sensorRead: (_) async => [sensor(homeA)],
        summaryRead: (_, cursor) async => CloudMeteredSummaryPage(
          granularity: 'day',
          summaries: cursor == null ? [measured()] : [],
          nextCursor: cursor == null ? 'more' : null,
        ),
      ),
    ).fetch(homeA))!;
    final page = result.localPage(
      sort: DeviceLocalSort.latestMeasuredBucketDesc,
    );
    expect(page.items.map((item) => item.appliance.id), [
      applianceId,
      'a',
      'b',
    ]);
    expect(page.isGlobalEnergyRanking, isFalse);
    expect(result.hasMoreMeteredPages, isFalse);
    expect(result.householdEnergyWh, isNull);
  });

  test('large inventory refuses local completeness', () async {
    final rows = List.generate(
      DevicesDomainSnapshot.maxLocalInventory,
      (index) => namedAppliance(homeA, 'id-$index', 'Appliance $index'),
    );
    Future<DevicesDomainSnapshot?> fetch(List<CloudAppliance> inventory) =>
        DevicesDomainRepository(
          FakeSource(
            applianceRead: (_) async => inventory,
            attachmentRead: (_) async => [],
            sensorRead: (_) async => [],
            summaryRead: (_, _) async => const CloudMeteredSummaryPage(
              granularity: 'day',
              summaries: [],
              nextCursor: null,
            ),
          ),
        ).fetch(homeA);
    expect(
      (await fetch(rows))?.items.length,
      DevicesDomainSnapshot.maxLocalInventory,
    );
    final overLimit = [...rows, namedAppliance(homeA, 'extra', 'Extra')];
    await expectLater(fetch(overLimit), throwsFormatException);
  });

  test('mutation and later evidence read invalidate earlier pages', () async {
    final repository = DevicesDomainRepository(fixed());
    final earlier = (await repository.fetch(homeA))!;
    expect(earlier.localPage().items, hasLength(1));
    final later = (await repository.fetch(homeA))!;
    expect(() => earlier.localPage(), throwsStateError);
    expect(later.localPage().items, hasLength(1));
    repository.invalidate();
    expect(() => later.localPage(), throwsStateError);
  });

  test('home switch invalidates already returned local pages', () async {
    final repository = DevicesDomainRepository(fixed());
    final previous = (await repository.fetch(homeA))!;
    await repository.fetch(homeB);
    expect(() => previous.localPage(), throwsStateError);
  });
}
