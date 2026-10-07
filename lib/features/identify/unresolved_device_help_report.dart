import 'dart:convert';
import 'dart:io';

import 'package:path_provider/path_provider.dart';

import '../../core/cloud_api/cloud_appliance.dart';

/// Appends unresolved real-device identities for internal human research.
///
/// The destination is injected so the app can use its private support or
/// documents directory without exposing the report through customer UI.
class UnresolvedDeviceHelpReport {
  const UnresolvedDeviceHelpReport(this.file);

  /// Creates the report in the app's private support directory.
  ///
  /// [supportDirectoryProvider] is injectable for deterministic tests. The
  /// production default always resolves the platform app-support directory.
  static Future<UnresolvedDeviceHelpReport> inAppSupportDirectory({
    Future<Directory> Function()? supportDirectoryProvider,
  }) async {
    final directory =
        await (supportDirectoryProvider ?? getApplicationSupportDirectory)();
    return UnresolvedDeviceHelpReport(
      File(
        '${directory.path}${Platform.pathSeparator}'
        'unresolved_device_help.jsonl',
      ),
    );
  }

  final File file;

  Future<void> append({
    required CloudAppliance appliance,
    required String reason,
    required String lookupStatus,
    required Iterable<String> sourcesAttempted,
    required DateTime attemptedAt,
  }) async {
    final row = <String, Object>{
      'appliance_id': appliance.id,
      'manufacturer': appliance.brand,
      'model': appliance.fullModel,
      'reason': reason,
      'lookup_status': lookupStatus,
      'attempted_at': attemptedAt.toUtc().toIso8601String(),
      'sources_attempted': sourcesAttempted.toList(growable: false),
    };
    await file.parent.create(recursive: true);
    await file.writeAsString(
      '${jsonEncode(row)}\n',
      mode: FileMode.append,
      flush: true,
    );
  }
}
