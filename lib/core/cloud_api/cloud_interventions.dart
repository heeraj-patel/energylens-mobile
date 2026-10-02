final _uuid = RegExp(
  r'^[0-9a-f]{8}-[0-9a-f]{4}-[1-8][0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$',
);

class CloudAttachment {
  const CloudAttachment({
    required this.id,
    required this.homeId,
    required this.applianceId,
    required this.startedAt,
    this.endedAt,
  });
  final String id;
  final String homeId;
  final String applianceId;
  final DateTime startedAt;
  final DateTime? endedAt;

  factory CloudAttachment.fromJson(Map<String, dynamic> json, String homeId) {
    final start = DateTime.tryParse(
      json['started_at'] is String ? json['started_at'] as String : '',
    );
    final end = json['ended_at'] is String
        ? DateTime.tryParse(json['ended_at'] as String)
        : null;
    if (json['id'] is! String ||
        !_uuid.hasMatch(json['id'] as String) ||
        json['home_id'] != homeId ||
        json['appliance_id'] is! String ||
        !_uuid.hasMatch(json['appliance_id'] as String) ||
        start == null ||
        !start.isUtc ||
        (json['ended_at'] != null &&
            (end == null || !end.isUtc || !end.isAfter(start)))) {
      throw const FormatException('Invalid cloud attachment');
    }
    return CloudAttachment(
      id: json['id'] as String,
      homeId: homeId,
      applianceId: json['appliance_id'] as String,
      startedAt: start,
      endedAt: end,
    );
  }

  bool activeAt(DateTime at) =>
      !startedAt.isAfter(at) && (endedAt == null || endedAt!.isAfter(at));
}

class CloudInterventionCreate {
  const CloudInterventionCreate({
    required this.applianceId,
    required this.attachmentId,
    required this.ruleId,
    required this.occurredAt,
    required this.comparableUse,
    required this.comparableWeather,
    required this.confounders,
  });
  final String applianceId;
  final String attachmentId;
  final String ruleId;
  final DateTime occurredAt;
  final bool comparableUse;
  final bool comparableWeather;
  final List<String> confounders;

  static const allowedConfounders = {
    'occupancy_changed',
    'use_changed',
    'weather_changed',
    'equipment_changed',
    'other',
    'unknown',
  };

  Map<String, dynamic> toJson() {
    if (!_uuid.hasMatch(applianceId) ||
        !_uuid.hasMatch(attachmentId) ||
        ruleId.isEmpty ||
        ruleId.length > 100 ||
        !occurredAt.isUtc ||
        occurredAt.minute != 0 ||
        occurredAt.second != 0 ||
        occurredAt.millisecond != 0 ||
        occurredAt.microsecond != 0 ||
        occurredAt.isAfter(DateTime.now().toUtc()) ||
        occurredAt.isBefore(
          DateTime.now().toUtc().subtract(const Duration(days: 23)),
        ) ||
        confounders.length > 8 ||
        confounders.any((c) => !allowedConfounders.contains(c))) {
      throw ArgumentError('Invalid manual action');
    }
    return {
      'appliance_id': applianceId,
      'attachment_id': attachmentId,
      'rule_id': ruleId,
      'occurred_at': occurredAt.toIso8601String(),
      'comparable_use': comparableUse,
      'comparable_weather': comparableWeather,
      'confounders': [...confounders]..sort(),
    };
  }
}

class CloudIntervention {
  const CloudIntervention(this.id);
  final String id;
  factory CloudIntervention.fromJson(Map<String, dynamic> json) {
    final id = json['id'];
    if (id is! String ||
        !_uuid.hasMatch(id) ||
        json['status'] != 'completed' ||
        json['outcome_status'] != 'collecting') {
      throw const FormatException('Invalid intervention response');
    }
    return CloudIntervention(id);
  }
}

class CloudOutcomePeriod {
  const CloudOutcomePeriod(
    this.from,
    this.to,
    this.expectedHours,
    this.measuredHours,
    this.coverageFraction,
    this.knownGapHours,
    this.allocatedHours,
    this.energyWh,
  );
  final DateTime from;
  final DateTime to;
  final int expectedHours;
  final int measuredHours;
  final double coverageFraction;
  final int knownGapHours;
  final int allocatedHours;
  final double? energyWh;

  factory CloudOutcomePeriod.fromJson(Map<String, dynamic> json) {
    final from = DateTime.tryParse(
      json['from'] is String ? json['from'] as String : '',
    );
    final to = DateTime.tryParse(
      json['to'] is String ? json['to'] as String : '',
    );
    final hours = json['expected_hours'];
    final measured = json['measured_hours'];
    final coverage = json['coverage_fraction'];
    final gaps = json['known_gap_hours'];
    final allocated = json['allocated_hours'];
    final energy = json['energy_wh'];
    if (from == null ||
        to == null ||
        !from.isUtc ||
        !to.isUtc ||
        !to.isAfter(from) ||
        hours != 168 ||
        measured is! int ||
        measured < 0 ||
        measured > hours ||
        coverage is! num ||
        !coverage.isFinite ||
        coverage < 0 ||
        coverage > 1 ||
        gaps is! int ||
        gaps < 0 ||
        allocated is! int ||
        allocated < 0 ||
        (energy != null &&
            (energy is! num || !energy.isFinite || energy < 0))) {
      throw const FormatException('Invalid outcome period');
    }
    return CloudOutcomePeriod(
      from,
      to,
      hours,
      measured,
      coverage.toDouble(),
      gaps,
      allocated,
      (energy as num?)?.toDouble(),
    );
  }
}

class CloudOutcome {
  const CloudOutcome({
    required this.status,
    required this.reasons,
    required this.before,
    required this.after,
    required this.deltaWh,
    required this.interpretation,
  });
  final String status;
  final List<String> reasons;
  final CloudOutcomePeriod before;
  final CloudOutcomePeriod after;
  final double? deltaWh;
  final String interpretation;

  factory CloudOutcome.fromJson(
    Map<String, dynamic> json,
    String homeId,
    String interventionId,
  ) {
    final action = json['action'];
    final status = json['status'];
    final reasons = json['reasons'];
    final delta = json['delta_wh'];
    if (action is! Map<String, dynamic> ||
        action['id'] != interventionId ||
        action['home_id'] != homeId ||
        status is! String ||
        !{'collecting', 'inconclusive', 'observed-change'}.contains(status) ||
        reasons is! List ||
        reasons.any((r) => r is! String) ||
        (delta != null && (delta is! num || !delta.isFinite)) ||
        (status != 'observed-change' && delta != null) ||
        json['before'] is! Map<String, dynamic> ||
        json['after'] is! Map<String, dynamic> ||
        json['interpretation'] is! String ||
        (json['interpretation'] as String).isEmpty) {
      throw const FormatException('Invalid outcome response');
    }
    return CloudOutcome(
      status: status,
      reasons: reasons.cast<String>(),
      before: CloudOutcomePeriod.fromJson(
        json['before'] as Map<String, dynamic>,
      ),
      after: CloudOutcomePeriod.fromJson(json['after'] as Map<String, dynamic>),
      deltaWh: (delta as num?)?.toDouble(),
      interpretation: json['interpretation'] as String,
    );
  }
}
