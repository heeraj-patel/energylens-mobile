import 'package:flutter/material.dart';

import '../../core/cloud_api/cloud_api_client.dart';
import '../../core/cloud_api/cloud_home.dart';
import '../../core/cloud_api/cloud_interventions.dart';
import '../../core/cloud_api/cloud_recommendations.dart';

class CloudInterventionScreen extends StatefulWidget {
  const CloudInterventionScreen({
    super.key,
    required this.api,
    required this.home,
    required this.action,
  });
  final CloudApiClient api;
  final CloudHome home;
  final CloudRecommendation action;

  @override
  State<CloudInterventionScreen> createState() =>
      _CloudInterventionScreenState();
}

class _CloudInterventionScreenState extends State<CloudInterventionScreen> {
  List<CloudAttachment>? _attachments;
  CloudAttachment? _selected;
  late DateTime _occurredAt;
  bool _verified = false;
  bool _comparableUse = false;
  bool _comparableWeather = false;
  final Set<String> _confounders = {};
  bool _busy = false;
  String? _error;
  String? _interventionId;
  CloudOutcome? _outcome;
  String _key = newCloudIdempotencyKey();
  CloudInterventionCreate? _pending;

  @override
  void initState() {
    super.initState();
    final now = DateTime.now().toUtc();
    _occurredAt = DateTime.utc(now.year, now.month, now.day, now.hour);
    _load();
  }

  Future<void> _load() async {
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      final preferences = await widget.api.accountPreferences();
      if (!preferences.value.historyAccepted) {
        throw StateError(
          'Accept the history disclosure in Cloud settings before recording an action.',
        );
      }
      final attachments = await widget.api.attachments(widget.home.id);
      final candidates = attachments
          .where(
            (a) =>
                a.applianceId.toLowerCase() ==
                    widget.action.applianceId.toLowerCase() &&
                a.activeAt(_occurredAt),
          )
          .toList();
      final verified = <CloudAttachment>[];
      for (final attachment in candidates) {
        if (await widget.api.hasExactMeterEvidence(
          widget.home.id,
          attachment.id,
        )) {
          verified.add(attachment);
        }
      }
      if (!mounted) return;
      setState(() {
        _attachments = verified;
        _selected = _attachments!.length == 1 ? _attachments!.single : null;
        if (_pending != null &&
            !verified.any((a) => a.id == _pending!.attachmentId)) {
          _pending = null;
          _key = newCloudIdempotencyKey();
          _verified = false;
        }
      });
    } on StateError catch (error) {
      if (mounted) setState(() => _error = error.message);
    } catch (_) {
      if (mounted) {
        setState(
          () => _error = 'Could not verify this home, disclosure, and attachment. Try again.',
        );
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  void _changed(VoidCallback change) {
    setState(() {
      change();
      _pending = null;
      _key = newCloudIdempotencyKey();
      _error = null;
    });
  }

  Future<void> _chooseDate() async {
    final now = DateTime.now().toUtc();
    final picked = await showDatePicker(
      context: context,
      initialDate: _occurredAt,
      firstDate: now.subtract(const Duration(days: 22)),
      lastDate: now,
    );
    if (picked == null) return;
    _changed(() {
      _occurredAt = DateTime.utc(
        picked.year,
        picked.month,
        picked.day,
        _occurredAt.hour,
      );
      _selected = null;
      _verified = false;
    });
    await _load();
  }

  Future<void> _submit() async {
    if (_selected == null || !_verified || _busy) return;
    final pending =
        _pending ??
        CloudInterventionCreate(
          applianceId: widget.action.applianceId.toLowerCase(),
          attachmentId: _selected!.id,
          ruleId: widget.action.ruleId,
          occurredAt: _occurredAt,
          comparableUse: _comparableUse,
          comparableWeather: _comparableWeather,
          confounders: _confounders.toList()..sort(),
        );
    setState(() {
      _pending = pending;
      _busy = true;
      _error = null;
    });
    try {
      final created = await widget.api.createIntervention(
        widget.home.id,
        pending,
        idempotencyKey: _key,
      );
      if (!mounted) return;
      setState(() => _interventionId = created.id);
      await _refreshOutcome();
    } on CloudApiException catch (error) {
      if (mounted) {
        setState(
          () => _error = switch (error.statusCode) {
            401 || 403 => 'Cloud sign-in or disclosure is required. Refresh verification before retrying.',
            404 => 'The selected home or attachment is no longer available. Refresh verification.',
            409 => 'This retry key conflicts with a different action. Change the form to start a new action.',
            _ => 'Could not confirm the action. Retry unchanged details with the same key.',
          },
        );
      }
    } catch (_) {
      if (mounted) {
        setState(
          () => _error = 'Could not confirm the action. Retry unchanged details with the same key.',
        );
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _refreshOutcome() async {
    final id = _interventionId;
    if (id == null) return;
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      final outcome = await widget.api.interventionOutcome(widget.home.id, id);
      if (mounted) setState(() => _outcome = outcome);
    } catch (_) {
      if (mounted) {
        setState(
          () => _error = 'Could not load the measured comparison. Try again.',
        );
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  String _reason(String reason) => switch (reason) {
    'follow_up_window_open' => 'The seven-day follow-up window is still open.',
    'rollup_pending' => 'Measured data is still being processed.',
    'attachment_changed' =>
      'The appliance attachment changed during the comparison.',
    'use_not_confirmed_comparable' => 'Comparable use was not confirmed.',
    'weather_not_confirmed_comparable' =>
      'Comparable weather was not confirmed.',
    'reported_confounders' => 'A reported change may affect the comparison.',
    'insufficient_measured_coverage' =>
      'Complete measured coverage is insufficient.',
    'allocated_measurement' =>
      'Some energy was allocated rather than exactly measured.',
    'no_clear_change' => 'No clear measured change was found.',
    _ => reason.replaceAll('_', ' '),
  };

  @override
  Widget build(BuildContext context) {
    final eligible =
        _attachments?.where((a) => a.activeAt(_occurredAt)).toList() ?? [];
    final outcome = _outcome;
    return Scaffold(
      appBar: AppBar(title: const Text('Record manual action')),
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
                Text(
                  widget.action.title,
                  style: Theme.of(context).textTheme.titleMedium,
                ),
                const SizedBox(height: 8),
                const Text(
                  'Record a change you made yourself. A before/after comparison can describe measured use; it cannot prove this action caused a change or establish savings.',
                ),
                const SizedBox(height: 16),
                if (_busy) const LinearProgressIndicator(),
                if (_interventionId == null) ...[
                  Text(
                    'Action time: ${_occurredAt.toIso8601String()} (UTC hour)',
                  ),
                  TextButton(
                    onPressed: _busy ? null : _chooseDate,
                    child: const Text('Choose UTC date'),
                  ),
                  DropdownButton<int>(
                    value: _occurredAt.hour,
                    items: [
                      for (var hour = 0; hour < 24; hour++)
                        DropdownMenuItem(
                          value: hour,
                          child: Text(
                            '${hour.toString().padLeft(2, '0')}:00 UTC',
                          ),
                        ),
                    ],
                    onChanged: _busy
                        ? null
                        : (hour) async {
                            if (hour == null) return;
                            _changed(() {
                              _occurredAt = DateTime.utc(
                                _occurredAt.year,
                                _occurredAt.month,
                                _occurredAt.day,
                                hour,
                              );
                              _selected = null;
                              _verified = false;
                            });
                            await _load();
                          },
                  ),
                  if (eligible.isEmpty && !_busy)
                    const Text(
                      'No verified Cloud attachment for this appliance at that hour. Connect and verify a metering attachment before recording an action.',
                    ),
                  if (eligible.isNotEmpty) ...[
                    DropdownButton<CloudAttachment>(
                      value: _selected,
                      hint: const Text('Select Cloud attachment'),
                      items: [
                        for (final a in eligible)
                          DropdownMenuItem(
                            value: a,
                            child: Text('Attachment ${a.id.substring(0, 8)}'),
                          ),
                      ],
                      onChanged: _busy
                          ? null
                          : (a) => _changed(() {
                              _selected = a;
                              _verified = false;
                            }),
                    ),
                    CheckboxListTile(
                      value: _verified,
                      onChanged: _busy || _selected == null
                          ? null
                          : (value) =>
                                _changed(() => _verified = value ?? false),
                      title: const Text(
                        'I verified this metering attachment was connected to this appliance when I made the change.',
                      ),
                    ),
                  ],
                  SwitchListTile(
                    value: _comparableUse,
                    onChanged: _busy
                        ? null
                        : (value) => _changed(() => _comparableUse = value),
                    title: const Text('Use was comparable before and after'),
                  ),
                  SwitchListTile(
                    value: _comparableWeather,
                    onChanged: _busy
                        ? null
                        : (value) => _changed(() => _comparableWeather = value),
                    title: const Text(
                      'Weather was comparable before and after',
                    ),
                  ),
                  const Text('Report any other changes that could affect use:'),
                  for (final entry in const {
                    'occupancy_changed': 'Occupancy changed',
                    'use_changed': 'Use changed',
                    'weather_changed': 'Weather changed',
                    'equipment_changed': 'Equipment changed',
                    'other': 'Other change',
                    'unknown': 'I am unsure',
                  }.entries)
                    CheckboxListTile(
                      dense: true,
                      title: Text(entry.value),
                      value: _confounders.contains(entry.key),
                      onChanged: _busy
                          ? null
                          : (value) => _changed(() {
                              if (value ?? false) {
                                _confounders.add(entry.key);
                              } else {
                                _confounders.remove(entry.key);
                              }
                            }),
                    ),
                  FilledButton(
                    key: const Key('recordManualAction'),
                    onPressed:
                        _busy ||
                            !_verified ||
                            _selected == null ||
                            _occurredAt.isAfter(DateTime.now().toUtc())
                        ? null
                        : _submit,
                    child: const Text('Record action and check outcome'),
                  ),
                ] else ...[
                  Text('Action recorded · ${_interventionId!.substring(0, 8)}'),
                  TextButton(
                    onPressed: _busy ? null : _refreshOutcome,
                    child: const Text('Refresh measured comparison'),
                  ),
                ],
                if (_error != null)
                  Text(_error!, key: const Key('interventionError')),
                if (_error != null && _interventionId == null)
                  TextButton(
                    onPressed: _busy ? null : _load,
                    child: const Text('Refresh verification'),
                  ),
                if (outcome != null) ...[
                  const SizedBox(height: 16),
                  Text(switch (outcome.status) {
                    'observed-change' => 'Observed measured difference',
                    'inconclusive' => 'Comparison inconclusive',
                    _ => 'Collecting follow-up measurements',
                  }, style: Theme.of(context).textTheme.titleLarge),
                  for (final period in [
                    ('Before', outcome.before),
                    ('After', outcome.after),
                  ])
                    Text(
                      '${period.$1}: ${period.$2.from.toIso8601String()} to ${period.$2.to.toIso8601String()} · ${period.$2.measuredHours}/${period.$2.expectedHours} measured hours · ${(period.$2.coverageFraction * 100).toStringAsFixed(1)}% coverage · ${period.$2.knownGapHours} gap hours · ${period.$2.allocatedHours} allocated hours${period.$2.energyWh == null ? '' : ' · ${period.$2.energyWh!.toStringAsFixed(1)} Wh'}',
                    ),
                  if (outcome.deltaWh != null)
                    Text(
                      'After minus before: ${outcome.deltaWh!.toStringAsFixed(1)} Wh',
                    ),
                  for (final reason in outcome.reasons)
                    Text('• ${_reason(reason)}'),
                  Text(outcome.interpretation),
                  const Text(
                    'This is an uncontrolled before/after comparison. Coverage gaps, changed use, weather, or other conditions can affect the result. No dollar or causal savings claim is made.',
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
