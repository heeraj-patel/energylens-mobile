import 'package:energylens_mobile/main.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets('shows the disconnected state without invented readings', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(390, 844);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await tester.pumpWidget(const EnergyLensApp());
    expect(find.text('No devices connected yet'), findsOneWidget);
    expect(find.textContaining('Waiting for a live reading'), findsOneWidget);

    await tester.tap(find.text('Stop Waste'));
    await tester.pumpAndSettle();
    expect(find.text('Find What’s Wasting Electricity'), findsOneWidget);
    expect(find.text('No findings yet'), findsOneWidget);

    await tester.tap(find.text('Sleep Check'));
    await tester.pumpAndSettle();
    expect(find.text('Sleep score unavailable'), findsOneWidget);

    await tester.tap(find.text('Ask & Add'));
    await tester.pumpAndSettle();
    expect(find.text('Answers need your home’s data'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
}
