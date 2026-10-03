const faqInsufficientAnswer = 'More usage information is needed.';

const faqIntents = <String, String>{
  'high_bill_possible_contributors': 'What could contribute to high use?',
  'top_waste_opportunities': 'Where could I reduce waste?',
  'device_operating_cost': 'What does a device cost to run?',
  'reduce_cost': 'How could I reduce cost?',
  'programs_for_device': 'Are there programs for a device?',
};

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
  const CloudFaqFinding(this.label, this.text, this.refs);
  final String label;
  final String text;
  final List<CloudFaqEvidence> refs;

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
    return CloudFaqFinding(label as String, text, refs);
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
  });
  final String intent;
  final String status;
  final String text;
  final List<CloudFaqFinding> findings;
  final DateTime asOf;
  final bool adaptiveQuestions;

  factory CloudFaqAnswer.fromJson(Map<String, dynamic> json, String intent) {
    final status = json['status'];
    final text = json['answer'];
    final rawFindings = json['findings'];
    final rawRefs = json['evidence_refs'];
    final asOf = json['as_of'] is String
        ? DateTime.tryParse(json['as_of'] as String)
        : null;
    if (!faqIntents.containsKey(intent) ||
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
    if (refs.length != expectedRefs.length ||
        Iterable.generate(refs.length).any(
          (index) =>
              refs[index].id != expectedRefs[index].id ||
              refs[index].kind != expectedRefs[index].kind ||
              refs[index].revision != expectedRefs[index].revision,
        )) {
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
                !findings.first.refs.any((ref) => ref.kind == 'catalog_fact') ||
                !findings.first.refs.any((ref) => ref.kind == 'tariff') ||
                findings.first.refs.any(
                  (ref) => !const {'catalog_fact', 'tariff'}.contains(ref.kind),
                )))) {
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
