import 'package:flutter/material.dart';

import 'discovery_api.dart';
import 'discovery_credentials.dart';
import 'discovery_screen.dart';

/// Household ZIP and electricity rate settings stored by the connected hub.
class ElectricitySettingsScreen extends StatefulWidget {
  const ElectricitySettingsScreen({
    super.key,
    this.api = const DiscoveryApi(),
    this.credentials = const DiscoveryCredentials(),
    this.onSaved,
  });

  final DiscoveryApi api;
  final DiscoveryCredentials credentials;
  final VoidCallback? onSaved;

  @override
  State<ElectricitySettingsScreen> createState() =>
      _ElectricitySettingsScreenState();
}

class _ElectricitySettingsScreenState extends State<ElectricitySettingsScreen> {
  final _postal = TextEditingController();
  final _rate = TextEditingController();
  String? _address;
  String? _token;
  ElectricitySettings? _saved;
  bool _loaded = false;
  bool _busy = false;
  String? _feedback;
  String? _error;

  bool get _pending {
    final saved = _saved;
    if (saved == null) return false;
    final rateText = _rate.text.trim();
    final rate = rateText.isEmpty ? null : double.tryParse(rateText);
    if (rateText.isNotEmpty && (rate == null || !rate.isFinite)) return true;
    return _postal.text.trim() != (saved.postalCode ?? '') ||
        rate != saved.rateUsdPerKwh;
  }

  @override
  void initState() {
    super.initState();
    _restoreAndLoad();
  }

  Future<void> _restoreAndLoad() async {
    try {
      final localPostal = await widget.credentials.readPostalCode();
      final (address, token) = await widget.credentials.read();
      if (!mounted) return;
      setState(() {
        _address = address;
        _token = token;
        _postal.text = localPostal ?? '';
      });
      if (address != null && token != null) await _load();
    } catch (_) {
      if (mounted) {
        setState(() => _error = 'Could not read saved hub settings.');
      }
    }
  }

  Future<void> _load() async {
    final address = _address;
    final token = _token;
    if (address == null || token == null || address.isEmpty || token.isEmpty) {
      setState(() {
        _error = 'Connect to a hub to load household electricity settings.';
        _feedback = null;
      });
      return;
    }
    if (_busy) return;
    setState(() {
      _busy = true;
      _error = null;
      _feedback = null;
    });
    try {
      final settings = await widget.api.electricitySettings(address, token);
      if (!mounted) return;
      setState(() {
        _saved = settings;
        _postal.text = settings.postalCode ?? '';
        _rate.text = settings.rateUsdPerKwh?.toString() ?? '';
        _loaded = true;
        _feedback =
            settings.postalCode == null && settings.rateUsdPerKwh == null
            ? 'No household electricity settings are saved on this hub yet.'
            : 'Settings loaded from this hub.';
      });
    } catch (_) {
      if (mounted) {
        setState(
          () => _error = 'Could not load electricity settings. Check the hub connection and try again.',
        );
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _save() async {
    final address = _address;
    final token = _token;
    final postal = _postal.text.trim();
    final rateText = _rate.text.trim();
    final rate = rateText.isEmpty ? null : double.tryParse(rateText);
    if (address == null || token == null || address.isEmpty || token.isEmpty) {
      setState(
        () => _error = 'Connect to a hub before saving electricity settings.',
      );
      return;
    }
    if (postal.isNotEmpty && !RegExp(r'^\d{5}$').hasMatch(postal)) {
      setState(() => _error = 'Enter a five-digit US ZIP code.');
      return;
    }
    if (rateText.isNotEmpty &&
        (rate == null || !rate.isFinite || rate < 0 || rate > 5)) {
      setState(() => _error = 'Enter a rate between 0 and 5 dollars per kWh.');
      return;
    }
    if (_busy) return;
    setState(() {
      _busy = true;
      _error = null;
      _feedback = null;
    });
    try {
      final settings = await widget.api.updateElectricitySettings(
        address,
        token,
        postalCode: postal.isEmpty ? null : postal,
        rateUsdPerKwh: rate,
      );
      if (!mounted) return;
      setState(() {
        _saved = settings;
        _postal.text = settings.postalCode ?? '';
        _rate.text = settings.rateUsdPerKwh?.toString() ?? '';
        _loaded = true;
        _feedback = 'Electricity settings saved on this hub.';
      });
      if (settings.postalCode == null) {
        await widget.credentials.clearPostalCode();
      } else {
        await widget.credentials.savePostalCode(settings.postalCode!);
      }
      widget.onSaved?.call();
    } catch (error) {
      if (mounted) {
        setState(
          () => _error = error is StateError ? error.message : 'Could not save electricity settings. Check the hub connection and try again.',
        );
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  void dispose() {
    _postal.dispose();
    _rate.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final connected = _address != null && _token != null;
    return Scaffold(
      appBar: AppBar(title: const Text('Home profile')),
      body: SafeArea(
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 620),
            child: ListView(
              padding: const EdgeInsets.fromLTRB(20, 8, 20, 32),
              children: [
                Text(
                  'Home energy profile',
                  style: theme.textTheme.headlineSmall,
                ),
                const SizedBox(height: 8),
                Text(
                  'Your ZIP code and bill rate apply to every device in this home. A bill rate takes priority over the regional rate.',
                  style: theme.textTheme.bodyMedium,
                ),
                const SizedBox(height: 20),
                TextField(
                  key: const Key('householdPostalCode'),
                  controller: _postal,
                  keyboardType: TextInputType.number,
                  textInputAction: TextInputAction.next,
                  decoration: const InputDecoration(
                    labelText: 'US ZIP code',
                    hintText: '78732',
                    border: OutlineInputBorder(),
                  ),
                  onChanged: (_) => setState(() {}),
                ),
                const SizedBox(height: 12),
                TextField(
                  key: const Key('householdElectricityRate'),
                  controller: _rate,
                  keyboardType: const TextInputType.numberWithOptions(
                    decimal: true,
                  ),
                  textInputAction: TextInputAction.done,
                  decoration: const InputDecoration(
                    labelText: 'Your bill rate in USD/kWh (optional)',
                    hintText: '0.14',
                    border: OutlineInputBorder(),
                  ),
                  onChanged: (_) => setState(() {}),
                ),
                const SizedBox(height: 8),
                Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: [
                    OutlinedButton.icon(
                      onPressed: _busy || !connected ? null : _load,
                      icon: const Icon(Icons.refresh),
                      label: const Text('Load from hub'),
                    ),
                    FilledButton.icon(
                      onPressed: _busy ? null : _save,
                      icon: const Icon(Icons.save_outlined),
                      label: const Text('Save settings'),
                    ),
                  ],
                ),
                if (_busy) ...[
                  const SizedBox(height: 14),
                  const LinearProgressIndicator(),
                  const SizedBox(height: 6),
                  Text(
                    'Updating electricity settings…',
                    style: theme.textTheme.bodySmall,
                  ),
                ],
                if (_feedback != null) ...[
                  const SizedBox(height: 12),
                  Semantics(liveRegion: true, child: Text(_feedback!)),
                ],
                if (_pending) ...[
                  const SizedBox(height: 8),
                  Text(
                    'Unsaved changes. Save settings before using them for cost estimates.',
                    style: theme.textTheme.bodySmall,
                  ),
                ],
                if (!_loaded &&
                    (_postal.text.isNotEmpty || _rate.text.isNotEmpty) &&
                    _error == null) ...[
                  const SizedBox(height: 8),
                  Text(
                    'Load settings for this hub or save these values before they are used for cost estimates.',
                    style: theme.textTheme.bodySmall,
                  ),
                ],
                if (_error != null) ...[
                  const SizedBox(height: 12),
                  Text(
                    _error!,
                    style: TextStyle(color: theme.colorScheme.error),
                  ),
                ],
                if (!connected) ...[
                  const SizedBox(height: 24),
                  Text(
                    'Hub connection required',
                    style: theme.textTheme.titleMedium,
                  ),
                  const SizedBox(height: 6),
                  const Text(
                    'Connect your local hub to store these settings and use them for estimates.',
                  ),
                  const SizedBox(height: 12),
                  OutlinedButton.icon(
                    onPressed: () async {
                      await Navigator.of(context).push(
                        MaterialPageRoute<void>(
                          builder: (_) => DiscoveryScreen(
                            api: widget.api,
                            credentials: widget.credentials,
                          ),
                        ),
                      );
                      await _restoreAndLoad();
                    },
                    icon: const Icon(Icons.radar),
                    label: const Text('Connect a hub'),
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
