import 'package:flutter/material.dart';

import '../../core/cloud_api/cloud_api_client.dart';
import '../../core/cloud_api/cloud_home.dart';
import '../../core/cloud_api/cloud_kasa_runtime.dart';

class CloudKasaRuntimeScreen extends StatefulWidget {
  const CloudKasaRuntimeScreen({
    super.key,
    required this.api,
    required this.home,
  });

  final CloudApiClient api;
  final CloudHome home;

  @override
  State<CloudKasaRuntimeScreen> createState() => _CloudKasaRuntimeScreenState();
}

class _CloudKasaRuntimeScreenState extends State<CloudKasaRuntimeScreen> {
  static const _maxPages = 5;
  final List<CloudKasaRuntimeSnapshot> _snapshots = [];
  DateTime? _from;
  DateTime? _to;
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

  @override
  void didUpdateWidget(covariant CloudKasaRuntimeScreen oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.home.id != widget.home.id || oldWidget.api != widget.api) {
      _refresh();
    }
  }

  Future<void> _refresh() async {
    final generation = ++_generation;
    setState(() {
      _snapshots.clear();
      _from = null;
      _to = null;
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
      final page = await widget.api.kasaRuntimeHistory(
        widget.home.id,
        cursor: cursor,
      );
      if (!mounted || generation != _generation) return;
      if (cursor != null && (page.from != _from || page.to != _to)) {
        throw const FormatException('Kasa runtime history period changed');
      }
      setState(() {
        _snapshots.addAll(page.snapshots);
        _from = page.from;
        _to = page.to;
        _nextCursor = page.nextCursor;
        _pages++;
      });
    } catch (_) {
      if (mounted && generation == _generation) {
        setState(
          () => _error = cursor == null
              ? 'Could not load Cloud Kasa runtime. Refresh to try again.'
              : 'Could not load the next runtime page. Try again.',
        );
      }
    } finally {
      if (mounted && generation == _generation) {
        setState(() => _loading = false);
      }
    }
  }

  String _time(DateTime value) => value.toUtc().toIso8601String();

  Widget _snapshot(CloudKasaRuntimeSnapshot item) {
    final label = switch (item.windowLabel) {
      'today' => 'Today',
      'past7' => 'Past 7 days',
      _ => 'Past 30 days',
    };
    final source = switch (item.method) {
      'get_device_usage' => 'Kasa device usage',
      _ => 'Kasa day statistics',
    };
    final transport = switch (item.transport) {
      'kasa_http_klap' => 'Kasa HTTP',
      _ => 'Kasa legacy TCP',
    };
    final clock = item.deviceClockValid
        ? 'Device clock checked'
        : 'Device clock unverified';
    return Card(
      key: Key('runtime-${item.snapshotId}'),
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(label, style: Theme.of(context).textTheme.titleMedium),
            Text('${item.nativeMinutes} reported relay-on minutes'),
            Text('Observed ${_time(item.observedAt)}'),
            Text('Source: $source · $transport'),
            Text('$clock · ${item.quality.replaceAll('_', ' ')}'),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: const Text('Cloud Kasa runtime')),
    body: SafeArea(
      child: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          Text(widget.home.name, style: Theme.of(context).textTheme.titleLarge),
          const SizedBox(height: 8),
          const Text(
            'Kasa reports relay-on minutes for overlapping windows. Each entry stands alone. A missing window means its runtime is unknown.',
          ),
          if (_from != null && _to != null)
            Text('Recent 30-day history · ${_time(_from!)} to ${_time(_to!)}'),
          const SizedBox(height: 8),
          OutlinedButton.icon(
            onPressed: _loading ? null : _refresh,
            icon: const Icon(Icons.refresh),
            label: const Text('Refresh Kasa runtime'),
          ),
          if (_loading) const LinearProgressIndicator(),
          if (_error != null) Text(_error!, key: const Key('kasaRuntimeError')),
          if (!_loading && _error == null && _snapshots.isEmpty)
            const Text(
              'No reported Kasa runtime in the recent 30-day history.',
            ),
          for (final snapshot in _snapshots) _snapshot(snapshot),
          if (_nextCursor != null && _pages < _maxPages)
            OutlinedButton(
              key: const Key('moreKasaRuntime'),
              onPressed: _loading ? null : _more,
              child: const Text('Load more runtime'),
            ),
          if (_nextCursor != null && _pages >= _maxPages)
            const Text('Showing the first 250 recent runtime entries.'),
        ],
      ),
    ),
  );
}
