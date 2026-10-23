const faqInsufficientAnswer = 'More usage information is needed.';

bool _validOperatingCostRefs(List<CloudFaqEvidence> refs, String? applianceId) {
  if (refs.length != 2) return false;
  final source = refs.where(
    (ref) => ref.kind == 'catalog_fact' || ref.kind == 'datawiz_resolution',
  );
  final tariff = refs.where((ref) => ref.kind == 'tariff');
  return source.length == 1 &&
      tariff.length == 1 &&
      (source.single.kind != 'datawiz_resolution' ||
          (source.single.revision == 1 && source.single.id == applianceId));
}

const faqIntents = <String, String>{
  'high_bill_possible_contributors': 'What could contribute to high use?',
  'top_waste_opportunities': 'Where could I reduce waste?',
  'device_operating_cost': 'What does a device cost to run?',
  'reduce_cost': 'How could I reduce cost?',
  'programs_for_device': 'Are there programs for a device?',
  'weather_tips': 'Which weather tips apply now?',
};

const faqWeatherNoTipsAnswer = 'No weather tips apply right now.';

bool isFaqIntent(String intent) => faqIntents.containsKey(intent);

class CloudFaqEvidence {
  const CloudFaqEvidence(this.id, this.kind, this.revision);
  final String id;
  final String kind;
  final int revision;

  factory CloudFaqEvidence.fromJson(Map<String, dynamic> json) {
    final id = json['id'];
    final kind = json['kind'];
    final revision = json['revision'];
    if (id is! String ||
        !RegExp(
          r'^[0-9a-fA-F]{8}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{12}$',
        ).hasMatch(id) ||
        kind is! String ||
        kind.isEmpty ||
        kind.length > 64 ||
        revision is! int ||
        revision < 1) {
      throw const FormatException('Invalid FAQ evidence');
    }
    return CloudFaqEvidence(id, kind, revision);
  }
}

class CloudFaqFinding {
  const CloudFaqFinding(this.label, this.text, this.refs, {this.sourceUrl});
  final String label;
  final String text;
  final List<CloudFaqEvidence> refs;
  final Uri? sourceUrl;

  factory CloudFaqFinding.fromJson(Map<String, dynamic> json, String intent) {
    final label = json['label'];
    final text = json['text'];
    final rawRefs = json['evidence_refs'];
    if (!const {'observation', 'estimate', 'hypothesis'}.contains(label) ||
        (intent == 'high_bill_possible_contributors' &&
            label == 'hypothesis') ||
        text is! String ||
        text.trim().isEmpty ||
        text.length > 1000 ||
        rawRefs is! List ||
        rawRefs.isEmpty ||
        rawRefs.length > 20) {
      throw const FormatException('Invalid FAQ finding');
    }
    final refs = rawRefs.map((raw) {
      if (raw is! Map<String, dynamic>) {
        throw const FormatException('Invalid FAQ evidence');
      }
      return CloudFaqEvidence.fromJson(raw);
    }).toList();
    final url = json['source_url'];
    final uri = url is String ? Uri.tryParse(url) : null;
    final validUrl =
        uri != null &&
        uri.scheme == 'https' &&
        uri.host.isNotEmpty &&
        uri.userInfo.isEmpty;
    return CloudFaqFinding(
      label as String,
      text,
      refs,
      sourceUrl: validUrl ? uri : null,
    );
  }
}

class CloudFaqAnswer {
  const CloudFaqAnswer({
    required this.intent,
    required this.status,
    required this.text,
    required this.findings,
    required this.asOf,
    required this.adaptiveQuestions,
    this.weatherStatus,
    this.weatherReason,
  });
  final String intent;
  final String status;
  final String text;
  final List<CloudFaqFinding> findings;
  final DateTime asOf;
  final bool adaptiveQuestions;
  final String? weatherStatus;
  final String? weatherReason;

  factory CloudFaqAnswer.fromJson(
    Map<String, dynamic> json,
    String intent, {
    String? applianceId,
  }) {
    final status = json['status'];
    final text = json['answer'];
    final rawFindings = json['findings'];
    final rawRefs = json['evidence_refs'];
    final asOf = json['as_of'] is String
        ? DateTime.tryParse(json['as_of'] as String)
        : null;
    if (!isFaqIntent(intent) ||
        json['question_id'] != intent ||
        !const {
          'insufficient_information',
          'partial',
          'supported',
        }.contains(status) ||
        text is! String ||
        rawFindings is! List ||
        rawFindings.length > 20 ||
        rawRefs is! List ||
        rawRefs.length > 100 ||
        asOf == null) {
      throw const FormatException('Invalid FAQ answer');
    }
    final findings = rawFindings.map((raw) {
      if (raw is! Map<String, dynamic>) {
        throw const FormatException('Invalid FAQ finding');
      }
      return CloudFaqFinding.fromJson(raw, intent);
    }).toList();
    final refs = rawRefs.map((raw) {
      if (raw is! Map<String, dynamic>) {
        throw const FormatException('Invalid FAQ evidence');
      }
      return CloudFaqEvidence.fromJson(raw);
    }).toList();
    final expectedRefs = findings.expand((finding) => finding.refs).toList();
    final weather = intent == 'weather_tips';
    bool inFindings(CloudFaqEvidence ref) => expectedRefs.any(
      (e) => e.id == ref.id && e.kind == ref.kind && e.revision == ref.revision,
    );
    // Weather answers may list a shared reference once.
    final refsMatch = weather
        ? refs.every(inFindings) && (findings.isEmpty || refs.isNotEmpty)
        : refs.length == expectedRefs.length &&
              Iterable.generate(refs.length).every(
                (index) =>
                    refs[index].id == expectedRefs[index].id &&
                    refs[index].kind == expectedRefs[index].kind &&
                    refs[index].revision == expectedRefs[index].revision,
              );
    if (!refsMatch) {
      throw const FormatException('FAQ evidence does not match findings');
    }
    final action = json['next_action'];
    if (status == 'insufficient_information') {
      if (text != faqInsufficientAnswer ||
          findings.isNotEmpty ||
          refs.isNotEmpty ||
          action is! Map<String, dynamic> ||
          action['kind'] != 'adaptive_questions' ||
          action['flow_id'] != 'faq-contributors/v1') {
        throw const FormatException('Invalid FAQ fallback');
      }
      return CloudFaqAnswer(
        intent: intent,
        status: status as String,
        text: text,
        findings: findings,
        asOf: asOf,
        adaptiveQuestions: true,
        weatherStatus: json['weather_status'] is String
            ? json['weather_status'] as String
            : null,
        weatherReason: json['weather_reason'] is String
            ? json['weather_reason'] as String
            : null,
      );
    }
    if (weather) {
      final none = findings.isEmpty;
      final ws = json['weather_status'];
      final wr = json['weather_reason'];
      if (action != null ||
          (none && (status != 'supported' || text != faqWeatherNoTipsAnswer)) ||
          text.trim().isEmpty ||
          (!none && refs.isEmpty)) {
        throw const FormatException('Unsupported FAQ finding');
      }
      return CloudFaqAnswer(
        intent: intent,
        status: status as String,
        text: text,
        findings: findings,
        asOf: asOf,
        adaptiveQuestions: false,
        weatherStatus: ws is String ? ws : null,
        weatherReason: wr is String ? wr : null,
      );
    }
    if (findings.isEmpty ||
        action != null ||
        (status == 'supported') != (intent == 'device_operating_cost') ||
        (intent == 'high_bill_possible_contributors' &&
            text !=
                'These observations give context for possible energy demand. They do not establish a change in home energy use or a bill cause.') ||
        (intent != 'high_bill_possible_contributors' &&
            intent != 'device_operating_cost' &&
            text !=
                'These options have supporting information. Review their details before making a change.') ||
        (intent == 'device_operating_cost' &&
            (text !=
                    'An operating cost estimate is available for this device.' ||
                findings.length != 1 ||
                findings.first.label != 'estimate' ||
                !RegExp(
                  r'^Estimated operating cost: [0-9]+(?:\.[0-9]+)? [A-Z]{3} for \d{4}-\d{2}-\d{2} to \d{4}-\d{2}-\d{2}\.$',
                ).hasMatch(findings.first.text) ||
                !_validOperatingCostRefs(findings.first.refs, applianceId)))) {
      throw const FormatException('Unsupported FAQ finding');
    }
    return CloudFaqAnswer(
      intent: intent,
      status: status as String,
      text: text,
      findings: findings,
      asOf: asOf,
      adaptiveQuestions: false,
    );
  }
}
