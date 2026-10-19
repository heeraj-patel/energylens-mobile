import 'dart:io';

import 'package:energylens_mobile/core/cloud_api/cloud_home.dart';
import 'package:energylens_mobile/core/cloud_auth/cloud_home_entry.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets(
    'offline create keeps the same idempotency key for unchanged retry',
    (tester) async {
      tester.view.physicalSize = const Size(800, 1400);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      final keys = <String>[];
      CloudHome? selected;
      await tester.pumpWidget(
        MaterialApp(
          home: CloudHomeEntry(
            homes: const [],
            onRefresh: () async {},
            onCreate: (input, key) async {
              keys.add(key);
              if (keys.length == 1) throw const SocketException('offline');
              return CloudHome(
                id: 'home-1',
                name: input.name,
                timezone: input.timezone,
                countryCode: input.countryCode,
                postalCode: input.postalCode,
              );
            },
            onSelect: (home) => selected = home,
            onSignOut: () {},
          ),
        ),
      );
      expect(find.text('Create a home'), findsOneWidget);
      expect(find.widgetWithText(TextField, 'Home name'), findsOneWidget);
      await tester.enterText(
        find.widgetWithText(TextField, 'Home name'),
        'New home',
      );
      await tester.enterText(
        find.widgetWithText(TextField, 'ZIP or postal code'),
        '60601',
      );
      // Device time zone defaults can vary on CI; enter one known IANA location.
      await tester.enterText(
        find.widgetWithText(TextField, 'IANA time zone'),
        'America/Chicago',
      );
      await tester.ensureVisible(find.text('Create home'));
      await tester.tap(find.text('Create home'));
      await tester.pumpAndSettle();
      expect(find.textContaining('Could not confirm creation'), findsOneWidget);
      await tester.tap(find.text('Create home'));
      await tester.pumpAndSettle();
      expect(keys.length, 2);
      expect(keys[0], keys[1]);
      expect(selected?.name, 'New home');
    },
  );

  testWidgets('listed cloud home can be selected without creating another', (
    tester,
  ) async {
    CloudHome? selected;
    const home = CloudHome(
      id: 'home-1',
      name: 'Main home',
      timezone: 'America/Chicago',
      countryCode: 'US',
      postalCode: '60601',
    );
    await tester.pumpWidget(
      MaterialApp(
        home: CloudHomeEntry(
          homes: const [home],
          onRefresh: () async {},
          onCreate: (_, _) async => throw StateError('unexpected create'),
          onSelect: (value) => selected = value,
          onSignOut: () {},
        ),
      ),
    );
    expect(find.text('Create a home'), findsNothing);
    expect(find.byType(TextField), findsNothing);
    expect(find.text('Create home'), findsNothing);
    await tester.tap(find.text('Main home'));
    expect(selected?.id, 'home-1');
  });

  testWidgets('create form waits for a confirmed empty home list', (
    tester,
  ) async {
    Future<void> show({
      bool loaded = false,
      bool loading = false,
      String? error,
    }) => tester.pumpWidget(
      MaterialApp(
        home: CloudHomeEntry(
          homes: const [],
          loaded: loaded,
          loading: loading,
          listError: error,
          onRefresh: () async {},
          onCreate: (_, _) async => throw StateError('unexpected create'),
          onSelect: (_) {},
          onSignOut: () {},
        ),
      ),
    );

    await show();
    expect(find.text('Create a home'), findsNothing);
    expect(find.byType(TextField), findsNothing);
    await show(loading: true);
    expect(find.text('Create home'), findsNothing);
    await show(error: 'Could not load homes');
    expect(find.text('Could not load homes'), findsOneWidget);
    expect(find.text('Create a home'), findsNothing);
    await show(loaded: true);
    expect(find.text('Create a home'), findsOneWidget);
    expect(find.widgetWithText(TextField, 'Home name'), findsOneWidget);
  });
}
