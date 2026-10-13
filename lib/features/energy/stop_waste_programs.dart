import 'dart:async';

import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../core/cloud_api/cloud_api_client.dart';
import '../../core/cloud_api/cloud_home.dart';
import '../../core/cloud_api/cloud_programs.dart';

class StopWastePrograms extends StatefulWidget {
  const StopWastePrograms({
    super.key,
    required this.api,
    required this.home,
    this.now,
  });

  final CloudApiClient api;
  final CloudHome home;
  final DateTime Function()? now;

  @override
  State<StopWastePrograms> createState() => _StopWasteProgramsState();
}

class _StopWasteProgramsState extends State<StopWastePrograms> {
  List<CloudProgram> _programs = const [];
  int _generation = 0;
  Timer? _expiryTimer;

  void _scheduleExpiry() {
    _expiryTimer?.cancel();
    final now = widget.now?.call() ?? DateTime.now();
    final upcoming =
        _programs
            .where((program) => program.isCurrentAt(now))
            .map((program) => program.displayExpiresAt.difference(now))
            .where((remaining) => !remaining.isNegative)
            .toList()
          ..sort();
    if (upcoming.isEmpty) return;
    final delay = upcoming.first;
    _expiryTimer = Timer(
      delay > const Duration(days: 1) ? const Duration(days: 1) : delay,
      () {
        if (!mounted) return;
        setState(() {});
        _scheduleExpiry();
      },
    );
  }

  @override
  void dispose() {
    _expiryTimer?.cancel();
    super.dispose();
  }

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void didUpdateWidget(covariant StopWastePrograms oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.api != widget.api || oldWidget.home.id != widget.home.id) {
      _programs = const [];
      _expiryTimer?.cancel();
      _load();
    } else if (oldWidget.now != widget.now) {
      _scheduleExpiry();
    }
  }

  Future<void> _load() async {
    final generation = ++_generation;
    try {
      final page = await widget.api.homePrograms(widget.home.id);
      if (!mounted || generation != _generation) return;
      setState(() => _programs = page.programs);
      _scheduleExpiry();
    } catch (_) {
      if (mounted && generation == _generation) {
        setState(() => _programs = const []);
      }
    }
  }

  @override
  Widget build(BuildContext context) => Column(
    key: const Key('stopWastePrograms'),
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      Text('Programs', style: Theme.of(context).textTheme.titleLarge),
      for (final program in _programs.where(
        (program) => program.isCurrentAt(widget.now?.call() ?? DateTime.now()),
      )) ...[
        const SizedBox(height: 8),
        ProgramOfferCard(
          key: Key('stopWasteProgram-${program.id}'),
          label: switch (program.administratorKind) {
            'federal' => 'Federal',
            'manufacturer' => 'Manufacturers',
            _ => 'Local',
          },
          title: program.title,
          benefit: program.benefitDisplay,
          sourceName: program.administratorName,
          sourceUrl: program.sourceUrl,
        ),
      ],
    ],
  );
}

class ProgramOfferCard extends StatelessWidget {
  const ProgramOfferCard({
    super.key,
    required this.label,
    required this.title,
    required this.benefit,
    required this.sourceName,
    required this.sourceUrl,
  });

  final String label;
  final String title;
  final String benefit;
  final String sourceName;
  final Uri sourceUrl;

  @override
  Widget build(BuildContext context) => Card(
    child: InkWell(
      onTap: () => launchUrl(sourceUrl, mode: LaunchMode.externalApplication),
      borderRadius: BorderRadius.circular(22),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(label, style: Theme.of(context).textTheme.labelMedium),
            const SizedBox(height: 4),
            Text(title, style: Theme.of(context).textTheme.titleMedium),
            const SizedBox(height: 4),
            Text(benefit),
            const SizedBox(height: 8),
            Text(sourceName),
            Text(
              sourceUrl.toString(),
              style: Theme.of(context).textTheme.bodySmall?.copyWith(
                color: Theme.of(context).colorScheme.primary,
                decoration: TextDecoration.underline,
              ),
              overflow: TextOverflow.ellipsis,
              maxLines: 1,
            ),
          ],
        ),
      ),
    ),
  );
}
