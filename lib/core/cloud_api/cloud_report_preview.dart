final _uuid = RegExp(
  r'^[0-9a-f]{8}-[0-9a-f]{4}-[1-8][0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$',
);
final _digest = RegExp(r'^[0-9a-f]{64}$');
final _decimal = RegExp(r'^(0|[1-9][0-9]*)(\.[0-9]+)?$');

Map<String, dynamic> _object(dynamic value) => value is Map<String, dynamic>
    ? value
    : throw const FormatException('Invalid report preview');
String _string(dynamic value) => value is String && value.isNotEmpty
    ? value
    : throw const FormatException('Invalid report preview text');
DateTime _instant(dynamic value) =>
    DateTime.tryParse(_string(value)) ??
    (throw const FormatException('Invalid report preview time'));

class CloudReportEstimate {
  const CloudReportEstimate(
    this.kind,
    this.energyKwh,
    this.costUsd,
    this.periodStart,
    this.periodEnd,
    this.asOf,
    this.sourceRefs,
  );
  final String kind, energyKwh, costUsd, periodStart, periodEnd;
  final DateTime asOf;
  final List<String> sourceRefs;

  factory CloudReportEstimate.fromJson(Map<String, dynamic> json) {
    final kind = _string(json['kind']);
    final energy = _string(json['energy_kwh']);
    final cost = _string(json['cost_usd']);
    final start = _string(json['period_start']);
    final end = _string(json['period_end']);
    final rawRefs = json['source_refs'];
    if (!{'estimated_operating_cost', 'estimated_useful_cost'}.contains(kind) ||
        !_decimal.hasMatch(energy) ||
        !_decimal.hasMatch(cost) ||
        !RegExp(r'^\d{4}-\d{2}-\d{2}$').hasMatch(start) ||
        !RegExp(r'^\d{4}-\d{2}-\d{2}$').hasMatch(end) ||
        end.compareTo(start) <= 0 ||
        rawRefs is! List ||
        rawRefs.length < 2 ||
        rawRefs.length > 4) {
      throw const FormatException('Invalid report estimate');
    }
    var fact = false, tariff = false;
    final refs = <String>[];
    for (final value in rawRefs) {
      final ref = _object(value);
      final id = _string(ref['id']);
      final sourceKind = _string(ref['kind']);
      final revision = ref['revision'];
      if (!_uuid.hasMatch(id) ||
          !{
            'catalog_fact',
            'reviewed_usage_fact',
            'tariff',
          }.contains(sourceKind) ||
          revision is! int ||
          revision < 1) {
        throw const FormatException('Invalid report source');
      }
      fact |=
          sourceKind == 'catalog_fact' || sourceKind == 'reviewed_usage_fact';
      tariff |= sourceKind == 'tariff';
      refs.add(
        '${sourceKind.replaceAll('_', ' ')} revision $revision (${id.substring(0, 8)})',
      );
    }
    if (!fact || !tariff) {
      throw const FormatException('Unsourced report estimate');
    }
    return CloudReportEstimate(
      kind,
      energy,
      cost,
      start,
      end,
      _instant(json['as_of']),
      List.unmodifiable(refs),
    );
  }
}

class CloudReportItem {
  const CloudReportItem(
    this.applianceId,
    this.category,
    this.explanation,
    this.estimate,
  );
  final String applianceId, category, explanation;
  final CloudReportEstimate? estimate;
}

/// Recipient-free status for the most recent delivery request on a preview.
class CloudReportDeliveryStatus {
  const CloudReportDeliveryStatus({
    required this.id,
    required this.state,
    required this.createdAt,
    required this.sentAt,
  });

  final String id, state;
  final DateTime createdAt;
  final DateTime? sentAt;

  factory CloudReportDeliveryStatus.fromJson(
    Map<String, dynamic> json,
    String previewId,
  ) {
    final id = json['id'];
    final state = json['state'];
    final createdRaw = json['created_at'];
    final sentRaw = json['sent_at'];
    if (json.keys.toSet().difference({
          'id',
          'state',
          'created_at',
          'sent_at',
        }).isNotEmpty ||
        id is! String ||
        !_uuid.hasMatch(id) ||
        id == previewId ||
        !{'pending', 'sent', 'canceled'}.contains(state) ||
        createdRaw is! String ||
        (sentRaw != null && sentRaw is! String)) {
      throw const FormatException('Invalid report delivery status');
    }
    final created = DateTime.tryParse(createdRaw);
    final sent = sentRaw == null ? null : DateTime.tryParse(sentRaw as String);
    if (created == null ||
        (sentRaw != null && sent == null) ||
        ((state == 'sent') != (sent != null)) ||
        (sent != null && sent.isBefore(created))) {
      throw const FormatException('Invalid report delivery status');
    }
    return CloudReportDeliveryStatus(
      id: id,
      state: state as String,
      createdAt: created,
      sentAt: sent,
    );
  }
}

class CloudReportPreview {
  const CloudReportPreview(
    this.id,
    this.snapshotSha256,
    this.homeId,
    this.createdAt,
    this.expiresAt,
    this.stale,
    this.assumptions,
    this.items, {
    this.latestDelivery,
  });
  final String id, snapshotSha256, homeId;
  final DateTime createdAt, expiresAt;
  final bool stale;
  final List<String> assumptions;
  final List<CloudReportItem> items;
  final CloudReportDeliveryStatus? latestDelivery;
  bool get isStale => stale || !DateTime.now().isBefore(expiresAt);

  factory CloudReportPreview.fromJson(
    Map<String, dynamic> json,
    String homeId,
    Set<String> applianceIds,
  ) {
    final id = _string(json['id']);
    final digest = _string(json['snapshot_sha256']);
    final responseHome = _string(json['home_id']);
    final created = _instant(json['created_at']);
    final expires = _instant(json['expires_at']);
    final stale = json['stale'];
    final rawAssumptions = json['assumptions'];
    final rawItems = json['items'];
    final rawLatestDelivery = json['latest_delivery'];
    final version = json['schema_version'];
    final measuredStatus = json['measured_status'];
    final recommendationsStatus = json['recommendations_status'];
    final validStatuses =
        (version == 'manual-preview/v1' &&
            measuredStatus == 'not_included' &&
            recommendationsStatus == 'not_included') ||
        (version == 'manual-preview/v2' &&
            {'unavailable', 'partial'}.contains(measuredStatus) &&
            {'unavailable', 'available'}.contains(recommendationsStatus));
    if (!_uuid.hasMatch(id) ||
        !_digest.hasMatch(digest) ||
        responseHome.toLowerCase() != homeId.toLowerCase() ||
        !validStatuses ||
        json['scope'] != 'selected_appliances' ||
        json['home_total_status'] != 'unavailable_incomplete_scope' ||
        !expires.isAfter(created) ||
        stale is! bool ||
        rawAssumptions is! List ||
        rawAssumptions.length > 8 ||
        rawItems is! List ||
        rawItems.isEmpty ||
        rawItems.length > 25) {
      throw const FormatException('Invalid report preview');
    }
    final assumptions = <String>[];
    for (final value in rawAssumptions) {
      if (value is! String || value.length > 300) {
        throw const FormatException('Invalid report assumption');
      }
      assumptions.add(value);
    }
    final items = <CloudReportItem>[];
    final seen = <String>{};
    for (final value in rawItems) {
      final item = _object(value);
      final applianceId = _string(item['appliance_id']);
      final category = _string(item['category']);
      final explanation = _string(item['explanation']);
      if (!_uuid.hasMatch(applianceId) ||
          !applianceIds.contains(applianceId.toLowerCase()) ||
          !seen.add(applianceId.toLowerCase()) ||
          !RegExp(r'^[a-z_]+$').hasMatch(category) ||
          explanation.length > 300) {
        throw const FormatException('Invalid report item');
      }
      items.add(
        CloudReportItem(
          applianceId,
          category,
          explanation,
          item['estimate'] == null
              ? null
              : CloudReportEstimate.fromJson(_object(item['estimate'])),
        ),
      );
    }
    final latestDelivery = rawLatestDelivery == null
        ? null
        : CloudReportDeliveryStatus.fromJson(_object(rawLatestDelivery), id);
    return CloudReportPreview(
      id,
      digest,
      responseHome,
      created,
      expires,
      stale,
      List.unmodifiable(assumptions),
      List.unmodifiable(items),
      latestDelivery: latestDelivery,
    );
  }
}
