import 'package:flutter/material.dart';
import 'package:flutter_appauth/flutter_appauth.dart';

import '../cloud_api/cloud_api_client.dart';
import '../cloud_api/cloud_home.dart';
import 'cloud_home_entry.dart';
import 'cloud_auth.dart';
import 'cloud_preferences_screen.dart';
import 'cloud_registration_screen.dart';
import 'cloud_local_auth.dart';

class CloudEntryGate extends StatefulWidget {
  const CloudEntryGate({
    super.key,
    required this.homeBuilder,
    this.session,
    this.api,
    this.registrationService,
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
  final CloudRegistrationService? registrationService;

  @override
  State<CloudEntryGate> createState() => _CloudEntryGateState();
}

class _CloudEntryGateState extends State<CloudEntryGate> {
  late final CloudSession _session;
  late final CloudApiClient _api;
  CloudLocalAuthClient? _ownedLocalAuth;
  final _localEmail = TextEditingController();
  final _localPassword = TextEditingController();
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
    final config = CloudAuthConfig.fromEnvironment();
    if (widget.session == null && config.isLocalAuthConfigured) {
      _ownedLocalAuth = CloudLocalAuthClient(baseUrl: config.apiUrl);
    }
    _session =
        widget.session ??
        CloudSession(
          config: config,
          store: const SecureCloudTokenStore(),
          authenticator: const AppAuthCloudAuthenticator(),
          localAuth: _ownedLocalAuth,
        );
    _api = widget.api ?? CloudApiClient(session: _session);
    _restore();
  }

  @override
  void dispose() {
    if (widget.api == null) _api.close();
    _ownedLocalAuth?.close();
    _localEmail.dispose();
    _localPassword.dispose();
    super.dispose();
  }

  Future<void> _restore() async {
    if (!_session.config.hasCloudSignIn) {
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
    } on FlutterAppAuthUserCancelledException {
      if (mounted) {
        setState(() => _message = 'Sign-in cancelled. Tap Sign in when ready.');
      }
    } on FlutterAppAuthPlatformException {
      if (mounted) {
        setState(
          () => _message = 'Could not start secure sign-in. Check your connection or app configuration.',
        );
      }
    } catch (_) {
      if (mounted) {
        setState(
          () => _message = 'Could not complete Cloud sign-in. Try again or ask for help with app configuration.',
        );
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _signInLocal() async {
    final email = _localEmail.text.trim();
    final password = _localPassword.text;
    if (email.isEmpty || password.isEmpty) {
      setState(() => _message = 'Enter your email and password.');
      return;
    }
    setState(() {
      _busy = true;
      _message = null;
    });
    try {
      await _session.signInLocal(email, password);
      await _validate();
    } on CloudLocalAuthException catch (error) {
      if (mounted) {
        setState(
          () => _message = switch (error.statusCode) {
            404 => 'Email sign-in is not available on this Cloud server.',
            401 => 'Could not sign in. Check your details and try again.',
            _ => 'Email sign-in is temporarily unavailable. Try again later.',
          },
        );
      }
    } catch (_) {
      if (mounted) {
        setState(
          () =>
              _message = 'Could not sign in. Check your details and try again.',
        );
      }
    } finally {
      _localPassword.clear();
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
                    _session.config.hasCloudSignIn
                        ? 'Sign in to your account to continue.'
                        : _session.config.hasPlaceholderEndpoint
                        ? 'This build uses placeholder Cloud settings. Install a Release build configured with a real OIDC issuer, public client ID, and Cloud API URL.'
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
                  if (!_busy &&
                      _session.config.isLocalAuthConfigured &&
                      _session.localAuth != null) ...[
                    const SizedBox(height: 8),
                    TextField(
                      key: const Key('localSignInEmail'),
                      controller: _localEmail,
                      keyboardType: TextInputType.emailAddress,
                      autofillHints: const [AutofillHints.email],
                      decoration: const InputDecoration(labelText: 'Email'),
                    ),
                    TextField(
                      key: const Key('localSignInPassword'),
                      controller: _localPassword,
                      obscureText: true,
                      autofillHints: const [AutofillHints.password],
                      decoration: const InputDecoration(labelText: 'Password'),
                    ),
                    const SizedBox(height: 8),
                    FilledButton(
                      onPressed: _signInLocal,
                      child: const Text('Sign in with email'),
                    ),
                  ],
                  if (!_busy &&
                      (widget.registrationService != null ||
                          (_session.config.isLocalAuthConfigured &&
                              _session.localAuth != null))) ...[
                    const SizedBox(height: 8),
                    TextButton(
                      onPressed: () => Navigator.of(context).push(
                        MaterialPageRoute<void>(
                          builder: (_) => CloudRegistrationScreen(
                            service:
                                widget.registrationService ??
                                _session.localAuth!,
                          ),
                        ),
                      ),
                      child: const Text('Create account'),
                    ),
                  ],
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
