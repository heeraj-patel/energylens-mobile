import 'package:flutter/material.dart';

import '../../core/cloud_api/cloud_api_client.dart';
import '../../core/cloud_api/cloud_appliance.dart';
import '../../core/cloud_api/cloud_cycle_comparison.dart';
import '../../core/cloud_api/cloud_home.dart';
import '../../core/cloud_api/cloud_interventions.dart';

/// A laboratory-reference comparison for one explicitly tagged meter interval.
class CloudCycleComparisonScreen extends StatefulWidget {
  const CloudCycleComparisonScreen({
    super.key,
    required this.api,
    required this.home,
  });

  final CloudApiClient api;
  final CloudHome home;

  @override
  State<CloudCycleComparisonScreen> createState() =>
      _CloudCycleComparisonScreenState();
}

class _CloudCycleComparisonScreenState
    extends State<CloudCycleComparisonScreen> {
  List<CloudAppliance>? _appliances;
  List<CloudAttachment> _attachments = const [];
  CloudAppliance? _appliance;
  CloudCycleReferenceOption? _reference;
  CloudAttachment? _attachment;
  late DateTime _start;
  late DateTime _end;
  bool _basisConfirmed = false;
  bool _dedicated = false;
  bool _busy = false;
  String? _error;
  CloudCycleComparisonResult? _result;
  CloudCycleComparisonRequest? _comparedRequest;
  String? _comparedApplianceId;
  CloudSavedCycleEvidence? _saved;
  String? _saveKey;
  int _generation = 0;

  @override
  void initState() {
    super.initState();
    final now = DateTime.now();
    _end = DateTime(now.year, now.month, now.day, now.hour, now.minute);
    _start = _end.subtract(const Duration(minutes: 90));
    _load();
  }

  Future<void> _load() async {
    final generation = ++_generation;
    setState(() {
      _busy = true;
      _error = null;
      _result = null;
      _comparedRequest = null;
      _saved = null;
      _saveKey = null;
    });
    try {
      final preferences = await widget.api.accountPreferences();
      if (!preferences.value.historyAccepted) {
        throw StateError(
          'Accept Cloud energy history in account settings before comparing a measured cycle.',
        );
      }
      final appliances = await widget.api.appliances(widget.home.id);
      final attachments = await widget.api.attachments(widget.home.id);
      if (!mounted || generation != _generation) return;
      final eligible = appliances
          .where(
            (a) =>
                a.category == 'dishwasher' &&
                a.fuel == 'electricity' &&
                a.matchQuality == 'confirmed_exact',
          )
          .toList();
      setState(() {
        _appliances = eligible;
        _attachments = attachments;
        _appliance = eligible.length == 1 ? eligible.single : null;
        _attachment = null;
        _reference = null;
      });
      if (_appliance != null) await _loadReference(_appliance!, generation);
    } on StateError catch (error) {
      if (mounted && generation == _generation) {
        setState(() => _error = error.message);
      }
    } catch (_) {
      if (mounted && generation == _generation) {
        setState(
          () => _error = 'Could not load Cloud cycle evidence. Try again.',
        );
      }
    } finally {
      if (mounted && generation == _generation) {
        setState(() => _busy = false);
      }
    }
  }

  Future<void> _loadReference(CloudAppliance appliance, int generation) async {
    try {
      final option = await widget.api.dishwasherCycleReference(
        widget.home.id,
        appliance.id,
        (_appliances ?? []).map((item) => item.id).toSet(),
      );
      if (!mounted ||
          generation != _generation ||
          _appliance?.id != appliance.id) {
        return;
      }
      setState(() => _reference = option);
    } catch (_) {
      if (mounted &&
          generation == _generation &&
          _appliance?.id == appliance.id) {
        setState(
          () => _error =
              'Could not load the reviewed cycle reference. Try again.',
        );
      }
    }
  }

  void _selectAppliance(CloudAppliance? appliance) {
    final generation = ++_generation;
    setState(() {
      _appliance = appliance;
      _reference = null;
      _attachment = null;
      _basisConfirmed = false;
      _dedicated = false;
      _result = null;
      _comparedRequest = null;
      _saved = null;
      _saveKey = null;
      _error = null;
    });
    if (appliance != null) _loadReference(appliance, generation);
  }

  Future<void> _pickWindowTime({required bool start}) async {
    final now = DateTime.now();
    final current = start ? _start : _end;
    final date = await showDatePicker(
      context: context,
      initialDate: current,
      firstDate: now.subtract(const Duration(days: 29)),
      lastDate: now,
    );
    if (!mounted || date == null) return;
    final time = await showTimePicker(
      context: context,
      initialTime: TimeOfDay.fromDateTime(current),
    );
    if (!mounted || time == null) return;
    setState(() {
      final picked = DateTime(
        date.year,
        date.month,
        date.day,
        time.hour,
        time.minute,
      );
      if (start) {
        _start = picked;
      } else {
        _end = picked;
      }
      _result = null;
      _comparedRequest = null;
      _saved = null;
      _saveKey = null;
      _attachment = null;
      _error = null;
    });
  }

  String _time(DateTime value) =>
      '${MaterialLocalizations.of(context).formatMediumDate(value)} · ${MaterialLocalizations.of(context).formatTimeOfDay(TimeOfDay.fromDateTime(value))}';

  List<CloudAttachment> get _windowAttachments {
    final appliance = _appliance;
    if (appliance == null || !_end.isAfter(_start)) return const [];
    return _attachments
        .where(
          (a) =>
              a.applianceId.toLowerCase() == appliance.id.toLowerCase() &&
              a.activeAt(_start.toUtc()) &&
              a.activeAt(
                _end.toUtc().subtract(const Duration(microseconds: 1)),
              ),
        )
        .toList();
  }

  bool get _validWindow {
    final now = DateTime.now().toUtc();
    final start = _start.toUtc();
    final end = _end.toUtc();
    return end.isAfter(start) &&
        end.difference(start) <= const Duration(hours: 24) &&
        !start.isBefore(now.subtract(const Duration(days: 30))) &&
        !end.isAfter(now);
  }

  Future<void> _compare() async {
    final appliance = _appliance;
    final reference = _reference?.fact;
    final attachment = _attachment;
    if (_busy ||
        appliance == null ||
        reference == null ||
        attachment == null ||
        !_basisConfirmed ||
        !_dedicated ||
        !_validWindow) {
      return;
    }
    final request = CloudCycleComparisonRequest(
      start: _start.toUtc(),
      end: _end.toUtc(),
      attachmentId: attachment.id,
      reference: reference,
      dedicatedNoOtherLoads: true,
    );
    setState(() {
      _busy = true;
      _error = null;
      _result = null;
      _comparedRequest = null;
      _saved = null;
      _saveKey = null;
    });
    try {
      final result = await widget.api.compareDishwasherCycle(
        widget.home.id,
        appliance.id,
        (_appliances ?? []).map((item) => item.id).toSet(),
        request,
      );
      if (mounted) {
        setState(() {
          _result = result;
          _comparedRequest = result.status == 'available' ? request : null;
          _comparedApplianceId = result.status == 'available'
              ? appliance.id
              : null;
          _saveKey = result.status == 'available'
              ? newCloudIdempotencyKey()
              : null;
        });
      }
    } on CloudApiException catch (error) {
      if (mounted) {
        setState(
          () => _error = switch (error.statusCode) {
            401 || 403 => 'Cloud sign-in or history consent is required.',
            404 => 'This home, dishwasher or attachment changed. Refresh the evidence.',
            _ => 'Could not compare this cycle. Try again.',
          },
        );
      }
    } catch (_) {
      if (mounted) {
        setState(() => _error = 'Could not compare this cycle. Try again.');
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _saveEvidence() async {
    final request = _comparedRequest;
    final applianceId = _comparedApplianceId;
    final key = _saveKey;
    if (_busy ||
        request == null ||
        applianceId == null ||
        key == null ||
        _appliance?.id != applianceId ||
        _result?.status != 'available') {
      return;
    }
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      final saved = await widget.api.saveDishwasherCycleEvidence(
        widget.home.id,
        applianceId,
        (_appliances ?? []).map((a) => a.id).toSet(),
        request,
        idempotencyKey: key,
      );
      if (mounted && _appliance?.id == applianceId) {
        setState(() => _saved = saved);
      }
    } on CloudApiException catch (error) {
      if (mounted) {
        setState(
          () => _error = switch (error.code) {
            'history_disclosure_required' =>
              'Accept Cloud energy history before saving this cycle.',
            'evidence_unavailable' =>
              'This cycle evidence changed. Refresh and compare again.',
            'idempotency_conflict' => 'This save request conflicts with an earlier attempt. Change the cycle and try again.',
            _ => 'Could not save this cycle. Retry to use the same request.',
          },
        );
      }
    } catch (_) {
      if (mounted) {
        setState(
          () => _error =
              'Could not save this cycle. Retry to use the same request.',
        );
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _refreshSavedEvidence() async {
    final saved = _saved;
    final request = _comparedRequest;
    final applianceId = _comparedApplianceId;
    if (_busy ||
        saved == null ||
        request == null ||
        applianceId == null ||
        _appliance?.id != applianceId) {
      return;
    }
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      final refreshed = await widget.api.dishwasherCycleEvidence(
        widget.home.id,
        applianceId,
        (_appliances ?? []).map((a) => a.id).toSet(),
        saved.id,
        request,
      );
      if (mounted && _appliance?.id == applianceId) {
        setState(() {
          _saved = refreshed;
          if (refreshed.status == 'invalidated') _result = null;
        });
      }
    } on CloudApiException catch (error) {
      if (mounted) {
        setState(
          () => _error = error.statusCode == 404
              ? 'Saved cycle evidence expired or is unavailable for this home.'
              : 'Could not refresh saved cycle evidence. Try again.',
        );
      }
    } catch (_) {
      if (mounted) {
        setState(
          () => _error = 'Could not refresh saved cycle evidence. Try again.',
        );
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  String _unavailableReason(String? reason) => switch (reason) {
    'attachment_unavailable' || 'attachment_not_dedicated_for_window' =>
      'The selected plug attachment did not cover the full cycle.',
    'raw_interval_coverage_or_scope_invalid' || 'coverage_gap_reported' =>
      'Meter intervals did not cover the entire cycle without gaps or overlap.',
    'outside_detail_retention' =>
      'Cycle detail is available only for the recent 30 days.',
    'reviewed_fact_missing_or_ambiguous' ||
    'reviewed_basis_not_confirmed' ||
    'fact_scope_not_appliance_electricity_only' =>
      'The reviewed model and cycle reference could not be confirmed.',
    'identity_not_exact' =>
      'Confirm the exact electric dishwasher model first.',
    _ => 'More compatible meter and source information is needed.',
  };

  @override
  Widget build(BuildContext context) {
    final fact = _reference?.fact;
    final attachments = _windowAttachments;
    final selectedAttachment = attachments.any((a) => a.id == _attachment?.id)
        ? _attachment
        : null;
    return Scaffold(
      appBar: AppBar(title: const Text('Compare a dishwasher cycle')),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          const Text(
            'Compare one metered dishwasher cycle with a reviewed laboratory reference. This describes a difference in conditions and use; it does not identify Waste or savings. You can save the verified evidence after comparing.',
          ),
          const SizedBox(height: 12),
          TextButton.icon(
            onPressed: _busy ? null : _load,
            icon: const Icon(Icons.refresh),
            label: const Text('Refresh Cloud evidence'),
          ),
          if (_busy) const LinearProgressIndicator(),
          if (_error != null)
            Text(_error!, key: const Key('cycleComparisonError')),
          if (_appliances != null && _appliances!.isEmpty)
            const Text(
              'No confirmed exact electric dishwasher is saved in this Cloud home.',
            ),
          if (_appliances != null && _appliances!.isNotEmpty) ...[
            DropdownButtonFormField<CloudAppliance>(
              key: const Key('cycleAppliance'),
              initialValue: _appliance,
              decoration: const InputDecoration(labelText: 'Dishwasher'),
              items: _appliances!
                  .map(
                    (a) => DropdownMenuItem(
                      value: a,
                      child: Text('${a.name} · ${a.fullModel}'),
                    ),
                  )
                  .toList(),
              onChanged: _busy ? null : _selectAppliance,
            ),
            if (_appliance != null && _reference?.status == 'unavailable')
              Text(
                'No exact reviewed electricity-per-cycle reference is available for this model. More source review is needed.',
                key: const Key('cycleReferenceUnavailable'),
              ),
            if (fact != null) ...[
              const SizedBox(height: 16),
              Text(
                'Reviewed laboratory reference: ${fact.valueKWhPerCycle.toStringAsFixed(3)} kWh/cycle',
                key: const Key('cycleReferenceValue'),
              ),
              Text('Test basis: ${fact.testBasis}'),
              Text('Cycle definition: ${fact.cycleDefinition}'),
              SelectableText(
                'Source: ${fact.sourceUrl} · reviewed ${fact.reviewedAt.toLocal()}',
              ),
              CheckboxListTile(
                key: const Key('cycleBasisConfirmed'),
                value: _basisConfirmed,
                onChanged: _busy
                    ? null
                    : (value) => setState(() {
                        _basisConfirmed = value ?? false;
                        _result = null;
                        _comparedRequest = null;
                        _saved = null;
                        _saveKey = null;
                      }),
                title: const Text(
                  'I used the listed cycle/program and reviewed the source test basis.',
                ),
                subtitle: const Text(
                  'Home conditions may still differ from the laboratory test.',
                ),
              ),
              const SizedBox(height: 8),
              OutlinedButton(
                key: const Key('cycleStartPicker'),
                onPressed: _busy ? null : () => _pickWindowTime(start: true),
                child: Text('Cycle started: ${_time(_start)}'),
              ),
              OutlinedButton(
                key: const Key('cycleEndPicker'),
                onPressed: _busy ? null : () => _pickWindowTime(start: false),
                child: Text('Cycle ended: ${_time(_end)}'),
              ),
              if (!_validWindow)
                const Text(
                  'Choose a completed cycle within the last 30 days, up to 24 hours long.',
                ),
              if (attachments.isEmpty)
                const Text(
                  'No Cloud plug or outlet attachment covers this whole cycle. Connect and verify one before comparing.',
                ),
              if (attachments.isNotEmpty)
                DropdownButtonFormField<CloudAttachment>(
                  key: const Key('cycleAttachment'),
                  initialValue: selectedAttachment,
                  decoration: const InputDecoration(
                    labelText: 'Meter attachment',
                  ),
                  items: attachments
                      .map(
                        (a) => DropdownMenuItem(
                          value: a,
                          child: Text(
                            'Plug/outlet attachment ${a.id.substring(0, 8)}',
                          ),
                        ),
                      )
                      .toList(),
                  onChanged: _busy
                      ? null
                      : (value) => setState(() {
                          _attachment = value;
                          _result = null;
                          _comparedRequest = null;
                          _saved = null;
                          _saveKey = null;
                        }),
                ),
              CheckboxListTile(
                key: const Key('cycleDedicatedConfirmed'),
                value: _dedicated,
                onChanged: _busy
                    ? null
                    : (value) => setState(() {
                        _dedicated = value ?? false;
                        _result = null;
                        _comparedRequest = null;
                        _saved = null;
                        _saveKey = null;
                      }),
                title: const Text(
                  'This plug or outlet served only this dishwasher during the tagged cycle.',
                ),
              ),
              FilledButton(
                key: const Key('compareDishwasherCycle'),
                onPressed:
                    _busy ||
                        !_validWindow ||
                        !_basisConfirmed ||
                        !_dedicated ||
                        selectedAttachment == null
                    ? null
                    : _compare,
                child: const Text('Compare this cycle'),
              ),
            ],
          ],
          if (_result != null) ...[
            const SizedBox(height: 16),
            if (_result!.status == 'available') ...[
              Text(
                'Measured this cycle: ${_result!.measuredKWh!.toStringAsFixed(3)} kWh',
                key: const Key('cycleMeasuredValue'),
              ),
              Text(
                'Reviewed laboratory reference: ${_result!.labReferenceKWhPerCycle!.toStringAsFixed(3)} kWh/cycle',
              ),
              Text(
                'Difference: ${_result!.differenceKWh!.toStringAsFixed(3)} kWh',
              ),
              const Text(
                'This is a descriptive comparison. Different load, program settings or conditions can affect the difference. No Waste or savings amount is established.',
              ),
              if (_saved == null)
                FilledButton(
                  key: const Key('saveCycleEvidence'),
                  onPressed: _busy ? null : _saveEvidence,
                  child: const Text('Save cycle evidence'),
                ),
            ] else
              Text(
                _unavailableReason(_result!.reason),
                key: const Key('cycleComparisonUnavailable'),
              ),
          ],
          if (_saved != null) ...[
            const SizedBox(height: 12),
            Text(
              _saved!.status == 'available'
                  ? 'Cycle evidence saved for this dishwasher.'
                  : 'Saved cycle evidence changed and is no longer available.',
              key: const Key('savedCycleEvidenceStatus'),
            ),
            if (_saved!.status == 'invalidated')
              const Text(
                'Review the meter coverage, attachment and appliance before comparing again.',
              ),
            TextButton(
              key: const Key('refreshSavedCycleEvidence'),
              onPressed: _busy ? null : _refreshSavedEvidence,
              child: const Text('Refresh saved evidence'),
            ),
          ],
        ],
      ),
    );
  }
}
