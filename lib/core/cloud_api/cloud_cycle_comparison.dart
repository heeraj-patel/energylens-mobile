final _uuid = RegExp(
  r'^[0-9a-fA-F]{8}-[0-9a-fA-F]{4}-[1-8][0-9a-fA-F]{3}-[89abAB][0-9a-fA-F]{3}-[0-9a-fA-F]{12}$',
);

const cycleComparisonInterpretation =
    'Measured electricity for this tagged cycle compared with the reviewed source laboratory reference. Conditions may differ.';

class CloudCycleReference {
  const CloudCycleReference({
    required this.id,
    required this.valueKWhPerCycle,
    required this.testBasis,
    required this.cycleDefinition,
    required this.sourceKind,
    required this.sourceUrl,
    required this.reviewedAt,
  });

  final String id;
  final double valueKWhPerCycle;
  final String testBasis;
  final String cycleDefinition;
  final String sourceKind;
  final Uri sourceUrl;
  final DateTime reviewedAt;

  factory CloudCycleReference.fromJson(Map<String, dynamic> json) {
    const allowed = {
      'id',
      'value_kwh_per_cycle',
      'test_basis',
      'cycle_definition',
      'source_kind',
      'source_url',
      'reviewed_at',
    };
    if (json.keys.any((key) => !allowed.contains(key))) {
      throw const FormatException('Unexpected reviewed reference claim');
    }
    final id = json['id'];
    final value = json['value_kwh_per_cycle'];
    final basis = json['test_basis'];
    final definition = json['cycle_definition'];
    final kind = json['source_kind'];
    final rawUrl = json['source_url'];
    final reviewed = json['reviewed_at'];
    final url = rawUrl is String ? Uri.tryParse(rawUrl) : null;
    final reviewedAt = reviewed is String ? DateTime.tryParse(reviewed) : null;
    if (id is! String ||
        !_uuid.hasMatch(id) ||
        value is! num ||
        !value.toDouble().isFinite ||
        value <= 0 ||
        basis is! String ||
        basis.trim().isEmpty ||
        definition is! String ||
        definition.trim().isEmpty ||
        kind is! String ||
        kind.isEmpty ||
        url == null ||
        !const ['https', 'http'].contains(url.scheme) ||
        url.host.isEmpty ||
        reviewedAt == null ||
        !reviewedAt.isUtc) {
      throw const FormatException('Invalid reviewed cycle reference');
    }
    return CloudCycleReference(
      id: id,
      valueKWhPerCycle: value.toDouble(),
      testBasis: basis,
      cycleDefinition: definition,
      sourceKind: kind,
      sourceUrl: url,
      reviewedAt: reviewedAt,
    );
  }
}

class CloudCycleReferenceOption {
  const CloudCycleReferenceOption({
    required this.status,
    this.reason,
    this.fact,
  });

  final String status;
  final String? reason;
  final CloudCycleReference? fact;

  factory CloudCycleReferenceOption.fromJson(Map<String, dynamic> json) {
    if (json.keys.any(
      (key) => !const {'status', 'reason', 'fact'}.contains(key),
    )) {
      throw const FormatException('Unexpected cycle reference claim');
    }
    final status = json['status'];
    final reason = json['reason'];
    final rawFact = json['fact'];
    if (status == 'available' &&
        reason == null &&
        rawFact is Map<String, dynamic>) {
      return CloudCycleReferenceOption(
        status: status as String,
        fact: CloudCycleReference.fromJson(rawFact),
      );
    }
    if (status == 'unavailable' &&
        reason is String &&
        reason.isNotEmpty &&
        rawFact == null) {
      return CloudCycleReferenceOption(
        status: status as String,
        reason: reason,
      );
    }
    throw const FormatException('Invalid cycle reference option');
  }
}

class CloudCycleComparisonRequest {
  const CloudCycleComparisonRequest({
    required this.start,
    required this.end,
    required this.attachmentId,
    required this.reference,
    required this.dedicatedNoOtherLoads,
  });

  final DateTime start;
  final DateTime end;
  final String attachmentId;
  final CloudCycleReference reference;
  final bool dedicatedNoOtherLoads;

  Map<String, dynamic> toJson() {
    final now = DateTime.now().toUtc();
    if (!start.isUtc ||
        !end.isUtc ||
        !end.isAfter(start) ||
        end.difference(start) > const Duration(hours: 24) ||
        start.isBefore(now.subtract(const Duration(days: 30))) ||
        end.isAfter(now) ||
        !_uuid.hasMatch(attachmentId)) {
      throw ArgumentError('Invalid tagged cycle');
    }
    return {
      'start': start.toIso8601String(),
      'end': end.toIso8601String(),
      'attachment_id': attachmentId,
      'fact_id': reference.id,
      'confirmed_test_basis': reference.testBasis,
      'confirmed_cycle_definition': reference.cycleDefinition,
      'dedicated_no_other_loads': dedicatedNoOtherLoads,
    };
  }
}

class CloudCycleComparisonResult {
  const CloudCycleComparisonResult({
    required this.status,
    required this.start,
    required this.end,
    this.reason,
    this.factId,
    this.measuredKWh,
    this.labReferenceKWhPerCycle,
    this.differenceKWh,
  });

  final String status;
  final DateTime start;
  final DateTime end;
  final String? reason;
  final String? factId;
  final double? measuredKWh;
  final double? labReferenceKWhPerCycle;
  final double? differenceKWh;

  factory CloudCycleComparisonResult.fromJson(
    Map<String, dynamic> json,
    CloudCycleComparisonRequest request,
  ) {
    const allowed = {
      'status',
      'reason',
      'start',
      'end',
      'fact_id',
      'measured_kwh',
      'lab_reference_kwh_per_cycle',
      'difference_kwh',
      'interpretation',
    };
    if (json.keys.any((key) => !allowed.contains(key))) {
      throw const FormatException('Unexpected comparison claim');
    }
    final start = json['start'] is String
        ? DateTime.tryParse(json['start'] as String)
        : null;
    final end = json['end'] is String
        ? DateTime.tryParse(json['end'] as String)
        : null;
    if (start == null ||
        end == null ||
        !start.isUtc ||
        !end.isUtc ||
        start != request.start ||
        end != request.end ||
        json['interpretation'] != cycleComparisonInterpretation) {
      throw const FormatException('Cycle comparison changed context');
    }
    final status = json['status'];
    if (status == 'unavailable' &&
        json['reason'] is String &&
        (json['reason'] as String).isNotEmpty &&
        json['fact_id'] == null &&
        json['measured_kwh'] == null &&
        json['lab_reference_kwh_per_cycle'] == null &&
        json['difference_kwh'] == null) {
      return CloudCycleComparisonResult(
        status: 'unavailable',
        reason: json['reason'] as String,
        start: start,
        end: end,
      );
    }
    final measured = json['measured_kwh'];
    final lab = json['lab_reference_kwh_per_cycle'];
    final difference = json['difference_kwh'];
    if (status == 'available' &&
        json['reason'] == null &&
        json['fact_id'] == request.reference.id &&
        measured is num &&
        lab is num &&
        difference is num &&
        measured.toDouble().isFinite &&
        lab.toDouble().isFinite &&
        difference.toDouble().isFinite &&
        measured >= 0 &&
        lab > 0 &&
        (lab - request.reference.valueKWhPerCycle).abs() < 0.000001 &&
        (difference - (measured - lab)).abs() < 0.000001) {
      return CloudCycleComparisonResult(
        status: 'available',
        start: start,
        end: end,
        factId: request.reference.id,
        measuredKWh: measured.toDouble(),
        labReferenceKWhPerCycle: lab.toDouble(),
        differenceKWh: difference.toDouble(),
      );
    }
    throw const FormatException('Invalid cycle comparison');
  }
}
