import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../core/cloud_api/cloud_api_client.dart';
import '../../core/cloud_api/cloud_home.dart';
import '../../core/cloud_api/cloud_programs.dart';

class StopWastePrograms extends StatefulWidget {
  const StopWastePrograms({super.key, required this.api, required this.home});

  final CloudApiClient api;
  final CloudHome home;

  @override
  State<StopWastePrograms> createState() => _StopWasteProgramsState();
}

class _StopWasteProgramsState extends State<StopWastePrograms> {
  List<CloudProgram> _programs = const [];
  int _generation = 0;

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
      _load();
    }
  }

  Future<void> _load() async {
    final generation = ++_generation;
    try {
      final appliances = await widget.api.appliances(widget.home.id);
      if (!mounted || generation != _generation) return;
      final ids = appliances.map((item) => item.id).toSet();
      final pages = await Future.wait(
        appliances.map((item) async {
          try {
            return await widget.api.programs(widget.home.id, item.id, ids);
          } catch (_) {
            return null;
          }
        }),
      );
      if (!mounted || generation != _generation) return;
      final now = DateTime.now();
      final byId = <String, CloudProgram>{};
      for (final page in pages) {
        if (page == null) continue;
        for (final program in page.programs) {
          if (program.availabilityStatus != 'open' ||
              !program.reviewExpiresAt.isAfter(now)) {
            continue;
          }
          byId.putIfAbsent(program.id.toLowerCase(), () => program);
        }
      }
      setState(() => _programs = byId.values.toList());
    } catch (_) {
      if (mounted && generation == _generation) {
        setState(() => _programs = const []);
      }
    }
  }

  String _label(String kind) => switch (kind) {
    'federal' => 'Federal',
    'manufacturer' => 'Manufacturers',
    _ => 'Local',
  };

  @override
  Widget build(BuildContext context) => Column(
    key: const Key('stopWastePrograms'),
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      Text('Programs', style: Theme.of(context).textTheme.titleLarge),
      for (final program in _programs) ...[
        const SizedBox(height: 8),
        Card(
          key: Key('stopWasteProgram-${program.id}'),
          child: InkWell(
            onTap: () => launchUrl(
              program.sourceUrl,
              mode: LaunchMode.externalApplication,
            ),
            borderRadius: BorderRadius.circular(22),
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    _label(program.administratorKind),
                    style: Theme.of(context).textTheme.labelMedium,
                  ),
                  const SizedBox(height: 4),
                  Text(
                    program.title,
                    style: Theme.of(context).textTheme.titleMedium,
                  ),
                  const SizedBox(height: 4),
                  Text(program.benefitDisplay),
                  const SizedBox(height: 8),
                  Text(program.administratorName),
                  Text(
                    program.sourceUrl.toString(),
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
        ),
      ],
    ],
  );
}
