import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';

import 'discovery_api.dart';
import 'attachment_history_screen.dart';

/// Measured energy and the separately sourced appliance estimate for one plug.
class DeviceEnergyDetailScreen extends StatefulWidget {
  const DeviceEnergyDetailScreen({
    required this.plug,
    required this.api,
    required this.hubAddress,
    required this.token,
    this.postalCode,
    this.rateUsdPerKwh,
    this.estimate,
    super.key,
  });

  final SavedPlug plug;
  final DiscoveryApi api;
  final String hubAddress;
  final String token;
  final String? postalCode;
  final double? rateUsdPerKwh;
  final EnergyEstimate? estimate;

  @override
  State<DeviceEnergyDetailScreen> createState() =>
      _DeviceEnergyDetailScreenState();
}

class _DeviceEnergyDetailScreenState extends State<DeviceEnergyDetailScreen> {
  static const _periods = <String, String>{
    'day': 'Day',
    'week': 'Week',
    'month': 'Month',
  };

  String _period = 'day';
  DeviceEnergy? _energy;
  EnergyEstimate? _estimate;
  ApplianceSpec? _spec;
  bool _loading = true;
  bool _estimateLoading = true;
  String? _error;
  String? _estimateError;
  int _energyRequestId = 0;

  @override
  void initState() {
    super.initState();
    _estimate = widget.estimate;
    _load();
    _loadEstimate();
    _loadSpec();
  }

  Future<void> _loadSpec() async {
    final appliance = widget.plug.connectedAppliance;
    if (appliance == null) return;
    try {
      final result = await widget.api.applianceSpec(
        widget.hubAddress,
        widget.token,
        appliance.id,
      );
      if (mounted) setState(() => _spec = result);
    } catch (_) {
      // Older hubs and unavailable sources simply have no optional rating.
    }
  }

  Future<void> _load() async {
    final requestId = ++_energyRequestId;
    final requestedPeriod = _period;
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final result = await widget.api.deviceEnergy(
        widget.hubAddress,
        widget.token,
        widget.plug.id,
        period: requestedPeriod,
        postalCode: widget.postalCode,
        rateUsdPerKwh: widget.rateUsdPerKwh,
      );
      if (!mounted ||
          requestId != _energyRequestId ||
          requestedPeriod != _period) {
        return;
      }
      setState(() {
        _energy = result;
        _loading = false;
      });
    } catch (_) {
      if (!mounted ||
          requestId != _energyRequestId ||
          requestedPeriod != _period) {
        return;
      }
      setState(() {
        _error = 'Could not load meter history. Check the hub connection and try again.';
        _loading = false;
      });
    }
  }

  Future<void> _loadEstimate() async {
    final appliance = widget.plug.connectedAppliance;
    if (appliance == null) {
      setState(() => _estimateLoading = false);
      return;
    }
    setState(() {
      _estimateLoading = true;
      _estimateError = null;
    });
    try {
      final result = await widget.api.estimate(
        widget.hubAddress,
        widget.token,
        appliance.id,
        postalCode: widget.postalCode,
        rateUsdPerKwh: widget.rateUsdPerKwh,
      );
      if (!mounted) return;
      setState(() {
        _estimate = result;
        _estimateLoading = false;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _estimateError = 'Could not load the appliance estimate.';
        _estimateLoading = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final plug = widget.plug;
    return Scaffold(
      appBar: AppBar(title: Text(plug.name)),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(16, 8, 16, 28),
        children: [
          Text(
            '${plug.model} · ${plug.room.isEmpty ? 'No room' : plug.room}',
            style: theme.textTheme.bodyMedium,
          ),
          const SizedBox(height: 20),
          Text('Measured energy', style: theme.textTheme.titleLarge),
          const SizedBox(height: 12),
          SegmentedButton<String>(
            segments: _periods.entries
                .map(
                  (entry) => ButtonSegment<String>(
                    value: entry.key,
                    label: Text(entry.value),
                  ),
                )
                .toList(growable: false),
            selected: {_period},
            onSelectionChanged: (selection) {
              setState(() => _period = selection.first);
              _load();
            },
          ),
          const SizedBox(height: 12),
          if (_loading)
            const _LoadingMetrics()
          else if (plug.meterStatus == 'absent')
            const _MessagePanel(
              icon: Icons.electrical_services_outlined,
              message: 'This plug does not provide energy monitoring.',
            )
          else if (_error case final message?)
            _MessagePanel(
              icon: Icons.cloud_off_outlined,
              message: message,
              action: TextButton.icon(
                onPressed: _load,
                icon: const Icon(Icons.refresh),
                label: const Text('Try again'),
              ),
            )
          else if (plug.meterStatus == 'unknown' &&
              (_energy == null || _energy!.readingCount == 0))
            const _MessagePanel(
              icon: Icons.help_outline,
              message: 'Meter capability has not been confirmed for this plug.',
              detail: 'No readings are available yet. This does not confirm that the plug lacks a meter.',
            )
          else if (_energy case final data?)
            _observedSection(context, data),
          if (_spec?.status == 'matched' &&
              _spec?.evidence?.sourceKind == 'oem_rated_input' &&
              _spec!.evidence!.ratedInputWatts.isFinite &&
              _spec!.evidence!.ratedInputWatts > 0) ...[
            const SizedBox(height: 24),
            _specSection(context, _spec!.evidence!),
          ],
          const SizedBox(height: 24),
          Text('Appliance estimate', style: theme.textTheme.titleLarge),
          const SizedBox(height: 10),
          if (plug.connectedAppliance == null)
            const _MessagePanel(
              icon: Icons.link_off,
              message: 'No appliance is attached to this plug yet. Attach one from the saved plug list to see a sourced estimate.',
            )
          else
            _estimateSection(context, plug.connectedAppliance!),
          const SizedBox(height: 20),
          OutlinedButton.icon(
            onPressed: () => Navigator.of(context).push<void>(
              MaterialPageRoute<void>(
                builder: (_) => AttachmentHistoryScreen(
                  plug: plug,
                  api: widget.api,
                  hubAddress: widget.hubAddress,
                  token: widget.token,
                ),
              ),
            ),
            icon: const Icon(Icons.history),
            label: const Text('Attachment history'),
          ),
        ],
      ),
    );
  }

  Widget _specSection(BuildContext context, ApplianceSpecEvidence evidence) {
    final theme = Theme.of(context);
    final source = Uri.tryParse(evidence.sourceUrl);
    final canOpen =
        source != null &&
        (source.scheme == 'https' || source.scheme == 'http') &&
        source.host.isNotEmpty;
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'OEM rated input (nameplate)',
              style: theme.textTheme.titleMedium,
            ),
            const SizedBox(height: 6),
            Text(
              '${_watts(evidence.ratedInputWatts)} W',
              style: theme.textTheme.headlineSmall,
            ),
            Text(
              'Manufacturer rating for ${evidence.matchedBrand} ${evidence.matchedModel}. Actual draw is shown under Measured energy.',
              style: theme.textTheme.bodySmall,
            ),
            if (canOpen)
              TextButton.icon(
                onPressed: () =>
                    launchUrl(source, mode: LaunchMode.externalApplication),
                icon: const Icon(Icons.open_in_new),
                label: const Text('Manufacturer source'),
              ),
          ],
        ),
      ),
    );
  }

  Widget _observedSection(BuildContext context, DeviceEnergy data) {
    final theme = Theme.of(context);
    if (data.status == 'no_data' || data.readingCount == 0) {
      return _MessagePanel(
        icon: Icons.show_chart,
        message:
            'No meter readings were recorded in the selected ${_periods[_period]!.toLowerCase()}.',
        detail: 'Observed energy covers only time with meter samples. The rest of the period is unknown.',
      );
    }
    final coveredHours = data.coveredSecs / 3600;
    final periodHours = switch (_period) {
      'day' => 24.0,
      'week' => 24.0 * 7,
      _ => 24.0 * 30,
    };
    final coverage = (data.coverageFraction * 100).clamp(0, 100).round();
    final hasValidCoverage =
        data.coveredSecs.isFinite &&
        data.coveredSecs > 0 &&
        data.coverageFraction.isFinite &&
        data.coverageFraction > 0;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Card(
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  data.latestWatts == null
                      ? 'Live power unavailable'
                      : '${_watts(data.latestWatts!)} W',
                  style: theme.textTheme.headlineMedium,
                ),
                Text(
                  data.latestWatts == null
                      ? 'The latest reading is not fresh enough to show as live.'
                      : 'Live power · fresh meter reading',
                ),
                if (data.latestWatts != null && data.latestSample != null)
                  Text(
                    'Sampled ${_sampleTime(context, data.latestSample!.ts)}',
                    style: theme.textTheme.bodySmall,
                  ),
                const Divider(height: 24),
                Text(
                  '${data.totalKwh.toStringAsFixed(3)} kWh',
                  style: theme.textTheme.titleLarge,
                ),
                const Text('Observed energy during covered time'),
                const SizedBox(height: 12),
                if (data.observedCostUsd != null && hasValidCoverage)
                  Text(
                    'Observed cost · \$${data.observedCostUsd!.toStringAsFixed(2)}',
                    style: theme.textTheme.titleMedium,
                  )
                else
                  const Text(
                    'Observed cost unavailable · no electricity rate was applied.',
                  ),
                if (data.rateStatus == 'stale' || data.rateIsStale)
                  Text(
                    'Using a cached regional rate${data.rateAsOf == null ? '' : ' from ${data.rateAsOf}'}; a fresh regional rate is unavailable.',
                    style: theme.textTheme.bodySmall,
                  )
                else if (data.rateUsdPerKwh != null)
                  Text(
                    '${data.rateSourceLabel ?? _rateLabel(data.rateSource)} · \$${data.rateUsdPerKwh!.toStringAsFixed(4)}/kWh${data.rateAsOf == null ? '' : ' · ${data.rateAsOf}'}',
                    style: theme.textTheme.bodySmall,
                  )
                else if (data.rateStatus == 'unavailable')
                  Text(
                    'Regional rate unavailable.',
                    style: theme.textTheme.bodySmall,
                  )
                else if (data.rateStatus == 'not_requested')
                  Text(
                    'No electricity rate applied.',
                    style: theme.textTheme.bodySmall,
                  ),
              ],
            ),
          ),
        ),
        const SizedBox(height: 8),
        Text(
          '$coverage% coverage · ${_duration(coveredHours)} of ${_duration(periodHours)}',
          style: theme.textTheme.titleSmall,
        ),
        Text(
          'Only the covered time is measured. The remaining ${_duration((periodHours - coveredHours).clamp(0, periodHours))} is unknown and is not included in the observed total.',
          style: theme.textTheme.bodySmall,
        ),
        if (data.latestWatts == null && data.readingCount > 0)
          Padding(
            padding: const EdgeInsets.only(top: 8),
            child: Text(
              'Older meter data is available, but no fresh live reading is available.',
              style: theme.textTheme.bodySmall,
            ),
          ),
      ],
    );
  }

  Widget _estimateSection(BuildContext context, SavedAppliance appliance) {
    final estimate = _estimate;
    final theme = Theme.of(context);
    if (_estimateLoading && estimate == null) {
      return const _LoadingMetrics();
    }
    if (_estimateError case final message? when estimate == null) {
      return _MessagePanel(
        icon: Icons.cloud_off_outlined,
        message: message,
        action: TextButton.icon(
          onPressed: _loadEstimate,
          icon: const Icon(Icons.refresh),
          label: const Text('Try again'),
        ),
      );
    }
    if (estimate == null || estimate.estimatedKwh == null) {
      return _MessagePanel(
        icon: Icons.info_outline,
        message: '${appliance.name}: no sourced energy estimate is available.',
        action: _estimateError == null
            ? null
            : TextButton.icon(
                onPressed: _loadEstimate,
                icon: const Icon(Icons.refresh),
                label: const Text('Try again'),
              ),
      );
    }
    final source = estimate.evidence;
    final measured = estimate.status == 'measured';
    final unit = measured
        ? 'Measured 30-day'
        : estimate.status == 'estimated'
        ? 'Estimated monthly'
        : 'Estimate';
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(appliance.name, style: theme.textTheme.titleMedium),
            if (_estimateError != null)
              Padding(
                padding: const EdgeInsets.only(top: 6, bottom: 2),
                child: Row(
                  children: [
                    const Icon(Icons.cloud_off_outlined, size: 16),
                    const SizedBox(width: 6),
                    Expanded(
                      child: Text(
                        'Could not refresh · showing cached estimate',
                        style: theme.textTheme.bodySmall,
                      ),
                    ),
                  ],
                ),
              ),
            const SizedBox(height: 6),
            Text(
              '$unit energy · ${estimate.estimatedKwh!.toStringAsFixed(1)} kWh',
            ),
            if (measured)
              if (estimate.measurementCoverageFraction case final fraction?)
                Text(
                  'Measurement coverage · ${(fraction * 100).clamp(0, 100).round()}% of the 30-day window',
                  style: theme.textTheme.bodySmall,
                ),
            if (estimate.estimatedCostUsd != null)
              Text(
                '$unit cost · \$${estimate.estimatedCostUsd!.toStringAsFixed(2)}',
              ),
            if (source != null) ...[
              const SizedBox(height: 8),
              Text(energySourceLabel(source), style: theme.textTheme.bodySmall),
              Text(
                '${source.matchedBrand} ${source.matchedModel}',
                style: theme.textTheme.bodySmall,
              ),
            ],
            Text(
              energyRateDescription(estimate),
              style: theme.textTheme.bodySmall,
            ),
            if (_estimateError case final refreshError?)
              Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(refreshError, style: theme.textTheme.bodySmall),
                  TextButton.icon(
                    onPressed: _loadEstimate,
                    icon: const Icon(Icons.refresh),
                    label: const Text('Retry estimate'),
                  ),
                ],
              ),
          ],
        ),
      ),
    );
  }

  String _watts(double value) => value == value.roundToDouble()
      ? value.toStringAsFixed(0)
      : value.toStringAsFixed(1);

  String _sampleTime(BuildContext context, DateTime timestamp) {
    final local = timestamp.toLocal();
    final date = MaterialLocalizations.of(context).formatMediumDate(local);
    final time = MaterialLocalizations.of(context)
        .formatTimeOfDay(TimeOfDay.fromDateTime(local));
    return '$date · $time';
  }

  String _duration(double hours) {
    final roundedMinutes = (hours * 60).round();
    final h = roundedMinutes ~/ 60;
    final m = roundedMinutes % 60;
    if (h == 0) return '${m}m';
    if (m == 0) return '${h}h';
    return '${h}h ${m}m';
  }

  String _rateLabel(String? source) => switch (source) {
    'user' => 'Your electricity rate',
    'utility' => 'Utility rate',
    'state' => 'State average',
    'national' => 'National average',
    'built_in' => 'Built-in rate',
    _ => 'Electricity rate',
  };
}

class _LoadingMetrics extends StatelessWidget {
  const _LoadingMetrics();

  @override
  Widget build(BuildContext context) => Card(
    child: Padding(
      padding: const EdgeInsets.all(18),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const LinearProgressIndicator(),
          const SizedBox(height: 20),
          Container(
            height: 24,
            width: 150,
            color: Theme.of(context).colorScheme.surfaceContainerHighest,
          ),
          const SizedBox(height: 12),
          Container(
            height: 14,
            width: 220,
            color: Theme.of(context).colorScheme.surfaceContainerHighest,
          ),
        ],
      ),
    ),
  );
}

class _MessagePanel extends StatelessWidget {
  const _MessagePanel({
    required this.icon,
    required this.message,
    this.detail,
    this.action,
  });

  final IconData icon;
  final String message;
  final String? detail;
  final Widget? action;

  @override
  Widget build(BuildContext context) => Card(
    child: Padding(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, color: Theme.of(context).colorScheme.primary),
          const SizedBox(height: 8),
          Text(message),
          if (detail != null) ...[
            const SizedBox(height: 4),
            Text(detail!, style: Theme.of(context).textTheme.bodySmall),
          ],
          ?action,
        ],
      ),
    ),
  );
}
