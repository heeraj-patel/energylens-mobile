import 'dart:async';

import 'package:energylens_mobile/features/design/local_pilot_device_lifecycle.dart';
import 'package:energylens_mobile/features/design/local_pilot_device_review_sheet.dart';
import 'package:energylens_mobile/features/discovery/discovery_api.dart';
import 'package:energylens_mobile/features/discovery/discovery_credentials.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

class _Store implements SecureKeyValueStore {
  final map = <String, String>{};
  @override
  Future<String?> read(String key) async => map[key];
  @override
  Future<void> write(String key, String value) async => map[key] = value;
  @override
  Future<void> delete(String key) async {
    map.remove(key);
  }
}

class _Api extends DiscoveryApi {
  final rows = <SavedAppliance>[];
  final inputs = <ApplianceInput>[];
  bool failRead = false;
  Completer<SavedAppliance>? heldPost;

  @override
  Future<bool> supportsNearbyDiscovery(String baseUrl, String token) async =>
      false;

  @override
  Future<List<SavedAppliance>> appliances(String address, String token) async {
    if (failRead) throw StateError('offline');
    return List.of(rows);
  }

  @override
  Future<SavedAppliance> addAppliance(
    String address,
    String token,
    ApplianceInput input,
  ) async {
    inputs.add(input);
    if (heldPost case final pending?) return pending.future;
    final row = SavedAppliance(
      id: inputs.length,
      name: input.name,
      room: input.room,
      category: input.category,
      manufacturer: input.manufacturer,
      model: input.model,
      loadKind: input.loadKind,
      onboardingMethod: input.onboardingMethod,
    );
    rows.add(row);
    return row;
  }
}

void main() {
  late _Api api;
  late LocalPilotDeviceLifecycle lifecycle;
  late LocalSaveSession session;

  setUp(() async {
    api = _Api();
    final credentials = DiscoveryCredentials(storage: _Store());
    await credentials.save('https://127.0.0.1:18787', 'token');
    lifecycle = LocalPilotDeviceLifecycle(api: api, credentials: credentials);
    session = (await lifecycle.beginSave((await lifecycle.inventory())!))!;
  });

  Future<void> showReview(
    WidgetTester tester,
    String method, {
    String manufacturer = 'Example',
    String model = 'Unlisted-100',
  }) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: Builder(
            builder: (context) => TextButton(
              onPressed: () => showDialog<LocalWriteResult>(
                context: context,
                builder: (_) => LocalPilotDeviceReviewSheet(
                  lifecycle: lifecycle,
                  session: session,
                  onboardingMethod: method,
                  initialCategory: 'refrigerator',
                  name: 'Kitchen Refrigerator',
                  manufacturer: manufacturer,
                  model: model,
                ),
              ),
              child: const Text('Open'),
            ),
          ),
        ),
      ),
    );
    await tester.tap(find.text('Open'));
    await tester.pumpAndSettle();
  }

  testWidgets('Cancel does not write', (tester) async {
    await showReview(tester, 'manual');
    await tester.tap(find.text('Cancel'));
    await tester.pumpAndSettle();
    expect(api.inputs, isEmpty);
  });

  for (final method in ['manual', 'photo']) {
    testWidgets('$method review saves Hub-required fields without fuel', (
      tester,
    ) async {
      await showReview(tester, method);
      await tester.enterText(
        find.byKey(const Key('localReviewDeviceName')),
        'Edited device',
      );
      await tester.tap(find.byKey(const Key('localReviewSave')));
      await tester.pumpAndSettle();
      expect(api.inputs.single.name, 'Edited device');
      expect(api.inputs.single.onboardingMethod, method);
      expect(api.inputs.single.room, '');
      expect(api.inputs.single.manufacturer, 'Example');
      expect(api.inputs.single.model, 'Unlisted-100');
      expect(find.byKey(const Key('reviewEnergySource')), findsNothing);
    });
  }

  testWidgets('incomplete identity keeps Save disabled', (tester) async {
    await showReview(tester, 'manual');
    final save = find.byKey(const Key('localReviewSave'));
    for (final fieldAndValue in [
      (const Key('localReviewManufacturer'), ''),
      (const Key('localReviewManufacturer'), '   '),
      (const Key('localReviewModel'), ''),
      (const Key('localReviewModel'), '   '),
    ]) {
      await tester.enterText(find.byKey(fieldAndValue.$1), fieldAndValue.$2);
      await tester.pump();
      expect(tester.widget<FilledButton>(save).onPressed, isNull);
      await tester.enterText(
        find.byKey(fieldAndValue.$1),
        fieldAndValue.$1 == const Key('localReviewManufacturer')
            ? 'Example'
            : 'Unlisted-100',
      );
      await tester.pump();
    }
    expect(api.inputs, isEmpty);
  });

  testWidgets('failed readback keeps edited draft and prevents second POST', (
    tester,
  ) async {
    await showReview(tester, 'manual');
    await tester.enterText(
      find.byKey(const Key('localReviewDeviceName')),
      'Edited device',
    );
    api.failRead = true;
    await tester.tap(find.byKey(const Key('localReviewSave')));
    await tester.pumpAndSettle();
    expect(find.text('Edited device'), findsOneWidget);
    expect(api.inputs.length, 1);
    await tester.tap(find.byKey(const Key('localReviewSave')));
    await tester.pumpAndSettle();
    expect(api.inputs.length, 1);
  });

  testWidgets('loading disables duplicate tap', (tester) async {
    await showReview(tester, 'manual');
    api.heldPost = Completer<SavedAppliance>();
    await tester.tap(find.byKey(const Key('localReviewSave')));
    await tester.pump();
    expect(find.byKey(const Key('localReviewSaving')), findsOneWidget);
    expect(
      tester
          .widget<FilledButton>(find.byKey(const Key('localReviewSave')))
          .onPressed,
      isNull,
    );
    expect(api.inputs.length, 1);
  });
}
