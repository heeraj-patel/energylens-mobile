import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../core/cloud_api/cloud_appliance_facts.dart';
import '../../core/cloud_api/cloud_programs.dart';
import 'usage_questions_panel.dart';

const programsHeading = 'Programs and rebates';
const programAmountFallback = 'Amount varies';
const programsEmptyMessage =
    'No programs found for this device in your area yet.';
const programsErrorMessage = "Couldn't load programs. Pull down to try again.";
String programsMoreLabel(int count) => 'See all $count programs';

const _collapsedCount = 3;
const _months = [
  'Jan',
  'Feb',
  'Mar',
  'Apr',
  'May',
  'Jun',
  'Jul',
  'Aug',
  'Sep',
  'Oct',
  'Nov',
  'Dec',
];

Future<void> _launchExternal(Uri url) =>
    launchUrl(url, mode: LaunchMode.externalApplication);

/// Device detail: current programs and rebates for one appliance, shown from
/// the facts read. A failure here never affects the usage questions.
class DeviceProgramsSection extends StatefulWidget {
  const DeviceProgramsSection({
    super.key,
    required this.programs,
    this.failed = false,
    this.now,
    Future<void> Function(Uri url)? openUrl,
  }) : openUrl = openUrl ?? _launchExternal;

  /// Null while the facts read is loading.
  final CloudFactsSection<CloudFactsPrograms>? programs;
  final bool failed;
  final DateTime Function()? now;
  final Future<void> Function(Uri url) openUrl;

  @override
  State<DeviceProgramsSection> createState() => DeviceProgramsSectionState();
}

class DeviceProgramsSectionState extends State<DeviceProgramsSection> {
  bool _expanded = false;

  String _date(DateTime value) {
    final local = value.toLocal();
    return '${_months[local.month - 1]} ${local.day}, ${local.year}';
  }

  Widget _row(CloudProgram program) {
    final amount = program.benefitDisplay.trim().isEmpty
        ? programAmountFallback
        : program.benefitDisplay;
    return Padding(
      padding: const EdgeInsets.only(top: 12),
      child: InkWell(
        key: Key('program-${program.id}'),
        onTap: () => widget.openUrl(program.sourceUrl),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              program.title,
              style: UsageQuestionStyle.label.copyWith(
                color: UsageQuestionStyle.primary,
              ),
            ),
            Text(amount, style: UsageQuestionStyle.body),
            Text(program.administratorName, style: UsageQuestionStyle.body),
            Text(
              _date(program.displayExpiresAt),
              style: UsageQuestionStyle.body,
            ),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final section = widget.programs;
    final failed = widget.failed || (section?.isFailed ?? false);
    final now = (widget.now ?? DateTime.now)();
    final programs = section == null || failed
        ? null
        : [
            for (final program in section.value?.items ?? <CloudProgram>[])
              if (program.isCurrentAt(now)) program,
          ];
    final children = <Widget>[
      const Text(programsHeading, style: UsageQuestionStyle.minorHeading),
    ];
    if (programs != null) {
      if (programs.isEmpty) {
        children.add(
          const Padding(
            padding: EdgeInsets.only(top: 12),
            child: Text(programsEmptyMessage, style: UsageQuestionStyle.body),
          ),
        );
      } else {
        final shown = _expanded || programs.length <= _collapsedCount
            ? programs
            : programs.take(_collapsedCount).toList();
        children.addAll(shown.map(_row));
        if (shown.length < programs.length) {
          children.add(
            Align(
              alignment: Alignment.centerLeft,
              child: TextButton(
                key: const Key('programsSeeAll'),
                onPressed: () => setState(() => _expanded = true),
                child: Text(
                  programsMoreLabel(programs.length),
                  style: UsageQuestionStyle.label.copyWith(
                    color: UsageQuestionStyle.primary,
                  ),
                ),
              ),
            ),
          );
        }
      }
    }
    if (failed) {
      children.add(
        const Padding(
          padding: EdgeInsets.only(top: 12),
          child: Text(
            programsErrorMessage,
            style: TextStyle(
              fontFamily: 'Source Sans 3',
              fontSize: 14,
              height: 1.5,
              color: UsageQuestionStyle.error,
            ),
          ),
        ),
      );
    } else if (section == null) {
      children.add(
        const Padding(
          padding: EdgeInsets.only(top: 12),
          child: SizedBox(
            width: 16,
            height: 16,
            child: CircularProgressIndicator(strokeWidth: 2),
          ),
        ),
      );
    }
    return DecoratedBox(
      decoration: BoxDecoration(
        color: UsageQuestionStyle.surfaceLowest,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: UsageQuestionStyle.outlineVariant),
      ),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: children,
        ),
      ),
    );
  }
}
