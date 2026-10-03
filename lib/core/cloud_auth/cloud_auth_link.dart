/// Reads one-use mail challenges without retaining or displaying their URL.
class CloudAuthLink {
  const CloudAuthLink._();

  static final _opaque = RegExp(r'^[A-Za-z0-9_-]{43}$');

  static String? capture(
    String input, {
    required String path,
    required String trustedOrigin,
  }) {
    final value = input.trim();
    if (_opaque.hasMatch(value)) return value;
    final origin = Uri.tryParse(trustedOrigin);
    final link = Uri.tryParse(value);
    if (origin == null ||
        link == null ||
        origin.scheme != 'https' ||
        origin.host.isEmpty ||
        origin.host == 'invalid' ||
        origin.host.endsWith('.invalid') ||
        origin.userInfo.isNotEmpty ||
        origin.path.isNotEmpty ||
        origin.hasQuery ||
        origin.hasFragment ||
        link.scheme != origin.scheme ||
        link.host != origin.host ||
        link.port != origin.port ||
        link.userInfo.isNotEmpty ||
        link.path != path ||
        link.hasQuery) {
      return null;
    }
    final fragment = link.fragment;
    if (!fragment.startsWith('token=')) return null;
    final token = fragment.substring('token='.length);
    return _opaque.hasMatch(token) ? token : null;
  }
}
