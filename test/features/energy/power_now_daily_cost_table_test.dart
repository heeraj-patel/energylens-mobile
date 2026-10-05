import 'package:energylens_mobile/features/energy/power_now_daily_cost_table.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets('shows approved columns and formats nullable daily costs', (
    tester,
  ) async {
    await tester.pumpWidget(
      const MaterialApp(
        home: Scaffold(
          body: PowerNowDailyCostTable(
            rows: [
              PowerNowDailyCostRow(
                deviceName: 'Refrigerator',
                plugName: 'Kitchen plug',
                usedTodayUsd: 1.2,
                wastedTodayUsd: 0,
              ),
              PowerNowDailyCostRow(
                deviceName: 'Freezer',
                usedTodayUsd: null,
                wastedTodayUsd: null,
              ),
            ],
          ),
        ),
      ),
    );

    expect(find.text('Device'), findsOneWidget);
    expect(find.text('Used today'), findsOneWidget);
    expect(find.text('Wasted today'), findsOneWidget);
    expect(find.text('Refrigerator'), findsOneWidget);
    expect(find.text('Kitchen plug'), findsOneWidget);
    expect(find.text('Freezer'), findsOneWidget);
    expect(find.text('\$1.20'), findsOneWidget);
    expect(find.text('\$0.00'), findsOneWidget);
    expect(find.text('N/A'), findsNWidgets(2));
  });

  testWidgets('omits blank plug subtext', (tester) async {
    await tester.pumpWidget(
      const MaterialApp(
        home: Scaffold(
          body: PowerNowDailyCostTable(
            rows: [
              PowerNowDailyCostRow(
                deviceName: 'Washer',
                plugName: '   ',
                usedTodayUsd: 0.25,
                wastedTodayUsd: 0.05,
              ),
            ],
          ),
        ),
      ),
    );

    expect(find.text('Washer'), findsOneWidget);
    expect(find.text('   '), findsNothing);
  });

  testWidgets('source amount opens source details on tap', (tester) async {
    await tester.pumpWidget(
      const MaterialApp(
        home: Scaffold(
          body: PowerNowDailyCostTable(
            rows: [
              PowerNowDailyCostRow(
                deviceName: 'Lamp',
                usedTodayUsd: 0.25,
                wastedTodayUsd: null,
                sourceName: 'ENERGY STAR data (EPA)',
                sourceUrl: 'https://example.com/source',
              ),
            ],
          ),
        ),
      ),
    );
    await tester.tap(find.text('\$0.25'));
    await tester.pumpAndSettle();
    expect(
      find.text('ENERGY STAR data (EPA)\nhttps://example.com/source'),
      findsOneWidget,
    );
  });

  testWidgets(
    'footer minus enters selection and checkmark hides selected rows',
    (tester) async {
      final removed = <int>[];
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: PowerNowDailyCostTable(
              rows: const [
                PowerNowDailyCostRow(
                  applianceId: 7,
                  deviceName: 'Fan',
                  usedTodayUsd: null,
                  wastedTodayUsd: null,
                ),
                PowerNowDailyCostRow(
                  applianceId: 8,
                  deviceName: 'Lamp',
                  usedTodayUsd: null,
                  wastedTodayUsd: null,
                ),
              ],
              onRemove: removed.add,
            ),
          ),
        ),
      );
      await tester.tap(find.byKey(const Key('power-now-selection-action')));
      await tester.pump();
      expect(find.byKey(const Key('power-now-select-7')), findsOneWidget);
      expect(find.byKey(const Key('power-now-select-8')), findsOneWidget);
      await tester.tap(find.byKey(const Key('power-now-select-7')));
      await tester.tap(find.byKey(const Key('power-now-select-8')));
      await tester.pump();
      await tester.tap(find.byKey(const Key('power-now-selection-action')));
      expect(removed, [7, 8]);
    },
  );
}
