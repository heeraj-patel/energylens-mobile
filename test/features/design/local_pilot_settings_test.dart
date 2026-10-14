import 'dart:io';

import 'package:energylens_mobile/features/design/local_pilot_settings.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('pilot settings survive a fresh store read', () async {
    final directory = await Directory.systemTemp.createTemp('pilot-settings-');
    addTearDown(() => directory.delete(recursive: true));
    final store = LocalPilotSettingsStore(directory: directory);
    final initial = await store.load('The Miller Home');
    expect(initial.homeName, 'The Miller Home');
    await store.save(
      initial.copyWith(
        homeName: 'My Home',
        ownerName: 'Alex',
        postalCode: '60601',
      ),
    );
    final reopened = await LocalPilotSettingsStore(
      directory: directory,
    ).load('Other Home');
    expect(reopened.homeName, 'My Home');
    expect(reopened.ownerName, 'Alex');
    expect(reopened.postalCode, '60601');
  });

  testWidgets('home editor returns entered name and ZIP code', (tester) async {
    LocalPilotSettings? saved;
    const initial = LocalPilotSettings(
      homeName: 'The Miller Home',
      ownerName: 'Alex Miller',
      postalCode: '',
    );
    await tester.pumpWidget(
      MaterialApp(
        home: Builder(
          builder: (context) => Scaffold(
            body: TextButton(
              onPressed: () async {
                saved = await Navigator.of(context).push<LocalPilotSettings>(
                  MaterialPageRoute(
                    builder: (_) => const LocalPilotSettingsEditor(
                      settings: initial,
                      editOwner: false,
                    ),
                  ),
                );
              },
              child: const Text('Edit'),
            ),
          ),
        ),
      ),
    );
    await tester.tap(find.text('Edit'));
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextField).first, 'My Home');
    await tester.enterText(find.byType(TextField).last, '60601');
    await tester.tap(find.text('Save changes'));
    await tester.pumpAndSettle();
    expect(saved?.homeName, 'My Home');
    expect(saved?.postalCode, '60601');
    expect(saved?.ownerName, 'Alex Miller');
  });
}
