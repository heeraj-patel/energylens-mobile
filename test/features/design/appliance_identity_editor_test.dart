import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:energylens_mobile/core/cloud_api/cloud_api_client.dart';
import 'package:energylens_mobile/core/cloud_api/cloud_appliance.dart';
import 'package:energylens_mobile/core/cloud_api/cloud_appliance_detail.dart';
import 'package:energylens_mobile/core/cloud_api/cloud_appliance_list.dart';
import 'package:energylens_mobile/core/cloud_api/cloud_preferences.dart';
import 'package:energylens_mobile/features/design/appliance_identity_editor.dart';
import 'package:energylens_mobile/features/design/appliance_identity_edit_screen.dart';

const home = '11111111-1111-4111-8111-111111111111';
const device = '22222222-2222-4222-8222-222222222222';
const key = '33333333-3333-4333-8333-333333333333';

CloudAppliance appliance({
  String brand = 'Acme',
  String model = 'A1',
  int version = 1,
  String? catalogId = '44444444-4444-4444-8444-444444444444',
  String matchQuality = 'confirmed_exact',
}) => CloudAppliance(
  id: device,
  homeId: home,
  name: 'Light',
  category: 'lighting',
  room: 'Kitchen',
  brand: brand,
  fullModel: model,
  fuel: 'electricity',
  variant: 'warm',
  region: 'US',
  catalogProductId: catalogId,
  matchQuality: matchQuality,
  fccId: 'FCC-1',
  icId: 'IC-1',
  serialNumber: 'SN-1',
  upc: '123',
  buildYear: 2021,
  bulbLabel: const BulbLabel(
    loadKind: 'replaceable_bulb',
    bulbCount: 2,
    combinedInputWatts: 16,
  ),
  version: version,
);

class Source implements ApplianceIdentityEditSource {
  CloudAppliance current = appliance();
  int patches = 0;
  int reads = 0;
  bool losePatchResponse = false;
  bool failReadback = false;
  CloudApiException? patchError;
  Completer<CloudApplianceDetail>? delayedDetail;
  String? receivedEtag;
  String? receivedKey;
  CloudAppliancePatch? receivedPatch;
  CloudApplianceDataMode mode = CloudApplianceDataMode.household;

  @override
  Future<CloudApplianceDetail> detail(String homeId, String applianceId) async {
    reads++;
    if (delayedDetail case final pending?) return pending.future;
    if (failReadback && reads > 1) {
      failReadback = false;
      throw StateError('GET unavailable');
    }
    return CloudApplianceDetail(
      appliance: current,
      etag: '"${current.version}"',
      dataMode: mode,
      fixtureRevision: mode == CloudApplianceDataMode.household ? null : 'r1',
    );
  }

  @override
  Future<CloudVersioned<CloudAppliance>> patch(
    String homeId,
    String applianceId,
    CloudAppliancePatch input, {
    required String ifMatch,
    required String idempotencyKey,
  }) async {
    patches++;
    if (patchError case final error?) throw error;
    receivedEtag = ifMatch;
    receivedKey = idempotencyKey;
    receivedPatch = input;
    if (patches == 1) {
      current = appliance(
        brand: input.identity!.brand,
        model: input.identity!.fullModel,
        version: 2,
        catalogId: '55555555-5555-4555-8555-555555555555',
      );
    }
    if (losePatchResponse && patches == 1) {
      throw StateError('response lost');
    }
    return CloudVersioned(value: current, etag: '"2"');
  }
}

ApplianceIdentityEditor editor(Source source, {bool Function()? current}) =>
    ApplianceIdentityEditor(
      source: source,
      homeId: home,
      applianceId: device,
      isCurrentScope: current ?? () => true,
      newOperationKey: () => key,
    );

void main() {
  Future<void> openForm(
    WidgetTester tester,
    Source source, {
    bool Function()? current,
    void Function(bool?)? onResult,
  }) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Builder(
          builder: (context) => Scaffold(
            body: TextButton(
              onPressed: () async {
                final result = await Navigator.of(context).push<bool>(
                  MaterialPageRoute<bool>(
                    builder: (_) => ApplianceIdentityEditScreen(
                      source: source,
                      homeId: home,
                      applianceId: device,
                      isCurrentScope: current ?? () => true,
                    ),
                  ),
                );
                onResult?.call(result);
              },
              child: const Text('Open'),
            ),
          ),
        ),
      ),
    );
    await tester.tap(find.text('Open'));
    await tester.pump(const Duration(milliseconds: 350));
    await tester.pump();
  }

  testWidgets('form prefills and closes after PATCH readback', (tester) async {
    final source = Source();
    bool? result;
    await openForm(tester, source, onResult: (value) => result = value);
    expect(find.text('Edit device'), findsOneWidget);
    expect(find.text('Manufacturer'), findsOneWidget);
    expect(find.text('Full model'), findsOneWidget);
    final fields = tester
        .widgetList<TextField>(find.byType(TextField))
        .toList();
    expect(fields[0].controller!.text, 'Acme');
    expect(fields[1].controller!.text, 'A1');
    await tester.enterText(find.byType(TextField).first, 'New brand');
    await tester.tap(find.text('Save changes'));
    await tester.pumpAndSettle();
    expect(source.patches, 1);
    expect(source.reads, 2);
    expect(result, true);
  });

  testWidgets('uncertain PATCH freezes fields and retries same operation', (
    tester,
  ) async {
    final source = Source()..losePatchResponse = true;
    await openForm(tester, source);
    await tester.enterText(find.byType(TextField).last, 'B2');
    await tester.tap(find.text('Save changes'));
    await tester.pumpAndSettle();
    expect(find.text('Internal Error, Try again later'), findsOneWidget);
    expect(
      tester.widget<TextField>(find.byType(TextField).first).enabled,
      false,
    );
    expect(
      tester.widget<TextField>(find.byType(TextField).last).enabled,
      false,
    );
    final firstKey = source.receivedKey;
    await tester.tap(find.text('Save changes'));
    await tester.pumpAndSettle();
    expect(source.patches, 2);
    expect(source.receivedKey, firstKey);
    expect(source.receivedEtag, '"1"');
  });

  testWidgets('version conflict shows approved copy and disables save', (
    tester,
  ) async {
    final source = Source()
      ..patchError = const CloudApiException(409, 'version_conflict');
    await openForm(tester, source);
    await tester.enterText(find.byType(TextField).last, 'B2');
    await tester.tap(find.text('Save changes'));
    await tester.pumpAndSettle();
    expect(
      find.text('Device details changed elsewhere. Reopen and try again.'),
      findsOneWidget,
    );
    expect(
      tester.widget<FilledButton>(find.byType(FilledButton)).onPressed,
      isNull,
    );
    expect(source.patches, 1);
  });

  testWidgets('scope lost during load drops completion', (tester) async {
    final source = Source()..delayedDetail = Completer<CloudApplianceDetail>();
    var current = true;
    await openForm(tester, source, current: () => current);
    current = false;
    source.delayedDetail!.complete(
      CloudApplianceDetail(
        appliance: source.current,
        etag: '"1"',
        dataMode: CloudApplianceDataMode.household,
        fixtureRevision: null,
      ),
    );
    await tester.pump();
    expect(source.patches, 0);
    expect(
      tester.widget<FilledButton>(find.byType(FilledButton)).onPressed,
      isNull,
    );
  });

  test(
    'brand edit preserves identity metadata and accepts server relink',
    () async {
      final source = Source();
      final edit = editor(source);
      await edit.load();
      final saved = await edit.save(' Other ', 'A1');
      expect(saved?.brand, 'Other');
      expect(saved?.version, 2);
      expect(source.receivedEtag, '"1"');
      expect(source.receivedKey, key);
      expect(source.patches, 1);
      expect(source.reads, 2);
      final body = source.receivedPatch!.toJson();
      expect(body.keys, ['identity']);
      final identity = body['identity'] as Map<String, dynamic>;
      expect(identity['full_model'], 'A1');
      expect(identity['match_quality'], 'unresolved');
      expect(identity.containsKey('catalog_product_id'), false);
      expect(identity['fuel'], 'electricity');
      expect(identity['variant'], 'warm');
      expect(identity['region'], 'US');
      expect(identity['fcc_id'], 'FCC-1');
      expect(identity['ic_id'], 'IC-1');
      expect(identity['serial_number'], 'SN-1');
      expect(identity['upc'], '123');
      expect(identity['build_year'], 2021);
      expect(identity['bulb_label'], {
        'load_kind': 'replaceable_bulb',
        'bulb_count': 2,
        'combined_input_watts': 16.0,
      });
    },
  );

  test('no-op does not PATCH and mixed real row remains editable', () async {
    final source = Source()..mode = CloudApplianceDataMode.mixed;
    final edit = editor(source);
    await edit.load();
    expect((await edit.save('Acme', 'A1'))?.version, 1);
    expect(source.patches, 0);
  });

  test('UTF-8 byte limit rejects oversized identity before PATCH', () async {
    final source = Source();
    final edit = editor(source);
    await edit.load();
    expect(
      () => edit.save(List.filled(61, 'é').join(), 'A1'),
      throwsArgumentError,
    );
    expect(source.patches, 0);
  });

  test('uncertain PATCH retries same key and frozen payload', () async {
    final source = Source()..losePatchResponse = true;
    final edit = editor(source);
    await edit.load();
    await expectLater(edit.save('Acme', 'B2'), throwsStateError);
    expect(() => edit.save('Acme', 'B3'), throwsStateError);
    expect((await edit.save('Acme', 'B2'))?.fullModel, 'B2');
    expect(source.patches, 2);
    expect(source.receivedEtag, '"1"');
    expect(source.receivedKey, key);
  });

  test('readback failure retries GET without another PATCH', () async {
    final source = Source()..failReadback = true;
    final edit = editor(source);
    await edit.load();
    await expectLater(edit.save('Acme', 'B2'), throwsStateError);
    expect((await edit.save('Acme', 'B2'))?.version, 2);
    expect(source.patches, 1);
    expect(source.reads, 3);
  });

  test('sample detail and stale scope cannot mutate', () async {
    final source = Source()..mode = CloudApplianceDataMode.sample;
    final edit = editor(source);
    await expectLater(edit.load(), throwsFormatException);
    expect(source.patches, 0);
    var current = true;
    final scoped = editor(Source(), current: () => current);
    await scoped.load();
    current = false;
    expect(await scoped.save('Other', 'A1'), isNull);
  });

  test('appliance read preserves build year and both bulb kinds', () {
    final identity = {
      'brand': 'Acme',
      'full_model': 'A1',
      'fuel': 'electricity',
      'match_quality': 'unresolved',
      'build_year': 2020,
      'bulb_label': {'load_kind': 'integrated_lamp'},
    };
    Map<String, dynamic> body() => {
      'id': device,
      'home_id': home,
      'name': 'Light',
      'category': 'lighting',
      'identity': identity,
    };
    expect(CloudAppliance.fromJson(body()).buildYear, 2020);
    expect(
      CloudAppliance.fromJson(body()).bulbLabel?.loadKind,
      'integrated_lamp',
    );
    identity['bulb_label'] = {
      'load_kind': 'replaceable_bulb',
      'bulb_count': 2,
      'combined_input_watts': 16,
    };
    expect(CloudAppliance.fromJson(body()).bulbLabel?.bulbCount, 2);
    expect(CloudAppliance.fromJson(body()).bulbLabel?.combinedInputWatts, 16);
  });
}
