class CloudVersioned<T> {
  const CloudVersioned({required this.value, required this.etag});
  final T value;
  final String etag;
}

class CloudAccountPreferences {
  const CloudAccountPreferences({
    required this.version,
    required this.emailReportsEnabled,
    required this.historyDisclosureAcceptedAt,
  });
  final int version;
  final bool emailReportsEnabled;
  final DateTime? historyDisclosureAcceptedAt;

  bool get historyAccepted => historyDisclosureAcceptedAt != null;

  factory CloudAccountPreferences.fromJson(Map<String, dynamic> json) {
    final version = json['version'];
    final accepted = json['history_disclosure_accepted_at'];
    final acceptedAt = accepted is String ? DateTime.tryParse(accepted) : null;
    if (version is! int ||
        version < 1 ||
        json['schema_version'] != 1 ||
        json['email_reports_enabled'] is! bool ||
        accepted != null && acceptedAt == null) {
      throw const FormatException('Invalid account preferences');
    }
    return CloudAccountPreferences(
      version: version,
      emailReportsEnabled: json['email_reports_enabled'] as bool,
      historyDisclosureAcceptedAt: acceptedAt,
    );
  }
}

class CloudHomePreferences {
  const CloudHomePreferences({
    required this.version,
    required this.goal,
    required this.comfortPriority,
  });
  final int version;
  final String goal;
  final String comfortPriority;

  static const goals = {
    'reduce_cost',
    'reduce_energy',
    'understand_usage',
    'unspecified',
  };
  static const comfortPriorities = {'high', 'balanced', 'flexible', 'unknown'};

  factory CloudHomePreferences.fromJson(Map<String, dynamic> json) {
    final version = json['version'];
    final goal = json['goal'];
    final comfort = json['comfort_priority'];
    if (version is! int ||
        version < 1 ||
        json['schema_version'] != 1 ||
        goal is! String ||
        !goals.contains(goal) ||
        comfort is! String ||
        !comfortPriorities.contains(comfort)) {
      throw const FormatException('Invalid home preferences');
    }
    return CloudHomePreferences(
      version: version,
      goal: goal,
      comfortPriority: comfort,
    );
  }
}

CloudVersioned<T> checkedPreference<T>(T value, String? etag, int version) {
  if (etag != '"$version"') {
    throw const FormatException('Invalid preference ETag');
  }
  return CloudVersioned(value: value, etag: etag!);
}
