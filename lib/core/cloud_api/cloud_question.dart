class CloudQuestionOption {
  const CloudQuestionOption({required this.key, required this.value});

  final String key;
  final num value;

  factory CloudQuestionOption.fromJson(Map<String, dynamic> json) {
    final value = json['value'];
    if (json.length != 2 ||
        json['key'] is! String ||
        (json['key'] as String).isEmpty ||
        value is! num ||
        !value.isFinite) {
      throw const FormatException('Invalid cloud question option');
    }
    return CloudQuestionOption(key: json['key'] as String, value: value);
  }
}

class CloudQuestion {
  const CloudQuestion({
    required this.id,
    required this.purpose,
    required this.version,
    required this.applianceId,
    required this.identityRevision,
    required this.prompt,
    required this.answerKind,
    required this.unit,
    required this.optional,
    this.options,
    this.sourceFactId,
    this.cycleDefinition,
    this.testBasis,
    this.sourceUrl,
  });

  final String id;
  final String purpose;
  final int version;
  final String applianceId;
  final int identityRevision;
  final String prompt;
  final String answerKind;
  final String? unit;
  final bool optional;
  final List<CloudQuestionOption>? options;
  final String? sourceFactId;
  final String? cycleDefinition;
  final String? testBasis;
  final String? sourceUrl;

  factory CloudQuestion.fromJson(Map<String, dynamic> json) {
    if (json['id'] is! String ||
        (json['purpose'] != 'onboarding' &&
            json['purpose'] != 'avoid' &&
            json['purpose'] != 'faq') ||
        json['version'] is! int ||
        json['appliance_id'] is! String ||
        json['identity_revision'] is! int ||
        json['prompt'] is! String ||
        json['answer_kind'] is! String ||
        json['optional'] is! bool) {
      throw const FormatException('Invalid cloud question');
    }
    const kinds = {'hours_per_week', 'cycles_per_week', 'boolean', 'choice'};
    final rawOptions = json['options'];
    String? text(String key, {bool uri = false}) {
      final value = json[key];
      if (value == null) return null;
      if (value is! String ||
          value.isEmpty ||
          (uri && Uri.tryParse(value) == null)) {
        throw const FormatException('Invalid cloud question');
      }
      return value;
    }

    if (!kinds.contains(json['answer_kind']) ||
        (rawOptions != null && (rawOptions is! List || rawOptions.isEmpty)) ||
        (json['answer_kind'] == 'choice' && rawOptions == null)) {
      throw const FormatException('Invalid cloud question');
    }
    return CloudQuestion(
      id: json['id'] as String,
      purpose: json['purpose'] as String,
      version: json['version'] as int,
      applianceId: json['appliance_id'] as String,
      identityRevision: json['identity_revision'] as int,
      prompt: json['prompt'] as String,
      answerKind: json['answer_kind'] as String,
      unit: json['unit'] as String?,
      optional: json['optional'] as bool,
      options: rawOptions == null
          ? null
          : (rawOptions as List)
                .map(
                  (row) =>
                      CloudQuestionOption.fromJson(row as Map<String, dynamic>),
                )
                .toList(),
      sourceFactId: text('source_fact_id'),
      cycleDefinition: text('cycle_definition'),
      testBasis: text('test_basis'),
      sourceUrl: text('source_url', uri: true),
    );
  }
}

class CloudAnswerCreate {
  const CloudAnswerCreate({
    required this.question,
    required this.value,
    required this.confirmedAt,
  });

  final CloudQuestion question;
  final num? value;
  final DateTime? confirmedAt;

  Map<String, dynamic> toJson() => {
    'question_id': question.id,
    'question_version': question.version,
    'appliance_id': question.applianceId,
    'identity_revision': question.identityRevision,
    'status': value == null ? 'unknown' : 'confirmed',
    'value': value,
    'confirmed_at': confirmedAt?.toUtc().toIso8601String(),
  };
}

class CloudSavedAnswer {
  const CloudSavedAnswer({
    required this.questionId,
    required this.questionVersion,
    required this.applianceId,
    required this.identityRevision,
    required this.status,
    required this.value,
  });

  final String questionId;
  final int questionVersion;
  final String applianceId;
  final int identityRevision;
  final String status;
  final num? value;

  factory CloudSavedAnswer.fromJson(Map<String, dynamic> json) {
    final status = json['status'];
    final value = json['value'];
    if (json['question_id'] is! String ||
        json['question_version'] is! int ||
        json['appliance_id'] is! String ||
        json['identity_revision'] is! int ||
        (status != 'unknown' && status != 'confirmed') ||
        (status == 'unknown' && value != null) ||
        (status == 'confirmed' &&
            (value is! num || !value.isFinite || value < 0))) {
      throw const FormatException('Invalid saved cloud answer');
    }
    return CloudSavedAnswer(
      questionId: json['question_id'] as String,
      questionVersion: json['question_version'] as int,
      applianceId: json['appliance_id'] as String,
      identityRevision: json['identity_revision'] as int,
      status: status as String,
      value: value as num?,
    );
  }

  bool matches(CloudQuestion question) =>
      questionId == question.id &&
      questionVersion == question.version &&
      applianceId == question.applianceId &&
      identityRevision == question.identityRevision;
}
