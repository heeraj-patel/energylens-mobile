final _uuid = RegExp(
  r'^[0-9a-fA-F]{8}-[0-9a-fA-F]{4}-[1-8][0-9a-fA-F]{3}-[89ab][0-9a-fA-F]{3}-[0-9a-fA-F]{12}$',
);
final _sha256 = RegExp(r'^[0-9a-f]{64}$');

bool _text(dynamic value, int max) =>
    value is String &&
    value.isNotEmpty &&
    value.length <= max &&
    value.trim() == value;
DateTime? _instant(dynamic value) =>
    _text(value, 64) ? DateTime.tryParse(value as String) : null;

class CloudProgram {
  const CloudProgram({
    required this.id,
    required this.title,
    required this.administratorName,
    required this.benefitKind,
    required this.reasons,
    required this.sourceUrl,
    required this.sourceSha256,
    required this.reviewExpiresAt,
  });
  final String id;
  final String title;
  final String administratorName;
  final String benefitKind;
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
      'benefit_kind',
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
        !_text(json['benefit_kind'], 80) ||
        json['status'] != 'unknown' ||
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
      benefitKind: json['benefit_kind'] as String,
      reasons: List<String>.from(reasons),
      sourceUrl: uri,
      sourceSha256: json['source_sha256'] as String,
      reviewExpiresAt: expiry,
    );
  }
}

class CloudProgramPage {
  const CloudProgramPage({
    required this.programs,
    required this.asOf,
    required this.locationRequired,
  });
  final List<CloudProgram> programs;
  final DateTime asOf;
  final bool locationRequired;

  factory CloudProgramPage.fromJson(Map<String, dynamic> json) {
    final rows = json['programs'];
    final asOf = _instant(json['as_of']);
    final reason = json['reason'];
    if (json.keys.any(
          (key) => !{'programs', 'as_of', 'reason'}.contains(key),
        ) ||
        rows is! List ||
        rows.length > 100 ||
        asOf == null ||
        (reason != null && reason != 'location_required') ||
        (reason == 'location_required' && rows.isNotEmpty)) {
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
    );
  }
}
