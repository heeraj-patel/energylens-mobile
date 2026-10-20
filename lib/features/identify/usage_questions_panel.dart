import 'package:flutter/material.dart';

import '../../core/backend_error.dart';
import '../../core/cloud_api/cloud_api_client.dart';
import '../../core/cloud_api/cloud_home.dart' show newCloudIdempotencyKey;
import '../../core/cloud_api/cloud_question.dart';

/// Glacier Energy tokens (DESIGN.md) for the native question surfaces.
abstract final class UsageQuestionStyle {
  static const primary = Color(0xFF006686);
  static const primaryContainer = Color(0xFF7DD3FC);
  static const onPrimaryContainer = Color(0xFF005B78);
  static const secondaryContainer = Color(0xFFBAE6FF);
  static const surface = Color(0xFFF9F9FF);
  static const surfaceLowest = Color(0xFFFFFFFF);
  static const surfaceLow = Color(0xFFF1F3FF);
  static const onSurface = Color(0xFF111B2F);
  static const onSurfaceVariant = Color(0xFF3F484E);
  static const outlineVariant = Color(0xFFBEC8CE);
  static const error = Color(0xFFBA1A1A);

  static const minorHeading = TextStyle(
    fontFamily: 'Manrope',
    fontSize: 15,
    fontWeight: FontWeight.w700,
    height: 1.3,
    color: onSurface,
  );
  static const body = TextStyle(
    fontFamily: 'Source Sans 3',
    fontSize: 14,
    height: 1.5,
    color: onSurfaceVariant,
  );
  static const label = TextStyle(
    fontFamily: 'Source Sans 3',
    fontSize: 14,
    fontWeight: FontWeight.w600,
    height: 20 / 14,
    color: onSurface,
  );
}

const notSureLabel = 'Not sure';

// Option key -> approved label (Q-C3, Q-C5, Q-C7, Q-C9, Q-C13), in display order.
const _optionLabels = <String, String>{
  'lt_1h': 'Less than 1 hour',
  '1_3h': '1-3 hours',
  '3_5h': '3-5 hours',
  '5_8h': '5-8 hours',
  'gt_8h': 'More than 8 hours',
  'all_year': 'All year',
  '6_months': 'About 6 months',
  '3_months': 'About 3 months',
  '1_month': 'About 1 month',
  '0_2': '0-2',
  '3_5': '3-5',
  '6_8': '6-8',
  '9_plus': '9 or more',
  '2016_or_newer': '2016 or newer',
  '2008_2015': '2008-2015',
  '2007_or_older': '2007 or older',
  'yes': 'Yes',
  'no': 'No',
};

/// Questions the app can show: choice questions whose every option has an
/// approved label.
List<CloudQuestion> displayableUsageQuestions(List<CloudQuestion> questions) =>
    [
      for (final question in questions)
        if (question.answerKind == 'choice' &&
            question.options != null &&
            question.options!.every((o) => _optionLabels.containsKey(o.key)))
          question,
    ];

List<CloudQuestionOption> _ordered(CloudQuestion question) {
  final keys = _optionLabels.keys.toList();
  return [...question.options!]
    ..sort((a, b) => keys.indexOf(a.key).compareTo(keys.indexOf(b.key)));
}

const _unsure = '\u0000unsure';

/// Loads one appliance's onboarding questions and saves each answer as soon as
/// an option is tapped. An unanswered question stays unanswered.
class UsageQuestionsPanel extends StatefulWidget {
  const UsageQuestionsPanel({
    super.key,
    required this.api,
    required this.homeId,
    required this.applianceId,
    this.onLoaded,
    this.onAllAnswered,
  });

  final CloudApiClient api;
  final String homeId;
  final String applianceId;

  /// Called with the number of questions shown after each load.
  final ValueChanged<int>? onLoaded;

  /// Called once every shown question has an answer.
  final VoidCallback? onAllAnswered;

  @override
  State<UsageQuestionsPanel> createState() => UsageQuestionsPanelState();
}

class UsageQuestionsPanelState extends State<UsageQuestionsPanel> {
  List<CloudQuestion>? _questions;
  final Map<String, String> _selected = {};
  String? _error;
  bool _busy = false;

  @override
  void initState() {
    super.initState();
    reload();
  }

  Future<void> reload() async {
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      final loaded = await widget.api.onboardingQuestions(
        widget.homeId,
        widget.applianceId,
      );
      final answers = await widget.api.currentQuestionAnswers(
        widget.homeId,
        widget.applianceId,
      );
      if (!mounted) return;
      final questions = displayableUsageQuestions(loaded);
      _selected.clear();
      for (final question in questions) {
        for (final answer in answers) {
          if (!answer.matches(question)) continue;
          if (answer.status == 'unknown') {
            _selected[question.id] = _unsure;
          } else {
            for (final option in question.options!) {
              if (option.value == answer.value) {
                _selected[question.id] = option.key;
              }
            }
          }
        }
      }
      setState(() => _questions = questions);
      widget.onLoaded?.call(questions.length);
    } catch (_) {
      if (mounted) setState(() => _error = internalErrorMessage);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _answer(CloudQuestion question, String choice) async {
    if (_busy || _selected[question.id] == choice) return;
    final value = choice == _unsure
        ? null
        : question.options!.firstWhere((o) => o.key == choice).value;
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      await widget.api.submitQuestionAnswers(widget.homeId, [
        CloudAnswerCreate(
          question: question,
          value: value,
          confirmedAt: value == null ? null : DateTime.now().toUtc(),
        ),
      ], idempotencyKey: newCloudIdempotencyKey());
      if (!mounted) return;
      setState(() => _selected[question.id] = choice);
      if (_questions!.every((q) => _selected.containsKey(q.id))) {
        widget.onAllAnswered?.call();
      }
    } catch (_) {
      if (mounted) setState(() => _error = internalErrorMessage);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final questions = _questions;
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        if (_busy)
          const LinearProgressIndicator(
            key: Key('usageQuestionsBusy'),
            minHeight: 2,
            color: UsageQuestionStyle.primary,
            backgroundColor: UsageQuestionStyle.surfaceLow,
          ),
        if (_error != null)
          Padding(
            padding: const EdgeInsets.only(top: 8),
            child: Semantics(
              liveRegion: true,
              child: Text(
                _error!,
                key: const Key('usageQuestionError'),
                style: UsageQuestionStyle.body.copyWith(
                  color: UsageQuestionStyle.error,
                ),
              ),
            ),
          ),
        if (questions != null)
          for (var i = 0; i < questions.length; i++) ...[
            if (i > 0) const SizedBox(height: 24),
            _QuestionBlock(
              question: questions[i],
              selected: _selected[questions[i].id],
              enabled: !_busy,
              onSelect: (choice) => _answer(questions[i], choice),
            ),
          ],
      ],
    );
  }
}

class _QuestionBlock extends StatelessWidget {
  const _QuestionBlock({
    required this.question,
    required this.selected,
    required this.enabled,
    required this.onSelect,
  });

  final CloudQuestion question;
  final String? selected;
  final bool enabled;
  final ValueChanged<String> onSelect;

  @override
  Widget build(BuildContext context) => Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      Semantics(
        header: true,
        child: Text(
          question.prompt,
          key: Key('usagePrompt-${question.id}'),
          style: UsageQuestionStyle.minorHeading,
        ),
      ),
      const SizedBox(height: 8),
      Wrap(
        spacing: 8,
        runSpacing: 8,
        children: [
          for (final option in _ordered(question))
            _OptionPill(
              key: Key('usageOption-${question.id}-${option.key}'),
              label: _optionLabels[option.key]!,
              selected: selected == option.key,
              onTap: enabled ? () => onSelect(option.key) : null,
            ),
          _OptionPill(
            key: Key('usageOption-${question.id}-unsure'),
            label: notSureLabel,
            selected: selected == _unsure,
            onTap: enabled ? () => onSelect(_unsure) : null,
          ),
        ],
      ),
    ],
  );
}

class _OptionPill extends StatelessWidget {
  const _OptionPill({
    super.key,
    required this.label,
    required this.selected,
    required this.onTap,
  });

  final String label;
  final bool selected;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) => Semantics(
    button: true,
    selected: selected,
    enabled: onTap != null,
    label: label,
    excludeSemantics: true,
    child: Material(
      color: selected
          ? UsageQuestionStyle.secondaryContainer
          : UsageQuestionStyle.surfaceLow,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(8),
        side: BorderSide(
          color: selected
              ? UsageQuestionStyle.primary
              : UsageQuestionStyle.outlineVariant,
          width: selected ? 1.5 : 1,
        ),
      ),
      child: InkWell(
        borderRadius: BorderRadius.circular(8),
        onTap: onTap,
        child: ConstrainedBox(
          constraints: const BoxConstraints(minHeight: 44),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                if (selected) ...[
                  const Icon(
                    Icons.check,
                    size: 16,
                    color: UsageQuestionStyle.onPrimaryContainer,
                  ),
                  const SizedBox(width: 4),
                ],
                Text(
                  label,
                  style: UsageQuestionStyle.label.copyWith(
                    color: selected
                        ? UsageQuestionStyle.onPrimaryContainer
                        : UsageQuestionStyle.onSurface,
                    fontWeight: selected ? FontWeight.w700 : FontWeight.w600,
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    ),
  );
}
