import 'package:energylens_mobile/core/cloud_api/cloud_tariff.dart';
import 'package:energylens_mobile/features/design/efficiency_peak_rates_adapter.dart';
import 'package:flutter_test/flutter_test.dart';

const homeA = '11111111-1111-4111-8111-111111111111';
const homeB = '22222222-2222-4222-8222-222222222222';
final now = DateTime.utc(2026, 10, 6);

CloudTariff _tariff({
  String home = homeA,
  String rate = '0.24',
  DateTime? sourceAsOf,
  DateTime? effectiveFrom,
  DateTime? effectiveTo,
}) => CloudTariff(
  homeId: home,
  rate: rate,
  sourceAsOf: sourceAsOf ?? DateTime.utc(2026, 9, 1),
  effectiveFrom: effectiveFrom ?? DateTime.utc(2026, 8, 1),
  effectiveTo: effectiveTo,
);

class _Source implements EfficiencyPeakRatesSource {
  _Source(this.tariffs);
  final List<CloudTariff> tariffs;
  String? requestedHome;

  @override
  Future<List<CloudTariff>> electricityTariffs(String homeId) async {
    requestedHome = homeId;
    return tariffs;
  }
}

void main() {
  test(
    'represents effective marginal tariff and leaves TOU unsupported',
    () async {
      final source = _Source([
        _tariff(
          rate: '0.19',
          effectiveFrom: DateTime.utc(2026, 1, 1),
          effectiveTo: DateTime.utc(2026, 8, 1),
        ),
        _tariff(rate: '0.24', effectiveFrom: DateTime.utc(2026, 8, 1)),
        _tariff(rate: '0.30', effectiveFrom: DateTime.utc(2026, 11, 1)),
      ]);

      final snapshot = await EfficiencyPeakRatesAdapter(
        source,
        clock: () => now,
      ).fetch(homeA);

      expect(source.requestedHome, homeA);
      expect(snapshot.status, EfficiencyTariffStatus.current);
      expect(snapshot.marginalRateUsdPerKwh, '0.24');
      expect(snapshot.effectiveFrom, DateTime.utc(2026, 8, 1));
      expect(snapshot.peakWindows, isNull);
      expect(snapshot.peakSavings, isNull);
    },
  );

  test('keeps effective tariff stale after its source date expires', () async {
    final adapter = EfficiencyPeakRatesAdapter(
      _Source([_tariff(sourceAsOf: DateTime.utc(2025, 4, 1))]),
      clock: () => now,
    );

    final snapshot = await adapter.fetch(homeA);

    expect(snapshot.status, EfficiencyTariffStatus.stale);
    expect(snapshot.marginalRateUsdPerKwh, isNull);
    expect(snapshot.sourceAsOf, DateTime.utc(2025, 4, 1));
  });

  test('expires a tariff exactly 60 days after source_as_of', () async {
    final boundary = now.subtract(const Duration(days: 60));
    final snapshot = await EfficiencyPeakRatesAdapter(
      _Source([_tariff(sourceAsOf: boundary)]),
      clock: () => now,
    ).fetch(homeA);

    expect(snapshot.status, EfficiencyTariffStatus.stale);
    expect(snapshot.marginalRateUsdPerKwh, isNull);
  });

  test('rejects a tariff with a future source date', () async {
    final adapter = EfficiencyPeakRatesAdapter(
      _Source([_tariff(sourceAsOf: now.add(const Duration(seconds: 1)))]),
      clock: () => now,
    );

    await expectLater(adapter.fetch(homeA), throwsFormatException);
  });

  test('rejects cross-home tariff evidence', () async {
    final adapter = EfficiencyPeakRatesAdapter(
      _Source([_tariff(home: homeB)]),
      clock: () => now,
    );

    await expectLater(adapter.fetch(homeA), throwsFormatException);
  });

  test('missing or only future tariff evidence stays unavailable', () async {
    for (final tariffs in <List<CloudTariff>>[
      const [],
      [_tariff(effectiveFrom: DateTime.utc(2026, 11, 1))],
    ]) {
      final snapshot = await EfficiencyPeakRatesAdapter(
        _Source(tariffs),
        clock: () => now,
      ).fetch(homeA);
      expect(snapshot.status, EfficiencyTariffStatus.unavailable);
      expect(snapshot.marginalRateUsdPerKwh, isNull);
      expect(snapshot.peakWindows, isNull);
      expect(snapshot.peakSavings, isNull);
    }
  });

  test('excludes a tariff whose effective period has ended', () async {
    final snapshot = await EfficiencyPeakRatesAdapter(
      _Source([_tariff(effectiveTo: DateTime.utc(2026, 10, 1))]),
      clock: () => now,
    ).fetch(homeA);

    expect(snapshot.status, EfficiencyTariffStatus.unavailable);
    expect(snapshot.marginalRateUsdPerKwh, isNull);
  });

  test('rejects overlapping effective electricity revisions', () async {
    final adapter = EfficiencyPeakRatesAdapter(
      _Source([
        _tariff(rate: '0.19', effectiveFrom: DateTime.utc(2026, 1, 1)),
        _tariff(rate: '0.24', effectiveFrom: DateTime.utc(2026, 8, 1)),
      ]),
      clock: () => now,
    );

    await expectLater(adapter.fetch(homeA), throwsFormatException);
  });
}
