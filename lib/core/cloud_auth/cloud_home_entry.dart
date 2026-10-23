import 'dart:convert';

import 'package:flutter/material.dart';

import '../backend_error.dart';
import '../cloud_api/cloud_api_client.dart';
import '../cloud_api/cloud_home.dart';

class CloudHomeEntry extends StatefulWidget {
  const CloudHomeEntry({
    super.key,
    required this.homes,
    this.loading = false,
    this.loaded = true,
    required this.onRefresh,
    required this.onCreate,
    this.onSaveOwner,
    this.initialOwnerName = '',
    required this.onSelect,
    required this.onSignOut,
    this.listError,
  });

  final List<CloudHome> homes;
  final bool loading;
  final bool loaded;
  final String? listError;
  final Future<void> Function() onRefresh;
  final Future<CloudHome> Function(CloudHomeCreate, String) onCreate;
  final Future<void> Function(String)? onSaveOwner;
  final String initialOwnerName;
  final ValueChanged<CloudHome> onSelect;
  final VoidCallback onSignOut;

  @override
  State<CloudHomeEntry> createState() => _CloudHomeEntryState();
}

class _CloudHomeEntryState extends State<CloudHomeEntry> {
  final _name = TextEditingController();
  late final TextEditingController _owner;
  final _zip = TextEditingController();
  late final TextEditingController _country;
  late final TextEditingController _timezone;
  String _idempotencyKey = newCloudIdempotencyKey();
  String? _message;
  bool _busy = false;
  bool _uncertain = false;
  bool _showLocationControls = false;
  String? _selectedUsZone;
  late bool _wasUs;

  bool get _isUs => _country.text.trim().toUpperCase() == 'US';

  @override
  void initState() {
    super.initState();
    _owner = TextEditingController(text: widget.initialOwnerName);
    final localeCountry =
        WidgetsBinding.instance.platformDispatcher.locale.countryCode;
    _country = TextEditingController(
      text:
          localeCountry != null &&
              RegExp(r'^[A-Za-z]{2}$').hasMatch(localeCountry)
          ? localeCountry.toUpperCase()
          : '',
    );
    _timezone = TextEditingController(text: resolvedDeviceIanaTimeZone() ?? '');
    _wasUs = _isUs;
    _showLocationControls =
        _isUs || _country.text.isEmpty || _timezone.text.isEmpty;
    _owner.addListener(_onOwnerEdit);
    _country.addListener(_onCountryEdit);
    for (final controller in [_name, _zip, _timezone]) {
      controller.addListener(_onEdit);
    }
  }

  void _onCountryEdit() {
    final isUs = _isUs;
    if (isUs != _wasUs) _selectedUsZone = null;
    _wasUs = isUs;
    _onEdit();
    if (mounted) setState(() {});
  }

  void _onOwnerEdit() {
    if (_message != null && mounted) setState(() => _message = null);
  }

  void _onEdit() {
    // Editing the payload requires a new key; retrying unchanged input keeps it.
    _idempotencyKey = newCloudIdempotencyKey();
    if (_message != null && mounted) {
      setState(() {
        _message = null;
        _uncertain = false;
      });
    }
  }

  @override
  void dispose() {
    _owner.dispose();
    _name.dispose();
    _zip.dispose();
    _country.dispose();
    _timezone.dispose();
    super.dispose();
  }

  Future<void> _create() async {
    if (_busy) return;
    final owner = _owner.text.trim();
    final input = CloudHomeCreate.validate(
      name: _name.text,
      timezone: _isUs ? _selectedUsZone ?? '' : _timezone.text,
      countryCode: _country.text,
      postalCode: _zip.text,
    );
    if (input == null ||
        (widget.onSaveOwner != null &&
            (owner.isEmpty ||
                utf8.encode(owner).length > 120 ||
                RegExp(r'[\x00-\x1f\x7f]').hasMatch(owner)))) {
      setState(() {
        _showLocationControls = true;
        _message = 'Check the home details and try again.';
      });
      return;
    }
    setState(() {
      _busy = true;
      _message = null;
    });
    var homeStarted = false;
    try {
      await widget.onSaveOwner?.call(owner);
      homeStarted = true;
      final home = await widget.onCreate(input, _idempotencyKey);
      if (mounted) widget.onSelect(home);
    } on CloudApiException catch (error) {
      if (!mounted) return;
      setState(() {
        _uncertain = homeStarted && error.statusCode >= 500;
        _message = switch (error.statusCode) {
          409 => 'This form key was used for different home details. Edit a field and try again.',
          400 || 422 => 'Check the home details and try again.',
          _ => internalErrorMessage,
        };
      });
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _uncertain = homeStarted;
        _message = internalErrorMessage;
      });
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(
      title: Text(
        widget.onSaveOwner != null && widget.homes.isEmpty
            ? 'Set up your home'
            : 'Your homes',
      ),
      actions: [
        IconButton(
          tooltip: 'Sign out',
          onPressed: widget.onSignOut,
          icon: const Icon(Icons.logout),
        ),
      ],
    ),
    body: SafeArea(
      child: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 560),
          child: ListView(
            padding: const EdgeInsets.all(20),
            children: [
              if (widget.homes.isNotEmpty) ...[
                Text(
                  'Choose a home',
                  style: Theme.of(context).textTheme.headlineSmall,
                ),
                const SizedBox(height: 8),
                const Text('Homes belong to your account.'),
              ],
              const SizedBox(height: 16),
              if (widget.loading)
                const Center(child: CircularProgressIndicator()),
              if (widget.listError != null) ...[
                Text(widget.listError!, key: const Key('homeListError')),
                const SizedBox(height: 8),
              ],
              if (widget.homes.isNotEmpty ||
                  widget.listError != null ||
                  _uncertain)
                OutlinedButton.icon(
                  onPressed: _busy || widget.loading ? null : widget.onRefresh,
                  icon: const Icon(Icons.refresh),
                  label: const Text('Refresh homes'),
                ),
              if (widget.onSaveOwner == null &&
                  widget.loaded &&
                  widget.homes.isEmpty &&
                  widget.listError == null &&
                  !widget.loading)
                const Padding(
                  padding: EdgeInsets.symmetric(vertical: 16),
                  child: Text('No homes yet. Create one below.'),
                ),
              for (final home in widget.homes)
                Card(
                  child: ListTile(
                    key: Key('selectHome-${home.id}'),
                    title: Text(home.name),
                    subtitle: Text('${home.postalCode} · ${home.timezone}'),
                    trailing: const Icon(Icons.chevron_right),
                    onTap: _busy || widget.loading
                        ? null
                        : () => widget.onSelect(home),
                  ),
                ),
              if (widget.loaded &&
                  widget.homes.isEmpty &&
                  widget.listError == null &&
                  !widget.loading) ...[
                const SizedBox(height: 20),
                if (widget.onSaveOwner == null) ...[
                  Text(
                    'Create a home',
                    style: Theme.of(context).textTheme.titleLarge,
                  ),
                  const SizedBox(height: 8),
                  const Text('Confirm the time zone before creating.'),
                ],
                const SizedBox(height: 12),
                if (widget.onSaveOwner != null)
                  TextField(
                    key: const Key('setupOwnerName'),
                    controller: _owner,
                    enabled: !_busy && !_uncertain,
                    maxLength: 120,
                    textInputAction: TextInputAction.next,
                    decoration: const InputDecoration(labelText: 'Owner name'),
                  ),
                TextField(
                  key: const Key('setupHomeName'),
                  controller: _name,
                  enabled: !_busy && !_uncertain,
                  maxLength: 120,
                  decoration: const InputDecoration(labelText: 'Home name'),
                  textInputAction: TextInputAction.next,
                ),
                TextField(
                  key: const Key('setupPostalCode'),
                  controller: _zip,
                  enabled: !_busy && !_uncertain,
                  maxLength: 20,
                  textCapitalization: TextCapitalization.characters,
                  decoration: InputDecoration(
                    labelText: widget.onSaveOwner == null
                        ? 'ZIP or postal code'
                        : 'ZIP code',
                  ),
                  textInputAction: TextInputAction.done,
                  onSubmitted: (_) => _create(),
                ),
                if (_showLocationControls)
                  TextField(
                    key: const Key('setupCountry'),
                    controller: _country,
                    enabled: !_busy && !_uncertain,
                    maxLength: 2,
                    textCapitalization: TextCapitalization.characters,
                    decoration: InputDecoration(
                      labelText: widget.onSaveOwner == null
                          ? 'Country code'
                          : 'Country',
                    ),
                  ),
                if (_isUs)
                  DropdownButtonFormField<String>(
                    key: const Key('setupTimeZone'),
                    initialValue: _selectedUsZone,
                    isExpanded: true,
                    menuMaxHeight: 320,
                    decoration: InputDecoration(
                      labelText: widget.onSaveOwner == null
                          ? 'IANA time zone'
                          : 'Time zone',
                    ),
                    items: [
                      for (final zone in usIanaTimeZones)
                        DropdownMenuItem(value: zone, child: Text(zone)),
                    ],
                    onChanged: _busy || _uncertain
                        ? null
                        : (value) {
                            setState(() => _selectedUsZone = value);
                            _onEdit();
                          },
                  )
                else if (_showLocationControls)
                  TextField(
                    key: const Key('setupTimeZone'),
                    controller: _timezone,
                    enabled: !_busy && !_uncertain,
                    maxLength: 100,
                    decoration: InputDecoration(
                      labelText: widget.onSaveOwner == null
                          ? 'IANA time zone'
                          : 'Time zone',
                    ),
                  ),
                if (_message != null)
                  Padding(
                    padding: const EdgeInsets.only(top: 8),
                    child: Semantics(
                      liveRegion: true,
                      child: Text(
                        _message!,
                        key: const Key('homeCreateMessage'),
                      ),
                    ),
                  ),
                if (_uncertain)
                  const Padding(
                    padding: EdgeInsets.only(top: 8),
                    child: Text(
                      'If your new home appears above after refresh, select it instead of submitting again.',
                    ),
                  ),
                const SizedBox(height: 12),
                FilledButton(
                  onPressed: _busy || widget.loading ? null : _create,
                  child: _busy
                      ? const Text('Creating…')
                      : Text(
                          widget.onSaveOwner == null
                              ? 'Create home'
                              : 'Continue',
                        ),
                ),
              ],
            ],
          ),
        ),
      ),
    ),
  );
}
