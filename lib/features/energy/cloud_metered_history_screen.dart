import 'package:flutter/material.dart';

import '../../core/cloud_api/cloud_api_client.dart';
import '../../core/cloud_api/cloud_home.dart';
import '../../core/cloud_api/cloud_metered_history.dart';

class CloudMeteredHistoryScreen extends StatefulWidget {
  const CloudMeteredHistoryScreen({
    super.key,
    required this.api,
    required this.home,
  });

  final CloudApiClient api;
  final CloudHome home;

  @override
  State<CloudMeteredHistoryScreen> createState() =>
      _CloudMeteredHistoryScreenState();
}

class _CloudMeteredHistoryScreenState extends State<CloudMeteredHistoryScreen> {
  static const _maxPages = 5;
  final List<CloudMeteredEvent> _events = [];
  DateTime? _asOf;
  int? _asOfCursor;
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
      _events.clear();
      _asOf = null;
      _asOfCursor = null;
      _nextCursor = null;
      _pages = 0;
      _error = null;
      _loading = true;
    });
    await _fetch(generation: generation);
  }

  Future<void> _more() async {
    if (_loading || _nextCursor == null || _pages >= _maxPages) return;
    setState(() {
      _loading = true;
      _error = null;
    });
    await _fetch(generation: _generation, cursor: _nextCursor);
  }

  Future<void> _fetch({required int generation, String? cursor}) async {
    try {
      final page = await widget.api.meteredHistory(
        widget.home.id,
        cursor: cursor,
      );
      if (!mounted || generation != _generation) return;
      if (cursor != null &&
          (page.asOfCursor != _asOfCursor || page.asOf != _asOf)) {
        throw const FormatException('Metered history snapshot changed');
      }
      setState(() {
        _events.addAll(page.events);
        _asOf = page.asOf;
        _asOfCursor = page.asOfCursor;
        _nextCursor = page.nextCursor;
        _pages++;
      });
    } catch (_) {
      if (mounted && generation == _generation) {
        setState(
          () => _error = cursor == null
              ? 'Could not load Cloud meter history. Refresh to try again.'
              : 'Could not load the next history page. Try again.',
        );
      }
    } finally {
      if (mounted && generation == _generation) {
        setState(() => _loading = false);
      }
    }
  }

  String _time(DateTime value) => value.toUtc().toIso8601String();

  Widget _event(CloudMeteredEvent event) {
    final label = switch (event.kind) {
      'power_point' => 'Power point',
      'energy_interval' => 'Measured energy interval',
      _ => 'Coverage gap',
    };
    final details = switch (event.kind) {
      'power_point' => [
        '${event.watts!.toStringAsFixed(1)} W at ${_time(event.start)}',
        'Sensor ${event.sensorId} · instantaneous reading',
      ],
      'energy_interval' => [
        '${event.energyWh!.toStringAsFixed(2)} measured Wh',
        '${_time(event.start)} to ${_time(event.end!)}',
        'Coverage: ${event.coveredSeconds} seconds · electricity',
        'Attached appliance ${event.applianceId} · attachment ${event.attachmentId}',
      ],
      _ => [
        'Missing data: ${event.gapReason!.replaceAll('_', ' ')}',
        '${_time(event.start)} to ${_time(event.end!)}',
        '${event.droppedCount} dropped event${event.droppedCount == 1 ? '' : 's'} · sensor ${event.sensorId}',
      ],
    };
    return Card(
      key: Key(
        'metered-${event.kind}-${event.sensorId}-${event.start.microsecondsSinceEpoch}',
      ),
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(label, style: Theme.of(context).textTheme.titleMedium),
            for (final line in details) Text(line),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: const Text('Cloud meter history')),
    body: SafeArea(
      child: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          Text(widget.home.name, style: Theme.of(context).textTheme.titleLarge),
          const SizedBox(height: 8),
          const Text(
            'Recent raw readings from this Cloud home. Power points are watts at a time; measured Wh belongs only to explicit intervals with coverage. Gaps mean data is missing. These records are separate from local hub readings and are not a utility bill.',
          ),
          if (_asOf != null)
            Text('Snapshot: ${_time(_asOf!)} · recent 24 hours'),
          const SizedBox(height: 8),
          OutlinedButton.icon(
            onPressed: _loading ? null : _refresh,
            icon: const Icon(Icons.refresh),
            label: const Text('Refresh Cloud meter history'),
          ),
          if (_loading) const LinearProgressIndicator(),
          if (_error != null)
            Text(_error!, key: const Key('meteredHistoryError')),
          if (!_loading && _error == null && _events.isEmpty)
            const Text('No Cloud meter events in the last 24 hours.'),
          for (final event in _events) _event(event),
          if (_nextCursor != null && _pages < _maxPages)
            OutlinedButton(
              key: const Key('moreMeteredHistory'),
              onPressed: _loading ? null : _more,
              child: const Text('Load more events'),
            ),
          if (_nextCursor != null && _pages >= _maxPages)
            const Text(
              'Showing the first 250 recent events. Refresh to see the latest snapshot.',
            ),
        ],
      ),
    ),
  );
}
