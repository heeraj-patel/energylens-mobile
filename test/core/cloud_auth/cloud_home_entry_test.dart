import 'dart:io';

import 'package:energylens_mobile/core/cloud_api/cloud_home.dart';
import 'package:energylens_mobile/core/cloud_api/cloud_api_client.dart';
import 'package:energylens_mobile/core/cloud_auth/cloud_home_entry.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets('US setup submits an empty zone for ZIP resolution', (
    tester,
  ) async {
    tester.binding.platformDispatcher.localeTestValue = const Locale(
      'en',
      'US',
    );
    addTearDown(tester.binding.platformDispatcher.clearLocaleTestValue);
    tester.view.physicalSize = const Size(800, 1400);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    CloudHomeCreate? submitted;
    CloudHome? selected;
    await tester.pumpWidget(
      MaterialApp(
        home: CloudHomeEntry(
          homes: const [],
          initialOwnerName: 'Owner',
          onSaveOwner: (_) async {},
          onRefresh: () async {},
          onCreate: (input, _) async {
            submitted = input;
            return const CloudHome(
              id: 'home-1',
              name: 'Home',
              timezone: 'America/Chicago',
              countryCode: 'US',
              postalCode: '60601',
            );
          },
          onSelect: (home) => selected = home,
          onSignOut: () {},
        ),
      ),
    );
    await tester.enterText(find.byKey(const Key('setupHomeName')), 'Home');
    await tester.enterText(find.byKey(const Key('setupPostalCode')), '60601');
    expect(find.byKey(const Key('setupCountry')), findsOneWidget);
    expect(find.byType(DropdownButtonFormField<String>), findsOneWidget);
    expect(find.byKey(const Key('setupTimeZone')), findsOneWidget);
    await tester.ensureVisible(find.text('Continue'));
    await tester.tap(find.text('Continue'));
    await tester.pumpAndSettle();
    expect(submitted?.toJson()['timezone'], '');
    expect(selected?.timezone, 'America/Chicago');
  });

  testWidgets('US dropdown sends selected zone; non-US retains text entry', (
    tester,
  ) async {
    tester.binding.platformDispatcher.localeTestValue = const Locale(
      'en',
      'US',
    );
    addTearDown(tester.binding.platformDispatcher.clearLocaleTestValue);
    tester.view.physicalSize = const Size(800, 1400);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final inputs = <CloudHomeCreate>[];
    await tester.pumpWidget(
      MaterialApp(
        home: CloudHomeEntry(
          homes: const [],
          onRefresh: () async {},
          onCreate: (input, _) async {
            inputs.add(input);
            throw const CloudApiException(400, 'invalid_request');
          },
          onSelect: (_) {},
          onSignOut: () {},
        ),
      ),
    );
    await tester.enterText(find.byKey(const Key('setupHomeName')), 'Home');
    await tester.enterText(find.byKey(const Key('setupPostalCode')), '60601');
    expect(find.byKey(const Key('setupCountry')), findsOneWidget);
    await tester.ensureVisible(find.byKey(const Key('setupTimeZone')));
    await tester.tap(find.byType(DropdownButton<String>));
    await tester.pumpAndSettle();
    await tester.scrollUntilVisible(
      find.text('America/Phoenix'),
      200,
      scrollable: find.byType(Scrollable).last,
    );
    await tester.tap(find.text('America/Phoenix').last);
    await tester.pumpAndSettle();
    await tester.ensureVisible(find.text('Create home'));
    await tester.tap(find.text('Create home'));
    await tester.pumpAndSettle();
    expect(inputs.single.timezone, 'America/Phoenix');

    await tester.enterText(find.byKey(const Key('setupCountry')), 'CA');
    await tester.enterText(find.byKey(const Key('setupPostalCode')), 'M5V 3L9');
    expect(find.byType(DropdownButtonFormField<String>), findsNothing);
    await tester.enterText(
      find.byKey(const Key('setupTimeZone')),
      'America/Toronto',
    );
    await tester.ensureVisible(find.text('Create home'));
    await tester.tap(find.text('Create home'));
    await tester.pumpAndSettle();
    expect(inputs.last.timezone, 'America/Toronto');
    expect(inputs.last.countryCode, 'CA');
  });

  testWidgets(
    'first-home setup saves owner before home and retries profile only',
    (tester) async {
      tester.binding.platformDispatcher.localeTestValue = const Locale(
        'en',
        'US',
      );
      addTearDown(tester.binding.platformDispatcher.clearLocaleTestValue);
      tester.view.physicalSize = const Size(800, 1400);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      var profileAttempts = 0;
      var homeCreates = 0;
      CloudHome? selected;
      await tester.pumpWidget(
        MaterialApp(
          home: CloudHomeEntry(
            homes: const [],
            initialOwnerName: 'Saved owner',
            onSaveOwner: (name) async {
              expect(name, 'Saved owner');
              profileAttempts++;
              if (profileAttempts == 1) throw const SocketException('offline');
            },
            onRefresh: () async {},
            onCreate: (input, _) async {
              homeCreates++;
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
      expect(find.text('Set up your home'), findsOneWidget);
      expect(
        tester
            .widget<TextField>(find.byKey(const Key('setupOwnerName')))
            .controller!
            .text,
        'Saved owner',
      );
      await tester.enterText(
        find.byKey(const Key('setupHomeName')),
        'New home',
      );
      await tester.enterText(
        find.byKey(const Key('setupPostalCode')),
        'bad code',
      );
      await tester.tap(find.text('Continue'));
      await tester.pumpAndSettle();
      expect(profileAttempts, 0);
      expect(homeCreates, 0);
      expect(find.byKey(const Key('setupCountry')), findsOneWidget);
      expect(find.byKey(const Key('setupTimeZone')), findsOneWidget);
      await tester.enterText(find.byKey(const Key('setupCountry')), 'US');
      await tester.enterText(find.byKey(const Key('setupPostalCode')), '60601');
      await tester.ensureVisible(find.text('Continue'));
      await tester.tap(find.text('Continue'));
      await tester.pumpAndSettle();
      expect(profileAttempts, 1);
      expect(homeCreates, 0);
      await tester.tap(find.text('Continue'));
      await tester.pumpAndSettle();
      expect(profileAttempts, 2);
      expect(homeCreates, 1);
      expect(selected?.name, 'New home');
    },
  );

  testWidgets(
    'offline create keeps the same idempotency key for unchanged retry',
    (tester) async {
      tester.binding.platformDispatcher.localeTestValue = const Locale(
        'en',
        'US',
      );
      addTearDown(tester.binding.platformDispatcher.clearLocaleTestValue);
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
      expect(find.byType(DropdownButtonFormField<String>), findsOneWidget);
      await tester.ensureVisible(find.text('Create home'));
      await tester.tap(find.text('Create home'));
      await tester.pumpAndSettle();
      expect(find.text('Internal Error, Try again later'), findsOneWidget);
      expect(find.text('Refresh homes'), findsOneWidget);
      expect(
        tester
            .widget<TextField>(find.byKey(const Key('setupHomeName')))
            .enabled,
        isFalse,
      );
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
