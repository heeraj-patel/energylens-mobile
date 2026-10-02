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
