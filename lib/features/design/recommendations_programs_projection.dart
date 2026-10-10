import '../../core/cloud_api/cloud_programs.dart';
import '../../core/cloud_api/cloud_recommendations.dart';
import 'design_context_coordinator.dart';
import 'efficiency_away_domain_adapter.dart';
import 'efficiency_domain_repository.dart';
import 'efficiency_habits_domain_adapter.dart';
import 'tips_domain_repository.dart';

/// Native-only rows for a selected page. The source objects retain their
/// original status, evidence, and order; a renderer decides placement later.
class RecommendationsProgramsProjection {
  const RecommendationsProgramsProjection({
    required this.accountId,
    required this.homeId,
    required this.mode,
    required this.page,
    required this.recommendations,
    required this.programs,
  });

  final String accountId;
  final String homeId;
  final DesignContextMode mode;
  final String page;
  final List<CloudRecommendation> recommendations;
  final List<CloudProgram> programs;

  static RecommendationsProgramsProjection? fromRead(DesignContextRead read) {
    final value = read.value;
    final List<CloudRecommendation> recommendations;
    final List<CloudProgram> programs;
    final String sourceHomeId;
    if (value is TipsDomainSnapshot) {
      if (read.page != _tipsPageId(value.page)) return null;
      sourceHomeId = value.homeId;
      recommendations = value.recommendations;
      programs = value.programs?.programs ?? const [];
    } else if (value is EfficiencyDomainSnapshot) {
      if (read.page != 'efficiency') return null;
      sourceHomeId = value.homeId;
      recommendations = value.recommendations;
      programs = const [];
    } else if (value is EfficiencyAwayDomainSnapshot) {
      if (read.page != 'efficiency_away') return null;
      sourceHomeId = value.homeId;
      recommendations = value.efficiency.recommendations;
      programs = const [];
    } else if (value is EfficiencyHabitsSnapshot) {
      if (read.page != 'efficiency_habits') return null;
      sourceHomeId = value.homeId;
      recommendations = value.recommendations;
      programs = const [];
    } else {
      return null;
    }
    if (sourceHomeId.toLowerCase() != read.homeId.toLowerCase()) {
      throw const FormatException('Projection belongs to another home');
    }
    return RecommendationsProgramsProjection(
      accountId: read.accountId,
      homeId: read.homeId,
      mode: read.mode,
      page: read.page,
      recommendations: List.unmodifiable(recommendations),
      programs: List.unmodifiable(programs),
    );
  }
}

String _tipsPageId(TipsPage page) => switch (page) {
  TipsPage.perksTips => 'perks_tips',
  TipsPage.efficiency => 'tips_efficiency',
  TipsPage.careUpgrades => 'tips_care_upgrades',
};
