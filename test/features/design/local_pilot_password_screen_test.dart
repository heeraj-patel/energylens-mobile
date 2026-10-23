import 'package:energylens_mobile/features/design/account_profile_screen.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  for (final password in ['1234567', '12345678', 'éééa', 'éééé']) {
    testWidgets('profile password ${password.length} character boundary', (
      tester,
    ) async {
      await tester.pumpWidget(
        MaterialApp(
          home: AccountProfileScreen.localPilotPassword(
            isCurrentAccount: () => true,
          ),
        ),
      );
      await tester.enterText(find.byType(TextField).at(0), 'current');
      await tester.enterText(find.byType(TextField).at(1), password);
      await tester.enterText(find.byType(TextField).at(2), password);
      await tester.tap(find.text('Save changes'));
      await tester.pumpAndSettle();
      expect(
        find.text('Couldn’t save changes. Check the fields and try again.'),
        (password == '1234567' || password == 'éééa')
            ? findsOneWidget
            : findsNothing,
      );
    });
  }
  for (final values in [
    ['', 'new-password-123', 'new-password-123'],
    ['current', 'short', 'short'],
    ['current', 'new-password-123', 'different-password'],
  ]) {
    testWidgets(
      'pilot rejects invalid password fields: ${values.indexWhere((v) => v.isEmpty || v == "short" || v == "different-password")}',
      (tester) async {
        await tester.pumpWidget(
          MaterialApp(
            home: AccountProfileScreen.localPilotPassword(
              isCurrentAccount: () => true,
            ),
          ),
        );
        for (var i = 0; i < values.length; i++) {
          await tester.enterText(find.byType(TextField).at(i), values[i]);
        }
        await tester.tap(find.text('Save changes'));
        await tester.pumpAndSettle();
        expect(
          find.text('Couldn’t save changes. Check the fields and try again.'),
          findsOneWidget,
        );
        expect(find.text('Change password'), findsOneWidget);
      },
    );
  }

  testWidgets('pilot simulates saving the validated form and returns success', (
    tester,
  ) async {
    bool? saved;
    await tester.pumpWidget(
      MaterialApp(
        home: Builder(
          builder: (context) => TextButton(
            onPressed: () async {
              saved = await Navigator.of(context).push<bool>(
                MaterialPageRoute(
                  builder: (_) => AccountProfileScreen.localPilotPassword(
                    isCurrentAccount: () => true,
                  ),
                ),
              );
            },
            child: const Text('Open'),
          ),
        ),
      ),
    );
    await tester.tap(find.text('Open'));
    await tester.pumpAndSettle();
    for (var i = 0; i < 3; i++) {
      await tester.enterText(
        find.byType(TextField).at(i),
        i == 0 ? 'current-password' : 'new-password-123',
      );
    }
    expect(
      tester
          .widgetList<TextField>(find.byType(TextField))
          .every((field) => field.obscureText),
      true,
    );
    await tester.tap(find.text('Save changes'));
    await tester.pumpAndSettle();
    expect(saved, true);
    expect(find.text('Open'), findsOneWidget);
  });

  testWidgets('pilot does not save after leaving the current profile context', (
    tester,
  ) async {
    var current = true;
    await tester.pumpWidget(
      MaterialApp(
        home: AccountProfileScreen.localPilotPassword(
          isCurrentAccount: () => current,
        ),
      ),
    );
    for (var i = 0; i < 3; i++) {
      await tester.enterText(
        find.byType(TextField).at(i),
        i == 0 ? 'current-password' : 'new-password-123',
      );
    }
    current = false;
    await tester.tap(find.text('Save changes'));
    await tester.pumpAndSettle();
    expect(find.text('Change password'), findsOneWidget);
    expect(
      find.text('Couldn’t save changes. Check the fields and try again.'),
      findsNothing,
    );
  });
}
