import 'package:flutter/material.dart';

import '../../core/cloud_api/cloud_api_client.dart';
import '../../core/cloud_api/cloud_appliance.dart';
import '../../core/cloud_api/cloud_energy_resolution.dart';
import 'attachment_history_screen.dart';
import 'discovery_api.dart';

class DeviceEnergyDetailScreen extends StatefulWidget {
  const DeviceEnergyDetailScreen({
    required this.plug,
    required this.api,
    required this.hubAddress,
    required this.token,
    this.postalCode,
    this.rateUsdPerKwh,
    this.estimate,
    this.cloudApi,
    this.cloudAppliance,
    super.key,
  });

  final SavedPlug plug;
  final DiscoveryApi api;
  final String hubAddress;
  final String token;
  final String? postalCode;
  final double? rateUsdPerKwh;
  final EnergyEstimate? estimate;
  final CloudApiClient? cloudApi;
  final CloudAppliance? cloudAppliance;

  @override
  State<DeviceEnergyDetailScreen> createState() =>
      _DeviceEnergyDetailScreenState();
}

class _DeviceEnergyDetailScreenState extends State<DeviceEnergyDetailScreen> {
  double? _kwh;
  double? _cost;
  bool _loading = true;

  bool get _attached =>
      widget.cloudAppliance != null || widget.plug.connectedAppliance != null;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() => _loading = true);
    double? kwh;
    double? cost;
    try {
      if (widget.plug.meterStatus == 'verified') {
        final measured = await widget.api.deviceEnergy(
          widget.hubAddress,
          widget.token,
          widget.plug.id,
          period: 'month',
          postalCode: widget.postalCode,
          rateUsdPerKwh: widget.rateUsdPerKwh,
        );
        if (measured.status == 'measured' && measured.readingCount > 0) {
          kwh = measured.totalKwh;
          cost = measured.observedCostUsd;
        }
      } else if (widget.cloudApi != null && widget.cloudAppliance != null) {
        final appliance = widget.cloudAppliance!;
        final CloudEnergyResolution? resolution = await widget.cloudApi!
            .energyResolution(appliance.homeId, appliance.id);
        if (resolution?.status == 'resolved' ||
            resolution?.status == 'simulated') {
          final dailyKwh = resolution?.values?.kwhPerDay;
          if (dailyKwh != null && dailyKwh.isFinite) {
            kwh = dailyKwh * 365 / 12;
            if (widget.rateUsdPerKwh != null) {
              cost = kwh * widget.rateUsdPerKwh!;
            }
          }
        }
      } else if (widget.plug.connectedAppliance != null) {
        final estimate = await widget.api.estimate(
          widget.hubAddress,
          widget.token,
          widget.plug.connectedAppliance!.id,
          postalCode: widget.postalCode,
          rateUsdPerKwh: widget.rateUsdPerKwh,
        );
        kwh = estimate.estimatedKwh;
        cost = estimate.estimatedCostUsd;
      }
    } catch (_) {
      // An unavailable result uses the approved empty state.
    }
    if (mounted) {
      setState(() {
        _kwh = kwh;
        _cost = cost;
        _loading = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Scaffold(
      appBar: AppBar(title: Text(widget.plug.name)),
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.all(16),
          children: [
            Text('Appliance energy', style: theme.textTheme.titleLarge),
            const SizedBox(height: 12),
            if (!_attached)
              const Text('Attach an appliance to see its energy and cost.')
            else if (_loading)
              const Center(child: CircularProgressIndicator())
            else if (_kwh == null)
              const Text('Energy data is not available yet.')
            else
              Card(
                child: Padding(
                  padding: const EdgeInsets.all(16),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        widget.plug.meterStatus == 'verified'
                            ? 'Last 30 days'
                            : 'Per month',
                        style: theme.textTheme.labelLarge,
                      ),
                      const SizedBox(height: 8),
                      Text(
                        'Energy · ${_kwh!.toStringAsFixed(1)} kWh',
                        style: theme.textTheme.titleMedium,
                      ),
                      if (_cost != null)
                        Text(
                          'Cost · \$${_cost!.toStringAsFixed(2)}',
                          style: theme.textTheme.titleMedium,
                        ),
                    ],
                  ),
                ),
              ),
            const SizedBox(height: 20),
            OutlinedButton.icon(
              onPressed: () => Navigator.of(context).push<void>(
                MaterialPageRoute<void>(
                  builder: (_) => AttachmentHistoryScreen(
                    plug: widget.plug,
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
      ),
    );
  }
}
