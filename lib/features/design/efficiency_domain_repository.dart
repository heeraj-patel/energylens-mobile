import '../../core/cloud_api/cloud_api_client.dart';
import '../../core/cloud_api/cloud_appliance.dart';
import '../../core/cloud_api/cloud_estimate.dart';
import '../../core/cloud_api/cloud_household_energy.dart';
import '../../core/cloud_api/cloud_recommendations.dart';
import 'dashboard_domain_repository.dart';

/// The four Efficiency routes share one evidence-backed, nonvisual model.
/// No existing response allocates savings to Away, Peak, or Habits.
enum EfficiencyPage { overview, away, peak, habits }

abstract interface class EfficiencyDomainSource
    implements DashboardDomainSource {
  Future<List<CloudAppliance>> appliances(String homeId);
  Future<CloudEstimateBatch> estimates(String homeId);
  Future<CloudRecommendationBatch> recommendations(
    String homeId,
    Set<String> applianceIds,
  );
}

abstract interface class EfficiencyRollingDomainSource {
  Future<CloudHouseholdEnergyTrends> rolling30Days(String homeId);
}

class CloudEfficiencyDomainSource
    implements EfficiencyDomainSource, EfficiencyRollingDomainSource {
  const CloudEfficiencyDomainSource(this.api);
  final CloudApiClient api;

  @override
  Future<CloudHouseholdDashboard> dashboard(String homeId) =>
      api.householdDashboard(homeId);
  @override
  Future<CloudHouseholdEnergyTrends> trends(String homeId) =>
      api.householdEnergyTrends(homeId, granularity: 'hour');
  @override
  Future<CloudHouseholdEnergyTrends> rolling30Days(String homeId) =>
      api.householdEnergyTrends(
        homeId,
        granularity: 'day',
        window: 'trailing_30_days',
      );
  @override
  Future<List<CloudAppliance>> appliances(String homeId) =>
      api.appliances(homeId);
  @override
  Future<CloudEstimateBatch> estimates(String homeId) => api.estimates(homeId);
  @override
  Future<CloudRecommendationBatch> recommendations(
    String homeId,
    Set<String> applianceIds,
  ) => api.recommendations(homeId, applianceIds);
}

class EfficiencyDomainSnapshot {
  const EfficiencyDomainSnapshot({
    required this.page,
    required this.energy,
    required this.operatingEstimates,
    required this.recommendations,
    this.rolling30Days,
  });

  final EfficiencyPage page;

  /// Dashboard and hourly trends have a verified shared snapshot, period,
  /// scope, and totals. Waste allocation, if present, is not a savings claim.
  final DashboardDomainSnapshot energy;

  /// Independent appliance records have no shared household snapshot token.
  /// Their periods and currencies must not be summed into household totals.
  final List<CloudEstimate> operatingEstimates;
  final List<CloudRecommendation> recommendations;
  final CloudHouseholdEnergyTrends? rolling30Days;

  String get homeId => energy.homeId;
  CloudEnergyAllocation get totals => energy.totals;
  List<CloudEnergyTrendBucket> get hourlyBuckets => energy.trends.buckets;

  String? get opportunityAmount => null;
  String? get awaySavingsAmount => null;
  String? get peakSavingsAmount => null;
  String? get habitsSavingsAmount => null;
  String? get awayOccupancyEvidence => null;
  String? get timeOfUseRate => null;
}

/// A caller must clear this repository at sign-out. Each fetch invalidates
/// earlier responses, including a response for the same home and another page.
class EfficiencyDomainRepository {
  EfficiencyDomainRepository(this.source)
    : _energy = DashboardDomainRepository(source);

  final EfficiencyDomainSource source;
  final DashboardDomainRepository _energy;
  String? _homeId;
  int _generation = 0;

  void clear() {
    _homeId = null;
    _generation++;
    _energy.clear();
  }

  Future<EfficiencyDomainSnapshot?> fetch(
    String homeId,
    EfficiencyPage page,
  ) async {
    if (!_uuid.hasMatch(homeId)) throw ArgumentError.value(homeId, 'homeId');
    _homeId = homeId;
    final generation = ++_generation;
    bool stale() => generation != _generation || _homeId != homeId;

    try {
      final energy = await _energy.fetch(homeId);
      if (stale() || energy == null) return null;
      final appliances = await source.appliances(homeId);
      if (stale()) return null;
      final ids = <String>{};
      for (final appliance in appliances) {
        if (appliance.homeId.toLowerCase() != homeId.toLowerCase() ||
            !ids.add(appliance.id.toLowerCase())) {
          throw const FormatException('Invalid Efficiency appliance inventory');
        }
      }
      final rollingSource = source is EfficiencyRollingDomainSource
          ? source as EfficiencyRollingDomainSource
          : null;
      final rollingRead =
          page == EfficiencyPage.overview && rollingSource != null
          ? rollingSource
                .rolling30Days(homeId)
                .then<CloudHouseholdEnergyTrends?>((value) => value)
                .catchError((Object _) => null)
          : Future<CloudHouseholdEnergyTrends?>.value(null);
      final results = await Future.wait<Object?>([
        source.estimates(homeId),
        source.recommendations(homeId, ids),
        rollingRead,
      ]);
      if (stale()) return null;
      final estimates = (results[0] as CloudEstimateBatch).estimates;
      final recommendations = (results[1] as CloudRecommendationBatch).actions;
      if (estimates.any(
            (estimate) =>
                !ids.contains(estimate.applianceId.toLowerCase()) ||
                !_validEstimatePeriod(estimate.period),
          ) ||
          recommendations.any(
            (action) => !ids.contains(action.applianceId.toLowerCase()),
          )) {
        throw const FormatException('Invalid Efficiency appliance evidence');
      }
      return EfficiencyDomainSnapshot(
        page: page,
        energy: energy,
        operatingEstimates: List.unmodifiable(estimates),
        recommendations: List.unmodifiable(recommendations),
        rolling30Days: results[2] as CloudHouseholdEnergyTrends?,
      );
    } catch (_) {
      if (stale()) return null;
      rethrow;
    }
  }
}

final _uuid = RegExp(
  r'^[0-9a-fA-F]{8}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{12}$',
);

bool _validEstimatePeriod(CloudEstimatePeriod period) {
  final start = DateTime.tryParse(period.start);
  final end = DateTime.tryParse(period.end);
  return period.timezone.trim().isNotEmpty &&
      start != null &&
      end != null &&
      start.isBefore(end);
}
