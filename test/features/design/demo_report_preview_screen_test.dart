import 'package:energylens_mobile/features/design/demo_report_preview_screen.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets('local pilot report is visibly sample-only and cannot send', (
    tester,
  ) async {
    await tester.pumpWidget(
      const MaterialApp(home: DemoReportPreviewScreen()),
    );
    await tester.pumpAndSettle();

    expect(find.text('Demo report preview'), findsOneWidget);
    expect(
      find.text('This is a sample preview. Nothing will be emailed.'),
      findsOneWidget,
    );
    expect(find.text('Study Desktop & Rig'), findsOneWidget);
    expect(find.textContaining('Useful:'), findsWidgets);
    expect(find.textContaining('Waste:'), findsWidgets);
    expect(find.byType(TextField), findsNothing);
    expect(find.byType(FilledButton), findsNothing);
  });
}
