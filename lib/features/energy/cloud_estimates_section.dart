import 'package:flutter/material.dart';

import '../../core/cloud_api/cloud_api_client.dart';
import '../../core/cloud_api/cloud_appliance.dart';
import '../../core/cloud_api/cloud_estimate.dart';
import '../../core/cloud_api/cloud_home.dart';
import 'cloud_electricity_rate_screen.dart';

String cloudEstimateUnavailableReason(
  String? reason, {
  String? fuel,
}) => switch (reason) {
  'identity_unresolved' =>
    'Confirm an exact model and reviewed product before estimating.',
  'source_unreviewed' =>
    'No reviewed energy fact is available for this exact product.',
  'usage_unknown' => 'More confirmed usage information is needed.',
  'rate_unavailable' =>
    fuel == 'natural_gas'
        ? 'No current comparable natural gas rate in USD/therm is available for this home.'
        : 'No current comparable electricity rate is available for this home.',
  'basis_incomparable' =>
    'The energy source and rate cannot be compared for this period.',
  _ => 'The estimate is unavailable. Refresh for the latest reason.',
};

String _sourceLabel(String quality) => switch (quality) {
  'reviewed_exact' => 'reviewed exact source',
  'reviewed_family' => 'reviewed family source',
  'candidate' => 'candidate source',
  _ => 'source unavailable',
};

String _rateLabel(String quality) => switch (quality) {
  'user_tariff' => 'your home tariff',
  'official_tariff' => 'official tariff',
  'regional_average' => 'regional average rate',
  _ => 'rate unavailable',
};

class CloudEstimatesSection extends StatefulWidget {
  const CloudEstimatesSection({
    super.key,
    required this.api,
    required this.home,
  });
  final CloudApiClient api;
  final CloudHome home;

  @override
  State<CloudEstimatesSection> createState() => _CloudEstimatesSectionState();
}

class _CloudEstimatesSectionState extends State<CloudEstimatesSection> {
  List<(CloudAppliance, CloudEstimate)> _rows = const [];
  DateTime? _asOf;
  String? _error;
  bool _loading = true;
  int _generation = 0;

  @override
  void initState() {
    super.initState();
    _refresh();
  }

  @override
  void didUpdateWidget(covariant CloudEstimatesSection oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.home.id != widget.home.id || oldWidget.api != widget.api) {
      _rows = const [];
      _asOf = null;
      _refresh();
    }
  }

  Future<void> _refresh() async {
    final generation = ++_generation;
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final inventory = await widget.api.appliances(widget.home.id);
      final batch = await widget.api.estimates(widget.home.id);
      if (!mounted || generation != _generation) return;
      final byId = {for (final appliance in inventory) appliance.id: appliance};
      final latest = <String, CloudEstimate>{};
      for (final estimate in batch.estimates) {
        final appliance = byId[estimate.applianceId];
        if (appliance == null) {
          throw const FormatException(
            'Estimate is outside selected home inventory',
          );
        }
        if (estimate.energy case final energy?) {
          if (energy.fuel != appliance.fuel) {
            throw const FormatException('Estimate fuel differs from appliance');
          }
        }
        final old = latest[estimate.applianceId];
        if (old == null || estimate.asOf.isAfter(old.asOf)) {
          latest[estimate.applianceId] = estimate;
        }
      }
      setState(() {
        _rows = [
          for (final appliance in inventory)
            if (latest[appliance.id] case final estimate?)
              (appliance, estimate),
        ];
        _asOf = batch.asOf;
      });
    } catch (_) {
      if (mounted && generation == _generation) {
        setState(() {
          _rows = const [];
          _asOf = null;
          _error = 'Could not load Cloud estimates for this home. Refresh to try again.';
        });
      }
    } finally {
      if (mounted && generation == _generation) {
        setState(() => _loading = false);
      }
    }
  }

  Future<void> _openMissingRate(CloudAppliance appliance) async {
    await Navigator.of(context).push<void>(
      MaterialPageRoute<void>(
        builder: (_) => appliance.fuel == 'natural_gas'
            ? CloudGasRateScreen(api: widget.api, home: widget.home)
            : CloudElectricityRateScreen(api: widget.api, home: widget.home),
      ),
    );
    if (mounted) _refresh();
  }

  @override
  Widget build(BuildContext context) => Card(
    child: Padding(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Cloud modeled estimates · ${widget.home.name}',
            style: Theme.of(context).textTheme.titleLarge,
          ),
          const SizedBox(height: 6),
          const Text(
            'These are reviewed product and home rate estimates. They are separate from local hub estimates and measured costs; totals are not combined.',
          ),
          if (_asOf != null)
            Text('Cloud refreshed ${_asOf!.toUtc().toIso8601String()}'),
          TextButton.icon(
            onPressed: _loading ? null : _refresh,
            icon: const Icon(Icons.refresh),
            label: const Text('Refresh Cloud estimates'),
          ),
          if (_loading) const LinearProgressIndicator(),
          if (_error != null)
            Text(_error!, key: const Key('cloudEstimatesError')),
          if (!_loading && _error == null && _rows.isEmpty)
            const Text('No Cloud estimates for saved cloud appliances yet.'),
          for (final (appliance, estimate) in _rows) ...[
            const Divider(),
            Text(
              appliance.name,
              style: Theme.of(context).textTheme.titleMedium,
            ),
            Text(
              '${appliance.brand} ${appliance.fullModel} · ${appliance.fuel}',
            ),
            Text(
              'Period: ${estimate.period.start} to before ${estimate.period.end} (${estimate.period.timezone})',
            ),
            if (estimate.kind == 'unavailable') ...[
              const Text('Estimated cost unavailable'),
              Text(
                cloudEstimateUnavailableReason(
                  estimate.unavailableReason,
                  fuel: appliance.fuel,
                ),
              ),
              if (estimate.unavailableReason == 'rate_unavailable' &&
                  const {'electricity', 'natural_gas'}.contains(appliance.fuel))
                TextButton.icon(
                  key: Key('estimateAddRate-${appliance.id}'),
                  onPressed: () => _openMissingRate(appliance),
                  icon: const Icon(Icons.receipt_long_outlined),
                  label: Text(
                    appliance.fuel == 'natural_gas'
                        ? 'Add Cloud gas rate'
                        : 'Add Cloud electricity rate',
                  ),
                ),
            ] else ...[
              Text(
                estimate.kind == 'estimated_useful_cost'
                    ? estimate.energy!.fuel == 'natural_gas'
                          ? 'Estimated useful gas cost'
                          : 'Estimated useful cost'
                    : 'Estimated operating cost',
              ),
              Text(
                '${estimate.cost} ${estimate.currency} · ${estimate.energy!.value} ${estimate.energy!.unit}',
              ),
            ],
            const Text('Waste: not yet assessed'),
            Text(
              'Basis: ${_sourceLabel(estimate.sourceQuality)} · ${estimate.consumptionQuality.replaceAll('_', ' ')} · ${_rateLabel(estimate.rateQuality)}',
            ),
            if (estimate.evidenceRefs.isNotEmpty)
              Text(
                'Evidence: ${estimate.evidenceRefs.map((ref) => '${ref.kind.replaceAll('_', ' ')} revision ${ref.revision}').join(' · ')}',
              ),
            Text(
              'Calculated ${estimate.asOf.toUtc().toIso8601String()} · ${estimate.formulaVersion}',
            ),
          ],
        ],
      ),
    ),
  );
}
