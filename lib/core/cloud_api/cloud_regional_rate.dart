/// Public regional estimate. It is never a home's effective tariff.
class CloudRegionalRate {
  const CloudRegionalRate({
    required this.usdPerKwh,
    required this.source,
    required this.sourceLabel,
    required this.asOf,
    required this.region,
    required this.sourceUrl,
    required this.fetchedAt,
    required this.isStale,
    required this.isStatic,
  });

  final double usdPerKwh;
  final String source;
  final String sourceLabel;
  final String asOf;
  final String? region;
  final Uri? sourceUrl;
  final DateTime? fetchedAt;
  final bool isStale;
  final bool isStatic;

  factory CloudRegionalRate.fromJson(Map<String, dynamic> json) {
    const keys = {
      'rate_usd_per_kwh',
      'source',
      'source_label',
      'as_of',
      'region',
      'source_url',
      'fetched_at',
      'is_stale',
      'is_static',
    };
    const requiredKeys = {
      'rate_usd_per_kwh',
      'source',
      'source_label',
      'as_of',
      'region',
      'fetched_at',
      'is_stale',
      'is_static',
    };
    final amount = json['rate_usd_per_kwh'];
    final source = json['source'];
    final label = json['source_label'];
    final asOf = json['as_of'];
    final region = json['region'];
    final rawUrl = json['source_url'];
    final rawFetch = json['fetched_at'];
    final stale = json['is_stale'];
    final staticRate = json['is_static'];
    if (!json.keys.toSet().containsAll(requiredKeys) ||
        json.keys.any((key) => !keys.contains(key)) ||
        amount is! num ||
        !amount.isFinite ||
        amount <= 0 ||
        (source != 'state' && source != 'national') ||
        label is! String ||
        label.isEmpty ||
        asOf is! String ||
        !_validDate(asOf) ||
        region != null && region is! String ||
        stale is! bool ||
        staticRate is! bool ||
        (staticRate && (rawFetch != null || stale)) ||
        (!staticRate && rawFetch is! String)) {
      throw const FormatException('Invalid regional electricity rate');
    }
    final Uri? sourceUrl;
    if (rawUrl == null) {
      sourceUrl = null;
    } else if (rawUrl is String) {
      final parsed = Uri.tryParse(rawUrl);
      if (parsed == null || !parsed.hasScheme) {
        throw const FormatException('Invalid regional rate source URL');
      }
      sourceUrl = parsed;
    } else {
      throw const FormatException('Invalid regional rate source URL');
    }
    final DateTime? fetchedAt;
    if (rawFetch == null) {
      fetchedAt = null;
    } else if (rawFetch is String &&
        RegExp(
          r'^\d{4}-\d{2}-\d{2}T\d{2}:\d{2}:\d{2}(?:\.\d+)?(?:Z|[+-]\d{2}:\d{2})$',
        ).hasMatch(rawFetch)) {
      fetchedAt = DateTime.tryParse(rawFetch);
      if (fetchedAt == null) {
        throw const FormatException('Invalid regional rate fetch time');
      }
    } else {
      throw const FormatException('Invalid regional rate fetch time');
    }
    return CloudRegionalRate(
      usdPerKwh: amount.toDouble(),
      source: source as String,
      sourceLabel: label,
      asOf: asOf,
      region: region as String?,
      sourceUrl: sourceUrl,
      fetchedAt: fetchedAt,
      isStale: stale,
      isStatic: staticRate,
    );
  }
}

bool _validDate(String value) {
  if (!RegExp(r'^\d{4}-\d{2}-\d{2}$').hasMatch(value)) return false;
  final year = int.parse(value.substring(0, 4));
  final month = int.parse(value.substring(5, 7));
  final day = int.parse(value.substring(8, 10));
  final parsed = DateTime.utc(year, month, day);
  return parsed.year == year && parsed.month == month && parsed.day == day;
}
