import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:flutter_appauth/flutter_appauth.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';

/// The callback scheme is registered in both native runners. A release build
/// with missing or mismatched configuration cannot open the local home screen.
class CloudAuthConfig {
  const CloudAuthConfig({
    required this.issuer,
    required this.audience,
    required this.clientId,
    required this.redirectUrl,
    required this.apiUrl,
    this.localAuthEnabled = false,
    this.devAuthEnabled = false,
    this.appEnvironment = '',
    this.devCertificateSha256 = '',
    this.localAuthLinkOrigin = '',
  });

  factory CloudAuthConfig.fromEnvironment() => const CloudAuthConfig(
    issuer: String.fromEnvironment('ENERGYLENS_OIDC_ISSUER'),
    audience: String.fromEnvironment('ENERGYLENS_OIDC_AUDIENCE'),
    clientId: String.fromEnvironment('ENERGYLENS_OIDC_CLIENT_ID'),
    redirectUrl: String.fromEnvironment('ENERGYLENS_OIDC_REDIRECT_URL'),
    apiUrl: String.fromEnvironment('ENERGYLENS_CLOUD_API_URL'),
    localAuthEnabled: bool.fromEnvironment(
      'ENERGYLENS_CLOUD_LOCAL_AUTH_ENABLED',
    ),
    devAuthEnabled: bool.fromEnvironment('ENERGYLENS_CLOUD_DEV_AUTH_ENABLED'),
    appEnvironment: String.fromEnvironment('ENERGYLENS_APP_ENV'),
    devCertificateSha256: String.fromEnvironment(
      'ENERGYLENS_CLOUD_DEV_CERT_SHA256',
    ),
    localAuthLinkOrigin: String.fromEnvironment(
      'ENERGYLENS_CLOUD_LOCAL_AUTH_LINK_ORIGIN',
    ),
  );

  final String issuer;
  final String audience;
  final String clientId;
  final String redirectUrl;
  final String apiUrl;
  final bool localAuthEnabled;
  final bool devAuthEnabled;
  final String appEnvironment;
  final String devCertificateSha256;
  final String localAuthLinkOrigin;

  bool get hasValidApiUrl {
    final uri = Uri.tryParse(apiUrl);
    return uri?.scheme == 'https' &&
        uri!.host.isNotEmpty &&
        uri.host != 'invalid' &&
        !uri.host.endsWith('.invalid') &&
        (uri.path.isEmpty || uri.path == '/') &&
        uri.userInfo.isEmpty &&
        !uri.hasQuery &&
        !uri.hasFragment;
  }

  bool get isDevAuthConfigured =>
      appEnvironment == 'dev' && devAuthEnabled && hasValidApiUrl;
  bool get isLocalAuthConfigured =>
      (localAuthEnabled || isDevAuthConfigured) && hasValidApiUrl;
  bool get hasCloudSignIn => isConfigured || isLocalAuthConfigured;

  bool get hasPlaceholderEndpoint {
    bool isPlaceholder(String value) {
      final host = Uri.tryParse(value)?.host.toLowerCase() ?? '';
      return host == 'invalid' || host.endsWith('.invalid');
    }

    return isPlaceholder(issuer) || isPlaceholder(apiUrl);
  }

  bool get isConfigured {
    final issuerUri = Uri.tryParse(issuer);
    final apiUri = Uri.tryParse(apiUrl);
    final redirectUri = Uri.tryParse(redirectUrl);
    return !hasPlaceholderEndpoint &&
        issuerUri?.scheme == 'https' &&
        issuerUri!.host.isNotEmpty &&
        apiUri?.scheme == 'https' &&
        apiUri!.host.isNotEmpty &&
        (apiUri.path.isEmpty || apiUri.path == '/') &&
        apiUri.userInfo.isEmpty &&
        !apiUri.hasQuery &&
        !apiUri.hasFragment &&
        clientId.trim().isNotEmpty &&
        audience.trim().isNotEmpty &&
        redirectUri?.scheme == 'io.energylens.app' &&
        redirectUri?.host == 'login-callback' &&
        redirectUri?.query.isEmpty == true &&
        redirectUri?.fragment.isEmpty == true;
  }

  bool get allowLocalPreview => kDebugMode && !hasCloudSignIn;
}

class CloudTokens {
  const CloudTokens({
    required this.accessToken,
    this.refreshToken,
    this.expiresAt,
    this.refreshExpiresAt,
    this.provider = 'oidc',
  });
  final String accessToken;
  final String? refreshToken;
  final DateTime? expiresAt;
  final DateTime? refreshExpiresAt;
  final String provider;

  bool needsRefresh(DateTime now) =>
      expiresAt != null &&
      !now.isBefore(expiresAt!.subtract(const Duration(seconds: 60)));
}

abstract interface class CloudTokenStore {
  Future<CloudTokens?> read();
  Future<void> save(CloudTokens tokens);
  Future<void> clear();
}

class SecureCloudTokenStore implements CloudTokenStore {
  SecureCloudTokenStore({
    required String origin,
    required this._profile,
    FlutterSecureStorage? storage,
  }) : _storage = storage ?? const FlutterSecureStorage(),
       _origin = Uri.parse(origin).origin;
  final FlutterSecureStorage _storage;
  final String _origin;
  String _profile;
  Future<void> _tail = Future.value();
  Future<T> _ordered<T>(Future<T> Function() action) {
    final result = _tail.then((_) => action());
    _tail = result.then<void>((_) {}, onError: (Object _, StackTrace _) {});
    return result;
  }

  static const _access = 'energylens.cloud.access_token';
  static const _refresh = 'energylens.cloud.refresh_token';
  static const _expiry = 'energylens.cloud.access_expiry';
  static const _provider = 'energylens.cloud.auth_provider';
  static const _refreshExpiry = 'energylens.cloud.refresh_expiry';
  String get _scopedKey =>
      'energylens.cloud.session.v2.${base64Url.encode(utf8.encode('$_origin|$_profile'))}';

  Future<void> selectProfile(String profile) => _ordered(() async {
    _profile = profile;
  });

  @override
  Future<CloudTokens?> read() => _ordered(() async {
    final profile = _profile;
    final key = _scopedKey;
    // Legacy unscoped credentials cannot establish their original API origin.
    await _clearLegacy();
    final raw = await _storage.read(key: key);
    if (raw == null) return null;
    try {
      final data = jsonDecode(raw) as Map<String, dynamic>;
      if (data['origin'] != _origin ||
          data['profile'] != profile ||
          data['access'] is! String ||
          (data['access'] as String).isEmpty ||
          data['provider'] is! String) {
        await _storage.delete(key: key);
        return null;
      }
      return CloudTokens(
        accessToken: data['access'] as String,
        refreshToken: data['refresh'] as String?,
        expiresAt: DateTime.tryParse(data['expiry'] as String? ?? ''),
        refreshExpiresAt: DateTime.tryParse(
          data['refresh_expiry'] as String? ?? '',
        ),
        provider: data['provider'] as String,
      );
    } catch (_) {
      await _storage.delete(key: key);
      return null;
    }
  });

  @override
  Future<void> save(CloudTokens tokens) => _ordered(() async {
    final profile = _profile;
    final key = _scopedKey;
    await _storage.write(
      key: key,
      value: jsonEncode({
        'origin': _origin,
        'profile': profile,
        'provider': tokens.provider,
        'access': tokens.accessToken,
        'refresh': tokens.refreshToken,
        'expiry': tokens.expiresAt?.toUtc().toIso8601String(),
        'refresh_expiry': tokens.refreshExpiresAt?.toUtc().toIso8601String(),
      }),
    );
  });

  @override
  Future<void> clear() => _ordered(() async {
    final key = _scopedKey;
    await _storage.delete(key: key);
    await _clearLegacy();
  });

  Future<void> _clearLegacy() async {
    await _storage.delete(key: _access);
    await _storage.delete(key: _refresh);
    await _storage.delete(key: _expiry);
    await _storage.delete(key: _provider);
    await _storage.delete(key: _refreshExpiry);
  }
}

abstract interface class CloudAuthenticator {
  Future<CloudTokens> signIn(CloudAuthConfig config);
  Future<CloudTokens> refresh(CloudAuthConfig config, String refreshToken);
}

abstract interface class CloudRegistrationService {
  Future<void> requestRegistration(String email, String password);
  Future<void> verifyEmail(String token);
}

/// Email signup returns a session only when a new account was created.
abstract interface class AuthenticatedCloudRegistrationService {
  Future<CloudTokens> registerSession(String email, String password);
}

abstract interface class LocalCloudAuthService
    implements CloudRegistrationService {
  Future<CloudTokens> login(String email, String password);
  Future<CloudTokens> refresh(String refreshToken);
  Future<void> logout(String refreshToken);
  Future<void> requestRecovery(String email);
  Future<void> resetPassword(String token, String password);
  Future<void> resetUsernamePassword(String username, String password);
}

/// The refresh endpoint has definitively rejected the stored credential.
class CloudRefreshCredentialRejected implements Exception {
  const CloudRefreshCredentialRejected();
}

class AppAuthCloudAuthenticator implements CloudAuthenticator {
  const AppAuthCloudAuthenticator([FlutterAppAuth? appAuth])
    : _appAuth = appAuth ?? const FlutterAppAuth();
  final FlutterAppAuth _appAuth;
  static const _scopes = ['openid', 'profile', 'email', 'offline_access'];

  @override
  Future<CloudTokens> signIn(CloudAuthConfig config) async {
    final result = await _appAuth.authorizeAndExchangeCode(
      AuthorizationTokenRequest(
        config.clientId,
        config.redirectUrl,
        issuer: config.issuer,
        scopes: _scopes,
        additionalParameters: {'audience': config.audience},
      ),
    );
    final access = result.accessToken;
    if (access == null || access.isEmpty) {
      throw const FormatException('Missing access token');
    }
    return CloudTokens(
      accessToken: access,
      refreshToken: result.refreshToken,
      expiresAt: result.accessTokenExpirationDateTime,
    );
  }

  @override
  Future<CloudTokens> refresh(
    CloudAuthConfig config,
    String refreshToken,
  ) async {
    final result = await _appAuth.token(
      TokenRequest(
        config.clientId,
        config.redirectUrl,
        issuer: config.issuer,
        refreshToken: refreshToken,
        scopes: _scopes,
        additionalParameters: {'audience': config.audience},
      ),
    );
    final access = result.accessToken;
    if (access == null || access.isEmpty) {
      throw const FormatException('Missing access token');
    }
    return CloudTokens(
      accessToken: access,
      refreshToken: result.refreshToken ?? refreshToken,
      expiresAt: result.accessTokenExpirationDateTime,
    );
  }
}

class CloudSession {
  CloudSession({
    required this.config,
    required this.store,
    required this.authenticator,
    this.localAuth,
  });
  final CloudAuthConfig config;
  final CloudTokenStore store;
  final CloudAuthenticator authenticator;
  final LocalCloudAuthService? localAuth;
  String credentialMethod = 'email_password';
  Future<CloudTokens?>? _refreshInFlight;
  int? _refreshGeneration;
  int _generation = 0;
  final ValueNotifier<int> _generationChanges = ValueNotifier<int>(0);
  bool _accepting = true;
  Future<void> _storageTail = Future.value();
  int get generation => _generation;
  ValueListenable<int> get generationChanges => _generationChanges;

  int _advanceGeneration() {
    _generationChanges.value = ++_generation;
    return _generation;
  }

  Future<void> selectCredentialMethod(String method) async {
    if (method != 'username_password' &&
        method != 'email_password' &&
        method != 'oidc') {
      throw ArgumentError.value(method, 'method');
    }
    if (method == credentialMethod) return;
    final generation = _advanceGeneration();
    _accepting = false;
    await _orderedWrite(() async {
      if (generation != _generation) return;
      if (store is SecureCloudTokenStore) {
        await (store as SecureCloudTokenStore).selectProfile(method);
      }
      credentialMethod = method;
      _accepting = true;
    });
  }

  Future<void> _orderedWrite(Future<void> Function() action) {
    final result = _storageTail.then((_) => action());
    _storageTail = result.catchError((Object _) {});
    return result;
  }

  Future<void> _saveIfCurrent(CloudTokens tokens, int generation) =>
      _orderedWrite(() async {
        if (generation == _generation) await store.save(tokens);
      });

  Future<void> _clearIfCurrent(int generation) => _orderedWrite(() async {
    if (generation == _generation) await store.clear();
  });

  /// Whether the stored session was created with EnergyLens local credentials.
  /// This deliberately checks the persisted token provider, not whether local
  /// auth happens to be configured alongside an OIDC account.
  Future<bool> get isLocalAuthSession async =>
      (await store.read())?.provider == 'local';

  Future<String?> accessToken() async {
    if (!config.hasCloudSignIn || !_accepting) return null;
    final generation = _generation;
    final tokens = await store.read();
    if (generation != _generation || !_accepting) return null;
    if (tokens == null) return null;
    if ((tokens.provider == 'local' &&
            (!config.isLocalAuthConfigured ||
                localAuth == null ||
                tokens.expiresAt == null ||
                tokens.refreshExpiresAt == null)) ||
        (tokens.provider != 'local' && !config.isConfigured)) {
      await _clearIfCurrent(generation);
      return null;
    }
    if (!tokens.needsRefresh(DateTime.now())) return tokens.accessToken;
    return refreshAccessToken();
  }

  Future<String?> refreshAccessToken() async {
    if (!config.hasCloudSignIn || !_accepting) return null;
    final generation = _generation;
    final inFlight = _refreshInFlight;
    if (inFlight != null && _refreshGeneration == generation) {
      final token = await inFlight;
      return generation == _generation && _accepting
          ? token?.accessToken
          : null;
    }
    final refresh = _refreshTokens();
    _refreshInFlight = refresh;
    _refreshGeneration = generation;
    try {
      final token = await refresh;
      return generation == _generation && _accepting
          ? token?.accessToken
          : null;
    } finally {
      if (identical(_refreshInFlight, refresh)) {
        _refreshInFlight = null;
        _refreshGeneration = null;
      }
    }
  }

  Future<CloudTokens?> _refreshTokens() async {
    final generation = _generation;
    final current = await store.read();
    if (generation != _generation) return null;
    final refreshToken = current?.refreshToken;
    if (refreshToken == null ||
        refreshToken.isEmpty ||
        (current?.provider == 'local' &&
            (current!.refreshExpiresAt == null ||
                !DateTime.now().isBefore(current.refreshExpiresAt!)))) {
      await _clearIfCurrent(generation);
      return null;
    }
    try {
      final tokens = current!.provider == 'local'
          ? await localAuth!.refresh(refreshToken)
          : await authenticator.refresh(config, refreshToken);
      if (tokens.provider != current.provider) {
        throw const FormatException('Auth provider changed during refresh');
      }
      await _saveIfCurrent(tokens, generation);
      return generation == _generation ? tokens : null;
    } on CloudRefreshCredentialRejected {
      await _clearIfCurrent(generation);
      return null;
    } on FlutterAppAuthPlatformException catch (error) {
      if (error.platformErrorDetails.error ==
          FlutterAppAuthOAuthError.invalidGrant) {
        await _clearIfCurrent(generation);
        return null;
      }
      rethrow;
    }
  }

  Future<void> signIn() async {
    if (!config.isConfigured) {
      throw StateError('Cloud sign-in is not configured');
    }
    final generation = _advanceGeneration();
    _accepting = false;
    await _clearIfCurrent(generation);
    final tokens = await authenticator.signIn(config);
    await _saveIfCurrent(tokens, generation);
    if (generation != _generation) throw StateError('Sign-in scope changed');
    _accepting = true;
  }

  Future<void> signInLocal(String email, String password) async {
    if (!config.isLocalAuthConfigured || localAuth == null) {
      throw StateError('Local Cloud sign-in is not configured');
    }
    final generation = _advanceGeneration();
    _accepting = false;
    await _clearIfCurrent(generation);
    final tokens = await localAuth!.login(email, password);
    if (tokens.provider != 'local') {
      throw const FormatException('Invalid local session');
    }
    await _saveIfCurrent(tokens, generation);
    if (generation != _generation) throw StateError('Sign-in scope changed');
    _accepting = true;
  }

  Future<void> registerLocal(
    AuthenticatedCloudRegistrationService registration,
    String email,
    String password,
  ) async {
    if (!config.isLocalAuthConfigured || credentialMethod != 'email_password') {
      throw StateError('Email registration is not configured');
    }
    final generation = _advanceGeneration();
    _accepting = false;
    await _clearIfCurrent(generation);
    final tokens = await registration.registerSession(email, password);
    if (tokens.provider != 'local' || tokens.refreshToken == null) {
      throw const FormatException('Invalid registration session');
    }
    await _saveIfCurrent(tokens, generation);
    if (generation != _generation) {
      throw StateError('Registration scope changed');
    }
    _accepting = true;
  }

  Future<void> signOut() async {
    _advanceGeneration();
    _accepting = false;
    CloudTokens? tokens;
    await _orderedWrite(() async {
      tokens = await store.read();
      await store.clear();
    });
    if (tokens?.provider == 'local' && tokens?.refreshToken != null) {
      try {
        await localAuth?.logout(tokens!.refreshToken!);
      } catch (_) {
        // Local access is already invalid, even when remote revoke fails.
      }
    }
  }
}
