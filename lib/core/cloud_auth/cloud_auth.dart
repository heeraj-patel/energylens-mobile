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
  });

  factory CloudAuthConfig.fromEnvironment() => const CloudAuthConfig(
    issuer: String.fromEnvironment('ENERGYLENS_OIDC_ISSUER'),
    audience: String.fromEnvironment('ENERGYLENS_OIDC_AUDIENCE'),
    clientId: String.fromEnvironment('ENERGYLENS_OIDC_CLIENT_ID'),
    redirectUrl: String.fromEnvironment('ENERGYLENS_OIDC_REDIRECT_URL'),
    apiUrl: String.fromEnvironment('ENERGYLENS_CLOUD_API_URL'),
  );

  final String issuer;
  final String audience;
  final String clientId;
  final String redirectUrl;
  final String apiUrl;

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

  bool get allowLocalPreview => kDebugMode && !isConfigured;
}

class CloudTokens {
  const CloudTokens({
    required this.accessToken,
    this.refreshToken,
    this.expiresAt,
  });
  final String accessToken;
  final String? refreshToken;
  final DateTime? expiresAt;

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
  const SecureCloudTokenStore([FlutterSecureStorage? storage])
    : _storage = storage ?? const FlutterSecureStorage();
  final FlutterSecureStorage _storage;
  static const _access = 'energylens.cloud.access_token';
  static const _refresh = 'energylens.cloud.refresh_token';
  static const _expiry = 'energylens.cloud.access_expiry';

  @override
  Future<CloudTokens?> read() async {
    final access = await _storage.read(key: _access);
    if (access == null || access.isEmpty) return null;
    final expiry = await _storage.read(key: _expiry);
    return CloudTokens(
      accessToken: access,
      refreshToken: await _storage.read(key: _refresh),
      expiresAt: expiry == null ? null : DateTime.tryParse(expiry),
    );
  }

  @override
  Future<void> save(CloudTokens tokens) async {
    await _storage.write(key: _access, value: tokens.accessToken);
    if (tokens.refreshToken == null) {
      await _storage.delete(key: _refresh);
    } else {
      await _storage.write(key: _refresh, value: tokens.refreshToken);
    }
    if (tokens.expiresAt == null) {
      await _storage.delete(key: _expiry);
    } else {
      await _storage.write(
        key: _expiry,
        value: tokens.expiresAt!.toUtc().toIso8601String(),
      );
    }
  }

  @override
  Future<void> clear() async {
    await _storage.delete(key: _access);
    await _storage.delete(key: _refresh);
    await _storage.delete(key: _expiry);
  }
}

abstract interface class CloudAuthenticator {
  Future<CloudTokens> signIn(CloudAuthConfig config);
  Future<CloudTokens> refresh(CloudAuthConfig config, String refreshToken);
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
  });
  final CloudAuthConfig config;
  final CloudTokenStore store;
  final CloudAuthenticator authenticator;
  Future<CloudTokens?>? _refreshInFlight;

  Future<String?> accessToken() async {
    if (!config.isConfigured) return null;
    final tokens = await store.read();
    if (tokens == null) return null;
    if (!tokens.needsRefresh(DateTime.now())) return tokens.accessToken;
    return refreshAccessToken();
  }

  Future<String?> refreshAccessToken() async {
    if (!config.isConfigured) return null;
    final inFlight = _refreshInFlight;
    if (inFlight != null) return (await inFlight)?.accessToken;
    final refresh = _refreshTokens();
    _refreshInFlight = refresh;
    try {
      return (await refresh)?.accessToken;
    } finally {
      _refreshInFlight = null;
    }
  }

  Future<CloudTokens?> _refreshTokens() async {
    final current = await store.read();
    final refreshToken = current?.refreshToken;
    if (refreshToken == null || refreshToken.isEmpty) {
      await store.clear();
      return null;
    }
    try {
      final tokens = await authenticator.refresh(config, refreshToken);
      await store.save(tokens);
      return tokens;
    } catch (_) {
      await store.clear();
      return null;
    }
  }

  Future<void> signIn() async {
    if (!config.isConfigured) {
      throw StateError('Cloud sign-in is not configured');
    }
    await store.save(await authenticator.signIn(config));
  }

  Future<void> signOut() => store.clear();
}
