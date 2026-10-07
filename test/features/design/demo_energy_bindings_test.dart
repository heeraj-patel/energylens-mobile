import 'package:energylens_mobile/features/design/demo_energy_bindings.dart';
import 'package:energylens_mobile/features/design/demo_energy_tree.dart';
import 'package:flutter_test/flutter_test.dart';

const homeId = '11111111-1111-4111-8111-111111111111';
const realDeviceId = 'aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa';

void main() {
  test('binds September sample totals to existing page IDs', () {
    final tree = buildSeptember2026DemoTree(homeId: homeId);

    final dashboard = DemoEnergyBindings.forPage(
      tree: tree,
      homeId: homeId,
      page: 'dashboard',
      period: 'day',
      localDate: '2026-09-30',
      referenceLocalDate: '2026-09-30',
    );
    expect(dashboard.bindings.map((binding) => binding.id), [
      'dashboard_text_006',
      'dashboard_text_009',
    ]);
    expect(dashboard.bindings.map((binding) => binding.text), [
      r'$6.96',
      r'$2.88',
    ]);

    final devices = DemoEnergyBindings.forPage(
      tree: tree,
      homeId: homeId,
      page: 'devices',
      period: 'day',
      localDate: '2026-09-30',
      referenceLocalDate: '2026-09-30',
    );
    expect(devices.bindings.map((binding) => binding.id), [
      'devices_text_006',
      'devices_text_009',
    ]);
    expect(devices.bindings.map((binding) => binding.text), [
      r'$1.96',
      r'$6.83',
    ]);

    final efficiency = DemoEnergyBindings.forPage(
      tree: tree,
      homeId: homeId,
      page: 'efficiency',
      period: 'month',
      localDate: '2026-09',
      referenceLocalDate: '2026-09-30',
    );
    expect(efficiency.bindings.single.id, 'efficiency_text_009');
    expect(efficiency.bindings.single.text, r'$142.30');
  });

  test('binds a dynamically built October tree by its own dates and month', () {
    final tree = buildDemoMonthTree(
      homeId: homeId,
      year: 2026,
      month: 10,
      timezone: 'America/Chicago',
      referenceDay: 7,
    );

    final dashboard = DemoEnergyBindings.forPage(
      tree: tree,
      homeId: homeId,
      page: 'dashboard',
      period: 'day',
      localDate: tree.referenceLocalDate,
      referenceLocalDate: tree.referenceLocalDate,
    );
    expect(dashboard.bindings.map((binding) => binding.text), [
      r'$6.96',
      r'$2.88',
    ]);
    final efficiency = DemoEnergyBindings.forPage(
      tree: tree,
      homeId: homeId,
      page: 'efficiency',
      period: 'month',
      localDate: '2026-10',
      referenceLocalDate: tree.referenceLocalDate,
    );
    expect(efficiency.bindings.single.id, 'efficiency_text_009');
    expect(efficiency.bindings.single.text, r'$37.42');
    expect(efficiency.bindings.single.text, isNot(r'$146.86'));
  });

  test('real mapped leaf changes day and month aggregates', () {
    final tree = buildSeptember2026DemoTree(homeId: homeId);
    final day = tree.day('2026-09-30');
    final reading = RealDeviceDay(
      homeId: homeId,
      deviceId: realDeviceId,
      period: day.period,
      coveredSeconds: day.period.seconds,
      usefulWh: 1000,
      wasteWh: 500,
      unclassifiedWh: 0,
      tariffRateUnitsPerKwh: 20000000,
      tariffId: 'verified-tariff',
      meterEvidenceId: 'meter-day-30',
      classificationEvidenceId: 'classification-day-30',
    );
    final merged = tree.mergeMeasured(
      reading,
      verifiedMockBranchId: day.devices.first.deviceId,
      mappingEvidenceId: 'verified-device-map',
    );

    final dashboard = DemoEnergyBindings.forPage(
      tree: merged,
      homeId: homeId,
      page: 'dashboard',
      period: 'day',
      localDate: '2026-09-30',
      referenceLocalDate: '2026-09-30',
    );
    expect(dashboard.bindings.map((binding) => binding.text), [
      r'$6.48',
      r'$2.63',
    ]);
    final efficiency = DemoEnergyBindings.forPage(
      tree: merged,
      homeId: homeId,
      page: 'efficiency',
      period: 'month',
      localDate: '2026-09',
      referenceLocalDate: '2026-09-30',
    );
    expect(efficiency.bindings.single.text, r'$141.57');
  });

  test('rejects mismatched home, date, and period', () {
    final tree = buildSeptember2026DemoTree(homeId: homeId);
    expect(
      () => DemoEnergyBindings.forPage(
        tree: tree,
        homeId: '22222222-2222-4222-8222-222222222222',
        page: 'dashboard',
        period: 'day',
        localDate: '2026-09-30',
        referenceLocalDate: '2026-09-30',
      ),
      throwsFormatException,
    );
    expect(
      () => DemoEnergyBindings.forPage(
        tree: tree,
        homeId: homeId,
        page: 'dashboard',
        period: 'week',
        localDate: '2026-09-30',
        referenceLocalDate: '2026-09-30',
      ),
      throwsFormatException,
    );
    expect(
      () => DemoEnergyBindings.forPage(
        tree: tree,
        homeId: homeId,
        page: 'devices',
        period: 'day',
        localDate: '2026-10-01',
        referenceLocalDate: '2026-10-01',
      ),
      throwsFormatException,
    );
  });

  test(
    'binds mapped illustrative split and gates unknown distinct real cost',
    () {
      final mock = buildSeptember2026DemoTree(homeId: homeId);
      final day = mock.day('2026-09-30');
      final mapped = mock.mergeMeasured(
        RealDeviceDay(
          homeId: homeId,
          deviceId: realDeviceId,
          period: day.period,
          coveredSeconds: day.period.seconds,
          usefulWh: 0,
          wasteWh: 0,
          unclassifiedWh: 2000,
          tariffRateUnitsPerKwh: 20000000,
          tariffId: 'verified-tariff',
          meterEvidenceId: 'meter-day-30',
        ),
        verifiedMockBranchId: day.devices.first.deviceId,
        mappingEvidenceId: 'verified-device-map',
      );
      final shown = DemoEnergyBindings.forPage(
        tree: mapped,
        homeId: homeId,
        page: 'dashboard',
        period: 'day',
        localDate: '2026-09-30',
        referenceLocalDate: '2026-09-30',
      );
      expect(shown.bindings, hasLength(2));
      expect(mapped.day('2026-09-30').devices.first.cost.unclassifiedCents, 40);

      final unknown = mapped.mergeMeasured(
        RealDeviceDay(
          homeId: homeId,
          deviceId: 'bbbbbbbb-bbbb-4bbb-8bbb-bbbbbbbbbbbb',
          period: day.period,
          coveredSeconds: day.period.seconds,
          usefulWh: 0,
          wasteWh: 0,
          unclassifiedWh: 1000,
          tariffRateUnitsPerKwh: 20000000,
          tariffId: 'verified-tariff',
          meterEvidenceId: 'meter-unknown',
        ),
      );
      expect(
        () => DemoEnergyBindings.forPage(
          tree: unknown,
          homeId: homeId,
          page: 'dashboard',
          period: 'day',
          localDate: '2026-09-30',
          referenceLocalDate: '2026-09-30',
        ),
        throwsFormatException,
      );
    },
  );
}
