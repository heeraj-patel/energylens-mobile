import 'package:flutter/material.dart';

import '../../core/cloud_api/cloud_api_client.dart';
import '../../core/cloud_api/cloud_appliance.dart';
import '../../core/cloud_api/cloud_home.dart';
import '../../core/cloud_api/cloud_recommendations.dart';
import '../identify/cloud_usage_questions_screen.dart';
import 'cloud_intervention_screen.dart';
import 'cloud_electricity_rate_screen.dart';

class CloudRecommendationsScreen extends StatefulWidget {
  const CloudRecommendationsScreen({
    super.key,
    required this.api,
    required this.home,
  });
  final CloudApiClient api;
  final CloudHome home;

  @override
  State<CloudRecommendationsScreen> createState() =>
      _CloudRecommendationsScreenState();
}

class _CloudRecommendationsScreenState
    extends State<CloudRecommendationsScreen> {
  List<CloudAppliance>? _appliances;
  CloudRecommendationBatch? _batch;
  String? _error;
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
      _batch = null;
    });
    try {
      final appliances = await widget.api.appliances(widget.home.id);
      final batch = await widget.api.recommendations(
        widget.home.id,
        appliances.map((a) => a.id).toSet(),
      );
      if (mounted) {
        setState(() {
          _appliances = appliances;
          _batch = batch;
        });
      }
    } on CloudApiException catch (error) {
      if (mounted) {
        setState(
          () => _error = error.statusCode == 401 || error.statusCode == 403
              ? 'Cloud sign-in is required to view these actions.'
              : 'Could not load actions for this home. Try again.',
        );
      }
    } catch (_) {
      if (mounted) {
        setState(
          () => _error = 'Could not load actions for this home. Try again.',
        );
      }
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _openQuestions(CloudAppliance appliance) async {
    await Navigator.of(context).push<void>(
      MaterialPageRoute<void>(
        builder: (_) => CloudUsageQuestionsScreen(
          home: widget.home,
          appliance: appliance,
          api: widget.api,
        ),
      ),
    );
    if (mounted) _load();
  }

  @override
  Widget build(BuildContext context) {
    final appliances = {
      for (final a in _appliances ?? <CloudAppliance>[]) a.id.toLowerCase(): a,
    };
    return Scaffold(
      appBar: AppBar(title: const Text('Actions to consider')),
      body: SafeArea(
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 680),
            child: ListView(
              padding: const EdgeInsets.all(20),
              children: [
                Text(
                  widget.home.name,
                  style: Theme.of(context).textTheme.titleLarge,
                ),
                const SizedBox(height: 8),
                const Text(
                  'These checks use saved appliance details and reviewed evidence when available. They are suggestions, not measured savings or proof of waste.',
                ),
                const SizedBox(height: 20),
                if (_loading)
                  const LinearProgressIndicator(
                    key: Key('recommendationsLoading'),
                  ),
                if (_error != null) ...[
                  Text(_error!, key: const Key('recommendationsError')),
                  TextButton(
                    onPressed: _load,
                    child: const Text('Retry actions'),
                  ),
                ],
                if (_batch case final batch?) ...[
                  if (batch.actions.isEmpty)
                    const Text(
                      'No actions are available for this home’s current appliances.',
                    ),
                  for (final action in batch.actions)
                    Card(
                      key: Key(
                        'recommendation-${action.ruleId}-${action.applianceId}',
                      ),
                      child: Padding(
                        padding: const EdgeInsets.all(16),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              action.state == 'active'
                                  ? 'Evidence available'
                                  : 'More information needed',
                              style: Theme.of(context).textTheme.labelLarge,
                            ),
                            const SizedBox(height: 4),
                            Text(
                              appliances[action.applianceId.toLowerCase()]
                                      ?.name ??
                                  '',
                              style: Theme.of(context).textTheme.bodySmall,
                            ),
                            const SizedBox(height: 10),
                            Text(
                              action.title,
                              style: Theme.of(context).textTheme.titleMedium,
                            ),
                            const SizedBox(height: 8),
                            Text(action.explanation),
                            const SizedBox(height: 8),
                            if (action.state == 'active')
                              Text(
                                'Based on ${action.evidenceCount} current evidence references. No savings amount has been calculated.',
                                style: Theme.of(context).textTheme.bodySmall,
                              )
                            else
                              const Text(
                                'This action has not been matched to enough current appliance evidence yet.',
                              ),
                            if (action.nextQuestion case final next?) ...[
                              const SizedBox(height: 8),
                              if (const {
                                'hours_per_week',
                                'cycles_per_week',
                              }.contains(next))
                                TextButton.icon(
                                  onPressed: () => _openQuestions(
                                    appliances[action.applianceId
                                        .toLowerCase()]!,
                                  ),
                                  icon: const Icon(Icons.edit_note),
                                  label: const Text(
                                    'Add usual usage information',
                                  ),
                                )
                              else
                                next == 'add_electricity_rate' ||
                                        next == 'add_gas_rate'
                                    ? TextButton.icon(
                                        key: Key(
                                          'recommendationRate-${action.applianceId}',
                                        ),
                                        onPressed: () async {
                                          await Navigator.of(context).push(
                                            MaterialPageRoute<void>(
                                              builder: (_) =>
                                                  CloudElectricityRateScreen(
                                                    api: widget.api,
                                                    home: widget.home,
                                                    gas: next == 'add_gas_rate',
                                                  ),
                                            ),
                                          );
                                          if (mounted) _load();
                                        },
                                        icon: const Icon(Icons.bolt_outlined),
                                        label: Text(
                                          next == 'add_gas_rate'
                                              ? 'Review Cloud natural gas rate'
                                              : 'Review Cloud electricity rate',
                                        ),
                                      )
                                    : Text(
                                        next == 'confirm_model'
                                            ? 'Review this appliance’s model.'
                                            : 'A reviewed energy source is needed.',
                                        style: Theme.of(context)
                                            .textTheme
                                            .bodySmall,
                                      ),
                            ],
                            if (action.state == 'active' &&
                                action.ruleId != 'dryer.gas_cycle_options') ...[
                              const SizedBox(height: 8),
                              TextButton.icon(
                                key: Key(
                                  'record-${action.ruleId}-${action.applianceId}',
                                ),
                                onPressed: () => Navigator.of(context).push(
                                  MaterialPageRoute<void>(
                                    builder: (_) => CloudInterventionScreen(
                                      api: widget.api,
                                      home: widget.home,
                                      action: action,
                                    ),
                                  ),
                                ),
                                icon: const Icon(Icons.check_circle_outline),
                                label: const Text('Record a manual change'),
                              ),
                            ],
                          ],
                        ),
                      ),
                    ),
                  const SizedBox(height: 12),
                  Text(
                    'Actions checked ${batch.asOf.toUtc().toIso8601String()}',
                    style: Theme.of(context).textTheme.bodySmall,
                  ),
                ],
              ],
            ),
          ),
        ),
      ),
    );
  }
}
