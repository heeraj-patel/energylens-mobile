import 'package:flutter/material.dart';
import 'package:flutter_appauth/flutter_appauth.dart';

import '../cloud_api/cloud_api_client.dart';
import '../cloud_api/cloud_home.dart';
import '../../features/design/design_context_coordinator.dart';
import 'cloud_auxiliary_domain_lifecycle.dart';
import 'cloud_home_entry.dart';
import 'cloud_auth.dart';
import 'cloud_preferences_screen.dart';
import 'cloud_registration_screen.dart';
import 'cloud_local_auth.dart';
import 'cloud_recovery_screen.dart';

class CloudEntryGate extends StatefulWidget {
  const CloudEntryGate({
    super.key,
    required this.homeBuilder,
    this.verifiedHomeBuilder,
    this.session,
    this.api,
    this.registrationService,
    this.designContextCoordinator,
    this.auxiliaryDomainLifecycle,
  });
  final Widget Function(
    CloudHome? selectedHome,
    VoidCallback? signOut,
    VoidCallback? changeHome,
    CloudApiClient cloudApi,
  )
  homeBuilder;

  /// Used for a selected home so nonvisual reads share the gate's verified lifecycle.
  final Widget Function(
    CloudHome selectedHome,
    VoidCallback signOut,
    VoidCallback changeHome,
    CloudApiClient cloudApi,
    CloudAuxiliaryDomainLifecycle lifecycle,
  )?
  verifiedHomeBuilder;
  final CloudSession? session;
  final CloudApiClient? api;
  final CloudRegistrationService? registrationService;

  /// Receives only account and home IDs verified through this gate's Cloud API.
  final DesignContextCoordinator? designContextCoordinator;
  final CloudAuxiliaryDomainLifecycle? auxiliaryDomainLifecycle;

  @override
  State<CloudEntryGate> createState() => _CloudEntryGateState();
}

class _CloudEntryGateState extends State<CloudEntryGate> {
  late final CloudSession _session;
  late final CloudApiClient _api;
  late final DesignContextCoordinator _designContextCoordinator;
  late final CloudAuxiliaryDomainLifecycle _auxiliaryDomainLifecycle;
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
  String? _verifiedAccountId;
  int _lifecycleEpoch = 0;

  void _invalidateDesignContext() {
    _lifecycleEpoch++;
    _verifiedAccountId = null;
    _selectedHome = null;
    _homes = const [];
    _designContextCoordinator.signOut();
    _auxiliaryDomainLifecycle.clear().ignore();
  }

  @override
  void initState() {
    super.initState();
    final config = CloudAuthConfig.fromEnvironment();
    if (widget.session == null && config.isLocalAuthConfigured) {
      _ownedLocalAuth = CloudLocalAuthClient(
        baseUrl: config.apiUrl,
        config: config,
      );
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
    _designContextCoordinator =
        widget.designContextCoordinator ??
        DesignContextCoordinator.forCloudApi(_api);
    _auxiliaryDomainLifecycle =
        widget.auxiliaryDomainLifecycle ??
        CloudAuxiliaryDomainLifecycle.forCloudApi(_api);
    _restore();
  }

  @override
  void dispose() {
    _invalidateDesignContext();
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
    final epoch = _lifecycleEpoch;
    try {
      final account = await _api.me();
      if (!mounted || epoch != _lifecycleEpoch) return;
      if (!account.emailVerified) {
        _invalidateDesignContext();
        if (mounted) {
          setState(() {
            _authenticated = false;
            _message = 'Verify your email address before continuing.';
          });
        }
        return;
      }
      final preferences = await _api.accountPreferences();
      if (!mounted || epoch != _lifecycleEpoch) return;
      _verifiedAccountId = account.id;
      if (mounted) {
        setState(() {
          _authenticated = true;
          _historyAccepted = preferences.value.historyAccepted;
          _message = null;
        });
      }
      if (preferences.value.historyAccepted) await _loadHomes();
    } on CloudApiException catch (error) {
      if (!mounted || epoch != _lifecycleEpoch) return;
      _invalidateDesignContext();
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
      if (!mounted || epoch != _lifecycleEpoch) return;
      _invalidateDesignContext();
      if (mounted) {
        setState(() {
          _authenticated = false;
          _message = 'Could not reach the cloud account service.';
        });
      }
    }
  }

  Future<void> _loadHomes() async {
    final epoch = _lifecycleEpoch;
    if (mounted) setState(() => _homeLoading = true);
    try {
      final homes = await _api.homes();
      if (!mounted || epoch != _lifecycleEpoch) return;
      if (mounted) {
        setState(() {
          _homes = homes;
          _homeListError = null;
        });
      }
    } on CloudApiException catch (error) {
      if (!mounted || epoch != _lifecycleEpoch) return;
      if (error.statusCode == 401 || error.statusCode == 403) {
        _invalidateDesignContext();
        await _session.signOut();
        if (mounted) {
          setState(() {
            _authenticated = false;
            _selectedHome = null;
            _homes = const [];
            _homeLoading = false;
            _message = 'Your cloud sign-in expired. Sign in again.';
          });
        }
        return;
      }
      if (_selectedHome != null) _invalidateDesignContext();
      if (mounted) {
        setState(() {
          _homes = const [];
          _selectedHome = null;
          _homeLoading = false;
          _homeListError = error.statusCode == 404
              ? 'Cloud homes are not available yet.'
              : 'Could not load homes (${error.code}). Refresh to try again.';
        });
      }
    } catch (_) {
      if (!mounted || epoch != _lifecycleEpoch) return;
      if (_selectedHome != null) _invalidateDesignContext();
      if (mounted) {
        setState(() {
          _homes = const [];
          _selectedHome = null;
          _homeLoading = false;
          _homeListError = 'Could not reach Cloud. Refresh to try again.';
        });
      }
    } finally {
      if (mounted && epoch == _lifecycleEpoch) {
        setState(() => _homeLoading = false);
      }
    }
  }

  Future<CloudHome> _createHome(CloudHomeCreate input, String key) async {
    final epoch = _lifecycleEpoch;
    try {
      final home = await _api.createHome(input, idempotencyKey: key);
      if (!mounted || epoch != _lifecycleEpoch || _verifiedAccountId == null) {
        throw StateError('Cloud account changed during home creation');
      }
      _homes = [..._homes.where((item) => item.id != home.id), home];
      return home;
    } on CloudApiException catch (error) {
      if (mounted &&
          epoch == _lifecycleEpoch &&
          (error.statusCode == 401 || error.statusCode == 403)) {
        _invalidateDesignContext();
        await _session.signOut();
        if (mounted) {
          setState(() {
            _authenticated = false;
            _selectedHome = null;
            _homes = const [];
          });
        }
      }
      rethrow;
    }
  }

  Future<void> _selectHome(CloudHome home) async {
    final accountId = _verifiedAccountId;
    if (accountId == null || !_homes.any((item) => item.id == home.id)) return;
    // The current UI can still select legacy IDs; they never enter the typed
    // design context, whose household adapters require UUID home IDs.
    final epoch = ++_lifecycleEpoch;
    try {
      _designContextCoordinator.useVerifiedContext(
        VerifiedDesignContext(
          accountId: accountId,
          homeId: home.id,
          mode: DesignContextMode.household,
        ),
      );
    } on ArgumentError {
      _designContextCoordinator.signOut();
    }
    try {
      await _auxiliaryDomainLifecycle.selectVerifiedHome(accountId, home.id);
    } catch (_) {
      // A device-local draft storage failure must not deny a verified home.
      _auxiliaryDomainLifecycle.clear().ignore();
    }
    if (!mounted || epoch != _lifecycleEpoch) return;
    setState(() => _selectedHome = home);
  }

  Future<void> _signIn() async {
    _invalidateDesignContext();
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
      _invalidateDesignContext();
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
    _invalidateDesignContext();
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
        void signOut() {
          _signOut();
        }

        void changeHome() {
          _lifecycleEpoch++;
          _designContextCoordinator.signOut();
          _auxiliaryDomainLifecycle.clear().ignore();
          setState(() => _selectedHome = null);
          _loadHomes();
        }

        return widget.verifiedHomeBuilder?.call(
              selected,
              signOut,
              changeHome,
              _api,
              _auxiliaryDomainLifecycle,
            ) ??
            widget.homeBuilder(selected, signOut, changeHome, _api);
      }
      return CloudHomeEntry(
        homes: _homes,
        loading: _homeLoading,
        listError: _homeListError,
        onRefresh: _loadHomes,
        onCreate: _createHome,
        onSelect: _selectHome,
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
                    if (!_session.config.isDevAuthConfigured)
                      TextButton(
                        onPressed: () => Navigator.of(context).push(
                          MaterialPageRoute<void>(
                            builder: (_) => CloudRecoveryScreen(
                              service: _session.localAuth!,
                              linkOrigin: _session.config.localAuthLinkOrigin,
                            ),
                          ),
                        ),
                        child: const Text('Forgot password?'),
                      ),
                  ],
                  if (!_busy &&
                      (widget.registrationService != null ||
                          (!_session.config.isDevAuthConfigured &&
                              _session.config.isLocalAuthConfigured &&
                              _session.localAuth != null))) ...[
                    const SizedBox(height: 8),
                    TextButton(
                      onPressed: () => Navigator.of(context).push(
                        MaterialPageRoute<void>(
                          builder: (_) => CloudRegistrationScreen(
                            service:
                                widget.registrationService ??
                                _session.localAuth!,
                            linkOrigin: _session.config.localAuthLinkOrigin,
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
