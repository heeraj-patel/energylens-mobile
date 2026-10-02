import 'package:flutter/material.dart';

import '../cloud_api/cloud_api_client.dart';
import '../cloud_api/cloud_home.dart';
import 'cloud_home_entry.dart';
import 'cloud_auth.dart';
import 'cloud_preferences_screen.dart';

class CloudEntryGate extends StatefulWidget {
  const CloudEntryGate({
    super.key,
    required this.homeBuilder,
    this.session,
    this.api,
  });
  final Widget Function(
    CloudHome? selectedHome,
    VoidCallback? signOut,
    VoidCallback? changeHome,
    CloudApiClient cloudApi,
  )
  homeBuilder;
  final CloudSession? session;
  final CloudApiClient? api;

  @override
  State<CloudEntryGate> createState() => _CloudEntryGateState();
}

class _CloudEntryGateState extends State<CloudEntryGate> {
  late final CloudSession _session;
  late final CloudApiClient _api;
  bool _busy = true;
  bool _authenticated = false;
  bool _historyAccepted = false;
  String? _message;
  List<CloudHome> _homes = const [];
  CloudHome? _selectedHome;
  String? _homeListError;
  bool _homeLoading = false;

  @override
  void initState() {
    super.initState();
    _session =
        widget.session ??
        CloudSession(
          config: CloudAuthConfig.fromEnvironment(),
          store: const SecureCloudTokenStore(),
          authenticator: const AppAuthCloudAuthenticator(),
        );
    _api = widget.api ?? CloudApiClient(session: _session);
    _restore();
  }

  @override
  void dispose() {
    if (widget.api == null) _api.close();
    super.dispose();
  }

  Future<void> _restore() async {
    if (!_session.config.isConfigured) {
      if (mounted) setState(() => _busy = false);
      return;
    }
    try {
      final token = await _session.accessToken();
      if (token != null) await _validate();
    } catch (_) {
      if (mounted) {
        setState(() => _message = 'Could not restore the cloud session.');
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _validate() async {
    try {
      final account = await _api.me();
      if (!account.emailVerified) {
        if (mounted) {
          setState(() {
            _authenticated = false;
            _message = 'Verify your email address before continuing.';
          });
        }
        return;
      }
      final preferences = await _api.accountPreferences();
      if (mounted) {
        setState(() {
          _authenticated = true;
          _historyAccepted = preferences.value.historyAccepted;
          _message = null;
        });
      }
      if (preferences.value.historyAccepted) await _loadHomes();
    } on CloudApiException catch (error) {
      if (error.statusCode == 401 || error.statusCode == 403) {
        await _session.signOut();
      }
      if (mounted) {
        setState(() {
          _authenticated = false;
          _message = error.statusCode == 404
              ? 'Cloud account service is not available yet.'
              : 'Could not verify the cloud account (${error.code}).';
        });
      }
    } catch (_) {
      if (mounted) {
        setState(() {
          _authenticated = false;
          _message = 'Could not reach the cloud account service.';
        });
      }
    }
  }

  Future<void> _loadHomes() async {
    if (mounted) setState(() => _homeLoading = true);
    try {
      final homes = await _api.homes();
      if (mounted) {
        setState(() {
          _homes = homes;
          _homeListError = null;
        });
      }
    } on CloudApiException catch (error) {
      if (error.statusCode == 401 || error.statusCode == 403) {
        await _session.signOut();
        if (mounted) {
          setState(() {
            _authenticated = false;
            _selectedHome = null;
            _homes = const [];
            _message = 'Your cloud sign-in expired. Sign in again.';
          });
        }
        return;
      }
      if (mounted) {
        setState(() {
          _homes = const [];
          _homeListError = error.statusCode == 404
              ? 'Cloud homes are not available yet.'
              : 'Could not load homes (${error.code}). Refresh to try again.';
        });
      }
    } catch (_) {
      if (mounted) {
        setState(() {
          _homes = const [];
          _homeListError = 'Could not reach Cloud. Refresh to try again.';
        });
      }
    } finally {
      if (mounted) setState(() => _homeLoading = false);
    }
  }

  Future<CloudHome> _createHome(CloudHomeCreate input, String key) =>
      _api.createHome(input, idempotencyKey: key);

  Future<void> _signIn() async {
    setState(() {
      _busy = true;
      _message = null;
    });
    try {
      await _session.signIn();
      await _validate();
    } catch (_) {
      if (mounted) {
        setState(
          () => _message = 'Sign-in was cancelled or failed. Please try again.',
        );
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _signOut() async {
    await _session.signOut();
    if (mounted) {
      setState(() {
        _authenticated = false;
        _historyAccepted = false;
        _selectedHome = null;
        _homes = const [];
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_session.config.allowLocalPreview) {
      return Banner(
        message: 'LOCAL PREVIEW',
        location: BannerLocation.topEnd,
        child: widget.homeBuilder(null, null, null, _api),
      );
    }
    if (_authenticated) {
      if (!_historyAccepted) {
        return CloudPreferencesScreen(
          api: _api,
          requireDisclosure: true,
          onDisclosureAccepted: () {
            setState(() => _historyAccepted = true);
            _loadHomes();
          },
          onSignOut: () {
            _signOut();
          },
        );
      }
      final selected = _selectedHome;
      if (selected != null) {
        return widget.homeBuilder(
          selected,
          () {
            _signOut();
          },
          () {
            setState(() => _selectedHome = null);
            _loadHomes();
          },
          _api,
        );
      }
      return CloudHomeEntry(
        homes: _homes,
        loading: _homeLoading,
        listError: _homeListError,
        onRefresh: _loadHomes,
        onCreate: _createHome,
        onSelect: (home) => setState(() => _selectedHome = home),
        onSignOut: () {
          _signOut();
        },
      );
    }
    return Scaffold(
      body: SafeArea(
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 420),
            child: Padding(
              padding: const EdgeInsets.all(28),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const Icon(Icons.bolt, size: 48),
                  const SizedBox(height: 16),
                  Text(
                    'EnergyLens',
                    style: Theme.of(context).textTheme.headlineMedium,
                  ),
                  const SizedBox(height: 12),
                  Text(
                    _session.config.isConfigured
                        ? 'Sign in to your account to continue.'
                        : 'Cloud sign-in is not configured for this build.',
                    textAlign: TextAlign.center,
                  ),
                  if (_message != null) ...[
                    const SizedBox(height: 12),
                    Text(_message!, textAlign: TextAlign.center),
                  ],
                  const SizedBox(height: 20),
                  if (_busy)
                    const CircularProgressIndicator()
                  else if (_session.config.isConfigured)
                    FilledButton(
                      onPressed: _signIn,
                      child: const Text('Sign in'),
                    ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
