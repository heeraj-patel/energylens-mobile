import 'package:energylens_mobile/features/design/demo_energy_tree.dart';
import 'package:flutter_test/flutter_test.dart';

const realApplianceId = 'aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa';
const homeId = '11111111-1111-4111-8111-111111111111';
const anotherHomeId = '22222222-2222-4222-8222-222222222222';

void main() {
  test('all 18 device leaves and home branches reconcile for every day', () {
    final month = buildSeptember2026DemoTree(homeId: homeId);
    expect(month.homeId, homeId);
    expect(month.days, hasLength(30));
    for (final day in month.days) {
      expect(day.homeId, homeId);
      expect(day.devices, hasLength(18));
      expect(day.devices.map((row) => row.deviceId).toSet(), hasLength(18));
      expect(day.devices.where((row) => row.name != null), hasLength(10));
      expect(day.devices.every((row) => row.cost.totalCents > 0), isTrue);
      expect(
        day.devices.every((row) => row.origin == DemoValueOrigin.mock),
        isTrue,
      );
      expect(day.devices.every((row) => row.period.sameAs(day.period)), isTrue);
      expect(day.unattributed.period.sameAs(day.period), isTrue);
      expect(
        day.homeCost.totalCents,
        day.devices
                .map((row) => row.cost.totalCents)
                .fold<int>(0, (a, b) => a + b) +
            day.unattributed.cost.totalCents,
      );
      expect(
        day.homeCost.totalCents,
        day.homeCost.usefulCents +
            day.homeCost.wasteCents +
            day.homeCost.unclassifiedCents,
      );
    }
    expect(month.homeCost.totalCents, 14230);
    expect(
      month.days.map((day) => day.homeCost.totalCents).reduce((a, b) => a + b),
      month.homeCost.totalCents,
    );
  });

  test('reference day derives page numbers from leaf values', () {
    final day = buildSeptember2026DemoTree(homeId: homeId).day('2026-09-30');
    expect(
      day.devices
          .take(10)
          .fold<int>(0, (sum, row) => sum + row.cost.usefulCents),
      667,
    );
    expect(
      day.devices
          .take(10)
          .fold<int>(0, (sum, row) => sum + row.cost.wasteCents),
      116,
    );
    expect(day.devicesCost.usefulCents, 683);
    expect(day.devicesCost.wasteCents, 196);
    expect(day.unattributed.cost.usefulCents, 13);
    expect(day.unattributed.cost.wasteCents, 92);
    expect(day.homeCost.usefulCents, 696);
    expect(day.homeCost.wasteCents, 288);
    expect(day.homeCost.totalCents, 984);
    expect(day.period.timezone, 'America/Chicago');
    expect(day.period.startUtc, DateTime.utc(2026, 9, 30, 5));
  });

  test(
    'complete priced measured leaf replaces one mock and updates parents',
    () {
      final month = buildSeptember2026DemoTree(homeId: homeId);
      final period = month.day('2026-09-30').period;
      final replacement = RealDeviceDay(
        homeId: homeId,
        deviceId: realApplianceId,
        period: period,
        coveredSeconds: period.seconds,
        usefulWh: 0,
        wasteWh: 0,
        unclassifiedWh: 5000,
        tariffRateUnitsPerKwh: 20000000,
        tariffId: 'tariff-revision-1',
        meterEvidenceId: 'meter-bucket-1',
      );
      final result = month.mergeMeasured(
        replacement,
        verifiedMockBranchId: 'demo-device-01',
        mappingEvidenceId: 'verified-identity-1',
      );
      final day = result.day('2026-09-30');
      final row = day.devices.first;
      expect(row.origin, DemoValueOrigin.measured);
      expect(row.energyWh, 5000);
      expect(row.cost.unclassifiedCents, 100);
      expect(row.tariffId, 'tariff-revision-1');
      expect(row.deviceId, realApplianceId);
      expect(row.mappedMockBranchId, 'demo-device-01');
      expect(row.mappingEvidenceId, 'verified-identity-1');
      expect(day.devicesCost.usefulCents, 615);
      expect(day.devicesCost.wasteCents, 161);
      expect(day.homeCost.unclassifiedCents, 100);
      expect(day.homeCost.totalCents, 981);
      expect(result.homeCost.totalCents, 14227);
      expect(month.homeCost.totalCents, 14230);
      expect(
        day.devices.skip(1).every((row) => row.origin == DemoValueOrigin.mock),
        isTrue,
      );
    },
  );

  test('rejects partial coverage and invented useful or waste allocation', () {
    final period = buildSeptember2026DemoTree(homeId: homeId)
        .day('2026-09-30')
        .period;
    RealDeviceDay reading({
      int? coverage,
      int usefulWh = 0,
      String? classificationEvidenceId,
    }) => RealDeviceDay(
      homeId: homeId,
      deviceId: realApplianceId,
      period: period,
      coveredSeconds: coverage ?? period.seconds,
      usefulWh: usefulWh,
      wasteWh: 0,
      unclassifiedWh: 5000,
      tariffRateUnitsPerKwh: 20000000,
      tariffId: 'tariff-revision-1',
      meterEvidenceId: 'meter-bucket-1',
      classificationEvidenceId: classificationEvidenceId,
    );
    expect(() => reading(coverage: 60), throwsFormatException);
    expect(() => reading(usefulWh: 1), throwsFormatException);
    expect(
      () => reading(usefulWh: 1, classificationEvidenceId: 'classifier-1'),
      returnsNormally,
    );
  });

  test('rejects a replacement for another date or device', () {
    final month = buildSeptember2026DemoTree(homeId: homeId);
    final period = month.day('2026-09-30').period;
    RealDeviceDay reading(String deviceId, DemoDayPeriod period) =>
        RealDeviceDay(
          homeId: homeId,
          deviceId: deviceId,
          period: period,
          coveredSeconds: period.seconds,
          usefulWh: 0,
          wasteWh: 0,
          unclassifiedWh: 1000,
          tariffRateUnitsPerKwh: 20000000,
          tariffId: 'tariff-1',
          meterEvidenceId: 'meter-1',
        );
    expect(
      () => month.mergeMeasured(
        reading(realApplianceId, period),
        verifiedMockBranchId: 'unknown',
        mappingEvidenceId: 'verified-1',
      ),
      throwsFormatException,
    );
    final outside = DemoDayPeriod(
      localDate: '2026-10-01',
      timezone: 'America/Chicago',
      startUtc: DateTime.utc(2026, 10, 1, 5),
      endUtc: DateTime.utc(2026, 10, 2, 5),
    );
    expect(
      () => month.mergeMeasured(reading(realApplianceId, outside)),
      throwsFormatException,
    );
  });

  test(
    'unmapped real branch adds to the home once and rejects a duplicate',
    () {
      final month = buildSeptember2026DemoTree(homeId: homeId);
      final period = month.day('2026-09-30').period;
      final reading = RealDeviceDay(
        homeId: homeId,
        deviceId: realApplianceId,
        period: period,
        coveredSeconds: period.seconds,
        usefulWh: 0,
        wasteWh: 0,
        unclassifiedWh: 5000,
        tariffRateUnitsPerKwh: 20000000,
        tariffId: 'tariff-1',
        meterEvidenceId: 'meter-1',
      );
      final merged = month.mergeMeasured(reading);
      final day = merged.day('2026-09-30');
      expect(day.devices, hasLength(19));
      expect(day.devices.last.name, isNull);
      expect(day.devices.last.origin, DemoValueOrigin.measured);
      expect(day.devices.last.cost.unclassifiedCents, 100);
      expect(day.unattributed.cost.totalCents, 105);
      expect(day.homeCost.totalCents, 1084);
      expect(merged.homeCost.totalCents, 14330);
      expect(() => merged.mergeMeasured(reading), throwsFormatException);
    },
  );

  test('unmapped real branch is not capped by unrelated mock cost', () {
    final month = buildSeptember2026DemoTree(homeId: homeId);
    final period = month.day('2026-09-30').period;
    final reading = RealDeviceDay(
      homeId: homeId,
      deviceId: realApplianceId,
      period: period,
      coveredSeconds: period.seconds,
      usefulWh: 0,
      wasteWh: 0,
      unclassifiedWh: 6000,
      tariffRateUnitsPerKwh: 20000000,
      tariffId: 'tariff-1',
      meterEvidenceId: 'meter-1',
    );
    expect(month.mergeMeasured(reading).homeCost.totalCents, 14350);
    expect(
      () =>
          month.mergeMeasured(reading, verifiedMockBranchId: 'demo-device-01'),
      throwsFormatException,
    );
  });

  test('home root rejects a measured reading from another home', () {
    final month = buildSeptember2026DemoTree(homeId: homeId);
    final period = month.day('2026-09-30').period;
    final reading = RealDeviceDay(
      homeId: anotherHomeId,
      deviceId: realApplianceId,
      period: period,
      coveredSeconds: period.seconds,
      usefulWh: 0,
      wasteWh: 0,
      unclassifiedWh: 1000,
      tariffRateUnitsPerKwh: 20000000,
      tariffId: 'tariff-2',
      meterEvidenceId: 'meter-2',
    );
    expect(() => month.mergeMeasured(reading), throwsFormatException);
    expect(
      () => month.day('2026-09-30').mergeMeasured(reading),
      throwsFormatException,
    );
    expect(month.homeCost.totalCents, 14230);
  });

  test('prices a fractional-cent tariff without truncating its rate', () {
    final period = buildSeptember2026DemoTree(homeId: homeId)
        .day('2026-09-30')
        .period;
    final reading = RealDeviceDay(
      homeId: homeId,
      deviceId: realApplianceId,
      period: period,
      coveredSeconds: period.seconds,
      usefulWh: 0,
      wasteWh: 0,
      unclassifiedWh: 1000,
      tariffRateUnitsPerKwh: 13524678, // $0.13524678/kWh
      tariffId: 'tariff-3',
      meterEvidenceId: 'meter-3',
    );
    expect(reading.toBranch().cost.unclassifiedCents, 14);
  });

  test(
    'low-draw dummy waste retains sub-cent daily value through month sum',
    () {
      var month = buildSeptember2026DemoTree(homeId: homeId);
      for (final day in month.days.toList()) {
        month = month.applyDummyWasteAfterKb(
          localDate: day.period.localDate,
          deviceId: realApplianceId,
          profileCategory: 'camera',
          durationEvidence: WasteDurationEvidence(
            seconds: day.period.seconds,
            evidenceId: 'duration-verified-1',
            intervalKind: WasteDurationIntervalKind.verifiedIdle,
          ),
          kbResult: KbWasteResult.wasteEvidenceUnavailableAfterKb,
          kbResultId: 'kb-final-1',
        );
      }
      final row = month.day('2026-09-30').devices.last;
      expect(row.origin, DemoValueOrigin.mock);
      expect(row.wasteProvenance, 'dummy_assumed_8h_after_kb_miss');
      expect(row.kbWasteResultId, 'kb-final-1');
      expect(row.wasteDurationEvidenceId, 'duration-verified-1');
      expect(row.cost.wasteMicros, 800);
      expect(row.cost.wasteCents, 0);
      expect(
        month.homeCost.wasteMicros,
        30 * 800 +
            buildSeptember2026DemoTree(homeId: homeId).homeCost.wasteMicros,
      );
      expect(
        month.homeCost.wasteCents,
        buildSeptember2026DemoTree(homeId: homeId).homeCost.wasteCents + 2,
      );
    },
  );

  test(
    'high-draw fallback allocates measured cost without increasing home total',
    () {
      final original = buildSeptember2026DemoTree(homeId: homeId);
      final period = original.day('2026-09-30').period;
      final measured = original.mergeMeasured(
        RealDeviceDay(
          homeId: homeId,
          deviceId: realApplianceId,
          period: period,
          coveredSeconds: period.seconds,
          usefulWh: 0,
          wasteWh: 0,
          unclassifiedWh: 5000,
          tariffRateUnitsPerKwh: 20000000,
          tariffId: 'tariff-1',
          meterEvidenceId: 'meter-1',
        ),
        verifiedMockBranchId: 'demo-device-01',
        mappingEvidenceId: 'verified-1',
      );
      final result = measured.applyDummyWasteAfterKb(
        localDate: '2026-09-30',
        deviceId: realApplianceId,
        profileCategory: 'dryer',
        durationEvidence: WasteDurationEvidence(
          seconds: period.seconds,
          evidenceId: 'duration-verified-1',
          intervalKind: WasteDurationIntervalKind.verifiedOff,
        ),
        kbResult: KbWasteResult.wasteEvidenceUnavailableAfterKb,
        kbResultId: 'kb-final-2',
      );
      final row = result.day('2026-09-30').devices.first;
      expect(row.origin, DemoValueOrigin.measured);
      expect(row.sourceId, 'meter-1');
      expect(row.wasteDurationEvidenceId, 'duration-verified-1');
      expect(row.cost.wasteMicros, 80000);
      expect(row.cost.unclassifiedMicros, 920000);
      expect(row.cost.totalMicros, 1000000);
      expect(
        result
            .day('2026-09-30')
            .devices
            .skip(1)
            .every((branch) => branch.origin == DemoValueOrigin.mock),
        isTrue,
      );
      expect(result.homeCost.totalMicros, measured.homeCost.totalMicros);
      expect(
        result.homeCost.wasteMicros - measured.homeCost.wasteMicros,
        80000,
      );
      expect(
        result.homeCost.unclassifiedMicros -
            measured.homeCost.unclassifiedMicros,
        -80000,
      );
    },
  );

  test('continuous device profiles receive no assumed idle allocation', () {
    final month = buildSeptember2026DemoTree(homeId: homeId);
    final result = month.applyDummyWasteAfterKb(
      localDate: '2026-09-30',
      deviceId: realApplianceId,
      profileCategory: 'refrigerator',
      kbResult: KbWasteResult.wasteEvidenceUnavailableAfterKb,
      kbResultId: 'kb-final-continuous',
    );
    expect(
      result
          .day('2026-09-30')
          .devices
          .any((row) => row.deviceId == realApplianceId),
      isFalse,
    );
    expect(result.homeCost.totalMicros, month.homeCost.totalMicros);
  });

  test(
    'caps dummy allocation and requires final KB decision and known profile',
    () {
      final month = buildSeptember2026DemoTree(homeId: homeId);
      final period = month.day('2026-09-30').period;
      final measured = month.mergeMeasured(
        RealDeviceDay(
          homeId: homeId,
          deviceId: realApplianceId,
          period: period,
          coveredSeconds: period.seconds,
          usefulWh: 0,
          wasteWh: 0,
          unclassifiedWh: 50,
          tariffRateUnitsPerKwh: 20000000,
          tariffId: 'tariff-1',
          meterEvidenceId: 'meter-1',
        ),
      );
      DemoMonthTree apply(KbWasteResult result, String profile) =>
          measured.applyDummyWasteAfterKb(
            localDate: '2026-09-30',
            deviceId: realApplianceId,
            profileCategory: profile,
            durationEvidence: WasteDurationEvidence(
              seconds: period.seconds,
              evidenceId: 'duration-verified-1',
              intervalKind: WasteDurationIntervalKind.verifiedOff,
            ),
            kbResult: result,
            kbResultId: 'kb-final-3',
          );
      expect(
        () => apply(KbWasteResult.pending, 'dryer'),
        throwsFormatException,
      );
      expect(
        () => apply(KbWasteResult.reviewedEvidence, 'dryer'),
        throwsFormatException,
      );
      expect(
        () => apply(KbWasteResult.wasteEvidenceUnavailableAfterKb, 'other'),
        throwsFormatException,
      );
      expect(dummyWasteDrawForProfile('sensor'), isNull);
      expect(dummyWasteDrawForProfile('freezer'), isNull);
      expect(dummyWasteDrawForProfile('modem'), isNull);
      expect(
        () => WasteDurationEvidence(
          seconds: 0,
          evidenceId: 'duration-verified-1',
          intervalKind: WasteDurationIntervalKind.verifiedOff,
        ),
        throwsFormatException,
      );
      expect(
        () => WasteDurationEvidence(
          seconds: 1,
          evidenceId: ' ',
          intervalKind: WasteDurationIntervalKind.verifiedIdle,
        ),
        throwsFormatException,
      );
      final capped = apply(
        KbWasteResult.wasteEvidenceUnavailableAfterKb,
        'dryer',
      );
      expect(capped.day('2026-09-30').devices.last.cost.wasteMicros, 10000);
      expect(capped.day('2026-09-30').devices.last.cost.unclassifiedMicros, 0);
      expect(capped.homeCost.totalMicros, measured.homeCost.totalMicros);
      expect(
        () => capped.applyDummyWasteAfterKb(
          localDate: '2026-09-30',
          deviceId: realApplianceId,
          profileCategory: 'dryer',
          durationEvidence: WasteDurationEvidence(
            seconds: period.seconds,
            evidenceId: 'duration-verified-1',
            intervalKind: WasteDurationIntervalKind.verifiedOff,
          ),
          kbResult: KbWasteResult.wasteEvidenceUnavailableAfterKb,
          kbResultId: 'kb-final-3',
        ),
        throwsFormatException,
      );
      expect(
        () => month.applyDummyWasteAfterKb(
          localDate: '2026-09-30',
          deviceId: realApplianceId,
          profileCategory: 'router',
          durationEvidence: WasteDurationEvidence(
            seconds: period.seconds + 1,
            evidenceId: 'duration-verified-2',
            intervalKind: WasteDurationIntervalKind.verifiedOff,
          ),
          kbResult: KbWasteResult.wasteEvidenceUnavailableAfterKb,
          kbResultId: 'kb-final-3',
        ),
        throwsFormatException,
      );
    },
  );

  test(
    'October 2026 uses 31 local days and accepts its reference-day reading',
    () {
      final month = buildDemoMonthTree(
        homeId: homeId,
        year: 2026,
        month: 10,
        timezone: 'America/Chicago',
        referenceDay: 7,
      );
      expect(month.referenceLocalDate, '2026-10-07');
      expect(month.days, hasLength(31));
      expect(month.day('2026-10-07').homeCost.totalCents, 984);
      expect(month.homeCost.totalCents, 14686);
      expect(
        month.day('2026-10-07').period.startUtc,
        DateTime.utc(2026, 10, 7, 5),
      );
      final period = month.day('2026-10-07').period;
      final reading = RealDeviceDay(
        homeId: homeId,
        deviceId: realApplianceId,
        period: period,
        coveredSeconds: period.seconds,
        usefulWh: 0,
        wasteWh: 0,
        unclassifiedWh: 1000,
        tariffRateUnitsPerKwh: 20000000,
        tariffId: 'tariff-october',
        meterEvidenceId: 'meter-october',
      );
      expect(month.mergeMeasured(reading).homeCost.totalCents, 14706);
    },
  );

  test('calendar builder respects DST and shorter months', () {
    DemoMonthTree month(int year, int number, int referenceDay) =>
        buildDemoMonthTree(
          homeId: homeId,
          year: year,
          month: number,
          timezone: 'America/Chicago',
          referenceDay: referenceDay,
        );
    final fall = month(2026, 11, 1);
    expect(fall.days, hasLength(30));
    expect(fall.day('2026-11-01').period.seconds, 90000);
    expect(fall.day('2026-11-02').period.seconds, 86400);
    final spring = month(2026, 3, 8);
    expect(spring.days, hasLength(31));
    expect(spring.day('2026-03-08').period.seconds, 82800);
    final february = month(2027, 2, 15);
    expect(february.days, hasLength(28));
    expect(february.homeCost.totalCents, 13318);
  });
}
