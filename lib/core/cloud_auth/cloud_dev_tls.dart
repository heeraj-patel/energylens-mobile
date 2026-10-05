import 'dart:io';

import 'package:crypto/crypto.dart';
import 'package:http/http.dart' as http;
import 'package:http/io_client.dart';

import 'cloud_auth.dart';

/// Trust one exact Cloud certificate only in an explicitly marked dev build.
http.Client cloudHttpClient(CloudAuthConfig config) {
  final pin = config.devCertificateSha256;
  if (pin.isEmpty) return http.Client();
  if (!config.isDevAuthConfigured || !RegExp(r'^[0-9a-f]{64}$').hasMatch(pin)) {
    throw StateError('Invalid development Cloud certificate pin');
  }
  final origin = Uri.parse(config.apiUrl);
  final client = HttpClient(context: SecurityContext(withTrustedRoots: false));
  client.badCertificateCallback = (certificate, host, port) {
    final now = DateTime.now();
    return host == origin.host &&
        port == origin.port &&
        !now.isBefore(certificate.startValidity) &&
        !now.isAfter(certificate.endValidity) &&
        sha256.convert(certificate.der).toString() == pin;
  };
  return IOClient(client);
}
