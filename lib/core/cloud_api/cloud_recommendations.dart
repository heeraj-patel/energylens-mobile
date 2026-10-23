import 'cloud_faq.dart';

const _ruleIds = {
  'computer.sleep_settings',
  'television.quick_start',
  'washer.cycle_options',
  'dryer.cycle_options',
  'dryer.gas_cycle_options',
  'dishwasher.cycle_options',
  'heat_pump.operating_guidance',
  'water_heater.operating_mode',
  'dehumidifier.humidity_setting',
  'lighting.equivalent_bulb',
  'fan.speed_setting',
  'pool_pump.operating_guidance',
  'refrigerator.maintenance',
  'air_conditioner.schedule',
  'space_heater.schedule',
  'furnace.gas_efficiency_check',
  'furnace.gas_standby',
  'boiler.gas_efficiency_check',
  'boiler.gas_standby',
  'water_heater.gas_cost',
  'water_heater.gas_efficiency_check',
  'space_heater.gas_schedule',
  'general.gather_information',
};
const _nextQuestions = {
  'confirm_model',
  'find_reviewed_energy_source',
  'hours_per_week',
  'cycles_per_week',
  'add_electricity_rate',
  'add_gas_rate',
  'household_size',
};
const _recommendationStates = {
  'active',
  'candidate',
  'accepted',
  'completed',
  'snoozed',
  'dismissed',
  'expired',
  'superseded',
};
final _uuid = RegExp(
  r'^[0-9a-fA-F]{8}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{12}$',
);
final _money = RegExp(r'^\d+(?:\.\d{1,6})?$');

enum CloudRecommendationTipCategory { general, care, upgrade }

/// Datawiz `research_evidence` tip text with its https source.
class CloudResearchTip {
  const CloudResearchTip({required this.sourceText, required this.sourceUrl});
  final String sourceText;
  final Uri sourceUrl;

  /// Returns null for any entry without text and an https source.
  static CloudResearchTip? tryParse(Object? json) {
    if (json is! Map) return null;
    final value = json['value'];
    final source = json['source'];
    if (value is! Map || source is! Map) return null;
    final text = value['action_source_text'];
    final url = source['url'];
    final uri = url is String ? Uri.tryParse(url) : null;
    if (text is! String ||
        text.trim().isEmpty ||
        uri == null ||
        uri.scheme != 'https' ||
        uri.host.isEmpty ||
        uri.userInfo.isNotEmpty) {
      return null;
    }
    return CloudResearchTip(sourceText: text.trim(), sourceUrl: uri);
  }
}

/// Official weather alert; event and headline are provider text.
class CloudWeatherAlert {
  const CloudWeatherAlert({
    required this.event,
    required this.headline,
    required this.startsAt,
    required this.endsAt,
    required this.sourceUrl,
    required this.evidence,
  });
  final String event;
  final String? headline;
  final DateTime startsAt;
  final DateTime endsAt;
  final Uri sourceUrl;
  final CloudFaqEvidence evidence;

  /// Returns null for any malformed alert.
  static CloudWeatherAlert? tryParse(Object? json) {
    if (json is! Map<String, dynamic>) return null;
    final event = json['event'];
    final headline = json['headline'];
    final starts = json['starts_at'];
    final ends = json['ends_at'];
    final url = json['source_url'];
    final ref = json['evidence_ref'];
    final uri = url is String ? Uri.tryParse(url) : null;
    final startsAt = starts is String ? DateTime.tryParse(starts) : null;
    final endsAt = ends is String ? DateTime.tryParse(ends) : null;
    if (event is! String ||
        event.trim().isEmpty ||
        (headline != null && headline is! String) ||
        startsAt == null ||
        endsAt == null ||
        uri == null ||
        uri.scheme != 'https' ||
        uri.host.isEmpty ||
        uri.userInfo.isNotEmpty ||
        ref is! Map<String, dynamic>) {
      return null;
    }
    try {
      return CloudWeatherAlert(
        event: event,
        headline: headline as String?,
        startsAt: startsAt,
        endsAt: endsAt,
        sourceUrl: uri,
        evidence: CloudFaqEvidence.fromJson(ref),
      );
    } on FormatException {
      return null;
    }
  }
}

/// Consecutive completed observed hot or cold days.
class CloudWeatherRun {
  const CloudWeatherRun({
    required this.kind,
    required this.days,
    required this.lastDay,
  });
  final String kind;
  final int days;
  final String lastDay;

  static CloudWeatherRun? tryParse(Object? json) {
    if (json is! Map<String, dynamic>) return null;
    final kind = json['kind'];
    final days = json['days'];
    final lastDay = json['last_day'];
    if (kind is! String ||
        kind.isEmpty ||
        days is! int ||
        days < 1 ||
        lastDay is! String ||
        !RegExp(r'^\d{4}-\d{2}-\d{2}$').hasMatch(lastDay)) {
      return null;
    }
    return CloudWeatherRun(kind: kind, days: days, lastDay: lastDay);
  }
}

/// Home-level weather tip with the trigger that activated it.
class CloudWeatherHomeTip {
  const CloudWeatherHomeTip({required this.tip, required this.trigger});
  final CloudResearchTip tip;
  final String trigger;

  static CloudWeatherHomeTip? tryParse(Object? json) {
    if (json is! Map<String, dynamic>) return null;
    final trigger = json['trigger'];
    final tip = CloudResearchTip.tryParse(json['fact']);
    if (tip == null || trigger is! String || trigger.isEmpty) return null;
    return CloudWeatherHomeTip(tip: tip, trigger: trigger);
  }
}

/// Page weather block; sent only with capability `weather_tips_v1`.
class CloudWeather {
  const CloudWeather({
    required this.available,
    required this.reason,
    required this.provider,
    required this.attribution,
    required this.alerts,
    required this.runs,
    required this.homeTips,
  });
  final bool available;
  final String? reason;
  final String? provider;
  final String? attribution;
  final List<CloudWeatherAlert> alerts;
  final List<CloudWeatherRun> runs;
  final List<CloudWeatherHomeTip> homeTips;

  /// Returns null when the block is absent or its status is not recognised.
  static CloudWeather? tryParse(Object? json) {
    if (json is! Map<String, dynamic>) return null;
    final status = json['status'];
    if (status != 'available' && status != 'unavailable') return null;
    final available = status == 'available';
    List<T> rows<T extends Object>(
      String key,
      T? Function(Object?) parse,
      int max,
    ) {
      final raw = json[key];
      if (!available || raw is! List) return const [];
      return List.unmodifiable(raw.map(parse).nonNulls.take(max));
    }

    final reason = json['reason'];
    final provider = json['provider'];
    final attribution = json['attribution'];
    return CloudWeather(
      available: available,
      reason: reason is String ? reason : null,
      provider: provider is String ? provider : null,
      attribution: attribution is String ? attribution : null,
      alerts: rows('alerts', CloudWeatherAlert.tryParse, 100),
      runs: rows('runs', CloudWeatherRun.tryParse, 2),
      homeTips: rows('home_tips', CloudWeatherHomeTip.tryParse, 3),
    );
  }
}

/// Page peak demand block; sent only with capability `peak_demand_v1`.
class CloudPeakDemand {
  const CloudPeakDemand({
    required this.windowLocal,
    required this.sourceUrl,
    required this.homeTips,
  });
  final String windowLocal;
  final Uri sourceUrl;
  final List<CloudResearchTip> homeTips;

  /// Returns null when the block is absent or malformed.
  static CloudPeakDemand? tryParse(Object? json) {
    if (json is! Map<String, dynamic> || json['status'] != 'available') {
      return null;
    }
    final window = json['window_local'];
    final url = json['source_url'];
    final tips = json['home_tips'];
    if (window is! String ||
        !RegExp(
          r'^([01][0-9]|2[0-3]):[0-5][0-9]-([01][0-9]|2[0-3]):[0-5][0-9]$',
        ).hasMatch(window) ||
        url is! String ||
        tips is! List) {
      return null;
    }
    final uri = Uri.tryParse(url);
    if (uri == null ||
        uri.scheme != 'https' ||
        uri.host.isEmpty ||
        uri.userInfo.isNotEmpty) {
      return null;
    }
    final parsed = tips
        .map(
          (tip) => tip is Map<String, dynamic>
              ? CloudResearchTip.tryParse(tip['fact'])
              : null,
        )
        .nonNulls
        .take(3);
    return CloudPeakDemand(
      windowLocal: window,
      sourceUrl: uri,
      homeTips: List.unmodifiable(parsed),
    );
  }
}

/// Weather trigger on a device tip, with the optional time-of-use cost line.
class CloudWeatherContext {
  const CloudWeatherContext({
    required this.trigger,
    required this.measuredUse,
    this.touSavingPerKwh,
    this.currency,
    this.peakStartLocal,
    this.peakEndLocal,
  });
  final String trigger;
  final bool measuredUse;
  final String? touSavingPerKwh;
  final String? currency;
  final String? peakStartLocal;
  final String? peakEndLocal;

  /// Returns null when absent or malformed; the action itself is kept.
  static CloudWeatherContext? tryParse(Object? json) {
    if (json is! Map<String, dynamic>) return null;
    final trigger = json['trigger'];
    final measured = json['measured_use'];
    if (trigger is! String || trigger.isEmpty || measured is! bool) return null;
    final saving = json['tou_saving_per_kwh'];
    final currency = json['currency'];
    final start = json['peak_start_local'];
    final end = json['peak_end_local'];
    final clock = RegExp(r'^([01][0-9]|2[0-3]):[0-5][0-9]$');
    final hasCost =
        saving is String &&
        _money.hasMatch(saving) &&
        currency == 'USD' &&
        start is String &&
        clock.hasMatch(start) &&
        end is String &&
        clock.hasMatch(end);
    return CloudWeatherContext(
      trigger: trigger,
      measuredUse: measured,
      touSavingPerKwh: hasCost ? saving : null,
      currency: hasCost ? currency : null,
      peakStartLocal: hasCost ? start : null,
      peakEndLocal: hasCost ? end : null,
    );
  }
}

class CloudRecommendation {
  const CloudRecommendation({
    required this.ruleId,
    required this.applianceId,
    required this.state,
    required this.title,
    required this.explanation,
    required this.nextQuestion,
    required this.evidenceCount,
    required this.scenarioRefs,
    this.savingsAmount,
    this.savingsPeriod,
    this.savingsCurrency,
    this.savingsBasis,
    this.sourceUrl,
    this.researchTip,
    this.tipCategory = CloudRecommendationTipCategory.general,
    this.weatherContext,
    this.peakDemandContext,
  });
  final String ruleId;
  final String applianceId;
  final String state;
  final String title;
  final String explanation;
  final String? nextQuestion;
  final int evidenceCount;
  final List<Map<String, dynamic>> scenarioRefs;
  final String? savingsAmount;
  final String? savingsPeriod;
  final String? savingsCurrency;
  final String? savingsBasis;
  final Uri? sourceUrl;
  final CloudResearchTip? researchTip;
  final CloudRecommendationTipCategory tipCategory;
  final CloudWeatherContext? weatherContext;

  /// `peak_demand_day` on device tips from the peak demand context, else null.
  final String? peakDemandContext;

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
    final scenarioRefs = json['scenario_refs'] ?? const <dynamic>[];
    final savingsAmount = json['savings_amount'];
    final savingsPeriod = json['savings_period'];
    final savingsCurrency = json['savings_currency'];
    final savingsBasis = json['savings_basis'];
    final sourceUrlValue = json['source_url'];
    final parsedSourceUrl = sourceUrlValue is String
        ? Uri.tryParse(sourceUrlValue)
        : null;
    final sourceUrl =
        savingsAmount != null &&
            savingsBasis == 'reviewed_action_scenario' &&
            parsedSourceUrl?.scheme == 'https' &&
            parsedSourceUrl?.host.isNotEmpty == true &&
            parsedSourceUrl?.userInfo.isEmpty == true
        ? parsedSourceUrl
        : null;
    final evidence = json['research_evidence'];
    final researchTip = evidence is List
        ? evidence.map(CloudResearchTip.tryParse).nonNulls.firstOrNull
        : null;
    final categoryValue = json['tip_category'];
    final tipCategory = categoryValue == null
        ? CloudRecommendationTipCategory.general
        : CloudRecommendationTipCategory.values
              .where((value) => value.name == categoryValue)
              .firstOrNull;
    if (ruleId is! String ||
        !_ruleIds.contains(ruleId) ||
        json['rule_version'] != 1 ||
        applianceId is! String ||
        !_uuid.hasMatch(applianceId) ||
        !applianceIds.contains(applianceId.toLowerCase()) ||
        state is! String ||
        !_recommendationStates.contains(state) ||
        title is! String ||
        title.trim().isEmpty ||
        title.length > 120 ||
        explanation is! String ||
        explanation.trim().isEmpty ||
        explanation.length > 500 ||
        json['benefit_group'] is! String ||
        (json['benefit_group'] as String).isEmpty ||
        tipCategory == null ||
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
        scenarioRefs is! List ||
        scenarioRefs.length > 12 ||
        scenarioRefs.any(
          (ref) =>
              ref is! Map<String, dynamic> ||
              ref['id'] is! String ||
              !_uuid.hasMatch(ref['id'] as String) ||
              ref['kind'] is! String ||
              (ref['kind'] as String).isEmpty ||
              ref['revision'] is! int ||
              (ref['revision'] as int) < 1,
        ) ||
        (savingsAmount != null &&
            (savingsAmount is! String || !_money.hasMatch(savingsAmount))) ||
        (savingsAmount == null &&
            (savingsPeriod != null ||
                savingsCurrency != null ||
                savingsBasis != null ||
                scenarioRefs.isNotEmpty)) ||
        (savingsAmount != null &&
            (savingsPeriod is! String ||
                savingsPeriod.isEmpty ||
                savingsCurrency is! String ||
                savingsCurrency != 'USD' ||
                savingsBasis is! String ||
                savingsBasis.isEmpty ||
                scenarioRefs.isEmpty)) ||
        (next != null && !_nextQuestions.contains(next)) ||
        (state == 'active'
            ? next != null || refs.length < 2
            : state == 'candidate'
            ? !_nextQuestions.contains(next)
            : false)) {
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
      scenarioRefs: List.unmodifiable(
        scenarioRefs.map(
          (ref) =>
              Map<String, dynamic>.unmodifiable(ref as Map<String, dynamic>),
        ),
      ),
      savingsAmount: savingsAmount as String?,
      savingsPeriod: savingsPeriod as String?,
      savingsCurrency: savingsCurrency as String?,
      savingsBasis: savingsBasis as String?,
      sourceUrl: sourceUrl,
      researchTip: researchTip,
      tipCategory: tipCategory,
      weatherContext: CloudWeatherContext.tryParse(json['weather_context']),
      peakDemandContext: json['peak_demand_context'] == 'peak_demand_day'
          ? 'peak_demand_day'
          : null,
    );
  }
}

class CloudRecommendationBatch {
  const CloudRecommendationBatch(
    this.actions,
    this.asOf, {
    this.weather,
    this.peakDemand,
  });
  final List<CloudRecommendation> actions;
  final DateTime asOf;
  final CloudWeather? weather;
  final CloudPeakDemand? peakDemand;

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
    final actions = <CloudRecommendation>[];
    for (final row in rows) {
      if (row is! Map<String, dynamic>) continue;
      try {
        actions.add(CloudRecommendation.fromJson(row, applianceIds));
      } on FormatException {
        // A malformed action cannot invalidate other owned actions.
      }
    }
    final keys = actions
        .map((action) => '${action.applianceId.toLowerCase()}/${action.ruleId}')
        .toSet();
    if (keys.length != actions.length) {
      throw const FormatException('Duplicate cloud recommendation');
    }
    return CloudRecommendationBatch(
      actions,
      asOf,
      weather: CloudWeather.tryParse(json['weather']),
      peakDemand: CloudPeakDemand.tryParse(json['peak_demand']),
    );
  }
}
