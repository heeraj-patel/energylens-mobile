import 'package:flutter/material.dart';

import '../../core/cloud_api/cloud_api_client.dart';
import '../../core/cloud_api/cloud_appliance.dart';
import '../../core/cloud_api/cloud_home.dart';
import '../../core/cloud_api/cloud_question.dart';

class CloudUsageQuestionsScreen extends StatefulWidget {
  const CloudUsageQuestionsScreen({
    super.key,
    required this.home,
    required this.appliance,
    required this.api,
    this.purpose = 'onboarding',
  });

  final CloudHome home;
  final CloudAppliance appliance;
  final CloudApiClient api;
  final String purpose;

  @override
  State<CloudUsageQuestionsScreen> createState() =>
      _CloudUsageQuestionsScreenState();
}

class _CloudUsageQuestionsScreenState extends State<CloudUsageQuestionsScreen> {
  List<CloudQuestion>? _questions;
  final Map<String, CloudSavedAnswer> _saved = {};
  final Map<String, String> _choices = {};
  final Map<String, TextEditingController> _values = {};
  String _saveKey = newCloudIdempotencyKey();
  List<CloudAnswerCreate>? _pendingAnswers;
  String? _error;
  bool _busy = false;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() {
      _busy = true;
      _error = null;
      _questions = null;
    });
    try {
      final questions = await widget.api.questions(
        widget.home.id,
        widget.appliance.id,
        purpose: widget.purpose,
      );
      final answers = await widget.api.currentQuestionAnswers(
        widget.home.id,
        widget.appliance.id,
      );
      if (!mounted) return;
      for (final controller in _values.values) {
        controller.dispose();
      }
      _values.clear();
      _choices.clear();
      _saved.clear();
      final currentQuestions = {for (final q in questions) q.id: q};
      for (final answer in answers) {
        final question = currentQuestions[answer.questionId];
        if (question == null || !answer.matches(question)) continue;
        _saved[question.id] = answer;
        _choices[question.id] = answer.status;
        if (answer.status == 'confirmed') {
          final controller = TextEditingController(text: '${answer.value}');
          controller.addListener(_changed);
          _values[question.id] = controller;
        }
      }
      _saveKey = newCloudIdempotencyKey();
      _pendingAnswers = null;
      setState(() => _questions = questions);
    } catch (_) {
      if (mounted) {
        setState(() => _error = 'Could not load usage questions. Try again.');
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  void _changed() {
    _saveKey = newCloudIdempotencyKey();
    _pendingAnswers = null;
    if (_error != null) setState(() => _error = null);
  }

  Future<void> _submit() async {
    if (_busy || _questions == null) return;
    final answers = <CloudAnswerCreate>[];
    for (final question in _questions!) {
      final choice = _choices[question.id];
      if (choice == null) {
        if (!question.optional) {
          setState(() => _error = 'Answer every required question.');
          return;
        }
        continue;
      }
      num? value;
      if (choice == 'confirmed') {
        final raw = _values[question.id]?.text.trim() ?? '';
        value = question.answerKind == 'cycles_per_week'
            ? int.tryParse(raw)
            : num.tryParse(raw);
        final maximum = question.answerKind == 'cycles_per_week' ? 100 : 168;
        if (value == null || !value.isFinite || value < 0 || value > maximum) {
          setState(
            () => _error =
                'Enter a number from 0 to $maximum for ${question.prompt}',
          );
          return;
        }
      }
      answers.add(
        CloudAnswerCreate(
          question: question,
          value: value,
          confirmedAt: choice == 'confirmed' ? DateTime.now().toUtc() : null,
        ),
      );
    }
    final changedAnswers = answers.where((answer) {
      final saved = _saved[answer.question.id];
      return saved == null ||
          saved.status != (answer.value == null ? 'unknown' : 'confirmed') ||
          saved.value != answer.value;
    }).toList();
    if (changedAnswers.isEmpty) {
      Navigator.of(context).pop();
      return;
    }
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      await widget.api.submitQuestionAnswers(
        widget.home.id,
        _pendingAnswers ??= changedAnswers,
        idempotencyKey: _saveKey,
      );
      if (!mounted) return;
      if (widget.purpose == 'onboarding') {
        Navigator.of(context).pop(true);
      } else {
        await _load();
      }
    } on CloudApiException catch (error) {
      if (!mounted) return;
      setState(
        () => _error = switch (error.code) {
          'version_conflict' =>
            'The appliance changed. Refresh questions before answering again.',
          'history_disclosure_required' => 'Accept the required history disclosure in Cloud settings before answering.',
          _ =>
            'Could not confirm answers (${error.code}). Retry unchanged answers with the same request key.',
        },
      );
    } catch (_) {
      if (mounted) {
        setState(
          () => _error = 'Could not confirm answers. Retry unchanged answers with the same request key.',
        );
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  void dispose() {
    for (final controller in _values.values) {
      controller.dispose();
    }
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(
      title: Text(
        widget.purpose == 'faq'
            ? 'Recent-use questions'
            : widget.purpose == 'avoid'
            ? 'Unused-on questions'
            : 'Usage questions',
      ),
    ),
    body: SafeArea(
      child: ListView(
        padding: const EdgeInsets.all(20),
        children: [
          Text(
            widget.appliance.name,
            style: Theme.of(context).textTheme.titleLarge,
          ),
          const SizedBox(height: 8),
          Text(
            widget.purpose == 'onboarding'
                ? 'These answers describe your usual use. They are estimates, not measured readings. Zero means confirmed none; Unknown means you do not know. You can leave optional questions unanswered.'
                : 'These optional answers add context. Zero means confirmed none; Unknown means you do not know. An answer alone does not establish waste or explain a bill.',
          ),
          if (_busy) const LinearProgressIndicator(),
          if (_error != null) ...[
            const SizedBox(height: 12),
            Text(_error!, key: const Key('usageQuestionError')),
          ],
          if (_questions == null) ...[
            const SizedBox(height: 16),
            OutlinedButton(
              onPressed: _busy ? null : _load,
              child: const Text('Retry loading questions'),
            ),
          ] else if (_questions!.isEmpty) ...[
            const SizedBox(height: 16),
            Text(
              widget.purpose == 'onboarding'
                  ? 'No usage questions are available for this appliance type yet.'
                  : 'No more questions are available in this flow for this appliance. This does not mean a cost or waste finding is supported.',
            ),
          ] else ...[
            for (final question in _questions!) ...[
              const SizedBox(height: 20),
              Text(
                question.prompt,
                style: Theme.of(context).textTheme.titleMedium,
              ),
              Text(switch (_saved[question.id]) {
                CloudSavedAnswer(status: 'unknown') => 'Saved: Unknown',
                CloudSavedAnswer(value: final value) =>
                  'Saved: $value ${question.unit ?? ''}'.trim(),
                _ => 'Not answered yet',
              }, key: Key('usageSaved-${question.id}')),
              ListTile(
                key: Key('usageConfirmed-${question.id}'),
                title: const Text('I know this amount'),
                leading: Icon(
                  _choices[question.id] == 'confirmed'
                      ? Icons.radio_button_checked
                      : Icons.radio_button_unchecked,
                ),
                onTap: _busy
                    ? null
                    : () => setState(() {
                        _choices[question.id] = 'confirmed';
                        _changed();
                      }),
              ),
              if (_choices[question.id] == 'confirmed')
                TextField(
                  key: Key('usageValue-${question.id}'),
                  controller: _values.putIfAbsent(question.id, () {
                    final controller = TextEditingController();
                    controller.addListener(_changed);
                    return controller;
                  }),
                  keyboardType: const TextInputType.numberWithOptions(
                    decimal: true,
                  ),
                  decoration: InputDecoration(
                    labelText: question.unit ?? 'Amount',
                    hintText: '0',
                  ),
                ),
              ListTile(
                key: Key('usageUnknown-${question.id}'),
                title: const Text('I do not know'),
                leading: Icon(
                  _choices[question.id] == 'unknown'
                      ? Icons.radio_button_checked
                      : Icons.radio_button_unchecked,
                ),
                onTap: _busy
                    ? null
                    : () => setState(() {
                        _choices[question.id] = 'unknown';
                        _changed();
                      }),
              ),
              if (question.optional && !_saved.containsKey(question.id))
                ListTile(
                  title: const Text('Leave unanswered'),
                  leading: Icon(
                    _choices[question.id] == null
                        ? Icons.radio_button_checked
                        : Icons.radio_button_unchecked,
                  ),
                  onTap: _busy
                      ? null
                      : () => setState(() {
                          _choices.remove(question.id);
                          _changed();
                        }),
                ),
            ],
          ],
          const SizedBox(height: 20),
          if (_questions != null)
            FilledButton(
              key: const Key('saveUsageAnswers'),
              onPressed: _busy ? null : _submit,
              child: Text(_questions!.isEmpty ? 'Done' : 'Save answers'),
            ),
          if (_questions != null && _questions!.isNotEmpty)
            TextButton(
              onPressed: _busy ? null : () => Navigator.of(context).pop(),
              child: const Text('Answer later'),
            ),
          if (_questions != null)
            TextButton(
              onPressed: _busy ? null : _load,
              child: const Text('Refresh questions'),
            ),
        ],
      ),
    ),
  );
}
