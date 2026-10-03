import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../core/cloud_api/cloud_api_client.dart';
import '../../core/cloud_api/cloud_appliance.dart';
import '../../core/cloud_api/cloud_home.dart';
import '../../core/cloud_api/cloud_programs.dart';

class CloudProgramsScreen extends StatefulWidget {
  const CloudProgramsScreen({super.key, required this.api, required this.home});
  final CloudApiClient api;
  final CloudHome home;

  @override
  State<CloudProgramsScreen> createState() => _CloudProgramsScreenState();
}

class _CloudProgramsScreenState extends State<CloudProgramsScreen> {
  List<CloudAppliance>? _appliances;
  String? _selectedId;
  CloudProgramPage? _page;
  String? _error;
  bool _loading = true;
  int _generation = 0;

  @override
  void initState() {
    super.initState();
    _loadInventory();
  }

  Future<void> _loadInventory() async {
    final generation = ++_generation;
    setState(() {
      _loading = true;
      _error = null;
      _page = null;
    });
    try {
      final appliances = await widget.api.appliances(widget.home.id);
      if (mounted && generation == _generation) {
        setState(() {
          _appliances = appliances;
          if (!appliances.any((item) => item.id == _selectedId)) {
            _selectedId = null;
          }
        });
        if (_selectedId != null) {
          await _loadPrograms();
        }
      }
    } on CloudApiException catch (error) {
      if (mounted && generation == _generation) {
        setState(
          () => _error = error.statusCode == 401 || error.statusCode == 403
              ? 'Cloud sign-in is required to view programs.'
              : 'Could not load this home’s appliances. Try again.',
        );
      }
    } catch (_) {
      if (mounted && generation == _generation) {
        setState(
          () => _error = 'Could not load this home’s appliances. Try again.',
        );
      }
    } finally {
      if (mounted && generation == _generation) {
        setState(() => _loading = false);
      }
    }
  }

  Future<void> _loadPrograms() async {
    final selectedId = _selectedId;
    final appliances = _appliances;
    if (selectedId == null || appliances == null) return;
    final generation = ++_generation;
    setState(() {
      _loading = true;
      _error = null;
      _page = null;
    });
    try {
      final page = await widget.api.programs(
        widget.home.id,
        selectedId,
        appliances.map((item) => item.id).toSet(),
      );
      if (mounted && generation == _generation) setState(() => _page = page);
    } on CloudApiException catch (error) {
      if (mounted && generation == _generation) {
        setState(
          () => _error = error.statusCode == 401 || error.statusCode == 403
              ? 'Cloud sign-in is required to view programs.'
              : 'Could not load programs for this appliance. Try again.',
        );
      }
    } catch (_) {
      if (mounted && generation == _generation) {
        setState(
          () =>
              _error = 'Could not load programs for this appliance. Try again.',
        );
      }
    } finally {
      if (mounted && generation == _generation) {
        setState(() => _loading = false);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final appliances = _appliances;
    return Scaffold(
      appBar: AppBar(title: const Text('Reviewed programs')),
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
                const Text(
                  'Explore source-cited program candidates for a saved appliance. Discovery covers only the sources identified for this ZIP; utility, local, county, state, federal, Tribal and manufacturer programs may be missing. A location or device match does not confirm eligibility, available benefits, or savings.',
                ),
                const SizedBox(height: 20),
                if (appliances != null && appliances.isNotEmpty)
                  DropdownButtonFormField<String>(
                    key: const Key('programAppliance'),
                    initialValue: _selectedId,
                    decoration: const InputDecoration(
                      labelText: 'Saved appliance',
                    ),
                    items: appliances
                        .map(
                          (item) => DropdownMenuItem(
                            value: item.id,
                            child: Text(item.name),
                          ),
                        )
                        .toList(),
                    onChanged: (value) {
                      setState(() => _selectedId = value);
                      _loadPrograms();
                    },
                  ),
                if (appliances != null && appliances.isEmpty)
                  const Padding(
                    padding: EdgeInsets.only(top: 16),
                    child: Text(
                      'Add an appliance to this home to check reviewed programs.',
                    ),
                  ),
                if (appliances != null &&
                    appliances.isNotEmpty &&
                    _selectedId == null)
                  const Padding(
                    padding: EdgeInsets.only(top: 16),
                    child: Text('Choose a saved appliance to check programs.'),
                  ),
                if (_loading)
                  const LinearProgressIndicator(key: Key('programsLoading')),
                if (_error != null) ...[
                  const SizedBox(height: 16),
                  Text(_error!, key: const Key('programsError')),
                  TextButton(
                    onPressed: appliances == null
                        ? _loadInventory
                        : _loadPrograms,
                    child: const Text('Retry programs'),
                  ),
                ],
                if (_page case final page?) ...[
                  const SizedBox(height: 20),
                  if (page.locationRequired)
                    const Text(
                      'A home location is needed before programs can be checked. Add the location for this home and try again.',
                    ),
                  if (!page.locationRequired && page.programs.isEmpty)
                    const Text(
                      'No matching programs found in the reviewed sources available here. Other sources may not have been checked; eligibility remains unknown.',
                    ),
                  if (!page.locationRequired) ...[
                    const SizedBox(height: 16),
                    Text(
                      'Source discovery for this ZIP',
                      style: Theme.of(context).textTheme.titleMedium,
                    ),
                    const SizedBox(height: 6),
                    if (page.coverage case final coverage?) ...[
                      Text(
                        'Latest matching run: ${coverage.state} · started ${coverage.startedAt.toUtc().toIso8601String()}',
                      ),
                      if (coverage.limitations.isNotEmpty)
                        const Text(
                          'This run has limitations. Some sources could not be identified or checked.',
                        ),
                      if (coverage.scopes.isEmpty)
                        const Text(
                          'No source scopes were identified in this run.',
                        ),
                      for (final scope in coverage.scopes)
                        Text(
                          '${scope.name} (${scope.kind.replaceAll('_', ' ')}) · ${scope.status == 'checked'
                              ? 'source checked'
                              : scope.status == 'failed'
                              ? 'check failed'
                              : 'not checked'}',
                        ),
                    ] else
                      const Text(
                        'No source discovery run is available for this ZIP and appliance category.',
                      ),
                    const SizedBox(height: 6),
                    const Text(
                      'A checked source means only that a source check ran. ZIP candidates do not confirm your utility provider or service at your address; other sources may be missing.',
                    ),
                  ],
                  for (final program in page.programs)
                    Card(
                      key: Key('program-${program.id}'),
                      child: Padding(
                        padding: const EdgeInsets.all(16),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              'Eligibility unknown',
                              style: Theme.of(context).textTheme.labelLarge,
                            ),
                            const SizedBox(height: 8),
                            Text(
                              program.title,
                              style: Theme.of(context).textTheme.titleMedium,
                            ),
                            const SizedBox(height: 4),
                            Text(
                              '${program.administratorName} · ${program.benefitKind.replaceAll('_', ' ')}',
                            ),
                            const SizedBox(height: 8),
                            Text(
                              'Still to confirm: ${program.reasons.map((reason) => reason.replaceAll('_', ' ')).join(', ')}.',
                            ),
                            TextButton.icon(
                              onPressed: () => launchUrl(
                                program.sourceUrl,
                                mode: LaunchMode.externalApplication,
                              ),
                              icon: const Icon(Icons.open_in_new),
                              label: const Text('Review official source'),
                            ),
                            Text(
                              'Source fingerprint ${program.sourceSha256.substring(0, 12)} · Review expires ${program.reviewExpiresAt.toUtc().toIso8601String()}',
                              style: Theme.of(context).textTheme.bodySmall,
                            ),
                          ],
                        ),
                      ),
                    ),
                  const SizedBox(height: 12),
                  Text(
                    'Catalog results loaded ${page.asOf.toUtc().toIso8601String()}',
                    style: Theme.of(context).textTheme.bodySmall,
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
