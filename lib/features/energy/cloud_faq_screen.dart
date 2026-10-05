import 'package:flutter/material.dart';

import '../../core/cloud_api/cloud_api_client.dart';
import '../../core/cloud_api/cloud_appliance.dart';
import '../../core/cloud_api/cloud_faq.dart';
import '../../core/cloud_api/cloud_home.dart';
import '../identify/cloud_usage_questions_screen.dart';

class CloudFaqScreen extends StatefulWidget {
  const CloudFaqScreen({super.key, required this.api, required this.home});

  final CloudApiClient api;
  final CloudHome home;

  @override
  State<CloudFaqScreen> createState() => _CloudFaqScreenState();
}

class _CloudFaqScreenState extends State<CloudFaqScreen> {
  String _intent = faqIntents.keys.first;
  String? _applianceId;
  List<CloudAppliance>? _appliances;
  CloudFaqAnswer? _answer;
  String? _error;
  bool _loading = false;
  bool _inventoryLoading = false;
  int _generation = 0;

  @override
  void initState() {
    super.initState();
    _loadAppliances();
    _loadAnswer();
  }

  Future<void> _loadAppliances() async {
    setState(() => _inventoryLoading = true);
    try {
      final appliances = await widget.api.appliances(widget.home.id);
      if (!mounted) return;
      setState(() {
        _appliances = appliances;
        if (_applianceId != null &&
            !appliances.any((a) => a.id == _applianceId)) {
          _applianceId = null;
          _answer = null;
        }
      });
    } catch (_) {
      if (mounted) setState(() => _appliances = null);
    } finally {
      if (mounted) setState(() => _inventoryLoading = false);
    }
  }

  Future<void> _loadAnswer() async {
    final generation = ++_generation;
    final intent = _intent;
    final applianceId = _applianceId;
    setState(() {
      _answer = null;
      _error = null;
      _loading = intent != 'device_operating_cost' || applianceId != null;
    });
    if (!_loading) return;
    try {
      final answer = await widget.api.faqAnswer(
        widget.home.id,
        intent,
        applianceId: applianceId,
      );
      if (mounted && generation == _generation) {
        setState(() => _answer = answer);
      }
    } on CloudApiException catch (error) {
      if (mounted && generation == _generation) {
        setState(
          () => _error = error.statusCode == 401 || error.statusCode == 403
              ? 'Cloud sign-in is required to view this answer.'
              : 'Could not load this answer. Try again.',
        );
      }
    } catch (_) {
      if (mounted && generation == _generation) {
        setState(() => _error = 'Could not load this answer. Try again.');
      }
    } finally {
      if (mounted && generation == _generation) {
        setState(() => _loading = false);
      }
    }
  }

  void _selectIntent(String intent) {
    if (_intent == intent) return;
    setState(() => _intent = intent);
    _loadAnswer();
  }

  Future<void> _openQuestions(CloudAppliance appliance, String purpose) async {
    await Navigator.of(context).push<void>(
      MaterialPageRoute<void>(
        builder: (_) => CloudUsageQuestionsScreen(
          home: widget.home,
          appliance: appliance,
          api: widget.api,
          purpose: purpose,
        ),
      ),
    );
    if (mounted) _loadAnswer();
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: const Text('Cloud answers')),
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
              const Text('Answers use information saved for this cloud home.'),
              const SizedBox(height: 20),
              RadioGroup<String>(
                groupValue: _intent,
                onChanged: (value) {
                  if (value != null) _selectIntent(value);
                },
                child: Column(
                  children: [
                    for (final entry in faqIntents.entries)
                      RadioListTile<String>(
                        key: Key('faqIntent-${entry.key}'),
                        title: Text(entry.value),
                        value: entry.key,
                      ),
                  ],
                ),
              ),
              if (_intent == 'device_operating_cost') ...[
                const SizedBox(height: 12),
                if (_inventoryLoading) const LinearProgressIndicator(),
                if (_appliances == null && !_inventoryLoading)
                  TextButton(
                    onPressed: _loadAppliances,
                    child: const Text('Retry loading cloud appliances'),
                  ),
                if (_appliances != null && _appliances!.isEmpty)
                  const Text(
                    'Add an appliance to this cloud home to ask about its operating cost.',
                  ),
                if (_appliances != null && _appliances!.isNotEmpty)
                  DropdownButtonFormField<String>(
                    key: const Key('faqAppliance'),
                    initialValue: _applianceId,
                    decoration: const InputDecoration(
                      labelText: 'Cloud appliance',
                    ),
                    items: [
                      for (final appliance in _appliances!)
                        DropdownMenuItem(
                          value: appliance.id,
                          child: Text(appliance.name),
                        ),
                    ],
                    onChanged: (id) {
                      setState(() => _applianceId = id);
                      _loadAnswer();
                    },
                  ),
                if (_applianceId == null)
                  const Padding(
                    padding: EdgeInsets.only(top: 12),
                    child: Text(
                      'Select an appliance to see its sourced operating cost.',
                    ),
                  ),
              ],
              const SizedBox(height: 20),
              if (_loading)
                const LinearProgressIndicator(key: Key('faqLoading')),
              if (_error != null) ...[
                Text(_error!, key: const Key('faqError')),
                TextButton(
                  onPressed: _loadAnswer,
                  child: const Text('Retry answer'),
                ),
              ],
              if (_answer case final answer?) ...[
                Text(
                  answer.text,
                  key: const Key('faqAnswer'),
                  style: Theme.of(context).textTheme.titleMedium,
                ),
                const SizedBox(height: 12),
                for (final finding in answer.findings)
                  Card(
                    child: Padding(
                      padding: const EdgeInsets.all(16),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            finding.label == 'estimate'
                                ? 'Estimate'
                                : finding.label == 'observation'
                                ? 'Observation'
                                : 'Possibility',
                            style: Theme.of(context).textTheme.labelLarge,
                          ),
                          const SizedBox(height: 6),
                          Text(finding.text),
                          const SizedBox(height: 8),
                          Text(
                            'Sources: ${finding.refs.map((ref) => '${ref.kind} · revision ${ref.revision}').join(', ')}',
                            style: Theme.of(context).textTheme.bodySmall,
                          ),
                        ],
                      ),
                    ),
                  ),
                if (answer.adaptiveQuestions) ...[
                  const SizedBox(height: 16),
                  const Text(
                    'Recent-use questions can add context for future answers. They do not explain a bill by themselves.',
                  ),
                  if (_appliances != null && _appliances!.isNotEmpty)
                    for (final appliance in _appliances!)
                      TextButton.icon(
                        key: Key('faqQuestions-${appliance.id}'),
                        onPressed: () => _openQuestions(appliance, 'faq'),
                        icon: const Icon(Icons.edit_note),
                        label: Text('Recent use for ${appliance.name}'),
                      ),
                  if (_appliances != null && _appliances!.isEmpty)
                    const Text(
                      'Add a cloud appliance to answer usage questions.',
                    ),
                  if (_appliances == null)
                    TextButton(
                      onPressed: _loadAppliances,
                      child: const Text('Load appliances for usage questions'),
                    ),
                ],
              ],
              if (_appliances != null && _appliances!.isNotEmpty) ...[
                const SizedBox(height: 24),
                Text(
                  'Unused-on time',
                  style: Theme.of(context).textTheme.titleMedium,
                ),
                const Text(
                  'Optional questions about devices left on without use. Answers are context, not a waste finding.',
                ),
                for (final appliance in _appliances!)
                  TextButton.icon(
                    key: Key('avoidQuestions-${appliance.id}'),
                    onPressed: () => _openQuestions(appliance, 'avoid'),
                    icon: const Icon(Icons.schedule_outlined),
                    label: Text('Unused-on questions for ${appliance.name}'),
                  ),
              ],
            ],
          ),
        ),
      ),
    ),
  );
}
