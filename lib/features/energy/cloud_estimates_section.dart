import 'package:flutter/material.dart';

import '../../core/cloud_api/cloud_api_client.dart';
import '../../core/cloud_api/cloud_appliance.dart';
import '../../core/cloud_api/cloud_estimate.dart';
import '../../core/cloud_api/cloud_home.dart';

/// Shows the latest Cloud energy and cost values for the selected home.
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
      _refresh();
    }
  }

  Future<void> _refresh() async {
    final generation = ++_generation;
    setState(() => _loading = true);
    try {
      final inventory = await widget.api.appliances(widget.home.id);
      final batch = await widget.api.estimates(widget.home.id);
      if (!mounted || generation != _generation) return;
      final byId = {for (final item in inventory) item.id: item};
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
      });
    } catch (_) {
      if (mounted && generation == _generation) {
        setState(() => _rows = const []);
      }
    } finally {
      if (mounted && generation == _generation) {
        setState(() => _loading = false);
      }
    }
  }

  Widget _energyValue(CloudEstimate estimate) {
    final energy = estimate.energy;
    final kwh = energy?.unit == 'kWh' ? double.tryParse(energy!.value) : null;
    if (kwh == null || !kwh.isFinite || kwh < 0) {
      return const Text('Energy data is not available yet.');
    }
    return Text('Energy · ${kwh.toStringAsFixed(1)} kWh');
  }

  Widget? _costValue(CloudEstimate estimate) {
    if (estimate.currency != 'USD') return null;
    final cost = double.tryParse(estimate.cost ?? '');
    if (cost == null || !cost.isFinite || cost < 0) return null;
    return Text('Cost · \$${cost.toStringAsFixed(2)}');
  }

  @override
  Widget build(BuildContext context) => Card(
    child: Padding(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Appliance energy',
            style: Theme.of(context).textTheme.titleLarge,
          ),
          if (_loading) const LinearProgressIndicator(),
          if (!_loading && _rows.isEmpty)
            const Text('Energy data is not available yet.'),
          for (final (appliance, estimate) in _rows) ...[
            const Divider(),
            Text(
              appliance.name,
              style: Theme.of(context).textTheme.titleMedium,
            ),
            const Text('Per month'),
            _energyValue(estimate),
            ?_costValue(estimate),
          ],
        ],
      ),
    ),
  );
}
