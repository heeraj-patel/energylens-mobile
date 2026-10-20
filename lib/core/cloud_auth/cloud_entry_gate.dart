import 'package:flutter/foundation.dart' show debugPrint, kDebugMode;
import 'package:flutter/material.dart';
import 'package:flutter_appauth/flutter_appauth.dart';
import 'package:http/http.dart' as http;

import '../backend_error.dart';
import '../cloud_api/cloud_api_client.dart';
import '../cloud_api/cloud_home.dart';
import '../cloud_api/cloud_hub_claim_flow.dart';
import '../../features/design/design_context_coordinator.dart';
import 'cloud_auxiliary_domain_lifecycle.dart';
import 'cloud_home_entry.dart';
import 'cloud_auth.dart';
import 'cloud_registration_screen.dart';
import 'cloud_local_auth.dart';
import 'cloud_recovery_screen.dart';
import '../../features/identify/onboarding_draft_store.dart';

class _UnavailableCloudTokenStore implements CloudTokenStore {
  @override
  Future<CloudTokens?> read() async => null;

  @override
  Future<void> save(CloudTokens value) async {}

  @override
  Future<void> clear() async {}
}

bool _isClientConfigUsable(CloudAuthConfig config) {
  final pin = config.devCertificateSha256;
  return config.hasCloudSignIn &&
      config.hasValidApiUrl &&
      (pin.isEmpty ||
          (config.isDevAuthConfigured &&
              RegExp(r'^[0-9a-f]{64}$').hasMatch(pin)));
}

class CloudEntryGate extends StatefulWidget {
  const CloudEntryGate({
    super.key,
    required this.homeBuilder,
    this.verifiedHomeBuilder,
    this.verifiedDesignHomeBuilder,
    this.session,
    this.api,
    this.registrationService,
    this.designContextCoordinator,
    this.auxiliaryDomainLifecycle,
    this.homeCreateStorage,
    this.activeHomeStorage,
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

  /// Supplies the same native coordinator whose scope is managed by this gate.
  /// Its context is null when a selected legacy home has no valid UUID.
  final Widget Function(
    CloudHome selectedHome,
    VoidCallback signOut,
    VoidCallback changeHome,
    CloudApiClient cloudApi,
    CloudAuxiliaryDomainLifecycle lifecycle,
    DesignContextCoordinator designContextCoordinator,
  )?
  verifiedDesignHomeBuilder;
  final CloudSession? session;
  final CloudApiClient? api;
  final CloudRegistrationService? registrationService;
  final OnboardingDraftStorage? homeCreateStorage;
  final OnboardingDraftStorage? activeHomeStorage;

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
  late final DurableHomeCreateDrafts _homeCreateDrafts;
  late final ActiveHomePreference _activeHomePreference;
  CloudLocalAuthClient? _ownedLocalAuth;
  final _localEmail = TextEditingController();
  final _localPassword = TextEditingController();
  bool _busy = true;
  bool _authenticated = false;
  String? _message;
  List<CloudHome> _homes = const [];
  CloudHome? _selectedHome;
  String? _homeListError;
  bool _homeLoading = false;
  bool _homeListLoaded = false;
  bool _allowRememberedRestore = true;
  bool _capabilitiesReady = false;
  CloudAuthCapabilities? _capabilities;
  bool _submitAttempted = false;
  bool _submitError = false;
  bool _allowSavedSessionRetry = true;
  String? _verifiedAccountId;
  int _lifecycleEpoch = 0;

  bool get _clientConfigUsable => _isClientConfigUsable(_session.config);

  void _invalidateDesignContext() {
    _lifecycleEpoch++;
    _busy = false;
    _verifiedAccountId = null;
    _selectedHome = null;
    _homes = const [];
    _homeListLoaded = false;
    _designContextCoordinator.signOut();
    _auxiliaryDomainLifecycle.clear().ignore();
    CloudHubClaimFlow.invalidatePendingClaims().ignore();
    _homeCreateDrafts.selectScope(null, null, null).ignore();
    _activeHomePreference.selectScope(null, null).ignore();
  }

  @override
  void initState() {
    super.initState();
    _localEmail.addListener(_clearSubmitErrorOnEdit);
    _localPassword.addListener(_clearSubmitErrorOnEdit);
    final config = CloudAuthConfig.fromEnvironment();
    final usable = _isClientConfigUsable(config);
    if (widget.session == null && usable && config.isLocalAuthConfigured) {
      _ownedLocalAuth = CloudLocalAuthClient(
        baseUrl: config.apiUrl,
        config: config,
      );
    }
    _session =
        widget.session ??
        CloudSession(
          config: config,
          store: usable
              ? SecureCloudTokenStore(
                  origin: config.apiUrl,
                  profile: 'email_password',
                )
              : _UnavailableCloudTokenStore(),
          authenticator: const AppAuthCloudAuthenticator(),
          localAuth: _ownedLocalAuth,
        );
    _api =
        widget.api ??
        CloudApiClient(
          session: _session,
          client: _clientConfigUsable ? null : http.Client(),
        );
    _homeCreateDrafts = DurableHomeCreateDrafts(
      widget.homeCreateStorage ??
          const SecureOnboardingDraftStorage.homeCreate(),
      _api,
    );
    _activeHomePreference = ActiveHomePreference(
      widget.activeHomeStorage ??
          const SecureOnboardingDraftStorage.activeHome(),
    );
    _designContextCoordinator =
        widget.designContextCoordinator ??
        DesignContextCoordinator.forCloudApi(_api);
    _auxiliaryDomainLifecycle =
        widget.auxiliaryDomainLifecycle ??
        CloudAuxiliaryDomainLifecycle.forCloudApi(_api);
    _api.onSessionRejected = _signOutRejectedSession;
    _restore();
  }

  @override
  void dispose() {
    _api.onSessionRejected = null;
    _invalidateDesignContext();
    if (widget.api == null) _api.close();
    _ownedLocalAuth?.close();
    _localEmail.dispose();
    _localPassword.dispose();
    super.dispose();
  }

  /// Cloud answered 401/403 (or the home cannot be verified): end the session
  /// so the user returns to sign-in and gets a new one.
  void _signOutRejectedSession() {
    if (!mounted || !_authenticated) return;
    _allowSavedSessionRetry = false;
    _invalidateDesignContext();
    _session.signOut().ignore();
    setState(() {
      _authenticated = false;
      _selectedHome = null;
      _homes = const [];
      _homeLoading = false;
      _message = 'Your cloud sign-in expired. Sign in again.';
    });
  }

  void _clearSubmitErrorOnEdit() {
    if (_submitError && mounted) setState(() => _submitError = false);
  }

  Future<void> _loadCapabilities(int epoch) async {
    final capabilities = await _api.authCapabilities();
    if (!mounted || epoch != _lifecycleEpoch) return;
    final method =
        capabilities?.method ??
        (_session.config.isLocalAuthConfigured ? 'email_password' : 'oidc');
    await _session.selectCredentialMethod(method);
    if (!mounted || epoch != _lifecycleEpoch) return;
    if (_session.localAuth is CloudLocalAuthClient) {
      (_session.localAuth! as CloudLocalAuthClient).credentialMethod = method;
    }
    if (!mounted) return;
    setState(() {
      _capabilities = capabilities;
      _capabilitiesReady = true;
    });
  }

  Future<void> _restore() async {
    final epoch = _lifecycleEpoch;
    if (!_clientConfigUsable) {
      if (mounted) setState(() => _busy = false);
      return;
    }
    try {
      await _loadCapabilities(epoch);
      if (!mounted || epoch != _lifecycleEpoch) return;
      final token = await _session.accessToken();
      if (token != null) await _validate();
    } catch (_) {
      if (mounted && epoch == _lifecycleEpoch) {
        setState(() => _submitError = true);
      }
    } finally {
      if (mounted && epoch == _lifecycleEpoch) setState(() => _busy = false);
    }
  }

  Future<void> _validate() async {
    final epoch = _lifecycleEpoch;
    try {
      final account = await _api.me();
      if (!mounted || epoch != _lifecycleEpoch) return;
      final usernameMode = _session.credentialMethod == 'username_password';
      final identityValid = usernameMode
          ? account.authMethod == 'username_password' &&
                account.username != null &&
                account.username!.isNotEmpty
          : account.emailVerified &&
                (account.authMethod == null ||
                    account.authMethod == _session.credentialMethod);
      if (!identityValid) {
        _allowSavedSessionRetry = false;
        if (kDebugMode) {
          final reason = usernameMode
              ? (account.authMethod != 'username_password'
                    ? 'auth_method is not username_password'
                    : 'username is missing or empty')
              : (!account.emailVerified
                    ? 'email is not verified'
                    : 'auth_method does not match the credential method');
          debugPrint(
            '[auth] identity check failed: $reason; '
            'credential_method=${_session.credentialMethod} '
            'auth_method=${account.authMethod} '
            'username_present=${account.username?.isNotEmpty ?? false} '
            'email_verified=${account.emailVerified}',
          );
        }
        _invalidateDesignContext();
        if (mounted) {
          setState(() {
            _authenticated = false;
            if (_submitAttempted) {
              _submitError = true;
              _message = null;
            } else {
              _message = usernameMode
                  ? 'Check your username and password.'
                  : 'Verify your email address before continuing.';
            }
          });
        }
        return;
      }
      if (!mounted || epoch != _lifecycleEpoch) return;
      _verifiedAccountId = account.id;
      _allowSavedSessionRetry = true;
      _allowRememberedRestore = true;
      final origin = Uri.parse(_session.config.apiUrl).origin;
      await _homeCreateDrafts.selectScope(
        origin,
        _session.credentialMethod,
        account.id,
      );
      await _activeHomePreference.selectScope(origin, account.id);
      if (!mounted || epoch != _lifecycleEpoch) return;
      if (mounted) {
        setState(() {
          _authenticated = true;
          _homeListLoaded = false;
          _message = null;
          _submitError = false;
          _submitAttempted = false;
        });
      }
      await _loadHomes();
    } on CloudApiException catch (error) {
      if (!mounted || epoch != _lifecycleEpoch) return;
      _invalidateDesignContext();
      final rejected = isSessionRejectionStatus(error.statusCode);
      if (rejected) {
        _allowSavedSessionRetry = false;
        await _session.signOut();
      }
      if (mounted) {
        setState(() {
          _authenticated = false;
          if (_submitAttempted || !rejected) {
            _submitError = true;
            _message = null;
          }
        });
      }
    } catch (_) {
      if (!mounted || epoch != _lifecycleEpoch) return;
      _invalidateDesignContext();
      if (mounted) {
        setState(() {
          _authenticated = false;
          _submitError = true;
          _message = null;
        });
      }
    }
  }

  Future<void> _loadHomes() async {
    final epoch = _lifecycleEpoch;
    if (mounted) {
      setState(() {
        _homeLoading = true;
        _homeListLoaded = false;
      });
    }
    try {
      final homes = await _api.homes();
      if (!mounted || epoch != _lifecycleEpoch) return;
      final resumed = await _homeCreateDrafts.restoreAndCommit();
      if (!mounted || epoch != _lifecycleEpoch) return;
      final ownedHomes =
          resumed == null || homes.any((home) => home.id == resumed.id)
          ? homes
          : [...homes, resumed];
      final remembered = await _activeHomePreference.restore(ownedHomes);
      if (!mounted || epoch != _lifecycleEpoch) return;
      if (mounted) {
        setState(() {
          _homes = ownedHomes;
          _homeListError = null;
          _homeListLoaded = true;
        });
      }
      if (_allowRememberedRestore &&
          remembered != null &&
          _selectedHome == null) {
        final home = ownedHomes
            .where((item) => item.id == remembered)
            .firstOrNull;
        if (home != null) await _selectHome(home);
      }
    } on CloudApiException catch (error) {
      if (!mounted || epoch != _lifecycleEpoch) return;
      if (isSessionRejectionStatus(error.statusCode)) {
        _signOutRejectedSession();
        return;
      }
      if (_selectedHome != null) _invalidateDesignContext();
      if (mounted) {
        setState(() {
          _homes = const [];
          _selectedHome = null;
          _homeLoading = false;
          _homeListError = internalErrorMessage;
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
          _homeListError = internalErrorMessage;
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
      final home = await _homeCreateDrafts.stageAndCommit(input, key);
      if (home == null) {
        throw StateError('Cloud account changed during home creation');
      }
      if (!mounted || epoch != _lifecycleEpoch || _verifiedAccountId == null) {
        throw StateError('Cloud account changed during home creation');
      }
      _homes = [..._homes.where((item) => item.id != home.id), home];
      return home;
    } on CloudApiException catch (error) {
      if (mounted &&
          epoch == _lifecycleEpoch &&
          isSessionRejectionStatus(error.statusCode)) {
        _signOutRejectedSession();
      }
      rethrow;
    }
  }

  Future<void> _selectHome(CloudHome home) async {
    final accountId = _verifiedAccountId;
    if (accountId == null || !_homes.any((item) => item.id == home.id)) {
      _signOutRejectedSession();
      return;
    }
    // The current UI can still select legacy IDs; they never enter the typed
    // design context, whose household adapters require UUID home IDs.
    final epoch = ++_lifecycleEpoch;
    try {
      _designContextCoordinator.useVerifiedContext(
        VerifiedDesignContext(
          accountId: accountId,
          homeId: home.id,
          mode: DesignContextMode.household,
          dataPolicy: DesignDataPolicy.sameHomeDemoFallback,
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
    await _activeHomePreference.remember(home);
    if (!mounted || epoch != _lifecycleEpoch) return;
    _allowRememberedRestore = true;
    setState(() => _selectedHome = home);
  }

  Future<void> _signIn() async {
    _invalidateDesignContext();
    final epoch = _lifecycleEpoch;
    setState(() {
      _busy = true;
      _message = null;
      _submitError = false;
    });
    try {
      final login = _session.signIn();
      final sessionGeneration = _session.generation;
      await login;
      if (!mounted ||
          epoch != _lifecycleEpoch ||
          sessionGeneration != _session.generation) {
        return;
      }
      await _validate();
    } on FlutterAppAuthUserCancelledException {
      if (mounted && epoch == _lifecycleEpoch) {
        setState(() => _message = null);
      }
    } on FlutterAppAuthPlatformException {
      if (mounted && epoch == _lifecycleEpoch) {
        setState(() => _submitError = true);
      }
    } catch (_) {
      if (mounted && epoch == _lifecycleEpoch) {
        setState(() => _submitError = true);
      }
    } finally {
      if (mounted && epoch == _lifecycleEpoch) setState(() => _busy = false);
    }
  }

  Future<void> _signInLocal() async {
    final email = _localEmail.text.trim();
    final password = _localPassword.text;
    if (email.isEmpty || password.isEmpty) {
      setState(() => _submitError = true);
      return;
    }
    setState(() {
      _invalidateDesignContext();
      _busy = true;
      _message = null;
      _submitError = false;
    });
    final epoch = _lifecycleEpoch;
    try {
      final login = _session.signInLocal(email, password);
      final sessionGeneration = _session.generation;
      await login;
      if (!mounted ||
          epoch != _lifecycleEpoch ||
          sessionGeneration != _session.generation) {
        return;
      }
      await _validate();
    } on CloudLocalAuthException {
      if (mounted && epoch == _lifecycleEpoch) {
        setState(() => _submitError = true);
      }
    } catch (_) {
      if (mounted && epoch == _lifecycleEpoch) {
        setState(() => _submitError = true);
      }
    } finally {
      final failed = _submitError;
      if (_localPassword.text == password) _localPassword.clear();
      if (failed) _submitError = true;
      if (mounted && epoch == _lifecycleEpoch) setState(() => _busy = false);
    }
  }

  Future<void> _submit() async {
    if (_busy) return;
    _submitAttempted = true;
    setState(() {
      _submitError = false;
      _message = null;
    });
    if (!_clientConfigUsable) {
      setState(() => _submitError = true);
      return;
    }
    if (!_capabilitiesReady) {
      final epoch = _lifecycleEpoch;
      setState(() => _busy = true);
      try {
        await _loadCapabilities(epoch);
      } catch (_) {
        if (mounted && epoch == _lifecycleEpoch) {
          setState(() => _submitError = true);
        }
        return;
      } finally {
        if (mounted && epoch == _lifecycleEpoch) {
          setState(() => _busy = false);
        }
      }
      if (!mounted || epoch != _lifecycleEpoch) return;
    }
    if (_allowSavedSessionRetry) {
      try {
        if (await _session.store.read() != null) {
          final token = await _session.accessToken();
          if (!mounted) return;
          if (token != null) {
            await _validate();
            return;
          }
        }
      } catch (_) {
        if (mounted) setState(() => _submitError = true);
        return;
      }
    }
    if (_session.credentialMethod == 'oidc') {
      await _signIn();
    } else if (_session.config.isLocalAuthConfigured &&
        _session.localAuth != null) {
      await _signInLocal();
    } else {
      setState(() => _submitError = true);
    }
  }

  Future<void> _signOut() async {
    _allowSavedSessionRetry = false;
    _invalidateDesignContext();
    if (mounted) {
      setState(() {
        _authenticated = false;
        _selectedHome = null;
        _homes = const [];
      });
    }
    await _session.signOut();
  }

  Future<void> _registerAndSignIn(String username, String password) async {
    _invalidateDesignContext();
    final epoch = _lifecycleEpoch;
    final login = _session.signInLocal(username, password);
    final sessionGeneration = _session.generation;
    await login;
    if (!mounted ||
        epoch != _lifecycleEpoch ||
        sessionGeneration != _session.generation) {
      throw StateError('Sign-in scope changed');
    }
    await _validate();
    if (!_authenticated) throw StateError('Account validation failed');
  }

  @override
  Widget build(BuildContext context) {
    if (_authenticated) {
      final selected = _selectedHome;
      if (selected != null) {
        void signOut() {
          _signOut();
        }

        void changeHome() {
          _lifecycleEpoch++;
          CloudHubClaimFlow.invalidatePendingClaims().ignore();
          _allowRememberedRestore = false;
          _designContextCoordinator.signOut();
          _auxiliaryDomainLifecycle.clear().ignore();
          setState(() => _selectedHome = null);
          _loadHomes();
        }

        return widget.verifiedDesignHomeBuilder?.call(
              selected,
              signOut,
              changeHome,
              _api,
              _auxiliaryDomainLifecycle,
              _designContextCoordinator,
            ) ??
            widget.verifiedHomeBuilder?.call(
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
        loaded: _homeListLoaded,
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
        child: LayoutBuilder(
          builder: (context, constraints) => SingleChildScrollView(
            child: ConstrainedBox(
              constraints: BoxConstraints(minHeight: constraints.maxHeight),
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
                        const SizedBox(height: 20),
                        TextField(
                          key: const Key('localSignInEmail'),
                          controller: _localEmail,
                          keyboardType:
                              _session.credentialMethod == 'email_password'
                              ? TextInputType.emailAddress
                              : TextInputType.text,
                          autofillHints: const [AutofillHints.username],
                          textInputAction: TextInputAction.next,
                          decoration: const InputDecoration(
                            labelText: 'Username',
                          ),
                        ),
                        TextField(
                          key: const Key('localSignInPassword'),
                          controller: _localPassword,
                          obscureText: true,
                          autofillHints: const [AutofillHints.password],
                          textInputAction: TextInputAction.done,
                          onSubmitted: (_) => _submit(),
                          decoration: const InputDecoration(
                            labelText: 'Password',
                          ),
                        ),
                        const SizedBox(height: 8),
                        FilledButton(
                          onPressed: _busy ? null : _submit,
                          child: const Text('Submit'),
                        ),
                        if (_submitError) ...[
                          const SizedBox(height: 8),
                          Semantics(
                            liveRegion: true,
                            child: Text(
                              internalErrorMessage,
                              textAlign: TextAlign.center,
                              style: Theme.of(context).textTheme.bodySmall
                                  ?.copyWith(
                                    color: Theme.of(context).colorScheme.error,
                                  ),
                            ),
                          ),
                        ] else if (_message != null) ...[
                          const SizedBox(height: 8),
                          Text(_message!, textAlign: TextAlign.center),
                        ],
                        if (!_busy &&
                            _capabilitiesReady &&
                            _session.config.isLocalAuthConfigured &&
                            _session.localAuth != null &&
                            _session.credentialMethod != 'oidc') ...[
                          if (!_session.config.isDevAuthConfigured &&
                              _session.credentialMethod == 'email_password' &&
                              (_capabilities?.passwordRecoveryEnabled ?? true))
                            TextButton(
                              onPressed: () => Navigator.of(context).push(
                                MaterialPageRoute<void>(
                                  builder: (_) => CloudRecoveryScreen(
                                    service: _session.localAuth!,
                                    linkOrigin:
                                        _session.config.localAuthLinkOrigin,
                                  ),
                                ),
                              ),
                              child: const Text('Forgot password?'),
                            ),
                        ],
                        if (!_busy &&
                            _capabilitiesReady &&
                            (_capabilities?.registrationEnabled ?? true) &&
                            (widget.registrationService != null ||
                                (!_session.config.isDevAuthConfigured &&
                                    _session.config.isLocalAuthConfigured &&
                                    _session.localAuth != null))) ...[
                          const SizedBox(height: 8),
                          TextButton(
                            onPressed: () {
                              final epoch = _lifecycleEpoch;
                              final sessionGeneration = _session.generation;
                              Navigator.of(context).push(
                                MaterialPageRoute<void>(
                                  builder: (_) => CloudRegistrationScreen(
                                    service:
                                        widget.registrationService ??
                                        _session.localAuth!,
                                    linkOrigin:
                                        _session.config.localAuthLinkOrigin,
                                    usernameMode:
                                        _session.credentialMethod ==
                                        'username_password',
                                    onUsernameRegistered: _registerAndSignIn,
                                    isCurrent: () =>
                                        mounted &&
                                        epoch == _lifecycleEpoch &&
                                        sessionGeneration ==
                                            _session.generation,
                                  ),
                                ),
                              );
                            },
                            child: const Text('Create account'),
                          ),
                        ],
                      ],
                    ),
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
