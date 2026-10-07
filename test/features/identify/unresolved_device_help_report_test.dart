import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:energylens_mobile/core/cloud_api/cloud_appliance.dart';
import 'package:energylens_mobile/features/identify/unresolved_device_help_report.dart';

void main() {
  late Directory tempDirectory;
  late File reportFile;

  setUp(() async {
    tempDirectory = await Directory.systemTemp.createTemp(
      'unresolved-device-report-',
    );
    reportFile = File('${tempDirectory.path}/internal/help.jsonl');
  });

  tearDown(() async {
    if (await tempDirectory.exists())
      await tempDirectory.delete(recursive: true);
  });

  CloudAppliance appliance({String id = 'appliance-42'}) => CloudAppliance(
    id: id,
    homeId: 'private-home-id',
    name: 'Kitchen refrigerator',
    category: 'refrigerator',
    room: 'Kitchen',
    brand: 'Acme OEM',
    fullModel: 'RF-2040',
    fuel: 'electric',
    matchQuality: 'confirmed_exact',
  );

  test(
    'writes only the identity and lookup details needed for human help',
    () async {
      await UnresolvedDeviceHelpReport(reportFile).append(
        appliance: appliance(),
        reason: 'No exact energy reference matched this model.',
        lookupStatus: 'no_match',
        sourcesAttempted: const ['EPA', 'ENERGY STAR', 'OEM'],
        attemptedAt: DateTime.utc(2026, 10, 7, 15, 30),
      );

      final lines = await reportFile.readAsLines();
      expect(lines, hasLength(1));
      final row = jsonDecode(lines.single) as Map<String, dynamic>;
      expect(row, {
        'appliance_id': 'appliance-42',
        'manufacturer': 'Acme OEM',
        'model': 'RF-2040',
        'reason': 'No exact energy reference matched this model.',
        'lookup_status': 'no_match',
        'attempted_at': '2026-10-07T15:30:00.000Z',
        'sources_attempted': ['EPA', 'ENERGY STAR', 'OEM'],
      });
      expect(row, isNot(contains('home_id')));
      expect(row, isNot(contains('name')));
      expect(row, isNot(contains('token')));
    },
  );

  test('appends rows so separate research attempts are preserved', () async {
    final report = UnresolvedDeviceHelpReport(reportFile);
    await report.append(
      appliance: appliance(),
      reason: 'No exact record.',
      lookupStatus: 'no_match',
      sourcesAttempted: const ['EPA'],
      attemptedAt: DateTime.utc(2026, 10, 7),
    );
    await report.append(
      appliance: appliance(),
      reason: 'OEM lookup unavailable.',
      lookupStatus: 'source_unavailable',
      sourcesAttempted: const ['OEM'],
      attemptedAt: DateTime.utc(2026, 10, 8),
    );

    final rows = (await reportFile.readAsLines())
        .map((line) => jsonDecode(line) as Map<String, dynamic>)
        .toList();
    expect(rows, hasLength(2));
    expect(rows.map((row) => row['lookup_status']), [
      'no_match',
      'source_unavailable',
    ]);
  });

  test('production factory uses the supplied app-support directory', () async {
    var providerCalled = false;
    final report = await UnresolvedDeviceHelpReport.inAppSupportDirectory(
      supportDirectoryProvider: () async {
        providerCalled = true;
        return tempDirectory;
      },
    );

    expect(providerCalled, isTrue);
    expect(
      report.file.path,
      '${tempDirectory.path}${Platform.pathSeparator}'
      'unresolved_device_help.jsonl',
    );
  });
}
