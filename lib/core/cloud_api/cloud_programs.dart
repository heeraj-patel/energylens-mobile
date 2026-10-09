import 'dart:convert';

final _uuid = RegExp(
  r'^[0-9a-fA-F]{8}-[0-9a-fA-F]{4}-[1-8][0-9a-fA-F]{3}-[89ab][0-9a-fA-F]{3}-[0-9a-fA-F]{12}$',
);
final _sha256 = RegExp(r'^[0-9a-f]{64}$');
final _rfc3339 = RegExp(
  r'^\d{4}-\d{2}-\d{2}T\d{2}:\d{2}:\d{2}(?:\.\d+)?(?:Z|[+-]\d{2}:\d{2})$',
);

bool _text(dynamic value, int max) =>
    value is String &&
    value.isNotEmpty &&
    value.length <= max &&
    value.trim() == value;
bool _benefitDisplay(dynamic value) =>
    value is String &&
    value.isNotEmpty &&
    value.trim() == value &&
    value.runes.length <= 160 &&
    !value.runes.any((rune) => rune < 0x20 || (rune >= 0x7f && rune <= 0x9f));
DateTime? _instant(dynamic value) =>
    _text(value, 64) ? DateTime.tryParse(value as String) : null;

class CloudProgram {
  const CloudProgram({
    required this.id,
    required this.title,
    required this.administratorName,
    required this.administratorKind,
    required this.benefitKind,
    required this.benefitDisplay,
    required this.benefitTerms,
    required this.eligibilityTerms,
    required this.stackingTerms,
    required this.availabilityStatus,
    required this.status,
    required this.reasons,
    required this.sourceUrl,
    required this.sourceSha256,
    required this.reviewExpiresAt,
  });
  final String id;
  final String title;
  final String administratorName;
  final String administratorKind;
  final String benefitKind;
  final String benefitDisplay;
  final Map<String, dynamic> benefitTerms;
  final Map<String, dynamic> eligibilityTerms;
  final Map<String, dynamic> stackingTerms;
  final String availabilityStatus;
  final String status;
  final List<String> reasons;
  final Uri sourceUrl;
  final String sourceSha256;
  final DateTime reviewExpiresAt;

  factory CloudProgram.fromJson(Map<String, dynamic> json) {
    const fields = {
      'program_id',
      'revision_id',
      'title',
      'administrator_name',
      'administrator_kind',
      'benefit_kind',
      'benefit_display',
      'benefit_terms',
      'eligibility_terms',
      'stacking_terms',
      'availability_status',
      'status',
      'reasons',
      'source_url',
      'source_sha256',
      'review_expires_at',
    };
    final reasons = json['reasons'];
    final uri = json['source_url'] is String
        ? Uri.tryParse(json['source_url'] as String)
        : null;
    final expiry = _instant(json['review_expires_at']);
    if (json.keys.any((key) => !fields.contains(key)) ||
        json['program_id'] is! String ||
        !_uuid.hasMatch(json['program_id'] as String) ||
        json['revision_id'] is! String ||
        !_uuid.hasMatch(json['revision_id'] as String) ||
        !_text(json['title'], 200) ||
        !_text(json['administrator_name'], 200) ||
        !{
          'utility',
          'city',
          'county',
          'state',
          'tribal',
          'federal',
          'manufacturer',
        }.contains(json['administrator_kind']) ||
        !_text(json['benefit_kind'], 80) ||
        !_benefitDisplay(json['benefit_display']) ||
        json['benefit_terms'] is! Map<String, dynamic> ||
        json['eligibility_terms'] is! Map<String, dynamic> ||
        json['stacking_terms'] is! Map<String, dynamic> ||
        !{
          'open',
          'upcoming',
          'waitlist',
          'exhausted',
          'suspended',
          'closed',
          'unknown',
        }.contains(json['availability_status']) ||
        !{'unknown', 'potentially_eligible'}.contains(json['status']) ||
        reasons is! List ||
        reasons.isEmpty ||
        reasons.length > 20 ||
        reasons.any((reason) => !_text(reason, 120)) ||
        reasons.toSet().length != reasons.length ||
        uri == null ||
        uri.scheme != 'https' ||
        uri.host.isEmpty ||
        uri.userInfo.isNotEmpty ||
        json['source_sha256'] is! String ||
        !_sha256.hasMatch(json['source_sha256'] as String) ||
        expiry == null) {
      throw const FormatException('Invalid reviewed program candidate');
    }
    return CloudProgram(
      id: json['program_id'] as String,
      title: json['title'] as String,
      administratorName: json['administrator_name'] as String,
      administratorKind: json['administrator_kind'] as String,
      benefitKind: json['benefit_kind'] as String,
      benefitDisplay: json['benefit_display'] as String,
      benefitTerms: Map<String, dynamic>.from(json['benefit_terms'] as Map),
      eligibilityTerms: Map<String, dynamic>.from(
        json['eligibility_terms'] as Map,
      ),
      stackingTerms: Map<String, dynamic>.from(json['stacking_terms'] as Map),
      availabilityStatus: json['availability_status'] as String,
      status: json['status'] as String,
      reasons: List<String>.from(reasons),
      sourceUrl: uri,
      sourceSha256: json['source_sha256'] as String,
      reviewExpiresAt: expiry,
    );
  }
}

class CloudProgramCoverageScope {
  const CloudProgramCoverageScope({
    required this.kind,
    required this.name,
    required this.providerRole,
    required this.status,
    required this.checkedAt,
    required this.retryAfter,
    required this.failureCode,
  });
  final String kind;
  final String name;
  final String? providerRole;
  final String status;
  final DateTime? checkedAt;
  final DateTime? retryAfter;
  final String? failureCode;

  factory CloudProgramCoverageScope.fromJson(Map<String, dynamic> json) {
    const kinds = {
      'utility',
      'city',
      'county',
      'state',
      'federal',
      'tribal',
      'manufacturer',
    };
    const roles = {
      'electric_service_candidate',
      'electric_distributor',
      'electric_retailer',
      'gas_distributor',
      'gas_retailer',
      'other_fuel',
    };
    const statuses = {'identified', 'checked', 'failed', 'pending'};
    final kind = json['kind'];
    final role = json['provider_role'];
    final status = json['status'];
    final checked = json['checked_at'];
    final retry = json['retry_after'];
    final failure = json['failure_code'];
    if (json.keys.toSet().difference({
          'kind',
          'key',
          'name',
          'provider_role',
          'status',
          'checked_at',
          'retry_after',
          'failure_code',
        }).isNotEmpty ||
        json.length != 8 ||
        !kinds.contains(kind) ||
        !_text(json['key'], 200) ||
        !_text(json['name'], 200) ||
        (kind == 'utility' ? !roles.contains(role) : role != null) ||
        !statuses.contains(status) ||
        (checked != null && _instant(checked) == null) ||
        (status == 'checked' && checked == null) ||
        (retry != null && _instant(retry) == null) ||
        (failure != null && !_text(failure, 64)) ||
        (status == 'failed' && failure == null)) {
      throw const FormatException('Invalid program discovery scope');
    }
    return CloudProgramCoverageScope(
      kind: kind as String,
      name: json['name'] as String,
      providerRole: role as String?,
      status: status as String,
      checkedAt: checked == null ? null : _instant(checked),
      retryAfter: retry == null ? null : _instant(retry),
      failureCode: failure as String?,
    );
  }
}

class CloudProgramCoverage {
  const CloudProgramCoverage({
    required this.state,
    required this.startedAt,
    required this.finishedAt,
    required this.limitations,
    required this.resolutionProvenance,
    required this.scopes,
  });
  final String state;
  final DateTime startedAt;
  final DateTime? finishedAt;
  final List<String> limitations;
  final Map<String, dynamic> resolutionProvenance;
  final List<CloudProgramCoverageScope> scopes;

  factory CloudProgramCoverage.fromJson(Map<String, dynamic> json) {
    final started = _instant(json['started_at']);
    final finished = json['finished_at'];
    final limitations = json['limitations'];
    final provenance = json['resolution_provenance'];
    final scopes = json['scopes'];
    if (json.keys.toSet().difference({
          'run_id',
          'category',
          'state',
          'started_at',
          'finished_at',
          'limitations',
          'resolution_provenance',
          'scopes',
        }).isNotEmpty ||
        json.length != 8 ||
        !_uuid.hasMatch(
          json['run_id'] is String ? json['run_id'] as String : '',
        ) ||
        (json['category'] != null && !_text(json['category'], 100)) ||
        !{'running', 'complete', 'partial', 'failed'}.contains(json['state']) ||
        started == null ||
        (finished != null && _instant(finished) == null) ||
        limitations is! List ||
        limitations.length > 32 ||
        limitations.any((item) => !_text(item, 120)) ||
        limitations.toSet().length != limitations.length ||
        provenance is! Map ||
        provenance.keys.any((key) => key is! String) ||
        provenance.length > 10 ||
        jsonEncode(provenance).length > 4096 ||
        scopes is! List ||
        scopes.length > 128) {
      throw const FormatException('Invalid program discovery coverage');
    }
    return CloudProgramCoverage(
      state: json['state'] as String,
      startedAt: started,
      finishedAt: finished == null ? null : _instant(finished),
      limitations: List<String>.from(limitations),
      resolutionProvenance: Map<String, dynamic>.from(provenance),
      scopes: scopes.map((row) {
        if (row is! Map<String, dynamic>) {
          throw const FormatException('Invalid program discovery scope');
        }
        return CloudProgramCoverageScope.fromJson(row);
      }).toList(),
    );
  }
}

class CloudProgramPage {
  const CloudProgramPage({
    required this.programs,
    required this.asOf,
    required this.locationRequired,
    required this.coverage,
  });
  final List<CloudProgram> programs;
  final DateTime asOf;
  final bool locationRequired;
  final CloudProgramCoverage? coverage;

  factory CloudProgramPage.fromJson(Map<String, dynamic> json) {
    final rows = json['programs'];
    final asOf = _instant(json['as_of']);
    final reason = json['reason'];
    if (json.keys.any(
          (key) => !{'programs', 'as_of', 'reason', 'coverage'}.contains(key),
        ) ||
        rows is! List ||
        rows.length > 100 ||
        asOf == null ||
        (reason != null && reason != 'location_required') ||
        (reason == 'location_required' &&
            (rows.isNotEmpty || json.containsKey('coverage'))) ||
        (reason == null && !json.containsKey('coverage')) ||
        (json['coverage'] != null &&
            json['coverage'] is! Map<String, dynamic>)) {
      throw const FormatException('Invalid reviewed program page');
    }
    final programs = rows.map((row) {
      if (row is! Map<String, dynamic>) {
        throw const FormatException('Invalid reviewed program candidate');
      }
      return CloudProgram.fromJson(row);
    }).toList();
    if (programs.map((program) => program.id.toLowerCase()).toSet().length !=
        programs.length) {
      throw const FormatException('Duplicate reviewed program');
    }
    return CloudProgramPage(
      programs: programs,
      asOf: asOf,
      locationRequired: reason == 'location_required',
      coverage: json['coverage'] == null
          ? null
          : CloudProgramCoverage.fromJson(
              json['coverage'] as Map<String, dynamic>,
            ),
    );
  }
}

class CloudProgramRefresh {
  const CloudProgramRefresh({
    required this.requestId,
    required this.state,
    required this.createdAt,
    required this.finishedAt,
    required this.coverage,
  });

  final String requestId;
  final String state;
  final DateTime createdAt;
  final DateTime? finishedAt;
  final CloudProgramCoverage? coverage;

  bool get isFinished =>
      state == 'complete' || state == 'partial' || state == 'failed';

  factory CloudProgramRefresh.fromJson(Map<String, dynamic> json) {
    DateTime? timestamp(dynamic value) =>
        _text(value, 64) && _rfc3339.hasMatch(value as String)
        ? DateTime.tryParse(value)
        : null;
    final created = timestamp(json['created_at']);
    final finished = json['finished_at'] == null
        ? null
        : timestamp(json['finished_at']);
    final state = json['state'];
    final active = state == 'pending' || state == 'running';
    if (json.keys.toSet().difference({
          'request_id',
          'state',
          'created_at',
          'finished_at',
          'coverage',
        }).isNotEmpty ||
        json.length != 5 ||
        json['request_id'] is! String ||
        !_uuid.hasMatch(json['request_id'] as String) ||
        !{
          'pending',
          'running',
          'complete',
          'partial',
          'failed',
        }.contains(state) ||
        created == null ||
        (active && (finished != null || json['coverage'] != null)) ||
        (!active && finished == null) ||
        ((state == 'complete' || state == 'partial') &&
            json['coverage'] == null) ||
        (finished != null && finished.isBefore(created)) ||
        (json['coverage'] != null &&
            json['coverage'] is! Map<String, dynamic>)) {
      throw const FormatException('Invalid program refresh status');
    }
    return CloudProgramRefresh(
      requestId: json['request_id'] as String,
      state: state as String,
      createdAt: created,
      finishedAt: finished,
      coverage: json['coverage'] == null
          ? null
          : CloudProgramCoverage.fromJson(
              json['coverage'] as Map<String, dynamic>,
            ),
    );
  }
}
