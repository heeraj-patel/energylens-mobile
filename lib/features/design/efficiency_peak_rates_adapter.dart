import '../../core/cloud_api/cloud_api_client.dart';
import '../../core/cloud_api/cloud_tariff.dart';
import 'efficiency_domain_repository.dart';

/// Reads the existing electricity tariff resource for Peak Rates.
/// The tariff API has no time-of-use schedule or peak attribution contract.
abstract interface class EfficiencyPeakRatesSource {
  Future<List<CloudTariff>> electricityTariffs(String homeId);
}

class CloudEfficiencyPeakRatesSource implements EfficiencyPeakRatesSource {
  const CloudEfficiencyPeakRatesSource(this.api);
  final CloudApiClient api;

  @override
  Future<List<CloudTariff>> electricityTariffs(String homeId) =>
      api.electricityTariffs(homeId);
}

enum EfficiencyTariffStatus { current, stale, unavailable }

class EfficiencyPeakRatesSnapshot {
  const EfficiencyPeakRatesSnapshot({
    required this.homeId,
    required this.status,
    required this.marginalRateUsdPerKwh,
    required this.sourceAsOf,
    required this.effectiveFrom,
    this.efficiencySnapshot,
  });

  final String homeId;
  final EfficiencyTariffStatus status;

  /// The currently effective marginal rate, when its bill source is recent.
  final String? marginalRateUsdPerKwh;
  final DateTime? sourceAsOf;
  final DateTime? effectiveFrom;
  final EfficiencyDomainSnapshot? efficiencySnapshot;

  /// Existing tariff data does not establish time-of-use windows or savings.
  String? get peakWindows => null;
  String? get peakSavings => null;
}

/// A conservative nonvisual adapter over the existing tariff API.
/// The tariff API's `source_as_of` is its available discovery/check date.
/// Rates expire 90 days after that date; future source dates are invalid.
class EfficiencyPeakRatesAdapter {
  EfficiencyPeakRatesAdapter(this.source, {DateTime Function()? clock})
    : _clock = clock ?? DateTime.now;

  final EfficiencyPeakRatesSource source;
  final DateTime Function() _clock;
  static final _uuid = RegExp(
    r'^[0-9a-fA-F]{8}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{12}$',
  );

  Future<EfficiencyPeakRatesSnapshot> fetch(String homeId) async {
    if (!_uuid.hasMatch(homeId)) throw ArgumentError.value(homeId, 'homeId');
    final now = _clock().toUtc();
    final tariffs = await source.electricityTariffs(homeId);
    if (tariffs.any(
      (tariff) => tariff.homeId.toLowerCase() != homeId.toLowerCase(),
    )) {
      throw const FormatException('Tariff belongs to another home');
    }
    if (tariffs.any((tariff) => tariff.sourceAsOf.toUtc().isAfter(now))) {
      throw const FormatException('Tariff source date is in the future');
    }

    final effective = tariffs
        .where(
          (tariff) =>
              !tariff.effectiveFrom.toUtc().isAfter(now) &&
              (tariff.effectiveTo == null ||
                  now.isBefore(tariff.effectiveTo!.toUtc())),
        )
        .toList();
    if (effective.isEmpty) {
      return EfficiencyPeakRatesSnapshot(
        homeId: homeId,
        status: EfficiencyTariffStatus.unavailable,
        marginalRateUsdPerKwh: null,
        sourceAsOf: null,
        effectiveFrom: null,
      );
    }
    // The cloud tariff list selects one effective revision per fuel. If an
    // alternate source returns overlapping revisions, choosing one locally
    // could silently claim the wrong current rate.
    if (effective.length != 1) {
      throw const FormatException('Ambiguous effective electricity tariff');
    }

    final tariff = effective.single;
    final sourceDate = tariff.sourceAsOf.toUtc();
    final isStale = !sourceDate.isAfter(now.subtract(electricityTariffLifetime));
    return EfficiencyPeakRatesSnapshot(
      homeId: homeId,
      status: isStale
          ? EfficiencyTariffStatus.stale
          : EfficiencyTariffStatus.current,
      marginalRateUsdPerKwh: isStale ? null : tariff.rate,
      sourceAsOf: sourceDate,
      effectiveFrom: tariff.effectiveFrom,
    );
  }
}
