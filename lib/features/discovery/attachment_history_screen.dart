import 'package:flutter/material.dart';

import 'discovery_api.dart';
import '../../core/backend_error.dart';

class AttachmentHistoryScreen extends StatefulWidget {
  const AttachmentHistoryScreen({
    required this.plug,
    required this.api,
    required this.hubAddress,
    required this.token,
    super.key,
  });

  final SavedPlug plug;
  final DiscoveryApi api;
  final String hubAddress;
  final String token;

  @override
  State<AttachmentHistoryScreen> createState() =>
      _AttachmentHistoryScreenState();
}

class _AttachmentHistoryScreenState extends State<AttachmentHistoryScreen> {
  List<AttachmentHistoryEntry>? _history;
  String? _error;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() => _error = null);
    try {
      final history = await widget.api.attachmentHistory(
        widget.hubAddress,
        widget.token,
        widget.plug.id,
      );
      if (mounted) setState(() => _history = history);
    } catch (_) {
      if (mounted) {
        setState(() => _error = internalErrorMessage);
      }
    }
  }

  String _date(int seconds) {
    final date = DateTime.fromMillisecondsSinceEpoch(seconds * 1000).toLocal();
    return MaterialLocalizations.of(context).formatMediumDate(date);
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: const Text('Attachment history')),
    body: ListView(
      padding: const EdgeInsets.all(16),
      children: [
        Text(widget.plug.name, style: Theme.of(context).textTheme.titleLarge),
        const SizedBox(height: 8),
        const Text(
          'Past estimates are shown only when the hub saved a snapshot. They are not meter readings.',
        ),
        const SizedBox(height: 16),
        if (_error case final error?) ...[
          Text(error),
          TextButton(onPressed: _load, child: const Text('Try again')),
        ] else if (_history == null)
          const Center(child: CircularProgressIndicator())
        else if (_history!.isEmpty)
          const Text('No appliance attachments recorded yet.')
        else
          for (final entry in _history!) _entry(context, entry),
      ],
    ),
  );

  Widget _entry(BuildContext context, AttachmentHistoryEntry entry) {
    final appliance = entry.applianceSnapshot;
    final estimate = entry.estimateSnapshot;
    final estimatedIdentity =
        estimate?['appliance_identity'] as Map<String, dynamic>?;
    final estimateUsage = estimate?['usage_inputs'] as Map<String, dynamic>?;
    final kwh = estimate?['estimated_kwh'] as num?;
    final cost = estimate?['estimated_cost_usd'] as num?;
    final name = appliance?['name'] as String?;
    final manufacturer = appliance?['manufacturer'] as String? ?? '';
    final model = appliance?['model'] as String? ?? '';
    final hours =
        appliance?['usage_value'] as num? ??
        appliance?['hours_per_week'] as num?;
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              name ?? 'Appliance #${entry.applianceId}',
              style: Theme.of(context).textTheme.titleMedium,
            ),
            Text(
              'Attached ${_date(entry.attachedAt)}${entry.detachedAt == null ? ' · Current' : ' · Detached ${_date(entry.detachedAt!)}'}',
            ),
            if (appliance == null)
              const Text(
                'This older attachment has no saved identity or estimate snapshot.',
              )
            else ...[
              if ('$manufacturer $model'.trim().isNotEmpty)
                Text('Attached as: ${'$manufacturer $model'.trim()}'),
              if (hours != null)
                Text(
                  'Usage at attachment: $hours ${appliance['usage_kind'] == 'cycles_per_week' ? 'cycles/week' : 'hours/week'}',
                ),
              if (entry.snapshotRecordedAt != null)
                Text('Identity saved ${_date(entry.snapshotRecordedAt!)}'),
              if (estimate?['status'] == 'estimated' && kwh != null) ...[
                if (estimatedIdentity != null)
                  Text(
                    'Estimate for ${estimatedIdentity['manufacturer'] ?? ''} ${estimatedIdentity['model'] ?? ''}'
                        .trim(),
                  ),
                if (estimate?['recorded_at'] case final int recordedAt)
                  Text('Estimate saved ${_date(recordedAt)}'),
                if (estimateUsage?['effective_value'] case final num value)
                  Text(
                    'Usage for estimate: $value ${estimateUsage?['usage_kind'] == 'cycles_per_week' ? 'cycles/week' : 'hours/week'}',
                  ),
                Text('Saved estimate: ${kwh.toStringAsFixed(2)} kWh/month'),
                if (cost != null)
                  Text(
                    'Saved cost estimate: \$${cost.toStringAsFixed(2)}/month',
                  ),
              ] else
                const Text(
                  'No monthly estimate was saved for this attachment.',
                ),
            ],
          ],
        ),
      ),
    );
  }
}
