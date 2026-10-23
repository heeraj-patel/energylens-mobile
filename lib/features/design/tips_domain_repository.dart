import '../../core/cloud_api/cloud_api_client.dart';
import '../../core/cloud_api/cloud_appliance.dart';
import '../../core/cloud_api/cloud_estimate.dart';
import '../../core/cloud_api/cloud_programs.dart';
import '../../core/cloud_api/cloud_recommendations.dart';

/// Source records for the three Tips pages. None of these reads has a shared
/// snapshot token, so the adapter does not derive totals or savings from them.
abstract interface class TipsDomainSource {
  Future<List<CloudAppliance>> appliances(String homeId);
  Future<CloudProgramPage> programs(String homeId);
  Future<CloudRecommendationBatch> recommendations(
    String homeId,
    Set<String> applianceIds,
  );
  Future<CloudEstimateBatch> estimates(String homeId);
}

class CloudTipsDomainSource implements TipsDomainSource {
  const CloudTipsDomainSource(this.api);
  final CloudApiClient api;

  @override
  Future<List<CloudAppliance>> appliances(String homeId) =>
      api.appliances(homeId);
  @override
  Future<CloudProgramPage> programs(String homeId) => api.homePrograms(homeId);
  @override
  Future<CloudRecommendationBatch> recommendations(
    String homeId,
    Set<String> applianceIds,
  ) => api.recommendations(homeId, applianceIds);
  @override
  Future<CloudEstimateBatch> estimates(String homeId) => api.estimates(homeId);
}

enum TipsPage { perksTips, efficiency, careUpgrades }

class TipsDomainSnapshot {
  const TipsDomainSnapshot({
    required this.homeId,
    required this.page,
    required this.programs,
    required this.recommendations,
    this.applianceNames = const {},
    this.applianceFuels = const {},
    required this.operatingEstimates,
    this.weather,
  });

  final String homeId;
  final TipsPage page;

  /// Reviewed candidates retain their original unknown/potential status.
  final CloudProgramPage? programs;

  /// Rule and appliance identity are retained; no new eligibility is inferred.
  final List<CloudRecommendation> recommendations;
  final Map<String, String> applianceNames;

  /// Lowercase appliance id to its fuel string.
  final Map<String, String> applianceFuels;

  /// These are operating estimates, never proposed savings.
  final List<CloudEstimate> operatingEstimates;

  /// Weather block of the recommendations read; null when absent.
  final CloudWeather? weather;

  String? get promotion => null;
  String? get savingsAmount => null;
  String? get eligibility => null;
}

/// Bounded nonvisual composition for perks_tips, tips_efficiency and
/// tips_care_upgrades. A caller must clear this repository on sign-out.
class TipsDomainRepository {
  TipsDomainRepository(this.source);
  final TipsDomainSource source;
  String? _homeId;
  int _generation = 0;

  void clear() {
    _homeId = null;
    _generation++;
  }

  Future<TipsDomainSnapshot?> fetch(String homeId, TipsPage page) async {
    if (!_uuid.hasMatch(homeId)) throw ArgumentError.value(homeId, 'homeId');
    _homeId = homeId;
    final generation = ++_generation;
    bool stale() => generation != _generation || _homeId != homeId;

    try {
      final appliances = await source.appliances(homeId);
      if (stale()) return null;
      final ids = <String>{};
      for (final appliance in appliances) {
        if (appliance.homeId.toLowerCase() != homeId.toLowerCase() ||
            !ids.add(appliance.id.toLowerCase())) {
          throw const FormatException('Invalid Tips appliance inventory');
        }
      }

      final results = await Future.wait<Object>([
        source.recommendations(homeId, ids),
        if (page == TipsPage.perksTips) source.programs(homeId),
        if (page != TipsPage.perksTips) source.estimates(homeId),
      ]);
      if (stale()) return null;
      final batch = results[0] as CloudRecommendationBatch;
      if (batch.actions.any(
        (action) => !ids.contains(action.applianceId.toLowerCase()),
      )) {
        throw const FormatException('Recommendation is outside home inventory');
      }
      final programs = page == TipsPage.perksTips
          ? results[1] as CloudProgramPage
          : null;
      final estimates = page == TipsPage.perksTips
          ? <CloudEstimate>[]
          : (results[1] as CloudEstimateBatch).estimates;
      if (estimates.any(
        (estimate) => !ids.contains(estimate.applianceId.toLowerCase()),
      )) {
        throw const FormatException('Estimate is outside home inventory');
      }

      return TipsDomainSnapshot(
        homeId: homeId,
        page: page,
        programs: programs,
        recommendations: List.unmodifiable(batch.actions),
        applianceNames: Map.unmodifiable({
          for (final appliance in appliances)
            appliance.id.toLowerCase(): appliance.name,
        }),
        applianceFuels: Map.unmodifiable({
          for (final appliance in appliances)
            appliance.id.toLowerCase(): appliance.fuel,
        }),
        operatingEstimates: List.unmodifiable(estimates),
        weather: batch.weather,
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
