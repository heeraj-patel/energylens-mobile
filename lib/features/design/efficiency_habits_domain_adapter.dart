import '../../core/cloud_api/cloud_household_energy.dart';
import '../../core/cloud_api/cloud_recommendations.dart';
import 'dashboard_domain_repository.dart';
import 'efficiency_domain_repository.dart';

/// Nonvisual projection for Efficiency Habits. It carries household energy
/// evidence and reviewed recommendation records without assigning routines.
class EfficiencyHabitsSnapshot {
  const EfficiencyHabitsSnapshot({
    required this.energy,
    required this.recommendations,
    this.efficiencySnapshot,
  });

  final DashboardDomainSnapshot energy;
  final List<CloudRecommendation> recommendations;
  final EfficiencyDomainSnapshot? efficiencySnapshot;

  String get homeId => energy.homeId;
  CloudEnergyAllocation get totals => energy.totals;
  List<CloudEnergyTrendBucket> get hourlyBuckets => energy.trends.buckets;

  /// No routine policy or supporting evidence currently supplies these.
  String? get routineClassification => null;
  String? get routineSavingsAmount => null;
}

/// Projects the shared Efficiency repository for the Habits domain.
/// Call [clear] on sign-out; stale home/page responses are discarded by the
/// underlying repository.
class EfficiencyHabitsDomainAdapter {
  const EfficiencyHabitsDomainAdapter(this.repository);

  final EfficiencyDomainRepository repository;

  void clear() => repository.clear();

  Future<EfficiencyHabitsSnapshot?> fetch(String homeId) async {
    final result = await repository.fetch(homeId, EfficiencyPage.habits);
    if (result == null) return null;
    return EfficiencyHabitsSnapshot(
      energy: result.energy,
      recommendations: result.recommendations,
      efficiencySnapshot: result,
    );
  }
}
