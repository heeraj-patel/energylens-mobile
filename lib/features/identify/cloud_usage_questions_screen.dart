import 'dart:async';

import 'package:flutter/material.dart';

import '../../core/backend_error.dart';
import '../../core/cloud_api/cloud_api_client.dart';
import '../../core/cloud_api/cloud_appliance_facts.dart';
import '../../core/cloud_api/cloud_home.dart' show newCloudIdempotencyKey;
import 'device_programs_section.dart';
import 'usage_questions_panel.dart';

const refreshEstimateLabel = 'Refresh estimate';
const refreshAcceptedMessage =
    'Checking for newer energy data. This can take a few minutes.';
const refreshRateLimitedMessage =
    'You refreshed this device recently. Try again later.';

/// Device detail: the appliance's usage questions and the estimate refresh.
class CloudUsageQuestionsScreen extends StatefulWidget {
  const CloudUsageQuestionsScreen({
    super.key,
    required this.homeId,
    required this.applianceId,
    required this.applianceName,
    required this.api,
    this.ownedApplianceIds,
    this.programsNow,
    this.openProgramUrl,
  });

  final String homeId;
  final String applianceId;
  final String applianceName;
  final CloudApiClient api;
  final Set<String>? ownedApplianceIds;
  final DateTime Function()? programsNow;
  final Future<void> Function(Uri url)? openProgramUrl;

  @override
  State<CloudUsageQuestionsScreen> createState() =>
      _CloudUsageQuestionsScreenState();
}

class _CloudUsageQuestionsScreenState extends State<CloudUsageQuestionsScreen> {
  final _panel = GlobalKey<UsageQuestionsPanelState>();
  CloudApplianceFacts? _facts;
  bool _factsFailed = false;
  int _factsGeneration = 0;
  Timer? _cooldown;
  String? _message;
  bool _messageIsError = false;
  bool _refreshing = false;
  bool _coolingDown = false;
  bool _noQuestions = false;

  @override
  void initState() {
    super.initState();
    if (widget.ownedApplianceIds != null) _loadFacts();
  }

  Future<void> _loadFacts() async {
    final generation = ++_factsGeneration;
    try {
      final facts = await widget.api.applianceFacts(
        widget.homeId,
        widget.applianceId,
      );
      if (!mounted || generation != _factsGeneration) return;
      setState(() {
        _facts = facts;
        _factsFailed = false;
      });
    } catch (_) {
      if (!mounted || generation != _factsGeneration) return;
      setState(() => _factsFailed = true);
    }
  }

  Future<void> _refresh() async {
    if (_refreshing || _coolingDown) return;
    setState(() {
      _refreshing = true;
      _message = null;
    });
    try {
      await widget.api.refreshEnergyResolution(
        widget.homeId,
        widget.applianceId,
        idempotencyKey: newCloudIdempotencyKey(),
      );
      if (!mounted) return;
      setState(() {
        _message = refreshAcceptedMessage;
        _messageIsError = false;
      });
    } on CloudApiException catch (error) {
      if (!mounted) return;
      if (error.statusCode == 429 && error.code == 'refresh_rate_limited') {
        final wait = error.retryAfterSeconds;
        setState(() {
          _message = refreshRateLimitedMessage;
          _messageIsError = false;
          if (wait != null && wait > 0) _coolingDown = true;
        });
        if (wait != null && wait > 0) {
          _cooldown?.cancel();
          _cooldown = Timer(Duration(seconds: wait), () {
            if (mounted) setState(() => _coolingDown = false);
          });
        }
      } else {
        setState(() {
          _message = internalErrorMessage;
          _messageIsError = true;
        });
      }
    } catch (_) {
      if (mounted) {
        setState(() {
          _message = internalErrorMessage;
          _messageIsError = true;
        });
      }
    } finally {
      if (mounted) setState(() => _refreshing = false);
    }
  }

  @override
  void dispose() {
    _cooldown?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    backgroundColor: UsageQuestionStyle.surface,
    appBar: AppBar(
      backgroundColor: UsageQuestionStyle.surfaceLowest,
      foregroundColor: UsageQuestionStyle.primary,
      surfaceTintColor: Colors.transparent,
      elevation: 0,
      shape: const Border(
        bottom: BorderSide(color: UsageQuestionStyle.outlineVariant),
      ),
      title: Text(
        widget.applianceName,
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
        style: const TextStyle(
          fontFamily: 'Manrope',
          fontSize: 20,
          fontWeight: FontWeight.w700,
          height: 26 / 20,
          color: UsageQuestionStyle.onSurface,
        ),
      ),
    ),
    body: SafeArea(
      child: Align(
        alignment: Alignment.topCenter,
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 680),
          child: RefreshIndicator(
            color: UsageQuestionStyle.primary,
            onRefresh: () async {
              await Future.wait([
                if (_panel.currentState != null) _panel.currentState!.reload(),
                if (widget.ownedApplianceIds != null) _loadFacts(),
              ]);
            },
            child: ListView(
              physics: const AlwaysScrollableScrollPhysics(),
              padding: const EdgeInsets.all(16),
              children: [
                Offstage(
                  offstage: _noQuestions,
                  child: DecoratedBox(
                    decoration: BoxDecoration(
                      color: UsageQuestionStyle.surfaceLowest,
                      borderRadius: BorderRadius.circular(8),
                      border: Border.all(
                        color: UsageQuestionStyle.outlineVariant,
                      ),
                    ),
                    child: Padding(
                      padding: const EdgeInsets.all(16),
                      child: UsageQuestionsPanel(
                        key: _panel,
                        api: widget.api,
                        homeId: widget.homeId,
                        applianceId: widget.applianceId,
                        onLoaded: (count) {
                          if (!mounted) return;
                          setState(() => _noQuestions = count == 0);
                        },
                      ),
                    ),
                  ),
                ),
                if (!_noQuestions) const SizedBox(height: 16),
                if (widget.ownedApplianceIds != null) ...[
                  DeviceProgramsSection(
                    programs: _facts?.programs,
                    failed: _factsFailed,
                    now: widget.programsNow,
                    openUrl: widget.openProgramUrl,
                  ),
                  const SizedBox(height: 16),
                ],
                SizedBox(
                  height: 48,
                  child: FilledButton.icon(
                    key: const Key('refreshEstimate'),
                    onPressed: _refreshing || _coolingDown ? null : _refresh,
                    style: FilledButton.styleFrom(
                      backgroundColor: UsageQuestionStyle.primaryContainer,
                      foregroundColor: UsageQuestionStyle.onPrimaryContainer,
                      disabledBackgroundColor: UsageQuestionStyle.surfaceLow,
                      disabledForegroundColor:
                          UsageQuestionStyle.onSurfaceVariant,
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(8),
                      ),
                      textStyle: UsageQuestionStyle.label,
                    ),
                    icon: _refreshing
                        ? const SizedBox(
                            width: 16,
                            height: 16,
                            child: CircularProgressIndicator(strokeWidth: 2),
                          )
                        : const Icon(Icons.refresh, size: 18),
                    label: const Text(refreshEstimateLabel),
                  ),
                ),
                if (_message != null)
                  Padding(
                    padding: const EdgeInsets.only(top: 12),
                    child: Semantics(
                      liveRegion: true,
                      child: Text(
                        _message!,
                        key: const Key('refreshMessage'),
                        style: UsageQuestionStyle.body.copyWith(
                          color: _messageIsError
                              ? UsageQuestionStyle.error
                              : UsageQuestionStyle.onSurfaceVariant,
                        ),
                      ),
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
