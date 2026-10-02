import 'package:flutter/material.dart';

import '../cloud_api/cloud_api_client.dart';
import '../cloud_api/cloud_home.dart';
import '../cloud_api/cloud_preferences.dart';
import '../../features/energy/cloud_electricity_rate_screen.dart';

class CloudPreferencesScreen extends StatefulWidget {
  const CloudPreferencesScreen({
    super.key,
    required this.api,
    this.home,
    this.requireDisclosure = false,
    this.onDisclosureAccepted,
    this.onSignOut,
  });

  final CloudApiClient api;
  final CloudHome? home;
  final bool requireDisclosure;
  final VoidCallback? onDisclosureAccepted;
  final VoidCallback? onSignOut;

  @override
  State<CloudPreferencesScreen> createState() => _CloudPreferencesScreenState();
}

class _CloudPreferencesScreenState extends State<CloudPreferencesScreen> {
  CloudVersioned<CloudAccountPreferences>? _account;
  CloudVersioned<CloudHomePreferences>? _home;
  String? _error;
  String? _message;
  bool _busy = false;
  bool _loading = true;
  bool _acceptedChecked = false;
  bool _emailEnabled = false;
  String _goal = 'unspecified';
  String _comfort = 'unknown';
  String? _pendingAcceptanceKey;
  String? _pendingAcceptanceAt;
  String? _pendingEmailKey;
  bool? _pendingEmailValue;
  String? _pendingHomeKey;
  String? _pendingGoal;
  String? _pendingComfort;

  @override
  void initState() {
    super.initState();
    _refresh();
  }

  Future<void> _refresh() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final account = await widget.api.accountPreferences();
      CloudVersioned<CloudHomePreferences>? home;
      if (widget.home != null && account.value.historyAccepted) {
        home = await widget.api.homePreferences(widget.home!.id);
      }
      if (mounted) {
        setState(() {
          _account = account;
          _home = home;
          _emailEnabled = account.value.emailReportsEnabled;
          _goal = home?.value.goal ?? 'unspecified';
          _comfort = home?.value.comfortPriority ?? 'unknown';
          _pendingAcceptanceKey = null;
          _pendingAcceptanceAt = null;
          _pendingEmailKey = null;
          _pendingEmailValue = null;
          _pendingHomeKey = null;
          _error = null;
        });
      }
    } catch (_) {
      if (mounted) {
        setState(() {
          _account = null;
          _home = null;
          _error = 'Could not load Cloud settings. Retry when connected.';
        });
      }
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _acceptDisclosure() async {
    final current = _account;
    if (current == null || !_acceptedChecked || _busy) return;
    _pendingAcceptanceKey ??= newCloudIdempotencyKey();
    _pendingAcceptanceAt ??= DateTime.now().toUtc().toIso8601String();
    setState(() {
      _busy = true;
      _message = null;
    });
    try {
      final saved = await widget.api.updateAccountPreferences(
        {'history_disclosure_accepted_at': _pendingAcceptanceAt},
        ifMatch: current.etag,
        idempotencyKey: _pendingAcceptanceKey!,
      );
      if (!mounted) return;
      setState(() {
        _account = saved;
        _pendingAcceptanceKey = null;
        _pendingAcceptanceAt = null;
        _message = 'History disclosure accepted.';
      });
      widget.onDisclosureAccepted?.call();
      if (widget.home != null) await _refresh();
    } on CloudApiException catch (error) {
      if (!mounted) return;
      setState(
        () => _message = error.statusCode == 409
            ? 'Settings changed. Refresh before trying again.'
            : error.statusCode == 400 || error.statusCode == 428
            ? 'This disclosure request expired. Refresh before trying again.'
            : 'Could not confirm acceptance. Retry the same request or refresh to check its status.',
      );
    } catch (_) {
      if (mounted) {
        setState(
          () => _message = 'Could not confirm acceptance. Retry the same request or refresh to check its status.',
        );
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _saveEmail() async {
    final current = _account;
    if (current == null || _busy) return;
    _pendingEmailKey ??= newCloudIdempotencyKey();
    _pendingEmailValue ??= _emailEnabled;
    setState(() {
      _busy = true;
      _message = null;
    });
    try {
      final saved = await widget.api.updateAccountPreferences(
        {'email_reports_enabled': _pendingEmailValue},
        ifMatch: current.etag,
        idempotencyKey: _pendingEmailKey!,
      );
      if (mounted) {
        setState(() {
          _account = saved;
          _pendingEmailKey = null;
          _pendingEmailValue = null;
          _message = 'Report preference saved.';
        });
      }
    } on CloudApiException catch (error) {
      if (mounted) {
        setState(
          () => _message = error.statusCode == 409
              ? 'Settings changed. Refresh before trying again.'
              : 'Could not confirm the report preference. Retry unchanged or refresh.',
        );
      }
    } catch (_) {
      if (mounted) {
        setState(
          () => _message = 'Could not confirm the report preference. Retry unchanged or refresh.',
        );
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _saveHome() async {
    final current = _home;
    final home = widget.home;
    if (current == null || home == null || _busy) return;
    _pendingHomeKey ??= newCloudIdempotencyKey();
    _pendingGoal ??= _goal;
    _pendingComfort ??= _comfort;
    setState(() {
      _busy = true;
      _message = null;
    });
    try {
      final saved = await widget.api.updateHomePreferences(
        home.id,
        CloudHomePreferences(
          version: current.value.version,
          goal: _pendingGoal!,
          comfortPriority: _pendingComfort!,
        ),
        ifMatch: current.etag,
        idempotencyKey: _pendingHomeKey!,
      );
      if (mounted) {
        setState(() {
          _home = saved;
          _pendingHomeKey = null;
          _pendingGoal = null;
          _pendingComfort = null;
          _message = 'Home preferences saved.';
        });
      }
    } on CloudApiException catch (error) {
      if (mounted) {
        setState(
          () => _message = error.statusCode == 409
              ? 'Home settings changed. Refresh before trying again.'
              : 'Could not confirm home settings. Retry unchanged or refresh.',
        );
      }
    } catch (_) {
      if (mounted) {
        setState(
          () => _message =
              'Could not confirm home settings. Retry unchanged or refresh.',
        );
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final account = _account;
    final home = _home;
    return Scaffold(
      appBar: AppBar(
        title: Text(
          widget.requireDisclosure ? 'History disclosure' : 'Cloud settings',
        ),
        automaticallyImplyLeading: !widget.requireDisclosure,
        actions: [
          IconButton(
            tooltip: 'Refresh settings',
            onPressed: _busy ? null : _refresh,
            icon: const Icon(Icons.refresh),
          ),
          if (widget.onSignOut != null)
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
                if (_loading) const Center(child: CircularProgressIndicator()),
                if (_error != null)
                  Text(_error!, key: const Key('cloudPreferencesError')),
                if (_message != null)
                  Padding(
                    padding: const EdgeInsets.only(bottom: 16),
                    child: Text(
                      _message!,
                      key: const Key('cloudPreferencesMessage'),
                    ),
                  ),
                if (account != null) ...[
                  Text(
                    'Energy history disclosure',
                    style: Theme.of(context).textTheme.titleLarge,
                  ),
                  const SizedBox(height: 8),
                  const Text(
                    'EnergyLens Cloud stores home inventory, usage answers, and energy history for your account. Detailed observations are retained for 30 days; hourly and daily summaries for 24 months.',
                  ),
                  const SizedBox(height: 12),
                  if (account.value.historyAccepted)
                    Text(
                      'Accepted ${account.value.historyDisclosureAcceptedAt!.toUtc().toIso8601String()}',
                    )
                  else ...[
                    CheckboxListTile(
                      key: const Key('acceptHistoryDisclosure'),
                      value: _acceptedChecked,
                      onChanged: _busy
                          ? null
                          : (value) => setState(
                              () => _acceptedChecked = value ?? false,
                            ),
                      title: const Text(
                        'I have read and accept this required history disclosure.',
                      ),
                      controlAffinity: ListTileControlAffinity.leading,
                      contentPadding: EdgeInsets.zero,
                    ),
                    FilledButton(
                      onPressed: _busy || !_acceptedChecked
                          ? null
                          : _acceptDisclosure,
                      child: const Text('Accept history disclosure'),
                    ),
                  ],
                  const SizedBox(height: 28),
                  Text(
                    'Email report preference',
                    style: Theme.of(context).textTheme.titleLarge,
                  ),
                  const SizedBox(height: 8),
                  const Text(
                    'Optional. This controls whether you may later request an email report. Reports are sent only after you review a snapshot and choose recipients. No recurring email is enabled here.',
                  ),
                  SwitchListTile(
                    key: const Key('emailReportsEnabled'),
                    title: const Text('Allow manual email reports'),
                    value: _emailEnabled,
                    onChanged: _busy
                        ? null
                        : (value) => setState(() {
                            _emailEnabled = value;
                            _pendingEmailKey = null;
                            _pendingEmailValue = null;
                          }),
                    contentPadding: EdgeInsets.zero,
                  ),
                  OutlinedButton(
                    onPressed: _busy ? null : _saveEmail,
                    child: const Text('Save report preference'),
                  ),
                  if (widget.home != null && account.value.historyAccepted) ...[
                    const SizedBox(height: 28),
                    TextButton.icon(
                      key: const Key('openCloudElectricityRate'),
                      onPressed: () => Navigator.of(context).push(
                        MaterialPageRoute<void>(
                          builder: (_) => CloudElectricityRateScreen(
                            api: widget.api,
                            home: widget.home!,
                          ),
                        ),
                      ),
                      icon: const Icon(Icons.bolt_outlined),
                      label: const Text('Cloud electricity rate'),
                    ),
                    TextButton.icon(
                      key: const Key('openCloudGasRate'),
                      onPressed: () => Navigator.of(context).push(
                        MaterialPageRoute<void>(
                          builder: (_) => CloudGasRateScreen(
                            api: widget.api,
                            home: widget.home!,
                          ),
                        ),
                      ),
                      icon: const Icon(Icons.local_fire_department_outlined),
                      label: const Text('Cloud gas rate'),
                    ),
                    const SizedBox(height: 12),
                    Text(
                      'Preferences for ${widget.home!.name}',
                      style: Theme.of(context).textTheme.titleLarge,
                    ),
                    const SizedBox(height: 8),
                    if (home == null)
                      const Text(
                        'Home preferences are unavailable. Refresh to try again.',
                      )
                    else ...[
                      DropdownButtonFormField<String>(
                        key: const Key('homeGoal'),
                        initialValue: _goal,
                        decoration: const InputDecoration(
                          labelText: 'Energy goal',
                        ),
                        items: const [
                          DropdownMenuItem(
                            value: 'unspecified',
                            child: Text('No goal selected'),
                          ),
                          DropdownMenuItem(
                            value: 'reduce_cost',
                            child: Text('Reduce cost'),
                          ),
                          DropdownMenuItem(
                            value: 'reduce_energy',
                            child: Text('Reduce energy use'),
                          ),
                          DropdownMenuItem(
                            value: 'understand_usage',
                            child: Text('Understand usage'),
                          ),
                        ],
                        onChanged: _busy
                            ? null
                            : (value) => setState(() {
                                _goal = value ?? 'unspecified';
                                _pendingHomeKey = null;
                                _pendingGoal = null;
                                _pendingComfort = null;
                              }),
                      ),
                      const SizedBox(height: 12),
                      DropdownButtonFormField<String>(
                        key: const Key('comfortPriority'),
                        initialValue: _comfort,
                        decoration: const InputDecoration(
                          labelText: 'Comfort priority',
                        ),
                        items: const [
                          DropdownMenuItem(
                            value: 'unknown',
                            child: Text('Not set'),
                          ),
                          DropdownMenuItem(value: 'high', child: Text('High')),
                          DropdownMenuItem(
                            value: 'balanced',
                            child: Text('Balanced'),
                          ),
                          DropdownMenuItem(
                            value: 'flexible',
                            child: Text('Flexible'),
                          ),
                        ],
                        onChanged: _busy
                            ? null
                            : (value) => setState(() {
                                _comfort = value ?? 'unknown';
                                _pendingHomeKey = null;
                                _pendingGoal = null;
                                _pendingComfort = null;
                              }),
                      ),
                      const SizedBox(height: 12),
                      FilledButton(
                        onPressed: _busy ? null : _saveHome,
                        child: const Text('Save home preferences'),
                      ),
                    ],
                  ],
                ],
              ],
            ),
          ),
        ),
      ),
    );
  }
}
