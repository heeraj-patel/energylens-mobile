import '../../core/cloud_api/cloud_home.dart';

/// Session-only state keyed by verified account, home, and auth generation.
/// A completed milestone never regresses in this session, even when an older
/// incomplete read or a failed refresh arrives later.
class FirstDeviceGuideState {
  final Map<String, bool> _known = <String, bool>{};

  bool shouldShow(String scope) => _known[scope] == false;

  void accept(String scope, CloudHome home) {
    if (!home.hasFirstDeviceStatus) return;
    if (home.firstDeviceAddedAt != null) {
      _known[scope] = true;
    } else {
      _known.putIfAbsent(scope, () => false);
    }
  }

  void clear() => _known.clear();
}
