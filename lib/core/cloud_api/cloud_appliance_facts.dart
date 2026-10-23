import 'cloud_appliance.dart';
import 'cloud_energy_resolution.dart';
import 'cloud_estimate.dart';
import 'cloud_programs.dart';
import 'cloud_question.dart';

const _statuses = {'ok', 'empty', 'unavailable', 'error'};
final _reasonPattern = RegExp(r'^[a-z][a-z0-9_]{0,63}$');

/// One section of the facts read: its status, optional reason, and body.
class CloudFactsSection<T> {
  const CloudFactsSection({required this.status, this.reason, this.value});
  final String status;
  final String? reason;
  final T? value;

  bool get isOk => status == 'ok';
  bool get isEmpty => status == 'empty';
  bool get isFailed => status == 'unavailable' || status == 'error';

  static CloudFactsSection<T> failed<T>() =>
      CloudFactsSection<T>(status: 'error');
}

class CloudFactsPrograms {
  const CloudFactsPrograms({required this.items, required this.total});
  final List<CloudProgram> items;
  final int total;
}

class CloudFactsRawItems {
  const CloudFactsRawItems(this.items);
  final List<Map<String, dynamic>> items;
}

class CloudApplianceFacts {
  const CloudApplianceFacts({
    required this.applianceId,
    required this.applianceVersion,
    required this.generatedAt,
    required this.identity,
    required this.catalogFacts,
    required this.estimate,
    required this.efficiency,
    required this.programs,
    required this.tips,
    required this.care,
    required this.usageAnswers,
  });

  final String applianceId;
  final int applianceVersion;
  final DateTime generatedAt;
  final CloudFactsSection<CloudAppliance> identity;
  final CloudFactsSection<CloudEnergyResolution> catalogFacts;
  final CloudFactsSection<CloudEstimate> estimate;
  final CloudFactsSection<Map<String, dynamic>> efficiency;
  final CloudFactsSection<CloudFactsPrograms> programs;
  final CloudFactsSection<CloudFactsRawItems> tips;
  final CloudFactsSection<CloudFactsRawItems> care;
  final CloudFactsSection<List<CloudSavedAnswer>> usageAnswers;

  /// The envelope must be valid; a malformed section body only marks that
  /// section `error` so the others stay usable.
  factory CloudApplianceFacts.fromJson(Map<String, dynamic> json) {
    final generatedAt = json['generated_at'] is String
        ? DateTime.tryParse(json['generated_at'] as String)
        : null;
    if (json['appliance_id'] is! String ||
        json['appliance_version'] is! int ||
        generatedAt == null) {
      throw const FormatException('Invalid appliance facts');
    }
    return CloudApplianceFacts(
      applianceId: json['appliance_id'] as String,
      applianceVersion: json['appliance_version'] as int,
      generatedAt: generatedAt,
      identity: _section(
        json['identity'],
        'appliance',
        (body) => CloudAppliance.fromJson(body as Map<String, dynamic>),
      ),
      catalogFacts: _section(
        json['catalog_facts'],
        'resolution',
        (body) => CloudEnergyResolution.fromJson(body as Map<String, dynamic>),
      ),
      estimate: _section(
        json['estimate'],
        'estimate',
        (body) => CloudEstimate.fromJson(body as Map<String, dynamic>),
      ),
      efficiency: _efficiency(json['efficiency']),
      programs: _programs(json['programs']),
      tips: _rawItems(json['tips']),
      care: _rawItems(json['care']),
      usageAnswers: _answers(json['usage_answers']),
    );
  }
}

Map<String, dynamic>? _head(dynamic raw) {
  if (raw is! Map<String, dynamic> || !_statuses.contains(raw['status'])) {
    return null;
  }
  final reason = raw['reason'];
  if (reason != null &&
      (reason is! String || !_reasonPattern.hasMatch(reason))) {
    return null;
  }
  return raw;
}

CloudFactsSection<T> _section<T>(
  dynamic raw,
  String key,
  T Function(dynamic body) parse,
) {
  final head = _head(raw);
  if (head == null) return CloudFactsSection.failed<T>();
  final status = head['status'] as String;
  final reason = head['reason'] as String?;
  if (status != 'ok') {
    return CloudFactsSection<T>(status: status, reason: reason);
  }
  try {
    return CloudFactsSection<T>(
      status: status,
      reason: reason,
      value: parse(head[key]),
    );
  } catch (_) {
    return CloudFactsSection.failed<T>();
  }
}

CloudFactsSection<Map<String, dynamic>> _efficiency(dynamic raw) {
  final head = _head(raw);
  if (head == null) return CloudFactsSection.failed();
  final status = head['status'] as String;
  return CloudFactsSection(
    status: status,
    reason: head['reason'] as String?,
    value: status == 'ok' ? Map<String, dynamic>.from(head) : null,
  );
}

CloudFactsSection<List<CloudSavedAnswer>> _answers(dynamic raw) {
  final head = _head(raw);
  if (head == null) return CloudFactsSection.failed();
  final status = head['status'] as String;
  final reason = head['reason'] as String?;
  if (status == 'unavailable' || status == 'error') {
    return CloudFactsSection(status: status, reason: reason);
  }
  try {
    final rows = head['items'];
    if (rows is! List || (status == 'empty' && rows.isNotEmpty)) {
      throw const FormatException('Invalid usage answers section');
    }
    return CloudFactsSection(
      status: status,
      reason: reason,
      value: [
        for (final row in rows)
          CloudSavedAnswer.fromJson(row as Map<String, dynamic>),
      ],
    );
  } catch (_) {
    return CloudFactsSection.failed();
  }
}

CloudFactsSection<CloudFactsRawItems> _rawItems(dynamic raw) {
  final head = _head(raw);
  if (head == null) return CloudFactsSection.failed();
  final status = head['status'] as String;
  final items = head['items'];
  if (status == 'ok' &&
      (items is! List || items.any((row) => row is! Map<String, dynamic>))) {
    return CloudFactsSection.failed();
  }
  return CloudFactsSection(
    status: status,
    reason: head['reason'] as String?,
    value: status == 'ok'
        ? CloudFactsRawItems(List<Map<String, dynamic>>.from(items as List))
        : null,
  );
}

CloudFactsSection<CloudFactsPrograms> _programs(dynamic raw) {
  final head = _head(raw);
  if (head == null) return CloudFactsSection.failed();
  final status = head['status'] as String;
  final reason = head['reason'] as String?;
  if (status == 'unavailable' || status == 'error') {
    return CloudFactsSection(status: status, reason: reason);
  }
  try {
    final rows = head['items'];
    final total = head['total'];
    if (rows is! List || rows.length > 100 || total is! int || total < 0) {
      throw const FormatException('Invalid programs section');
    }
    final items = [
      for (final row in rows)
        CloudProgram.fromJson(row as Map<String, dynamic>),
    ];
    if (items.map((p) => p.id.toLowerCase()).toSet().length != items.length ||
        (status == 'ok' && (items.isEmpty || total < 1)) ||
        (status == 'empty' && (items.isNotEmpty || total != 0))) {
      throw const FormatException('Invalid programs section');
    }
    return CloudFactsSection(
      status: status,
      reason: reason,
      value: CloudFactsPrograms(items: items, total: total),
    );
  } catch (_) {
    return CloudFactsSection.failed();
  }
}
