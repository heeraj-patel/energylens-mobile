import '../../core/cloud_api/cloud_api_client.dart';
import '../../core/cloud_api/cloud_household_energy.dart';

/// Native data source for the Dashboard page. It uses the same typed client in
/// household and isolated sample mode; it does not render or change the page.
abstract interface class DashboardDomainSource {
  Future<CloudHouseholdDashboard> dashboard(String homeId);
  Future<CloudHouseholdEnergyTrends> trends(String homeId);
}

/// Optional typed period reads. Each period has its own snapshot identity.
abstract interface class DashboardPeriodDomainSource {
  Future<CloudHouseholdEnergyTrends> periodTrends(
    String homeId,
    String granularity,
  );
}

/// The current Monday-start week is a separate read from chart occurrences.
abstract interface class DashboardCurrentWeekDomainSource {
  Future<CloudHouseholdEnergyTrends> currentWeekTrends(String homeId);
}

class CloudDashboardDomainSource
    implements
        DashboardDomainSource,
        DashboardPeriodDomainSource,
        DashboardCurrentWeekDomainSource {
  const CloudDashboardDomainSource(this.api);
  final CloudApiClient api;

  @override
  Future<CloudHouseholdDashboard> dashboard(String homeId) =>
      api.householdDashboard(homeId);

  @override
  Future<CloudHouseholdEnergyTrends> trends(String homeId) =>
      api.householdEnergyTrends(homeId, granularity: 'hour');

  @override
  Future<CloudHouseholdEnergyTrends> periodTrends(
    String homeId,
    String granularity,
  ) => api.householdEnergyTrends(
    homeId,
    granularity: granularity,
    window: 'last_5_occurrences',
  );

  @override
  Future<CloudHouseholdEnergyTrends> currentWeekTrends(String homeId) =>
      api.householdEnergyTrends(homeId, granularity: 'day');
}

class DashboardDomainSnapshot {
  const DashboardDomainSnapshot(
    this.dashboard,
    this.trends, {
    this.periodTrends = const {},
    this.weekToDateTrends,
    this.isCurrent,
  });
  final CloudHouseholdDashboard dashboard;
  final CloudHouseholdEnergyTrends trends;
  final Map<String, CloudHouseholdEnergyTrends> periodTrends;
  final CloudHouseholdEnergyTrends? weekToDateTrends;
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
      final dashboardRead = source.dashboard(homeId);
      final hourlyRead = source.trends(homeId);
      final DashboardPeriodDomainSource? periodSource =
          source is DashboardPeriodDomainSource
          ? source as DashboardPeriodDomainSource
          : null;
      final periodReads = periodSource != null
          ? Future.wait<CloudHouseholdEnergyTrends?>([
              for (final granularity in const ['day', 'week', 'month'])
                periodSource
                    .periodTrends(homeId, granularity)
                    .then<CloudHouseholdEnergyTrends?>((value) => value)
                    .catchError((Object _) => null),
            ])
          : Future.value(<CloudHouseholdEnergyTrends?>[]);
      final DashboardCurrentWeekDomainSource? weekSource =
          source is DashboardCurrentWeekDomainSource
          ? source as DashboardCurrentWeekDomainSource
          : null;
      final weekRead = weekSource == null
          ? Future<CloudHouseholdEnergyTrends?>.value(null)
          : weekSource
                .currentWeekTrends(homeId)
                .then<CloudHouseholdEnergyTrends?>((value) => value)
                .catchError((Object _) => null);
      final results = await Future.wait<Object?>([
        dashboardRead,
        hourlyRead,
        periodReads,
        weekRead,
      ]);
      if (stale()) return null;
      final dashboard = results[0] as CloudHouseholdDashboard;
      final trends = results[1] as CloudHouseholdEnergyTrends;
      if (!_sameSnapshot(dashboard, trends, homeId)) {
        throw const FormatException('Dashboard and trends disagree');
      }
      final periodRows = results[2] as List<CloudHouseholdEnergyTrends?>;
      final periodTrends = <String, CloudHouseholdEnergyTrends>{};
      for (var i = 0; i < periodRows.length; i++) {
        final row = periodRows[i];
        final granularity = const ['day', 'week', 'month'][i];
        if (row != null &&
            row.granularity == granularity &&
            _samePeriodContext(dashboard, row, homeId)) {
          periodTrends[granularity] = row;
        }
      }
      final weekRow = results[3] as CloudHouseholdEnergyTrends?;
      return DashboardDomainSnapshot(
        dashboard,
        trends,
        periodTrends: Map.unmodifiable(periodTrends),
        weekToDateTrends:
            weekRow != null &&
                weekRow.granularity == 'day' &&
                _samePeriodContext(dashboard, weekRow, homeId)
            ? weekRow
            : null,
        isCurrent: () => !stale(),
      );
    } catch (_) {
      if (stale()) return null;
      rethrow;
    }
  }
}

bool _samePeriodContext(
  CloudHouseholdDashboard dashboard,
  CloudHouseholdEnergyTrends trends,
  String homeId,
) =>
    trends.homeId.toLowerCase() == homeId.toLowerCase() &&
    trends.dataMode == dashboard.dataMode &&
    trends.fixtureRevision == dashboard.fixtureRevision &&
    trends.timezone == dashboard.timezone &&
    trends.scope == dashboard.scope &&
    trends.schemaRevision == dashboard.schemaRevision &&
    trends.generatedAt.difference(dashboard.generatedAt).abs() <=
        const Duration(minutes: 5) &&
    !dashboard.generatedAt.isBefore(trends.period.start) &&
    dashboard.generatedAt.isBefore(trends.period.endExclusive);

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
