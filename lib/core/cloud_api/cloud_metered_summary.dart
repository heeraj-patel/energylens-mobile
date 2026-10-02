class CloudMeteredSummary {
  const CloudMeteredSummary({
    required this.kind,
    required this.bucketStart,
    required this.sensorId,
    required this.hubId,
    required this.ownershipEpoch,
    required this.computedAt,
    required this.sourceCount,
    this.attachmentId,
    this.energyWh,
    this.coveredSeconds,
    this.intervalCount,
    this.status,
    this.allocationMethod,
    this.sampleCount,
    this.minWatts,
    this.maxWatts,
    this.meanWatts,
    this.gapOverlapCount,
    this.droppedCountStarted,
  });

  final String kind;
  final DateTime bucketStart;
  final String sensorId;
  final String hubId;
  final int ownershipEpoch;
  final DateTime computedAt;
  final int sourceCount;
  final String? attachmentId;
  final double? energyWh;
  final double? coveredSeconds;
  final int? intervalCount;
  final String? status;
  final String? allocationMethod;
  final int? sampleCount;
  final double? minWatts;
  final double? maxWatts;
  final double? meanWatts;
  final int? gapOverlapCount;
  final int? droppedCountStarted;

  factory CloudMeteredSummary.fromJson(Map<String, dynamic> json) {
    String nonempty(String key) {
      final value = json[key];
      if (value is! String || value.isEmpty) {
        throw const FormatException('Invalid metered summary identity');
      }
      return value;
    }

    DateTime timestamp(String key) {
      final value = json[key];
      final parsed = value is String ? DateTime.tryParse(value) : null;
      if (parsed == null || !parsed.isUtc) {
        throw const FormatException('Invalid metered summary time');
      }
      return parsed;
    }

    int count(String key, {bool positive = false}) {
      final value = json[key];
      if (value is! int || value < (positive ? 1 : 0)) {
        throw const FormatException('Invalid metered summary count');
      }
      return value;
    }

    double number(String key) {
      final value = json[key];
      if (value is! num || !value.isFinite || value < 0) {
        throw const FormatException('Invalid metered summary value');
      }
      return value.toDouble();
    }

    final kind = nonempty('kind');
    final bucket = timestamp('bucket_start');
    final computed = timestamp('computed_at');
    final sensor = nonempty('sensor_id');
    final hub = nonempty('hub_id');
    final epoch = count('ownership_epoch', positive: true);
    final refs = json['source_refs'];
    if (refs is! List) {
      throw const FormatException('Invalid metered summary sources');
    }
    switch (kind) {
      case 'energy':
        final status = nonempty('status');
        final method = nonempty('allocation_method');
        if (!{
              'complete',
              'no_intervals',
              'overlap_conflict',
            }.contains(status) ||
            !{'exact', 'duration_proportional', 'none'}.contains(method) ||
            (status == 'complete') != (json['energy_wh'] != null) ||
            (status == 'complete') != (json['covered_seconds'] != null)) {
          throw const FormatException('Invalid measured energy quality');
        }
        return CloudMeteredSummary(
          kind: kind,
          bucketStart: bucket,
          sensorId: sensor,
          hubId: hub,
          ownershipEpoch: epoch,
          computedAt: computed,
          sourceCount: refs.length,
          attachmentId: nonempty('attachment_id'),
          energyWh: status == 'complete' ? number('energy_wh') : null,
          coveredSeconds: status == 'complete'
              ? number('covered_seconds')
              : null,
          intervalCount: count('interval_count'),
          status: status,
          allocationMethod: method,
        );
      case 'power_sample_stats':
        final samples = count('sample_count');
        final min = samples == 0 ? null : number('min_watts');
        final max = samples == 0 ? null : number('max_watts');
        final mean = samples == 0 ? null : number('mean_watts');
        if (samples == 0 &&
                (json['min_watts'] != null ||
                    json['max_watts'] != null ||
                    json['mean_watts'] != null) ||
            samples > 0 && (min! > mean! || mean > max!)) {
          throw const FormatException('Invalid power sample range');
        }
        return CloudMeteredSummary(
          kind: kind,
          bucketStart: bucket,
          sensorId: sensor,
          hubId: hub,
          ownershipEpoch: epoch,
          computedAt: computed,
          sourceCount: refs.length,
          sampleCount: samples,
          minWatts: min,
          maxWatts: max,
          meanWatts: mean,
        );
      case 'coverage_gap':
        return CloudMeteredSummary(
          kind: kind,
          bucketStart: bucket,
          sensorId: sensor,
          hubId: hub,
          ownershipEpoch: epoch,
          computedAt: computed,
          sourceCount: refs.length,
          gapOverlapCount: count('gap_overlap_count'),
          droppedCountStarted: count('dropped_count_started'),
        );
      default:
        throw const FormatException('Unknown metered summary kind');
    }
  }
}

class CloudMeteredSummaryPage {
  const CloudMeteredSummaryPage({
    required this.granularity,
    required this.summaries,
    required this.nextCursor,
  });

  final String granularity;
  final List<CloudMeteredSummary> summaries;
  final String? nextCursor;

  factory CloudMeteredSummaryPage.fromJson(Map<String, dynamic> json) {
    final granularity = json['granularity'];
    final rows = json['summaries'];
    final next = json['next_cursor'];
    if ((granularity != 'hour' && granularity != 'day') ||
        rows is! List ||
        rows.length > 100 ||
        (next != null && (next is! String || next.isEmpty))) {
      throw const FormatException('Invalid metered summary page');
    }
    return CloudMeteredSummaryPage(
      granularity: granularity as String,
      summaries: rows
          .map(
            (row) => CloudMeteredSummary.fromJson(row as Map<String, dynamic>),
          )
          .toList(),
      nextCursor: next as String?,
    );
  }
}
