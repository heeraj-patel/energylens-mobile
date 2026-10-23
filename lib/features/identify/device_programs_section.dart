import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../core/cloud_api/cloud_api_client.dart';
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

/// Device detail: current programs and rebates for one appliance. Loads on
/// its own so a failure here never affects the usage questions.
class DeviceProgramsSection extends StatefulWidget {
  const DeviceProgramsSection({
    super.key,
    required this.api,
    required this.homeId,
    required this.applianceId,
    required this.ownedApplianceIds,
    this.now,
    Future<void> Function(Uri url)? openUrl,
  }) : openUrl = openUrl ?? _launchExternal;

  final CloudApiClient api;
  final String homeId;
  final String applianceId;
  final Set<String> ownedApplianceIds;
  final DateTime Function()? now;
  final Future<void> Function(Uri url) openUrl;

  @override
  State<DeviceProgramsSection> createState() => DeviceProgramsSectionState();
}

class DeviceProgramsSectionState extends State<DeviceProgramsSection> {
  List<CloudProgram>? _programs;
  bool _failed = false;
  bool _expanded = false;
  int _generation = 0;

  @override
  void initState() {
    super.initState();
    reload();
  }

  Future<void> reload() async {
    final generation = ++_generation;
    try {
      final page = await widget.api.programs(
        widget.homeId,
        widget.applianceId,
        widget.ownedApplianceIds,
      );
      if (!mounted || generation != _generation) return;
      final now = (widget.now ?? DateTime.now)();
      setState(() {
        _programs = [
          for (final program in page.programs)
            if (program.isCurrentAt(now)) program,
        ];
        _failed = false;
      });
    } catch (_) {
      if (!mounted || generation != _generation) return;
      setState(() => _failed = true);
    }
  }

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
    final programs = _programs;
    final children = <Widget>[
      const Text(programsHeading, style: UsageQuestionStyle.minorHeading),
    ];
    if (programs != null && !_failed) {
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
    if (_failed) {
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
    } else if (programs == null) {
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
