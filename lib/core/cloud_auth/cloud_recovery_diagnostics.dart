import 'package:flutter/foundation.dart' show debugPrint;

/// Emits credential-free recovery events to Release device logs.
void recordCloudRecoveryEvent(String event, {void Function(String)? sink}) {
  debugPrint('[auth.recovery] $event');
  try {
    sink?.call(event);
  } catch (_) {
    // Diagnostics must never change the authentication flow.
  }
}
