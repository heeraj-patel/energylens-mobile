import 'package:flutter/material.dart';

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
  final ValueChanged<CloudHome> onSelect;
  final VoidCallback onSignOut;

  @override
  State<CloudHomeEntry> createState() => _CloudHomeEntryState();
}

class _CloudHomeEntryState extends State<CloudHomeEntry> {
  final _name = TextEditingController();
  final _zip = TextEditingController();
  late final TextEditingController _country;
  late final TextEditingController _timezone;
  String _idempotencyKey = newCloudIdempotencyKey();
  String? _message;
  bool _busy = false;
  bool _uncertain = false;

  @override
  void initState() {
    super.initState();
    final localeCountry =
        WidgetsBinding.instance.platformDispatcher.locale.countryCode;
    _country = TextEditingController(
      text: localeCountry == null || localeCountry.isEmpty
          ? 'US'
          : localeCountry,
    );
    _timezone = TextEditingController(text: deviceIanaTimeZone());
    for (final controller in [_name, _zip, _country, _timezone]) {
      controller.addListener(_onEdit);
    }
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
    _name.dispose();
    _zip.dispose();
    _country.dispose();
    _timezone.dispose();
    super.dispose();
  }

  Future<void> _create() async {
    final input = CloudHomeCreate.validate(
      name: _name.text,
      timezone: _timezone.text,
      countryCode: _country.text,
      postalCode: _zip.text,
    );
    if (input == null) {
      setState(
        () => _message = 'Check the home name, IANA time zone, country code, and ZIP or postal code.',
      );
      return;
    }
    setState(() {
      _busy = true;
      _message = null;
    });
    try {
      final home = await widget.onCreate(input, _idempotencyKey);
      if (mounted) widget.onSelect(home);
    } on CloudApiException catch (error) {
      if (!mounted) return;
      setState(() {
        _uncertain = error.statusCode >= 500;
        _message = switch (error.statusCode) {
          401 ||
          403 => 'Your cloud sign-in expired. Sign out and sign in again.',
          409 => 'This form key was used for different home details. Edit a field and try again.',
          400 || 422 => 'Cloud rejected these home details. Check the fields and try again.',
          _ => 'Could not confirm creation. Refresh homes before retrying unchanged details.',
        };
      });
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _uncertain = true;
        _message = 'Could not confirm creation. Refresh homes before retrying unchanged details.';
      });
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(
      title: const Text('Your cloud homes'),
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
              Text(
                'Choose a home',
                style: Theme.of(context).textTheme.headlineSmall,
              ),
              const SizedBox(height: 8),
              const Text(
                'Homes belong to your account. Local hub devices are not linked to a cloud home yet.',
              ),
              const SizedBox(height: 16),
              if (widget.loading)
                const Center(child: CircularProgressIndicator()),
              if (widget.listError != null) ...[
                Text(widget.listError!, key: const Key('homeListError')),
                const SizedBox(height: 8),
              ],
              OutlinedButton.icon(
                onPressed: _busy || widget.loading ? null : widget.onRefresh,
                icon: const Icon(Icons.refresh),
                label: const Text('Refresh homes'),
              ),
              if (widget.loaded &&
                  widget.homes.isEmpty &&
                  widget.listError == null &&
                  !widget.loading)
                const Padding(
                  padding: EdgeInsets.symmetric(vertical: 16),
                  child: Text('No cloud homes yet. Create one below.'),
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
                Text(
                  'Create a home',
                  style: Theme.of(context).textTheme.titleLarge,
                ),
                const SizedBox(height: 8),
                const Text(
                  'Home and postal location are saved in EnergyLens Cloud. Confirm the time zone before creating.',
                ),
                const SizedBox(height: 12),
                TextField(
                  controller: _name,
                  maxLength: 120,
                  decoration: const InputDecoration(
                    labelText: 'Home name',
                    hintText: 'My home',
                  ),
                ),
                TextField(
                  controller: _zip,
                  maxLength: 20,
                  textCapitalization: TextCapitalization.characters,
                  decoration: const InputDecoration(
                    labelText: 'ZIP or postal code',
                    hintText: '60601',
                  ),
                ),
                TextField(
                  controller: _country,
                  maxLength: 2,
                  textCapitalization: TextCapitalization.characters,
                  decoration: const InputDecoration(
                    labelText: 'Country code',
                    hintText: 'US',
                  ),
                ),
                TextField(
                  controller: _timezone,
                  maxLength: 100,
                  decoration: const InputDecoration(
                    labelText: 'IANA time zone',
                    hintText: 'America/Chicago',
                  ),
                ),
                if (_message != null)
                  Padding(
                    padding: const EdgeInsets.only(top: 8),
                    child: Text(_message!, key: const Key('homeCreateMessage')),
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
                      : const Text('Create home'),
                ),
              ],
            ],
          ),
        ),
      ),
    ),
  );
}
