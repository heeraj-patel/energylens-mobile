import 'discovery_api.dart';

String plugConnectionLabel(SavedPlug plug, {required bool hubConnected}) {
  if (!hubConnected) return 'Hub disconnected · plug status unknown';
  return switch (plug.connectionStatus) {
    'connected' => 'Plug connected',
    'disconnected' => 'Plug disconnected',
    'identity_changed' => 'Needs verification · different plug at this address',
    _ => 'Plug connection not checked',
  };
}

String plugConnectionDetail(SavedPlug plug) {
  final checked = plug.statusCheckedAt;
  if (checked == null) {
    return 'Last verified ${_localTime(plug.lastVerifiedAt)}';
  }
  return 'Last checked ${_localTime(checked)}';
}

String _localTime(int unixSeconds) =>
    DateTime.fromMillisecondsSinceEpoch(unixSeconds * 1000)
        .toLocal()
        .toString();
