import 'package:flutter/material.dart';

import '../../core/cloud_api/cloud_api_client.dart';
import '../../core/cloud_api/cloud_home.dart';
import '../../core/cloud_api/cloud_metered_summary.dart';

class CloudMeteredSummaryScreen extends StatefulWidget {
  const CloudMeteredSummaryScreen({
    super.key,
    required this.api,
    required this.home,
  });

  final CloudApiClient api;
  final CloudHome home;

  @override
  State<CloudMeteredSummaryScreen> createState() =>
      _CloudMeteredSummaryScreenState();
}

class _CloudMeteredSummaryScreenState extends State<CloudMeteredSummaryScreen> {
  static const _maxPages = 5;
  String _granularity = 'day';
  final List<CloudMeteredSummary> _rows = [];
  String? _nextCursor;
  String? _error;
  bool _loading = false;
  int _pages = 0;
  int _generation = 0;

  @override
  void initState() {
    super.initState();
    _refresh();
  }

  Future<void> _refresh() async {
    final generation = ++_generation;
    setState(() {
      _rows.clear();
      _nextCursor = null;
      _pages = 0;
      _error = null;
      _loading = true;
    });
    await _fetch(generation);
  }

  Future<void> _more() async {
    if (_loading || _nextCursor == null || _pages >= _maxPages) return;
    setState(() {
      _loading = true;
      _error = null;
    });
    await _fetch(_generation, cursor: _nextCursor);
  }

  Future<void> _fetch(int generation, {String? cursor}) async {
    try {
      final page = await widget.api.meteredSummaries(
        widget.home.id,
        granularity: _granularity,
        cursor: cursor,
      );
      if (!mounted || generation != _generation) return;
      setState(() {
        _rows.addAll(page.summaries);
        _nextCursor = page.nextCursor;
        _pages++;
      });
    } catch (_) {
      if (mounted && generation == _generation) {
        setState(
          () => _error = cursor == null
              ? 'Could not load Cloud meter summaries. Refresh to try again.'
              : 'Could not load the next summary page. Try again.',
        );
      }
    } finally {
      if (mounted && generation == _generation) {
        setState(() => _loading = false);
      }
    }
  }

  String _time(DateTime time) => time.toUtc().toIso8601String();

  Widget _summary(CloudMeteredSummary row) {
    final title = switch (row.kind) {
      'energy' => 'Measured energy',
      'power_sample_stats' => 'Power sample statistics',
      _ => 'Coverage gaps',
    };
    final details = switch (row.kind) {
      'energy' => [
        if (row.status == 'complete')
          '${row.energyWh!.toStringAsFixed(2)} measured Wh · ${row.coveredSeconds!.toStringAsFixed(2)} covered seconds'
        else
          'Measured energy unavailable for this bucket',
        '${row.intervalCount} explicit intervals · attachment ${row.attachmentId}',
        'Quality: ${row.status!.replaceAll('_', ' ')} · allocation: ${row.allocationMethod}',
      ],
      'power_sample_stats' => [
        if (row.sampleCount == 0)
          'No power samples in this bucket; measured energy is unknown'
        else ...[
          '${row.sampleCount} power samples · mean ${row.meanWatts!.toStringAsFixed(1)} W',
          'Range ${row.minWatts!.toStringAsFixed(1)}–${row.maxWatts!.toStringAsFixed(1)} W · instantaneous sample statistics only',
        ],
      ],
      _ => [
        '${row.gapOverlapCount} overlapping gaps · ${row.droppedCountStarted} dropped events started',
        'Missing sensor coverage; use during gaps is unknown',
      ],
    };
    return Card(
      key: Key(
        'summary-${row.kind}-${row.sensorId}-${row.bucketStart.microsecondsSinceEpoch}',
      ),
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(title, style: Theme.of(context).textTheme.titleMedium),
            Text('UTC bucket: ${_time(row.bucketStart)}'),
            for (final line in details) Text(line),
            Text(
              'Sensor ${row.sensorId} · ownership epoch ${row.ownershipEpoch}',
            ),
            Text(
              'Cloud rollup · ${row.sourceCount} source references · computed ${_time(row.computedAt)}',
            ),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: const Text('Cloud meter summaries')),
    body: SafeArea(
      child: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          Text(widget.home.name, style: Theme.of(context).textTheme.titleLarge),
          const SizedBox(height: 8),
          const Text(
            'UTC sensor and attachment buckets for this home over the last 30 days. Hourly and daily views are alternate resolutions. Measured Wh belongs only to explicit attachments; power samples and missing coverage do not create home or appliance totals. Late corrections can change rows between pages.',
          ),
          const SizedBox(height: 8),
          SegmentedButton<String>(
            segments: const [
              ButtonSegment(value: 'day', label: Text('Daily')),
              ButtonSegment(value: 'hour', label: Text('Hourly')),
            ],
            selected: {_granularity},
            onSelectionChanged: (selection) {
              if (selection.first == _granularity) return;
              setState(() => _granularity = selection.first);
              _refresh();
            },
          ),
          OutlinedButton.icon(
            onPressed: _loading ? null : _refresh,
            icon: const Icon(Icons.refresh),
            label: const Text('Refresh Cloud meter summaries'),
          ),
          if (_loading) const LinearProgressIndicator(),
          if (_error != null)
            Text(_error!, key: const Key('meteredSummaryError')),
          if (!_loading && _error == null && _rows.isEmpty)
            const Text(
              'No Cloud meter summaries in the last 30 days. This does not mean energy use was zero.',
            ),
          for (final row in _rows) _summary(row),
          if (_nextCursor != null && _pages < _maxPages)
            OutlinedButton(
              key: const Key('moreMeteredSummaries'),
              onPressed: _loading ? null : _more,
              child: const Text('Load more summaries'),
            ),
          if (_nextCursor != null && _pages >= _maxPages)
            const Text(
              'Showing the first 250 summaries. Refresh to see the latest results.',
            ),
        ],
      ),
    ),
  );
}
