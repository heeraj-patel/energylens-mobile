import 'package:flutter/material.dart';

import 'discovery_api.dart';
import 'plug_connection_status.dart';
import 'discovery_credentials.dart';
import 'hub_pairing_screen.dart';
import '../identify/appliance_onboarding_screen.dart';
import 'device_energy_detail_screen.dart';

/// Local discovery, adoption, and readback from the pilot hub.
class DiscoveryScreen extends StatefulWidget {
  const DiscoveryScreen({
    super.key,
    this.api = const DiscoveryApi(),
    this.credentials = const DiscoveryCredentials(),
    this.autoScan = false,
  });

  final DiscoveryApi api;
  final DiscoveryCredentials credentials;
  final bool autoScan;

  @override
  State<DiscoveryScreen> createState() => _DiscoveryScreenState();
}

class _DiscoveryScreenState extends State<DiscoveryScreen> {
  final _hub = TextEditingController();
  final _token = TextEditingController();
  final _ip = TextEditingController();
  String _manualProtocol = 'kasa';
  List<DiscoveredPlug> _candidates = const [];
  List<SavedPlug> _saved = const [];
  final Map<int, EnergyEstimate> _estimates = {};
  bool _busy = false;
  bool _hubConnected = false;
  bool _paired = false;
  bool _showConnectionSettings = false;
  bool _showManualEntry = false;
  String? _pairedHubId;
  bool _searched = false;
  final Set<String> _statusChecking = {};
  String? _error;
  void _invalidateHubData() {
    if (_saved.isEmpty &&
        _estimates.isEmpty &&
        _candidates.isEmpty &&
        !_searched) {
      return;
    }
    setState(() {
      _saved = const [];
      _hubConnected = false;
      _estimates.clear();
      _candidates = const [];
      _searched = false;
      _error = null;
    });
  }

  @override
  void initState() {
    super.initState();
    _restore();
  }

  Future<void> _restore() async {
    try {
      await widget.credentials.importDebugPairingFile();
      final pairing = await widget.credentials.readPairing();
      if (pairing != null) {
        if (!mounted) return;
        setState(() {
          _paired = true;
          _pairedHubId = pairing.hubId;
          _hub.text = pairing.address;
          _token.text = pairing.token;
        });
        await widget.api.verifyStoredPairing(
          StoredHubIdentity(address: pairing.address, hubId: pairing.hubId),
        );
        await _loadSaved();
        if (widget.autoScan) await _search();
        return;
      }
      final (address, token) = await widget.credentials.read();
      if (!mounted) return;
      if (address != null) _hub.text = address;
      if (token != null) _token.text = token;
      if (address != null && token != null) {
        await _loadSaved();
        if (widget.autoScan) await _search();
      }
    } catch (error) {
      if (mounted) {
        setState(() {
          _hubConnected = false;
          _error = error is PairingException
              ? error.message
              : 'Could not restore the hub connection. Pair again or retry.';
        });
      }
    }
  }

  Future<void> _openPairing() async {
    final result = await Navigator.of(context).push<bool>(
      MaterialPageRoute(
        builder: (_) =>
            HubPairingScreen(api: widget.api, credentials: widget.credentials),
      ),
    );
    if (result == true && mounted) {
      _invalidateHubData();
      await _restore();
    }
  }

  Future<void> _loadSaved() async {
    try {
      final plugs = await widget.api.saved(
        _hub.text.trim(),
        _token.text.trim(),
      );
      if (mounted) {
        setState(() {
          _saved = plugs;
          _hubConnected = true;
          _error = null;
        });
        for (final plug in plugs) {
          final appliance = plug.connectedAppliance;
          if (appliance == null) continue;
          if (plug.connectionStatus == 'identity_changed') {
            _estimates.remove(appliance.id);
            continue;
          }
          try {
            final estimate = await widget.api.estimate(
              _hub.text.trim(),
              _token.text.trim(),
              appliance.id,
            );
            if (mounted) setState(() => _estimates[appliance.id] = estimate);
          } catch (_) {
            // The plug remains visible when the source cache is unavailable.
          }
        }
      }
    } catch (_) {
      if (mounted) {
        setState(() {
          _hubConnected = false;
          _error =
              'Could not load saved plugs from the hub. Check its connection.';
        });
      }
    }
  }

  Future<void> _refreshPlugStatus(SavedPlug plug) async {
    if (_statusChecking.contains(plug.id)) return;
    setState(() {
      _statusChecking.add(plug.id);
      _error = null;
    });
    try {
      final refreshed = await widget.api.refreshPlugStatus(
        _hub.text.trim(),
        _token.text.trim(),
        plug.id,
      );
      if (!mounted) return;
      setState(() {
        _saved = [
          for (final current in _saved)
            if (current.id == refreshed.id) refreshed else current,
        ];
        if (refreshed.connectionStatus == 'identity_changed') {
          final applianceId = refreshed.connectedAppliance?.id;
          if (applianceId != null) _estimates.remove(applianceId);
        }
      });
    } catch (_) {
      if (mounted) {
        setState(
          () => _error =
              'Could not check ${plug.name}. Check the hub connection and retry.',
        );
      }
    } finally {
      if (mounted) setState(() => _statusChecking.remove(plug.id));
    }
  }

  Future<void> _checkConnectedEnergy(SavedAppliance appliance) async {
    if (_busy) return;
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      await widget.api.lookupEnergy(
        _hub.text.trim(),
        _token.text.trim(),
        appliance.id,
      );
      final estimate = await widget.api.estimate(
        _hub.text.trim(),
        _token.text.trim(),
        appliance.id,
      );
      if (mounted) setState(() => _estimates[appliance.id] = estimate);
    } catch (error) {
      if (mounted) {
        setState(
          () => _error = error is StateError
              ? error.message
              : 'Could not check energy data.',
        );
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  void _showSource(EnergyEvidence source, EnergyEstimate estimate) {
    showModalBottomSheet<void>(
      context: context,
      builder: (context) => SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(20),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                energySourceHeading(source),
                style: Theme.of(context).textTheme.titleLarge,
              ),
              if (source.sourceKind != 'user_label')
                Text(
                  'Matched model: ${source.matchedBrand} ${source.matchedModel}',
                ),
              Text(
                source.sourceKind == 'user_label'
                    ? 'Calculated energy: ${source.annualKwh.toStringAsFixed(1)} kWh/year'
                    : 'Published energy${estimate.bulbCount != null && estimate.bulbCount! > 1 ? ' per bulb' : ''}: ${source.annualKwh.toStringAsFixed(1)} kWh/year',
              ),
              Text('Basis: ${source.usageBasis}'),
              if (source.sourceKind != 'user_label')
                Text('Dataset: ${source.datasetId}'),
              Text(
                'Source date: ${DateTime.fromMillisecondsSinceEpoch(source.retrievedAt * 1000).toLocal()}',
              ),
              Text(energyRateDescription(estimate)),
              if (estimate.rateSourceUrl case final url?) SelectableText(url),
              if (source.sourceUrl.isNotEmpty) SelectableText(source.sourceUrl),
              const SizedBox(height: 8),
              const Text(
                'Estimated energy for the connected load. No live energy measurement.',
              ),
            ],
          ),
        ),
      ),
    );
  }

  Future<void> _connectAppliance(SavedPlug plug) async {
    if (_busy) return;
    List<SavedAppliance> appliances;
    try {
      appliances = await widget.api.appliances(
        _hub.text.trim(),
        _token.text.trim(),
      );
    } catch (_) {
      if (mounted) {
        setState(() => _error = 'Could not load appliances from the hub.');
      }
      return;
    }
    if (!mounted) return;
    final choice = await showDialog<Object>(
      context: context,
      builder: (context) => SimpleDialog(
        title: const Text('Connected appliance or lamp'),
        children: [
          const Padding(
            padding: EdgeInsets.fromLTRB(24, 0, 24, 12),
            child: Text(
              'For appliance-specific readings, connect only that appliance to this plug. A shared plug measures the combined load.',
            ),
          ),
          for (final item in appliances)
            SimpleDialogOption(
              onPressed: () => Navigator.pop(context, item.id),
              child: Text('${item.name} · ${item.category}'),
            ),
          const Divider(),
          SimpleDialogOption(
            onPressed: () => Navigator.pop(context, 'manual'),
            child: const Text('Enter a new appliance'),
          ),
          SimpleDialogOption(
            onPressed: () => Navigator.pop(context, 'photo'),
            child: const Text('Identify a new appliance from photo'),
          ),
        ],
      ),
    );
    if (!mounted || choice == null) return;
    if (choice is String) {
      final attached = await Navigator.push<SavedPlug>(
        context,
        MaterialPageRoute(
          builder: (_) => ApplianceOnboardingScreen(
            method: choice,
            plugId: plug.id,
            api: widget.api,
            credentials: widget.credentials,
          ),
        ),
      );
      if (attached != null && mounted) {
        setState(
          () => _saved = [
            for (final item in _saved)
              if (item.id == attached.id) attached else item,
          ],
        );
        if (attached.connectedAppliance != null) {
          await _checkConnectedEnergy(attached.connectedAppliance!);
        }
      }
      return;
    }
    if (choice is! int) return;
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      final attached = await widget.api.attachAppliance(
        _hub.text.trim(),
        _token.text.trim(),
        plug.id,
        choice,
      );
      if (mounted) {
        setState(
          () => _saved = [
            for (final item in _saved)
              if (item.id == attached.id) attached else item,
          ],
        );
      }
    } catch (error) {
      if (mounted) {
        setState(
          () => _error = error is StateError
              ? error.message
              : 'Could not connect this appliance to the plug.',
        );
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _adopt(DiscoveredPlug plug) async {
    final name = TextEditingController(
      text: plug.alias?.isNotEmpty == true ? plug.alias : plug.model,
    );
    final room = TextEditingController();
    var acknowledged = false;
    final details = await showDialog<(String, String, bool)>(
      context: context,
      builder: (dialogContext) => StatefulBuilder(
        builder: (context, update) => AlertDialog(
          title: const Text('Save smart plug'),
          content: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                TextField(
                  controller: name,
                  decoration: const InputDecoration(labelText: 'Plug name'),
                ),
                TextField(
                  controller: room,
                  decoration: const InputDecoration(labelText: 'Room'),
                ),
                if (plug.meterStatus == 'absent')
                  CheckboxListTile(
                    value: acknowledged,
                    onChanged: (value) =>
                        update(() => acknowledged = value ?? false),
                    contentPadding: EdgeInsets.zero,
                    title: const Text(
                      'I understand this plug cannot measure energy',
                    ),
                  ),
              ],
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(dialogContext),
              child: const Text('Cancel'),
            ),
            FilledButton(
              onPressed:
                  name.text.trim().isEmpty ||
                      (plug.meterStatus == 'absent' && !acknowledged)
                  ? null
                  : () => Navigator.pop(dialogContext, (
                      name.text.trim(),
                      room.text.trim(),
                      acknowledged,
                    )),
              child: const Text('Save plug'),
            ),
          ],
        ),
      ),
    );
    name.dispose();
    room.dispose();
    if (details == null || !mounted) return;
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      final saved = await widget.api.adopt(
        _hub.text.trim(),
        _token.text.trim(),
        plug,
        details.$1,
        details.$2,
        details.$3,
      );
      if (!mounted) return;
      setState(() {
        _saved = [..._saved.where((item) => item.id != saved.id), saved];
      });
      try {
        if (!_paired) {
          await widget.credentials.save(_hub.text.trim(), _token.text.trim());
        }
      } catch (_) {
        if (mounted) {
          setState(
            () => _error = 'Plug saved on the hub. Enter the hub address and token again next time.',
          );
        }
      }
    } catch (error) {
      if (mounted) {
        setState(
          () => _error = error is StateError ? error.message : 'Could not save the plug. Check that it is still connected and try again.',
        );
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  void dispose() {
    _hub.dispose();
    _token.dispose();
    _ip.dispose();
    super.dispose();
  }

  Future<void> _search({bool manual = false}) async {
    if (_busy) return;
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      if (_token.text.trim().isEmpty) {
        throw const FormatException('Enter the hub discovery token.');
      }
      final results = manual
          ? [
              await widget.api.probe(
                _hub.text.trim(),
                _token.text.trim(),
                _ip.text.trim(),
                protocol: _manualProtocol,
              ),
            ]
          : await widget.api.scan(_hub.text.trim(), _token.text.trim());
      if (!mounted) return;
      setState(() {
        final byId = <String, DiscoveredPlug>{
          for (final candidate in _candidates) candidate.id: candidate,
          for (final candidate in results) candidate.id: candidate,
        };
        _candidates = byId.values.toList();
        _searched = true;
        _hubConnected = true;
        if (_candidates.isEmpty) _showManualEntry = true;
      });
    } catch (error) {
      if (!mounted) return;
      setState(
        () => _error = error is FormatException
            ? error.message
            : error is StateError
            ? error.message
            : 'Could not reach the hub or plug. Check the address and try again.',
      );
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  List<Widget> _detectedResults(ThemeData theme) {
    final savedIds = _saved.map((plug) => plug.id).toSet();
    final candidates = [..._candidates]
      ..sort((left, right) {
        final savedOrder = (savedIds.contains(right.id) ? 1 : 0).compareTo(
          savedIds.contains(left.id) ? 1 : 0,
        );
        if (savedOrder != 0) return savedOrder;
        final modelOrder = left.model.compareTo(right.model);
        return modelOrder != 0 ? modelOrder : left.ip.compareTo(right.ip);
      });
    return [
      const SizedBox(height: 24),
      Text('Detected plugs', style: theme.textTheme.titleLarge),
      const SizedBox(height: 4),
      Text(
        _searched
            ? '${candidates.length} verified in this session · Tap a plug for details'
            : 'Scan results will appear here. Detection does not save a plug yet.',
        style: theme.textTheme.bodyMedium,
      ),
      if (_searched && candidates.isEmpty) ...[
        const SizedBox(height: 8),
        const Text(
          'No verified plugs found. Check that the plug is powered on and try its IP address.',
        ),
      ],
      for (final candidate in candidates) ...[
        const SizedBox(height: 8),
        _PlugCandidateCard(
          candidate: candidate,
          saved: savedIds.contains(candidate.id),
          savedName: _saved
              .where((plug) => plug.id == candidate.id)
              .firstOrNull
              ?.name,
          onSave: _busy ? null : () => _adopt(candidate),
        ),
      ],
    ];
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Scaffold(
      appBar: AppBar(title: const Text('Find a smart plug')),
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.all(20),
          children: [
            if (_hubConnected) ...[
              Row(
                children: [
                  Icon(
                    Icons.check_circle_outline,
                    color: theme.colorScheme.primary,
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Text(
                      'Hub connected',
                      style: theme.textTheme.titleMedium,
                    ),
                  ),
                  TextButton(
                    onPressed: () => setState(
                      () => _showConnectionSettings = !_showConnectionSettings,
                    ),
                    child: Text(
                      _showConnectionSettings
                          ? 'Hide details'
                          : 'Connection details',
                    ),
                  ),
                ],
              ),
            ],
            if (!_hubConnected || _showConnectionSettings) ...[
              Text(
                'Connect to your local hub',
                style: theme.textTheme.titleLarge,
              ),
              const SizedBox(height: 8),
              const Text(
                'Connect the plug to the same Wi-Fi network as your local hub. Pair this phone with the hub, then scan for TP-Link Kasa plugs or enter a local plug IP.',
              ),
              const SizedBox(height: 18),
              FilledButton.icon(
                onPressed: _busy ? null : _openPairing,
                icon: const Icon(Icons.phonelink_lock),
                label: Text(
                  _paired ? 'Pair with a different hub' : 'Pair with hub',
                ),
              ),
              if (_pairedHubId != null) ...[
                const SizedBox(height: 8),
                Text('Paired hub: $_pairedHubId'),
              ],
              if (_paired && !_hubConnected) ...[
                const SizedBox(height: 8),
                OutlinedButton.icon(
                  onPressed: _busy ? null : _restore,
                  icon: const Icon(Icons.refresh),
                  label: const Text('Retry hub connection'),
                ),
              ],
              const SizedBox(height: 16),
              TextField(
                key: const Key('hubAddress'),
                controller: _hub,
                decoration: InputDecoration(
                  labelText: _paired ? 'Paired hub address' : 'Hub address',
                  hintText: 'https://192.168.68.136:18787#sha256=…',
                  border: OutlineInputBorder(),
                ),
                keyboardType: TextInputType.url,
                autocorrect: false,
                readOnly: _paired,
                onChanged: (_) => _invalidateHubData(),
              ),
              const SizedBox(height: 12),
              if (!_paired)
                TextField(
                  controller: _token,
                  decoration: const InputDecoration(
                    labelText: 'Pilot discovery token',
                    border: OutlineInputBorder(),
                  ),
                  obscureText: true,
                  autocorrect: false,
                  onChanged: (_) => _invalidateHubData(),
                ),
            ],
            const SizedBox(height: 16),
            FilledButton.icon(
              onPressed: _busy ? null : () => _search(),
              icon: const Icon(Icons.radar),
              label: const Text('Scan for plugs'),
            ),
            ..._detectedResults(theme),
            const SizedBox(height: 14),
            TextButton.icon(
              onPressed: () =>
                  setState(() => _showManualEntry = !_showManualEntry),
              icon: Icon(_showManualEntry ? Icons.expand_less : Icons.add_link),
              label: Text(
                _showManualEntry
                    ? 'Hide manual IP entry'
                    : 'Enter a plug IP address',
              ),
            ),
            if (_showManualEntry) ...[
              const Text(
                'If the scan misses your plug, enter its local IP address.',
              ),
              const SizedBox(height: 8),
              TextField(
                key: const Key('manualPlugIp'),
                controller: _ip,
                decoration: const InputDecoration(
                  labelText: 'Plug IP address',
                  hintText: '192.168.1.42',
                  border: OutlineInputBorder(),
                ),
                // iOS maps this to the decimal pad, which includes the period
                // needed for dotted IPv4 addresses. Leave input unrestricted
                // so users can paste a complete address; the hub validates it.
                keyboardType: const TextInputType.numberWithOptions(
                  decimal: true,
                ),
              ),
              const SizedBox(height: 8),
              DropdownButtonFormField<String>(
                initialValue: _manualProtocol,
                decoration: const InputDecoration(
                  labelText: 'Device type',
                  border: OutlineInputBorder(),
                ),
                items: const [
                  DropdownMenuItem(value: 'kasa', child: Text('TP-Link Kasa')),
                  DropdownMenuItem(
                    value: 'shelly_gen2',
                    child: Text('Shelly Gen2'),
                  ),
                  DropdownMenuItem(value: 'tasmota', child: Text('Tasmota')),
                ],
                onChanged: _busy
                    ? null
                    : (value) {
                        if (value != null) {
                          setState(() => _manualProtocol = value);
                        }
                      },
              ),
              const SizedBox(height: 8),
              OutlinedButton(
                onPressed: _busy ? null : () => _search(manual: true),
                child: const Text('Check this IP address'),
              ),
            ],
            if (_busy) ...[
              const SizedBox(height: 18),
              const Center(child: CircularProgressIndicator()),
              const Center(child: Text('Checking the local network…')),
            ],
            if (_error != null) ...[
              const SizedBox(height: 16),
              Text(_error!, style: TextStyle(color: theme.colorScheme.error)),
            ],
            const SizedBox(height: 24),
            Row(
              children: [
                Expanded(
                  child: Text(
                    'Saved smart plugs',
                    style: theme.textTheme.titleLarge,
                  ),
                ),
                IconButton(
                  onPressed: _busy ? null : _loadSaved,
                  icon: const Icon(Icons.refresh),
                  tooltip: 'Refresh saved plugs',
                ),
              ],
            ),
            if (_saved.isEmpty)
              const Text('No smart plugs saved on this hub yet.'),
            for (final plug in _saved) ...[
              const SizedBox(height: 10),
              Card(
                child: Padding(
                  padding: const EdgeInsets.all(16),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'Smart plug · Saved',
                        style: theme.textTheme.labelLarge,
                      ),
                      Text(plug.name, style: theme.textTheme.titleMedium),
                      Text(
                        '${plug.model} · ${plug.room.isEmpty ? 'No room' : plug.room}',
                      ),
                      if (plug.mac != null) Text('MAC ${plug.mac}'),
                      if (plug.localProtocol == 'http')
                        Text('Local API · HTTP ${plug.httpPort ?? 80}'),
                      Text(
                        plug.meterStatus == 'absent'
                            ? 'No energy monitoring'
                            : 'Meter status: ${plug.meterStatus}',
                      ),
                      TextButton.icon(
                        onPressed: () => Navigator.of(context).push<void>(
                          MaterialPageRoute<void>(
                            builder: (_) => DeviceEnergyDetailScreen(
                              plug: plug,
                              api: widget.api,
                              hubAddress: _hub.text.trim(),
                              token: _token.text.trim(),
                              estimate: plug.connectedAppliance == null
                                  ? null
                                  : _estimates[plug.connectedAppliance!.id],
                            ),
                          ),
                        ),
                        icon: const Icon(Icons.electric_meter_outlined),
                        label: const Text('View energy details'),
                      ),
                      Text(
                        plugConnectionLabel(plug, hubConnected: _hubConnected),
                      ),
                      Text(
                        plugConnectionDetail(plug),
                        style: theme.textTheme.bodySmall,
                      ),
                      TextButton.icon(
                        onPressed: _statusChecking.contains(plug.id)
                            ? null
                            : () => _refreshPlugStatus(plug),
                        icon: _statusChecking.contains(plug.id)
                            ? const SizedBox(
                                width: 18,
                                height: 18,
                                child: CircularProgressIndicator(
                                  strokeWidth: 2,
                                ),
                              )
                            : const Icon(Icons.refresh),
                        label: Text(
                          _statusChecking.contains(plug.id)
                              ? 'Checking plug…'
                              : 'Check plug connection',
                        ),
                      ),
                      const Divider(height: 24),
                      Text(
                        'Connected appliance or lamp',
                        style: theme.textTheme.labelLarge,
                      ),
                      if (plug.connectedAppliance case final appliance?) ...[
                        Text(
                          appliance.name,
                          style: theme.textTheme.titleMedium,
                        ),
                        Text(
                          '${appliance.category} · ${appliance.model.isEmpty ? 'Model unknown' : appliance.model}',
                        ),
                        const Text('Connected load · No live readings'),
                        if (plug.connectionStatus == 'identity_changed')
                          const Text(
                            'Estimate hidden until this plug is verified.',
                          )
                        else if (_estimates[appliance.id] case final estimate?)
                          Padding(
                            padding: const EdgeInsets.only(top: 4),
                            child: Text(
                              energyRateDescription(estimate),
                              style: theme.textTheme.bodySmall,
                            ),
                          ),
                        if (plug.connectionStatus != 'identity_changed') ...[
                          if (_estimates[appliance.id]?.evidence
                              case final source?) ...[
                            Text(
                              _estimates[appliance.id]!.estimatedCostUsd == null
                                  ? 'Estimated monthly energy: ${_estimates[appliance.id]!.estimatedKwh!.toStringAsFixed(1)} kWh'
                                  : 'Estimated monthly cost: \$${_estimates[appliance.id]!.estimatedCostUsd!.toStringAsFixed(2)} · ${_estimates[appliance.id]!.estimatedKwh!.toStringAsFixed(1)} kWh',
                            ),
                            TextButton.icon(
                              onPressed: () => _showSource(
                                source,
                                _estimates[appliance.id]!,
                              ),
                              icon: Icon(
                                source.sourceKind == 'energy_star' ||
                                        source.sourceKind == 'epa_exact'
                                    ? Icons.verified_outlined
                                    : Icons.info_outline,
                              ),
                              label: Text(energySourceLabel(source)),
                            ),
                          ] else
                            const Text(
                              'Estimate unavailable · Exact model/source needed',
                            ),
                        ],
                        TextButton(
                          onPressed: _busy
                              ? null
                              : () => _checkConnectedEnergy(appliance),
                          child: const Text('Check energy data or update cost'),
                        ),
                      ] else
                        const Text('Not identified yet · Estimate unavailable'),
                      TextButton(
                        onPressed: _busy ? null : () => _connectAppliance(plug),
                        child: Text(
                          plug.connectedAppliance == null
                              ? 'Identify connected appliance'
                              : 'Change connected appliance',
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

class _PlugCandidateCard extends StatelessWidget {
  const _PlugCandidateCard({
    required this.candidate,
    required this.saved,
    required this.savedName,
    required this.onSave,
  });

  final DiscoveredPlug candidate;
  final bool saved;
  final String? savedName;
  final VoidCallback? onSave;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final noMeter = candidate.meterStatus == 'absent';
    return Card(
      child: ExpansionTile(
        leading: Icon(
          saved ? Icons.check_circle_outline : Icons.power_outlined,
          color: saved ? theme.colorScheme.primary : null,
        ),
        title: Text(
          savedName?.isNotEmpty == true
              ? savedName!
              : candidate.alias?.isNotEmpty == true
              ? candidate.alias!
              : candidate.model,
          style: theme.textTheme.titleMedium,
        ),
        subtitle: Text(
          '${candidate.ip} · ${noMeter
              ? 'No energy monitoring'
              : candidate.meterStatus == 'verified'
              ? 'Energy meter verified'
              : 'Energy meter unknown'}${saved ? ' · Saved' : ''}',
        ),
        childrenPadding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
        expandedCrossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Detected · ${noMeter
                ? 'No energy monitoring'
                : candidate.meterStatus == 'verified'
                ? 'Energy meter verified'
                : 'Energy meter unknown'}',
          ),
          Text(
            'Model ${candidate.model}${candidate.hardwareVersion == null ? '' : ' · Hardware ${candidate.hardwareVersion}'}',
          ),
          if (candidate.mac != null) Text('MAC ${candidate.mac}'),
          if (candidate.localProtocol == 'http')
            Text('Local API · HTTP ${candidate.httpPort ?? 80}'),
          if (candidate.relayOn != null)
            Text(
              'Switch ${candidate.relayOn! ? 'on' : 'off'} · This is not a power reading',
            ),
          const SizedBox(height: 8),
          Text(
            'Connected appliance or lamp',
            style: theme.textTheme.labelLarge,
          ),
          const Text(
            'Not identified yet. Add its model after saving the plug to estimate cost.',
          ),
          const SizedBox(height: 8),
          Text(
            saved
                ? 'Already saved on this hub'
                : 'Detected for this scan · Not saved yet',
            style: theme.textTheme.bodySmall,
          ),
          if (!saved) ...[
            const SizedBox(height: 8),
            FilledButton(
              onPressed: onSave,
              child: const Text('Save this plug'),
            ),
          ],
        ],
      ),
    );
  }
}
