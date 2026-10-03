import 'dart:convert';

import 'package:http/http.dart' as http;

import 'cloud_auth.dart';

class CloudLocalAuthException implements Exception {
  const CloudLocalAuthException(this.statusCode);
  final int statusCode;
}

/// Public first-party auth routes. The server returns 404 while its gate is off.
class CloudLocalAuthClient implements LocalCloudAuthService {
  CloudLocalAuthClient({required this.baseUrl, http.Client? client})
    : _client = client ?? http.Client() {
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
    await _post('registration', {'email': email, 'password': password}, 202);
  }

  @override
  Future<void> verifyEmail(String token) async {
    await _post('verify-email', {'token': token}, 204);
  }

  @override
  Future<CloudTokens> login(String email, String password) async => _tokens(
    await _post('login', {'email': email, 'password': password}, 200),
  );

  @override
  Future<CloudTokens> refresh(String refreshToken) async =>
      _tokens(await _post('refresh', {'refresh_token': refreshToken}, 200));

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
