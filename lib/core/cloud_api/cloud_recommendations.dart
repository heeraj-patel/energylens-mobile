const _ruleIds = {
  'computer.sleep_settings',
  'television.quick_start',
  'washer.cycle_options',
  'dryer.cycle_options',
  'dryer.gas_cycle_options',
  'refrigerator.maintenance',
  'air_conditioner.schedule',
  'space_heater.schedule',
  'general.gather_information',
};
const _nextQuestions = {
  'confirm_model',
  'find_reviewed_energy_source',
  'hours_per_week',
  'cycles_per_week',
  'add_electricity_rate',
  'add_gas_rate',
};
final _uuid = RegExp(
  r'^[0-9a-fA-F]{8}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{12}$',
);

class CloudRecommendation {
  const CloudRecommendation({
    required this.ruleId,
    required this.applianceId,
    required this.state,
    required this.title,
    required this.explanation,
    required this.nextQuestion,
    required this.evidenceCount,
  });
  final String ruleId;
  final String applianceId;
  final String state;
  final String title;
  final String explanation;
  final String? nextQuestion;
  final int evidenceCount;

  factory CloudRecommendation.fromJson(
    Map<String, dynamic> json,
    Set<String> applianceIds,
  ) {
    final ruleId = json['rule_id'];
    final applianceId = json['appliance_id'];
    final state = json['state'];
    final title = json['title'];
    final explanation = json['explanation'];
    final next = json['next_question'];
    final refs = json['evidence_refs'];
    if (ruleId is! String ||
        !_ruleIds.contains(ruleId) ||
        json['rule_version'] != 1 ||
        applianceId is! String ||
        !_uuid.hasMatch(applianceId) ||
        !applianceIds.contains(applianceId.toLowerCase()) ||
        state is! String ||
        !const {'active', 'candidate'}.contains(state) ||
        title is! String ||
        title.trim().isEmpty ||
        title.length > 120 ||
        explanation is! String ||
        explanation.trim().isEmpty ||
        explanation.length > 500 ||
        json['benefit_group'] is! String ||
        (json['benefit_group'] as String).isEmpty ||
        refs is! List ||
        refs.length > 8 ||
        refs.any(
          (ref) =>
              ref is! Map<String, dynamic> ||
              ref['id'] is! String ||
              !_uuid.hasMatch(ref['id'] as String) ||
              ref['kind'] is! String ||
              (ref['kind'] as String).isEmpty ||
              ref['revision'] is! int ||
              (ref['revision'] as int) < 1,
        ) ||
        json['savings_amount'] != null ||
        (state == 'active'
            ? next != null || refs.length < 2
            : !_nextQuestions.contains(next))) {
      throw const FormatException('Invalid cloud recommendation');
    }
    return CloudRecommendation(
      ruleId: ruleId,
      applianceId: applianceId,
      state: state,
      title: title,
      explanation: explanation,
      nextQuestion: next as String?,
      evidenceCount: refs.length,
    );
  }
}

class CloudRecommendationBatch {
  const CloudRecommendationBatch(this.actions, this.asOf);
  final List<CloudRecommendation> actions;
  final DateTime asOf;

  factory CloudRecommendationBatch.fromJson(
    Map<String, dynamic> json,
    Set<String> applianceIds,
  ) {
    final rows = json['actions'];
    final asOf = json['as_of'] is String
        ? DateTime.tryParse(json['as_of'] as String)
        : null;
    if (rows is! List || rows.length > 200 || asOf == null) {
      throw const FormatException('Invalid cloud recommendation list');
    }
    final actions = rows.map((row) {
      if (row is! Map<String, dynamic>) {
        throw const FormatException('Invalid cloud recommendation');
      }
      return CloudRecommendation.fromJson(row, applianceIds);
    }).toList();
    final keys = actions
        .map((action) => '${action.applianceId.toLowerCase()}/${action.ruleId}')
        .toSet();
    if (keys.length != actions.length) {
      throw const FormatException('Duplicate cloud recommendation');
    }
    return CloudRecommendationBatch(actions, asOf);
  }
}
