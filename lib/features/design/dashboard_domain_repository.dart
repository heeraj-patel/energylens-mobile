import '../../core/cloud_api/cloud_api_client.dart';
import '../../core/cloud_api/cloud_household_energy.dart';

/// Native data source for the Dashboard page. It uses the same typed client in
/// household and isolated sample mode; it does not render or change the page.
abstract interface class DashboardDomainSource {
  Future<CloudHouseholdDashboard> dashboard(String homeId);
  Future<CloudHouseholdEnergyTrends> trends(String homeId);
}

class CloudDashboardDomainSource implements DashboardDomainSource {
  const CloudDashboardDomainSource(this.api);
  final CloudApiClient api;

  @override
  Future<CloudHouseholdDashboard> dashboard(String homeId) =>
      api.householdDashboard(homeId);

  @override
  Future<CloudHouseholdEnergyTrends> trends(String homeId) =>
      api.householdEnergyTrends(homeId, granularity: 'hour');
}

class DashboardDomainSnapshot {
  const DashboardDomainSnapshot(this.dashboard, this.trends, {this.isCurrent});
  final CloudHouseholdDashboard dashboard;
  final CloudHouseholdEnergyTrends trends;
  final bool Function()? isCurrent;

  String get homeId => dashboard.homeId;
  String get snapshotId => dashboard.snapshotId;
  String get dataMode => dashboard.dataMode;
  CloudEnergyAllocation get totals => dashboard.totals;

  bool matchesHomeAndSnapshot(String homeId) =>
      (isCurrent?.call() ?? false) && _sameSnapshot(dashboard, trends, homeId);
}

/// Invalidates pending reads when navigation, home switch or sign-out occurs.
/// A renderer may consume a returned snapshot only after its presentation is
/// approved; null means the request became stale.
class DashboardDomainRepository {
  DashboardDomainRepository(this.source);
  final DashboardDomainSource source;
  String? _homeId;
  int _generation = 0;

  void clear() {
    _homeId = null;
    _generation++;
  }

  Future<DashboardDomainSnapshot?> fetch(String homeId) async {
    if (!_uuid.hasMatch(homeId)) throw ArgumentError.value(homeId, 'homeId');
    _homeId = homeId;
    final generation = ++_generation;
    bool stale() => generation != _generation || _homeId != homeId;
    try {
      final results = await Future.wait<Object>([
        source.dashboard(homeId),
        source.trends(homeId),
      ]);
      if (stale()) return null;
      final dashboard = results[0] as CloudHouseholdDashboard;
      final trends = results[1] as CloudHouseholdEnergyTrends;
      if (!_sameSnapshot(dashboard, trends, homeId)) {
        throw const FormatException('Dashboard and trends disagree');
      }
      return DashboardDomainSnapshot(
        dashboard,
        trends,
        isCurrent: () => !stale(),
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

bool _sameSnapshot(
  CloudHouseholdDashboard dashboard,
  CloudHouseholdEnergyTrends trends,
  String homeId,
) {
  final d = dashboard.metadata;
  final t = trends.metadata;
  return d.homeId.toLowerCase() == homeId.toLowerCase() &&
      t.homeId.toLowerCase() == homeId.toLowerCase() &&
      d.snapshotId == t.snapshotId &&
      d.schemaRevision == t.schemaRevision &&
      d.contentRevision == t.contentRevision &&
      d.dataMode == t.dataMode &&
      d.fixtureRevision == t.fixtureRevision &&
      d.timezone == t.timezone &&
      d.scope == t.scope &&
      d.period.start.isAtSameMomentAs(t.period.start) &&
      d.period.endExclusive.isAtSameMomentAs(t.period.endExclusive) &&
      d.availability == t.availability &&
      d.evidenceBasis == t.evidenceBasis &&
      trends.granularity == 'hour' &&
      _sameAllocation(dashboard.totals, trends.totals);
}

bool _sameAllocation(CloudEnergyAllocation a, CloudEnergyAllocation b) =>
    a.energy?.value == b.energy?.value &&
    a.cost?.amount == b.cost?.amount &&
    a.cost?.currency == b.cost?.currency &&
    a.usefulEnergy?.value == b.usefulEnergy?.value &&
    a.usefulCost?.amount == b.usefulCost?.amount &&
    a.usefulCost?.currency == b.usefulCost?.currency &&
    a.wasteEnergy?.value == b.wasteEnergy?.value &&
    a.wasteCost?.amount == b.wasteCost?.amount &&
    a.wasteCost?.currency == b.wasteCost?.currency &&
    a.unclassifiedEnergy?.value == b.unclassifiedEnergy?.value &&
    a.unclassifiedCost?.amount == b.unclassifiedCost?.amount &&
    a.unclassifiedCost?.currency == b.unclassifiedCost?.currency &&
    a.availability == b.availability &&
    a.evidenceBasis == b.evidenceBasis;
