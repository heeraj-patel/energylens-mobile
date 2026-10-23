import 'dart:convert';

import 'package:http/http.dart' as http;

import 'cloud_auth.dart';
import 'cloud_dev_tls.dart';

class CloudLocalAuthException implements Exception {
  const CloudLocalAuthException(this.statusCode);
  final int statusCode;
}

class CloudAuthCapabilities {
  const CloudAuthCapabilities({
    required this.method,
    required this.registrationEnabled,
    required this.registrationConfigurationError,
    required this.emailVerificationRequired,
    required this.passwordRecoveryEnabled,
    required this.sessionLogoutRevokesAccess,
  });

  final String method;
  final bool registrationEnabled;
  final bool registrationConfigurationError;
  final bool emailVerificationRequired;
  final bool passwordRecoveryEnabled;
  final bool sessionLogoutRevokesAccess;

  static CloudAuthCapabilities fromJson(
    Map<String, dynamic> data,
    CloudAuthConfig build,
  ) {
    final methods = data['methods'];
    if (data['schema_version'] != 1 ||
        methods is! List ||
        methods.isEmpty ||
        methods.any(
          (m) =>
              m is! String ||
              !{'username_password', 'email_password', 'oidc'}.contains(m),
        ) ||
        methods.toSet().length != methods.length ||
        data['registration_enabled'] is! bool ||
        data['email_verification_required'] is! bool ||
        data['password_recovery_enabled'] is! bool ||
        data['session_logout_revokes_access'] is! bool) {
      throw const FormatException('Invalid Cloud auth capabilities');
    }
    final chosen =
        methods.contains('email_password') && build.isLocalAuthConfigured
        ? 'email_password'
        : methods.contains('username_password') && build.isLocalAuthConfigured
        ? 'username_password'
        : methods.contains('oidc') && build.isConfigured
        ? 'oidc'
        : null;
    if (chosen == null) {
      throw const FormatException('Unsupported Cloud auth capabilities');
    }
    if (chosen == 'username_password' &&
        (data['email_verification_required'] != false ||
            data['password_recovery_enabled'] != false ||
            data['session_logout_revokes_access'] != true)) {
      throw const FormatException('Invalid username auth capabilities');
    }
    // A contradictory signup configuration must not take down sign-in.
    // Suppress registration while retaining the supported login method.
    final registrationConfigurationError =
        chosen == 'email_password' &&
        data['registration_enabled'] == true &&
        data['email_verification_required'] == true;
    final registrationEnabled =
        data['registration_enabled'] == true && !registrationConfigurationError;
    return CloudAuthCapabilities(
      method: chosen,
      registrationEnabled: registrationEnabled,
      registrationConfigurationError: registrationConfigurationError,
      emailVerificationRequired: data['email_verification_required'] as bool,
      passwordRecoveryEnabled: data['password_recovery_enabled'] as bool,
      sessionLogoutRevokesAccess: data['session_logout_revokes_access'] as bool,
    );
  }
}

/// Public first-party auth routes. The server returns 404 while its gate is off.
class CloudLocalAuthClient
    implements LocalCloudAuthService, AuthenticatedCloudRegistrationService {
  CloudLocalAuthClient({
    required this.baseUrl,
    http.Client? client,
    CloudAuthConfig? config,
  }) : _client =
           client ??
           cloudHttpClient(config ?? CloudAuthConfig.fromEnvironment()) {
    final uri = Uri.tryParse(baseUrl);
    if (uri?.scheme != 'https' ||
        uri!.host.isEmpty ||
        uri.host == 'invalid' ||
        uri.host.endsWith('.invalid') ||
        (uri.path.isNotEmpty && uri.path != '/') ||
        uri.userInfo.isNotEmpty ||
        uri.hasQuery ||
        uri.hasFragment) {
      throw ArgumentError.value(
        baseUrl,
        'baseUrl',
        'HTTPS Cloud origin required',
      );
    }
  }

  final String baseUrl;
  final http.Client _client;
  String credentialMethod = 'email_password';

  Future<CloudAuthCapabilities?> capabilities(CloudAuthConfig build) async {
    final response = await _client
        .get(
          Uri.parse(baseUrl).resolve('/v1/auth/config'),
          headers: const {'Accept': 'application/json'},
        )
        .timeout(const Duration(seconds: 15));
    if (response.statusCode == 404) return null;
    if (response.statusCode != 200) {
      throw CloudLocalAuthException(response.statusCode);
    }
    final body = jsonDecode(response.body);
    if (body is! Map<String, dynamic>) {
      throw const FormatException('Invalid Cloud auth capabilities');
    }
    return CloudAuthCapabilities.fromJson(body, build);
  }

  void close() => _client.close();

  Future<http.Response> _post(
    String path,
    Map<String, String> body,
    int status,
  ) async {
    final response = await _client
        .post(
          Uri.parse(baseUrl).resolve('/v1/auth/local/$path'),
          headers: const {
            'Content-Type': 'application/json',
            'Accept': 'application/json',
          },
          body: jsonEncode(body),
        )
        .timeout(const Duration(seconds: 15));
    if (response.statusCode != status) {
      throw CloudLocalAuthException(response.statusCode);
    }
    return response;
  }

  @override
  Future<void> requestRegistration(String email, String password) async {
    if (credentialMethod != 'username_password') {
      throw StateError('Email registration requires a session');
    }
    await _post('registration', {
      credentialMethod == 'username_password' ? 'username' : 'email': email,
      'password': password,
    }, 201);
  }

  @override
  Future<CloudTokens> registerSession(String email, String password) async {
    if (credentialMethod != 'email_password') {
      throw StateError('Authenticated registration requires email auth');
    }
    return _tokens(
      await _post('registration', {'email': email, 'password': password}, 201),
    );
  }

  @override
  Future<void> verifyEmail(String token) async {
    await _post('verify-email', {'token': token}, 204);
  }

  @override
  Future<CloudTokens> login(String email, String password) async => _tokens(
    await _post('login', {
      credentialMethod == 'username_password' ? 'username' : 'email': email,
      'password': password,
    }, 200),
  );

  @override
  Future<CloudTokens> refresh(String refreshToken) async {
    try {
      return _tokens(
        await _post('refresh', {'refresh_token': refreshToken}, 200),
      );
    } on CloudLocalAuthException catch (error) {
      if (error.statusCode == 401) {
        throw const CloudRefreshCredentialRejected();
      }
      rethrow;
    }
  }

  @override
  Future<void> logout(String refreshToken) async {
    await _post('logout', {'refresh_token': refreshToken}, 204);
  }

  @override
  Future<void> requestRecovery(String email) async {
    await _post('recovery', {'email': email}, 202);
  }

  @override
  Future<void> resetPassword(String token, String password) async {
    await _post('reset-password', {'token': token, 'password': password}, 204);
  }

  CloudTokens _tokens(http.Response response) {
    final body = jsonDecode(response.body);
    if (body is! Map<String, dynamic> ||
        body['token_type'] != 'Bearer' ||
        body['access_token'] is! String ||
        (body['access_token'] as String).isEmpty ||
        body['refresh_token'] is! String ||
        (body['refresh_token'] as String).isEmpty ||
        body['access_expires_at'] is! String ||
        body['refresh_expires_at'] is! String) {
      throw const FormatException('Invalid local auth response');
    }
    final accessExpiry = DateTime.tryParse(body['access_expires_at'] as String);
    final refreshExpiry = DateTime.tryParse(
      body['refresh_expires_at'] as String,
    );
    final now = DateTime.now();
    if (accessExpiry == null ||
        refreshExpiry == null ||
        !accessExpiry.isAfter(now) ||
        !refreshExpiry.isAfter(accessExpiry)) {
      throw const FormatException('Invalid local auth expiry');
    }
    return CloudTokens(
      accessToken: body['access_token'] as String,
      refreshToken: body['refresh_token'] as String,
      expiresAt: accessExpiry,
      refreshExpiresAt: refreshExpiry,
      provider: 'local',
    );
  }
}
